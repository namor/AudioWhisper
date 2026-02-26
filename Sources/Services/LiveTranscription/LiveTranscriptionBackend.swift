import Foundation
import AVFoundation

/// Transcription update emitted by a live transcription backend.
internal struct LiveTranscriptionUpdate: Sendable {
    let finalizedText: String?
    let volatileText: String?
}

/// Backend that processes an audio stream and produces live transcription updates.
internal protocol LiveTranscriptionBackend: AnyObject, Sendable {
    func start(audioStream: AsyncStream<AudioData>) -> AsyncStream<LiveTranscriptionUpdate>
    func finish() async
}

/// User-facing live transcription engine selection.
internal enum LiveTranscriptionProvider: String, CaseIterable, Codable, Sendable {
    case off = "off"
    case fluidAudio = "fluidAudio"
    case appleSpeech = "appleSpeech"

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .fluidAudio:
            return "FluidAudio Streaming"
        case .appleSpeech:
            return "Apple Speech (Live)"
        }
    }

    var requiresMacOS26: Bool {
        self == .appleSpeech
    }

    static var availableProviders: [LiveTranscriptionProvider] {
        var providers: [LiveTranscriptionProvider] = [.off, .fluidAudio]
        #if swift(>=6.2)
        if #available(macOS 26, *) {
            providers.append(.appleSpeech)
        }
        #endif
        return providers
    }
}
