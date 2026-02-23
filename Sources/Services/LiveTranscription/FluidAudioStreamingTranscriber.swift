import Foundation
import AVFoundation
import FluidAudio
import os.log

/// Live transcription backend using FluidAudio's StreamingAsrManager.
/// Accepts AVAudioPCMBuffer from the recorder and produces volatile/confirmed
/// transcription updates via FluidAudio's Parakeet TDT model.
internal final class FluidAudioStreamingTranscriber: LiveTranscriptionBackend, @unchecked Sendable {
    private var streamingAsr: StreamingAsrManager?
    private var feedTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?

    func start(audioStream: AsyncStream<AudioData>) -> AsyncStream<LiveTranscriptionUpdate> {
        let (outputStream, outputContinuation) = AsyncStream<LiveTranscriptionUpdate>.makeStream()

        feedTask = Task { [weak self] in
            guard let self else { return }

            do {
                let config = StreamingAsrConfig.streaming
                let asr = StreamingAsrManager(config: config)
                self.streamingAsr = asr

                try await asr.start(source: .microphone)

                self.updateTask = Task { [weak self] in
                    guard self != nil else { return }
                    for await update in await asr.transcriptionUpdates {
                        guard !Task.isCancelled else { break }
                        if update.isConfirmed {
                            outputContinuation.yield(
                                LiveTranscriptionUpdate(finalizedText: update.text, volatileText: nil)
                            )
                        } else {
                            outputContinuation.yield(
                                LiveTranscriptionUpdate(finalizedText: nil, volatileText: update.text)
                            )
                        }
                    }
                    outputContinuation.finish()
                }

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
}
