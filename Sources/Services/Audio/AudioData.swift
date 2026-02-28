import AVFoundation

/// Wraps an audio buffer and its timestamp for streaming through async sequences.
/// Marked @unchecked Sendable because AVAudioPCMBuffer is not formally Sendable
/// but is safe to pass across concurrency boundaries when not mutated after creation.
internal struct AudioData: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let time: AVAudioTime
}
