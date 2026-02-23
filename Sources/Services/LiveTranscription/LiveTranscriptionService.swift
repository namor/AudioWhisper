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

    func start(
        audioStream: AsyncStream<AudioData>,
        provider: LiveTranscriptionProvider
    ) {
        guard provider != .off else { return }

        stop()

        finalizedTranscript = ""
        volatileTranscript = ""
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
                }
                if let volatile = update.volatileText {
                    self.volatileTranscript = volatile
                }
            }
            guard let self else { return }
            self.isActive = false
        }
    }

    func stop() {
        updateTask?.cancel()
        updateTask = nil

        if let backend {
            Task { await backend.finish() }
        }
        backend = nil
        isActive = false
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
