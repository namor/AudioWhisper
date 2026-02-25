import Foundation
import AVFoundation
import FluidAudio
import os.log

internal final class FluidAudioStreamingTranscriber: LiveTranscriptionBackend, @unchecked Sendable {
    private var streamingAsr: StreamingAsrManager?
    private var feedTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?

    /// Short-chunk config optimised for interactive live preview during recording.
    /// First update arrives after ~4s (3s chunk + 1s right context).
    private static let liveConfig = StreamingAsrConfig(
        chunkSeconds: 3.0,
        leftContextSeconds: 2.0,
        rightContextSeconds: 1.0,
        minContextForConfirmation: 5.0,
        confirmationThreshold: 0.75
    )

    func start(audioStream: AsyncStream<AudioData>) -> AsyncStream<LiveTranscriptionUpdate> {
        let (outputStream, outputContinuation) = AsyncStream<LiveTranscriptionUpdate>.makeStream()

        feedTask = Task { [weak self] in
            guard let self else { return }

            do {
                let modelDir = AsrModels.defaultCacheDirectory(for: .v3)
                guard AsrModels.modelsExist(at: modelDir, version: .v3) else {
                    Logger.app.warning("FluidAudio Parakeet model not downloaded — skipping live transcription")
                    outputContinuation.finish()
                    return
                }

                let asr = StreamingAsrManager(config: Self.liveConfig)
                self.streamingAsr = asr

                try await asr.start(source: .microphone)

                self.updateTask = Task { [weak self] in
                    guard self != nil else { return }
                    for await update in await asr.transcriptionUpdates {
                        guard !Task.isCancelled else { break }
                        let timing = Self.segmentTiming(from: update)
                        let mapped = LiveTranscriptionUpdate(
                            finalizedText: update.isConfirmed ? update.text : nil,
                            volatileText: update.isConfirmed ? nil : update.text,
                            segmentTiming: timing
                        )
                        outputContinuation.yield(mapped)
                    }
                    outputContinuation.finish()
                }

                await Task.yield()

                for await audioData in audioStream {
                    guard !Task.isCancelled else { break }
                    await asr.streamAudio(audioData.buffer)
                }

                let finalText = try await asr.finish()
                if !finalText.isEmpty {
                    outputContinuation.yield(
                        LiveTranscriptionUpdate(finalizedText: finalText, volatileText: nil)
                    )
                }
            } catch {
                Logger.app.error("FluidAudioStreamingTranscriber error: \(error.localizedDescription)")
            }

            outputContinuation.finish()
        }

        return outputStream
    }

    func finalize() async {
        await feedTask?.value
        updateTask?.cancel()
        if let asr = streamingAsr { try? await asr.reset() }
        streamingAsr = nil
        feedTask = nil
        updateTask = nil
    }

    func finish() async {
        feedTask?.cancel()
        updateTask?.cancel()
        if let asr = streamingAsr {
            let _ = try? await asr.finish()
            try? await asr.reset()
        }
        streamingAsr = nil
        feedTask = nil
        updateTask = nil
    }

    // MARK: - Private

    private static func segmentTiming(from update: StreamingTranscriptionUpdate) -> SegmentTiming? {
        guard !update.tokenTimings.isEmpty, !update.text.isEmpty else { return nil }
        let start = update.tokenTimings.first!.startTime
        let end = update.tokenTimings.last!.endTime
        return SegmentTiming(text: update.text, start: start, end: end)
    }
}
