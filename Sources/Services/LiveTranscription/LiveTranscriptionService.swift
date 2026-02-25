import Foundation
import Combine
import os.log

/// Orchestrates live transcription during recording by routing audio to
/// the appropriate backend (FluidAudio or Apple SpeechAnalyzer).
@MainActor
internal class LiveTranscriptionService: ObservableObject {
    @Published var finalizedTranscript: String = ""
    @Published var volatileTranscript: String = ""
    @Published var isActive: Bool = false

    private var backend: (any LiveTranscriptionBackend)?
    private var updateTask: Task<Void, Never>?
    private var accumulatedSegments: [(text: String, start: Float, end: Float)] = []

    func start(
        audioStream: AsyncStream<AudioData>,
        provider: LiveTranscriptionProvider
    ) {
        guard provider != .off else { return }

        stop()

        finalizedTranscript = ""
        volatileTranscript = ""
        accumulatedSegments = []
        isActive = true

        let selectedBackend = Self.makeBackend(provider: provider)
        backend = selectedBackend

        let updates = selectedBackend.start(audioStream: audioStream)

        updateTask = Task { [weak self] in
            for await update in updates {
                guard let self, !Task.isCancelled else { break }
                if let finalized = update.finalizedText, !finalized.isEmpty {
                    if !self.finalizedTranscript.isEmpty {
                        self.finalizedTranscript += " "
                    }
                    self.finalizedTranscript += finalized
                    self.volatileTranscript = ""

                    if let t = update.segmentTiming {
                        self.accumulatedSegments.append(
                            (text: t.text, start: Float(t.start), end: Float(t.end))
                        )
                    }
                }
                if let volatile = update.volatileText {
                    self.volatileTranscript = volatile
                }
            }
            guard let self else { return }
            self.isActive = false
        }
    }

    /// Gracefully drain the live transcription pipeline after the audio stream
    /// has ended (i.e. after `audioRecorder.stopRecording()`).
    /// Returns the accumulated transcript and segment timings for diarization alignment.
    func finalize() async -> LiveTranscriptionResult {
        guard isActive, backend != nil else {
            return LiveTranscriptionResult(text: currentTranscript, segments: accumulatedSegments)
        }

        await updateTask?.value
        updateTask = nil

        if let backend {
            await backend.finalize()
        }
        backend = nil
        isActive = false

        return LiveTranscriptionResult(text: currentTranscript, segments: accumulatedSegments)
    }

    func stop() {
        updateTask?.cancel()
        updateTask = nil

        if let backend {
            Task { await backend.finish() }
        }
        backend = nil
        isActive = false
        accumulatedSegments = []
    }

    var currentTranscript: String {
        if volatileTranscript.isEmpty { return finalizedTranscript }
        if finalizedTranscript.isEmpty { return volatileTranscript }
        return finalizedTranscript + " " + volatileTranscript
    }

    // MARK: - Private

    private nonisolated static func makeBackend(
        provider: LiveTranscriptionProvider
    ) -> any LiveTranscriptionBackend {
        switch provider {
        case .off:
            fatalError("Cannot create backend for .off provider")

        case .appleSpeech:
            #if swift(>=6.2)
            if #available(macOS 26, *) {
                return SpeechAnalyzerTranscriber()
            }
            #endif
            Logger.app.warning("Apple Speech not available, falling back to FluidAudio streaming")
            return FluidAudioStreamingTranscriber()

        case .fluidAudio:
            return FluidAudioStreamingTranscriber()
        }
    }
}
