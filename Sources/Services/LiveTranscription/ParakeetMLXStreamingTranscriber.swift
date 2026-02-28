import AVFoundation
import os.log

/// Live transcription backend that uses the MLX Parakeet model (e.g. TDT 1.1B)
/// via the ML daemon. Accumulates audio and periodically transcribes the full
/// buffer, yielding incremental updates as text grows.
internal final class ParakeetMLXStreamingTranscriber: LiveTranscriptionBackend, @unchecked Sendable {
    private var feedTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.audiowhisper.app", category: "ParakeetMLXStreaming")

    /// Transcribe accumulated audio every N seconds of wall-clock time.
    private let chunkInterval: TimeInterval = 5.0

    func start(audioStream: AsyncStream<AudioData>) -> AsyncStream<LiveTranscriptionUpdate> {
        let (outputStream, outputContinuation) = AsyncStream<LiveTranscriptionUpdate>.makeStream()

        feedTask = Task { [weak self] in
            guard let self else {
                outputContinuation.finish()
                return
            }

            let repo = await MLXModelManager.parakeetRepo
            let daemon = MLDaemonManager.shared

            var accumulatedSamples: [Float] = []
            var converter: AVAudioConverter?
            var targetFormat: AVAudioFormat?
            var previousText = ""
            var lastTranscribeTime = Date()

            for await audioData in audioStream {
                guard !Task.isCancelled else { break }

                let inputFormat = audioData.buffer.format

                if converter == nil {
                    guard let fmt = AVAudioFormat(
                        commonFormat: .pcmFormatFloat32,
                        sampleRate: 16000,
                        channels: 1,
                        interleaved: true
                    ) else {
                        self.logger.error("Failed to create 16kHz target format")
                        break
                    }
                    targetFormat = fmt
                    converter = AVAudioConverter(from: inputFormat, to: fmt)
                    if converter == nil {
                        self.logger.error("Failed to create audio converter from \(inputFormat) to 16kHz mono")
                        break
                    }
                }

                guard let conv = converter, let _ = targetFormat else { break }

                let inputFrameCount = audioData.buffer.frameLength
                let ratio = 16000.0 / inputFormat.sampleRate
                let outputFrameCount = AVAudioFrameCount(Double(inputFrameCount) * ratio)

                guard outputFrameCount > 0,
                      let outputBuffer = AVAudioPCMBuffer(
                          pcmFormat: targetFormat!,
                          frameCapacity: outputFrameCount + 16
                      )
                else { continue }

                var conversionError: NSError?
                let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    outStatus.pointee = .haveData
                    return audioData.buffer
                }

                let status = conv.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)

                if status == .error {
                    if let err = conversionError {
                        self.logger.error("Audio conversion error: \(err.localizedDescription)")
                    }
                    continue
                }

                if let channelData = outputBuffer.floatChannelData?[0] {
                    let count = Int(outputBuffer.frameLength)
                    accumulatedSamples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: count))
                }

                let elapsed = Date().timeIntervalSince(lastTranscribeTime)
                if elapsed >= self.chunkInterval && accumulatedSamples.count >= 16000 {
                    lastTranscribeTime = Date()

                    let samples = accumulatedSamples
                    do {
                        let text = try await self.transcribeSamples(samples, repo: repo, daemon: daemon)
                        if !text.isEmpty && text != previousText {
                            let update = LiveTranscriptionUpdate(
                                finalizedText: previousText.isEmpty ? nil : previousText,
                                volatileText: self.incrementalText(previous: previousText, current: text)
                            )
                            outputContinuation.yield(update)
                            previousText = text
                        }
                    } catch {
                        self.logger.error("Live transcription chunk failed: \(error.localizedDescription)")
                    }
                }
            }

            // Final transcription of remaining audio
            if !Task.isCancelled && accumulatedSamples.count >= 1600 {
                do {
                    let text = try await self.transcribeSamples(accumulatedSamples, repo: repo, daemon: daemon)
                    if !text.isEmpty {
                        outputContinuation.yield(LiveTranscriptionUpdate(
                            finalizedText: text,
                            volatileText: nil
                        ))
                    }
                } catch {
                    self.logger.error("Final live transcription failed: \(error.localizedDescription)")
                    if !previousText.isEmpty {
                        outputContinuation.yield(LiveTranscriptionUpdate(
                            finalizedText: previousText,
                            volatileText: nil
                        ))
                    }
                }
            }

            outputContinuation.finish()
        }

        return outputStream
    }

    func finalize() async {
        await feedTask?.value
        feedTask = nil
    }

    func finish() async {
        feedTask?.cancel()
        feedTask = nil
    }

    // MARK: - Private

    private func transcribeSamples(
        _ samples: [Float],
        repo: String,
        daemon: MLDaemonManager
    ) async throws -> String {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("live_pcm_\(UUID().uuidString).raw")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let data = samples.withUnsafeBytes { Data($0) }
        try data.write(to: tempURL)

        return try await daemon.transcribe(repo: repo, pcmPath: tempURL.path)
    }

    /// Returns the new portion of text that wasn't in the previous result.
    private func incrementalText(previous: String, current: String) -> String {
        if current.hasPrefix(previous) {
            let suffix = String(current.dropFirst(previous.count)).trimmingCharacters(in: .whitespaces)
            return suffix.isEmpty ? current : suffix
        }
        return current
    }
}
