import Foundation

enum Provider: String, CaseIterable, Identifiable {
    case elevenlabs, openai, gemini, groq, deepgram, soniox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .elevenlabs: "ElevenLabs"
        case .openai: "OpenAI"
        case .gemini: "Google Gemini"
        case .groq: "Groq"
        case .deepgram: "Deepgram"
        case .soniox: "Soniox"
        }
    }

    var detail: String {
        switch self {
        case .elevenlabs: "Scribe v2 realtime, words appear while you speak"
        case .openai: "GPT-4o transcribe, strong multilingual accuracy"
        case .gemini: "Gemini audio understanding with an AI Studio key"
        case .groq: "Whisper large v3 on Groq, very fast and cheap"
        case .deepgram: "Nova-3, check language support for Uzbek"
        case .soniox: "Async multilingual speech-to-text"
        }
    }

    var symbol: String {
        switch self {
        case .elevenlabs: "waveform"
        case .openai: "circle.hexagongrid"
        case .gemini: "sparkle"
        case .groq: "bolt.fill"
        case .deepgram: "d.circle"
        case .soniox: "s.circle"
        }
    }

    var isRealtime: Bool { self == .elevenlabs }

    var keyURL: URL {
        switch self {
        case .elevenlabs: URL(string: "https://elevenlabs.io/app/settings/api-keys")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: URL(string: "https://aistudio.google.com/apikey")!
        case .groq: URL(string: "https://console.groq.com/keys")!
        case .deepgram: URL(string: "https://console.deepgram.com/")!
        case .soniox: URL(string: "https://console.soniox.com/")!
        }
    }

    var models: [String] {
        switch self {
        case .elevenlabs: Preferences.models.map(\.id)
        case .openai: ["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"]
        case .gemini: ["gemini-3.8-flash", "gemini-3.5-transcribe-preview", "gemini-2.5-flash"]
        case .groq: ["whisper-large-v3-turbo", "whisper-large-v3"]
        case .deepgram: ["nova-3", "nova-2"]
        case .soniox: ["stt-async-preview"]
        }
    }

    var modelKey: String {
        self == .elevenlabs ? Preferences.modelKey : "model.\(rawValue)"
    }

    var model: String {
        let stored = UserDefaults.standard.string(forKey: modelKey) ?? ""
        return stored.isEmpty ? models[0] : stored
    }

    var apiKey: String? {
        guard let key = Secrets.read(rawValue), !key.isEmpty else { return nil }
        return key
    }

    static var current: Provider {
        Provider(rawValue: UserDefaults.standard.string(forKey: Preferences.providerKey) ?? "") ?? .elevenlabs
    }
}

protocol Transcriber: AnyObject {
    var onPartial: ((String) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    func connect()
    func send(_ pcm: Data)
    func finish(timeout: Duration) async -> Result<String, ScribeError>
    func cancel()
}

extension ScribeClient: Transcriber {}

struct TranscriptionRequest {
    var provider: Provider
    var apiKey: String
    var model: String
    var language: String
    var keyterms: [String]
    var sampleRate = 16_000
}

final class BatchTranscriber: Transcriber {
    var onPartial: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let request: TranscriptionRequest
    private var audio = Data()
    private var cancelled = false

    init(request: TranscriptionRequest) {
        self.request = request
    }

    func connect() {}

    func send(_ pcm: Data) {
        audio.append(pcm)
    }

    func cancel() {
        cancelled = true
        audio = Data()
    }

