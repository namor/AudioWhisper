import Foundation
@testable import AudioWhisper

final class MockLiveTranscriptionBackend: LiveTranscriptionBackend, @unchecked Sendable {
    var startCalled = false
    var finishCalled = false

    /// Updates to yield when `start` is called.
    var updatesToEmit: [LiveTranscriptionUpdate] = []

    func start(audioStream: AsyncStream<AudioData>) -> AsyncStream<LiveTranscriptionUpdate> {
        startCalled = true
        let updates = updatesToEmit
        return AsyncStream { continuation in
            for update in updates {
                continuation.yield(update)
            }
            continuation.finish()
        }
    }

    func finish() async {
        finishCalled = true
    }
}
