import Foundation
import AVFoundation

/// A timed segment of transcribed text with absolute audio-timeline bounds.
internal struct SegmentTiming: Sendable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

/// Aggregated output returned when live transcription is gracefully drained.
internal struct LiveTranscriptionResult: Sendable {
    let text: String
    let segments: [(text: String, start: Float, end: Float)]

    static let empty = LiveTranscriptionResult(text: "", segments: [])
}

/// Transcription update emitted by a live transcription backend.
internal struct LiveTranscriptionUpdate: Sendable {
    let finalizedText: String?
    let volatileText: String?
    let segmentTiming: SegmentTiming?

    init(finalizedText: String?, volatileText: String?, segmentTiming: SegmentTiming? = nil) {
        self.finalizedText = finalizedText
        self.volatileText = volatileText
        self.segmentTiming = segmentTiming
    }
}

/// Backend that processes an audio stream and produces live transcription updates.
internal protocol LiveTranscriptionBackend: AnyObject, Sendable {
    func start(audioStream: AsyncStream<AudioData>) -> AsyncStream<LiveTranscriptionUpdate>
    /// Gracefully drain remaining audio through the ASR pipeline.
    /// Called after the audio stream has ended (stopRecording).
    func finalize() async
    /// Hard cancel — discards remaining audio.
    func finish() async
}

extension LiveTranscriptionBackend {
    func finalize() async { await finish() }
}

/// User-facing live transcription engine selection.
internal enum LiveTranscriptionProvider: String, CaseIterable, Codable, Sendable {
    case off = "off"
    case fluidAudio = "fluidAudio"
    case parakeetMLX = "parakeetMLX"
    case appleSpeech = "appleSpeech"

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .fluidAudio:
            return "FluidAudio Streaming"
        case .parakeetMLX:
            return "Parakeet MLX (Advanced)"
        case .appleSpeech:
            return "Apple Speech (Live)"
        }
    }

    var requiresMacOS26: Bool {
        self == .appleSpeech
    }

    static var availableProviders: [LiveTranscriptionProvider] {
        var providers: [LiveTranscriptionProvider] = [.off, .fluidAudio, .parakeetMLX]
        #if swift(>=6.2)
        if #available(macOS 26, *) {
            providers.append(.appleSpeech)
        }
        #endif
        return providers
    }
}