    func finish(timeout: Duration) async -> Result<String, ScribeError> {
        guard !audio.isEmpty else { return .success("") }
        let wav = WAV.encode(pcm: audio, sampleRate: request.sampleRate)
        let request = self.request
        do {
            let text = try await Self.transcribe(wav: wav, request: request)
            return cancelled ? .success("") : .success(text.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch let error as ScribeError {
            return .failure(error)
        } catch {
            return .failure(ScribeError(message: "\(request.provider.title): \(error.localizedDescription)"))
        }
    }

    private static func transcribe(wav: Data, request: TranscriptionRequest) async throws -> String {
        switch request.provider {
        case .openai:
            try await openAICompatible(wav: wav, request: request, endpoint: "https://api.openai.com/v1/audio/transcriptions")
        case .groq:
            try await openAICompatible(wav: wav, request: request, endpoint: "https://api.groq.com/openai/v1/audio/transcriptions")
        case .deepgram:
            try await deepgram(wav: wav, request: request)
        case .gemini:
            try await gemini(wav: wav, request: request)
        case .soniox:
            try await soniox(wav: wav, request: request)
        case .elevenlabs:
            throw ScribeError(message: "ElevenLabs uses the realtime client")
        }
    }

    private static func openAICompatible(wav: Data, request: TranscriptionRequest, endpoint: String) async throws -> String {
        var form = MultipartForm()
        form.addFile(name: "file", filename: "audio.wav", mimeType: "audio/wav", data: wav)
        form.addField(name: "model", value: request.model)
        form.addField(name: "response_format", value: "json")
        if !request.language.isEmpty {
            form.addField(name: "language", value: request.language)
        }
        if !request.keyterms.isEmpty {
            form.addField(name: "prompt", value: request.keyterms.joined(separator: ", "))
        }
        var urlRequest = URLRequest(url: URL(string: endpoint)!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = form.finalize()
        let json = try await perform(urlRequest, provider: request.provider)
        return json["text"] as? String ?? ""
    }

    private static func deepgram(wav: Data, request: TranscriptionRequest) async throws -> String {
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        var items = [
            URLQueryItem(name: "model", value: request.model),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
        ]
        items.append(request.language.isEmpty
            ? URLQueryItem(name: "detect_language", value: "true")
            : URLQueryItem(name: "language", value: request.language))
        items += request.keyterms.prefix(50).map { URLQueryItem(name: "keyterm", value: $0) }
        components.queryItems = items
        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Token \(request.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = wav
        let json = try await perform(urlRequest, provider: request.provider)
        let results = json["results"] as? [String: Any]
        let channel = (results?["channels"] as? [[String: Any]])?.first
        let alternative = (channel?["alternatives"] as? [[String: Any]])?.first
        return alternative?["transcript"] as? String ?? ""
    }

    private static func gemini(wav: Data, request: TranscriptionRequest) async throws -> String {
        let languageName = Preferences.languages.first { $0.code == request.language }?.name
        var instruction = "Transcribe this audio exactly as spoken. Output only the transcript text with punctuation, no commentary, no quotes, no timestamps."
        if let languageName, !request.language.isEmpty {
            instruction += " The speech is in \(languageName)."
        }
        if request.language == "uz" {
            instruction += " Write Uzbek in the Latin alphabet (oʻ, gʻ, sh, ch)."
        }
        if !request.keyterms.isEmpty {
            instruction += " Spell these terms exactly: \(request.keyterms.joined(separator: ", "))."
        }
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": instruction],
                    ["inline_data": ["mime_type": "audio/wav", "data": wav.base64EncodedString()]],
                ],
            ]],
            "generationConfig": ["temperature": 0],
        ]
        let model = request.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? request.model
        var urlRequest = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(request.apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json = try await perform(urlRequest, provider: request.provider)
        let candidate = (json["candidates"] as? [[String: Any]])?.first
        let content = candidate?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]] ?? []
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    private static func soniox(wav: Data, request: TranscriptionRequest) async throws -> String {
        let base = "https://api.soniox.com/v1"
        let auth = "Bearer \(request.apiKey)"

        var form = MultipartForm()
        form.addFile(name: "file", filename: "audio.wav", mimeType: "audio/wav", data: wav)
        var upload = URLRequest(url: URL(string: "\(base)/files")!)
        upload.httpMethod = "POST"
        upload.setValue(auth, forHTTPHeaderField: "Authorization")
        upload.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        upload.httpBody = form.finalize()
        guard let fileID = try await perform(upload, provider: request.provider)["id"] as? String else {
            throw ScribeError(message: "Soniox: upload failed")
        }
        defer { Task { await delete("\(base)/files/\(fileID)", auth: auth) } }

        var create = URLRequest(url: URL(string: "\(base)/transcriptions")!)
        create.httpMethod = "POST"
        create.setValue(auth, forHTTPHeaderField: "Authorization")
        create.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["model": request.model, "file_id": fileID]
        if !request.language.isEmpty {
            body["language_hints"] = [request.language]
        }
        create.httpBody = try JSONSerialization.data(withJSONObject: body)
        guard let transcriptionID = try await perform(create, provider: request.provider)["id"] as? String else {
            throw ScribeError(message: "Soniox: could not start transcription")
        }
        defer { Task { await delete("\(base)/transcriptions/\(transcriptionID)", auth: auth) } }

        var status = URLRequest(url: URL(string: "\(base)/transcriptions/\(transcriptionID)")!)
        status.setValue(auth, forHTTPHeaderField: "Authorization")
        let deadline = ContinuousClock.now + .seconds(90)
        while ContinuousClock.now < deadline {
            let json = try await perform(status, provider: request.provider)
            switch json["status"] as? String {
            case "completed":
                var transcript = URLRequest(url: URL(string: "\(base)/transcriptions/\(transcriptionID)/transcript")!)
                transcript.setValue(auth, forHTTPHeaderField: "Authorization")
                return try await perform(transcript, provider: request.provider)["text"] as? String ?? ""
            case "error":
                throw ScribeError(message: "Soniox: \(json["error_message"] as? String ?? "transcription failed")")
            default:
                try await Task.sleep(for: .milliseconds(400))
            }
        }
        throw ScribeError(message: "Soniox: timed out")
    }

    private static func delete(_ url: String, auth: String) async {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "DELETE"
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func perform(_ request: URLRequest, provider: Provider) async throws -> [String: Any] {
        var request = request
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            switch status {
            case 401, 403: throw ScribeError(message: "Invalid \(provider.title) API key")
            case 429: throw ScribeError(message: "\(provider.title): rate limited or out of credit")
            default:
                let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
                throw ScribeError(message: "\(provider.title) error \(status): \(snippet)")
            }
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

enum WAV {
    static func encode(pcm: Data, sampleRate: Int) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcm.count))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}

struct MultipartForm {
    private let boundary = "Boundary-\(UUID().uuidString)"
    private var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(name: String, value: String) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data: Data) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    func finalize() -> Data {
        body + Data("--\(boundary)--\r\n".utf8)
    }
}
