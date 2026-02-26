import AVFoundation
@testable import AudioWhisper

final class MockAudioCaptureEngine: AudioCaptureEngine {
    var inputFormat: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    }

    private(set) var tapInstalled = false
    private(set) var prepareCalled = false
    private(set) var startCalled = false
    private(set) var stopCalled = false
    private(set) var tapRemoved = false

    var shouldThrowOnStart = false
    var tapBlock: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?

    func installTap(
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) {
        tapInstalled = true
        tapBlock = block
    }

    func removeTap() {
        tapRemoved = true
        tapInstalled = false
        tapBlock = nil
    }

    func prepare() {
        prepareCalled = true
    }

    func start() throws {
        if shouldThrowOnStart {
            throw NSError(domain: "MockAudioCaptureEngine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Mock engine start failure"])
        }
        startCalled = true
    }

    func stop() {
        stopCalled = true
    }

    /// Simulate delivering a buffer from the tap (for testing audio pipeline).
    func simulateTapBuffer() {
        guard let block = tapBlock,
              let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) else { return }
        buffer.frameLength = 1024
        let time = AVAudioTime(sampleTime: 0, atRate: 44100)
        block(buffer, time)
    }
}
