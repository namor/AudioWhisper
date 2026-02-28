import Foundation
import AVFoundation
import os.log

// SpeechAnalyzer/SpeechTranscriber require macOS 26+ SDK (ships with Swift 6.2+).
// On older toolchains the entire implementation is excluded at compile time.
#if swift(>=6.2)
import Speech

/// Live transcription backend using Apple's SpeechAnalyzer (macOS 26+).
/// Provides true streaming transcription with volatile and finalized results.
@available(macOS 26, *)
internal final class SpeechAnalyzerTranscriber: LiveTranscriptionBackend, @unchecked Sendable {
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var analyzerFormat: AVAudioFormat?
    private let bufferConverter = AudioBufferFormatConverter()
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var processingTask: Task<Void, Never>?

    func start(audioStream: AsyncStream<AudioData>) -> AsyncStream<LiveTranscriptionUpdate> {
        let (updateStream, updateContinuation) = AsyncStream<LiveTranscriptionUpdate>.makeStream()

        processingTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await self.setUp()
            } catch {
                Logger.app.error("SpeechAnalyzerTranscriber setup failed: \(error.localizedDescription)")
                updateContinuation.finish()
                return
            }

            Task { [weak self] in
                guard let self, let transcriber = self.transcriber else { return }
                for await result in transcriber.results {
                    let text = result.transcription.characters.map(String.init).joined()
                    if result.isFinal {
                        updateContinuation.yield(
                            LiveTranscriptionUpdate(finalizedText: text, volatileText: nil)
                        )
                    } else {
                        updateContinuation.yield(
                            LiveTranscriptionUpdate(finalizedText: nil, volatileText: text)
                        )
                    }
                }
                updateContinuation.finish()
            }

            for await audioData in audioStream {
                guard !Task.isCancelled else { break }
                do {
                    try self.streamBuffer(audioData.buffer)
                } catch {
                    Logger.app.error("SpeechAnalyzerTranscriber buffer error: \(error.localizedDescription)")
                }
            }

            self.inputContinuation?.finish()
            self.analyzer?.finalizeAndFinishThroughEndOfInput()
        }

        return updateStream
    }

    func finalize() async {
        inputContinuation?.finish()
        analyzer?.finalizeAndFinishThroughEndOfInput()
        await processingTask?.value
        processingTask = nil
    }

    func finish() async {
        inputContinuation?.finish()
        analyzer?.finalizeAndFinishThroughEndOfInput()
        processingTask?.cancel()
        processingTask = nil
    }

    // MARK: - Private

    private func setUp() async throws {
        let locale = Locale(identifier: "en-US")

        let speechTranscriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        transcriber = speechTranscriber

        let speechAnalyzer = SpeechAnalyzer(modules: [speechTranscriber])
        analyzer = speechAnalyzer

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [speechTranscriber]
        )

        let (inputSequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        try await speechAnalyzer.start(inputSequence: inputSequence)
    }

    private func streamBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard let targetFormat = analyzerFormat else { return }
        let converted = try bufferConverter.convert(buffer, to: targetFormat)
        let input = AnalyzerInput(buffer: converted)
        inputContinuation?.yield(input)
    }
}

/// Converts AVAudioPCMBuffers between formats for SpeechAnalyzer compatibility.
@available(macOS 26, *)
private final class AudioBufferFormatConverter {
    private var converter: AVAudioConverter?
    private var lastInputFormat: AVAudioFormat?

    func convert(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        if inputFormat == targetFormat { return buffer }

        if converter == nil || lastInputFormat != inputFormat {
            guard let newConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw NSError(domain: "AudioBufferFormatConverter", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"])
            }
            converter = newConverter
            lastInputFormat = inputFormat
        }

        guard let converter else {
            throw NSError(domain: "AudioBufferFormatConverter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Converter unavailable"])
        }

        let sampleRateRatio = targetFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRateRatio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            throw NSError(domain: "AudioBufferFormatConverter", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to allocate output buffer"])
        }

        var error: NSError?
        var inputConsumed = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error { throw error }
        guard status != .error else {
            throw NSError(domain: "AudioBufferFormatConverter", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Conversion failed"])
        }

        return outputBuffer
    }
}

#endif // swift(>=6.2)
