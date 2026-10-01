import AVFoundation

enum AudioEvent: Sendable {
    case pcm(Data)
    case level(Float)
}

enum AudioCaptureError: LocalizedError {
    case noInput
    case converter

    var errorDescription: String? {
        switch self {
        case .noInput: "No microphone found"
        case .converter: "Could not convert audio format"
        }
    }
}

nonisolated final class Resampler: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let output: AVAudioFormat
    private let ratio: Double

    init?(from input: AVAudioFormat, sampleRate: Double) {
        guard
            let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true),
            let converter = AVAudioConverter(from: input, to: output)
        else { return nil }
        self.converter = converter
        self.output = output
        self.ratio = sampleRate / input.sampleRate
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) var consumed = false
        nonisolated(unsafe) let source = buffer
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return source
        }
        guard error == nil, out.frameLength > 0, let samples = out.int16ChannelData else { return nil }
        return Data(bytes: samples[0], count: Int(out.frameLength) * MemoryLayout<Int16>.size)
    }

    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count {
            sum += channel[i] * channel[i]
        }
        let rms = (sum / Float(count)).squareRoot()
        let db = 20 * log10(max(rms, 0.000_01))
        return min(max((db + 55) / 45, 0), 1)
    }
}

nonisolated final class AudioCapture {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AudioEvent>.Continuation?

    func start(sampleRate: Double = 16_000) throws -> AsyncStream<AudioEvent> {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioCaptureError.noInput }
        guard let resampler = Resampler(from: format, sampleRate: sampleRate) else { throw AudioCaptureError.converter }

        let (stream, continuation) = AsyncStream.makeStream(of: AudioEvent.self, bufferingPolicy: .unbounded)
        self.continuation = continuation

        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            continuation.yield(.level(Resampler.level(of: buffer)))
            if let data = resampler.convert(buffer) {
                continuation.yield(.pcm(data))
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            continuation.finish()
            throw error
        }
        return stream
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
    }
}
