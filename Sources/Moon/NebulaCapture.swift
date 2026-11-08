import AVFoundation
import Speech

/// AVAudioEngine serializes calls to this tap. Its converter is used only there;
/// each yielded AnalyzerInput owns a newly allocated buffer.
final class NebulaAudioConverter: @unchecked Sendable {
    let converter: AVAudioConverter
    let format: AVAudioFormat
    let ratio: Double

    init(from source: AVAudioFormat, to target: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: source, to: target) else {
            throw NebulaCapture.Failure.audioFormat
        }
        self.converter = converter
        format = target
        ratio = target.sampleRate / source.sampleRate
    }

    func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio)) + 128
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw NebulaCapture.Failure.audioFormat
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            guard !supplied else { state.pointee = .noDataNow; return nil }
            supplied = true
            state.pointee = .haveData
            return input
        }
        if let error { throw error }
        guard status != .error else { throw NebulaCapture.Failure.audioFormat }
        return output
    }
}

@MainActor
final class NebulaCapture {
    enum Failure: LocalizedError {
        case audioFormat, overrun
        var errorDescription: String? {
            switch self {
            case .audioFormat: "The microphone’s audio format is unavailable. Check your input device."
            case .overrun: "Speech processing fell behind. Please try a shorter recording."
            }
        }
    }

    private let engine = AVAudioEngine()
    private var installed = false
    private var configurationObserver: NSObjectProtocol?
    private var continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?

    var inputFormat: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }

    func start(format: AVAudioFormat) throws -> AsyncThrowingStream<AnalyzerInput, Error> {
        let source = inputFormat
        guard source.sampleRate > 0, source.channelCount > 0 else { throw Failure.audioFormat }
        let conversion = try NebulaAudioConverter(from: source, to: format)
        let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingOldest(8))
        self.continuation = continuation
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: source) { buffer, _ in
            do {
                let converted = try conversion.convert(buffer)
                guard converted.frameLength > 0 else { return }
                if case .dropped = continuation.yield(AnalyzerInput(buffer: converted)) {
                    continuation.finish(throwing: Failure.overrun)
                }
            } catch { continuation.finish(throwing: error) }
        }
        installed = true
        do { try engine.start() }
        catch { stop(); throw error }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in
                continuation.finish(throwing: Failure.audioFormat)
            }
        return stream
    }

    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.stop()
        if installed { engine.inputNode.removeTap(onBus: 0); installed = false }
        continuation?.finish()
        continuation = nil
    }
}
