import Foundation

struct ScribeOptions {
    var apiKey: String
    var language: String
    var keyterms: [String]
    var noVerbatim: Bool
    var model = "scribe_v2_realtime"
    var sampleRate = 16_000
}

final class ScribeClient {
    var onPartial: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let options: ScribeOptions
    private var socket: URLSessionWebSocketTask?
    private var ready = false
    private var pending = Data()
    private var queued: [(Data, Bool)] = []
    private var committed: [String] = []
    private var awaitingFinal = false
    private var finalWaiter: CheckedContinuation<Void, Never>?
    private var failure: String?

    private let chunkBytes = 3_200

    init(options: ScribeOptions) {
        self.options = options
    }

    func connect() {
        var components = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
        var items = [
            URLQueryItem(name: "model_id", value: options.model),
            URLQueryItem(name: "audio_format", value: "pcm_\(options.sampleRate)"),
            URLQueryItem(name: "commit_strategy", value: "manual"),
        ]
        if !options.language.isEmpty {
            items.append(URLQueryItem(name: "language_code", value: options.language))
        }
        if options.noVerbatim {
            items.append(URLQueryItem(name: "no_verbatim", value: "true"))
        }
        items += options.keyterms.map { URLQueryItem(name: "keyterms", value: $0) }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue(options.apiKey, forHTTPHeaderField: "xi-api-key")
        let socket = URLSession.shared.webSocketTask(with: request)
        self.socket = socket
        socket.resume()
        Task { await receiveLoop(socket) }
    }

    func send(_ pcm: Data) {
        pending.append(pcm)
        while pending.count >= chunkBytes {
            let chunk = pending.prefix(chunkBytes)
            pending.removeFirst(chunkBytes)
            enqueue(Data(chunk), commit: false)
        }
    }

    func finish(timeout: Duration = .seconds(8)) async -> Result<String, ScribeError> {
        pending.append(Data(count: chunkBytes))
        let tail = pending
        pending = Data()
        awaitingFinal = true
        enqueue(tail, commit: true)

        if failure == nil {
            await withCheckedContinuation { continuation in
                finalWaiter = continuation
                Task {
                    try? await Task.sleep(for: timeout)
                    self.resolveFinal()
                }
            }
        }
        close()

        let text = committed
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if text.isEmpty, let failure {
            return .failure(ScribeError(message: failure))
        }
        return .success(text)
    }

    func cancel() {
        resolveFinal()
        close()
    }

    private func close() {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
    }

    private func enqueue(_ chunk: Data, commit: Bool) {
        if ready {
            transmit(chunk, commit: commit)
        } else {
            queued.append((chunk, commit))
        }
    }

    private func transmit(_ chunk: Data, commit: Bool) {
        let payload: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": chunk.base64EncodedString(),
            "commit": commit,
            "sample_rate": options.sampleRate,
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let string = String(data: data, encoding: .utf8)
        else { return }
        socket?.send(.string(string)) { _ in }
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) async {
        while self.socket === socket {
            do {
                let message = try await socket.receive()
                switch message {
                case .string(let text):
                    handle(Data(text.utf8))
                case .data(let data):
                    handle(data)
                @unknown default:
                    break
                }
            } catch {
                if self.socket === socket {
                    fail(Self.describe(socket: socket, error: error))
                }
                return
            }
        }
    }

    private func handle(_ data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["message_type"] as? String
        else { return }

        switch type {
        case "session_started":
            ready = true
            let backlog = queued
            queued.removeAll()
            for (chunk, commit) in backlog {
                transmit(chunk, commit: commit)
            }
        case "partial_transcript":
            let partial = object["text"] as? String ?? ""
            onPartial?((committed + [partial]).joined(separator: " "))
        case "committed_transcript":
            committed.append(object["text"] as? String ?? "")
            onPartial?(committed.joined(separator: " "))
            if awaitingFinal {
                resolveFinal()
            }
        case "committed_transcript_with_timestamps":
            break
        default:
            let detail = object["error"] as? String ?? object["message"] as? String ?? type
            fail(Self.humanize(detail))
        }
    }

    private func fail(_ message: String) {
        if failure == nil {
            failure = message
        }
        if !awaitingFinal {
            onError?(message)
        }
        resolveFinal()
    }

    private func resolveFinal() {
        finalWaiter?.resume()
        finalWaiter = nil
    }

    private static func describe(socket: URLSessionWebSocketTask, error: Error) -> String {
        if let response = socket.response as? HTTPURLResponse, response.statusCode == 401 || response.statusCode == 403 {
            return "Invalid ElevenLabs API key"
        }
        return "Connection lost: \(error.localizedDescription)"
    }

    private static func humanize(_ code: String) -> String {
        switch code {
        case "auth_error": "Invalid ElevenLabs API key"
        case "quota_exceeded": "ElevenLabs quota exceeded"
        case "rate_limited": "Rate limited, try again shortly"
        case "insufficient_audio_activity": "No speech detected"
        case "unaccepted_terms": "Accept the terms in your ElevenLabs dashboard"
        default: "ElevenLabs error: \(code)"
        }
    }
}

struct ScribeError: Error {
    let message: String
}
