import XCTest
@testable import AudioWhisper

@MainActor
final class LiveTranscriptionServiceTests: XCTestCase {

    func testStartSetsIsActive() async throws {
        let service = LiveTranscriptionService()
        let (stream, continuation) = AsyncStream<AudioData>.makeStream()

        service.start(audioStream: stream, provider: .fluidAudio)

        XCTAssertTrue(service.isActive)

        continuation.finish()
        service.stop()
    }

    func testStartWithOffProviderDoesNotActivate() {
        let service = LiveTranscriptionService()
        let (stream, _) = AsyncStream<AudioData>.makeStream()

        service.start(audioStream: stream, provider: .off)

        XCTAssertFalse(service.isActive)
        XCTAssertTrue(service.currentTranscript.isEmpty)
    }

    func testStopClearsBackendAndDeactivates() async throws {
        let service = LiveTranscriptionService()
        let (stream, continuation) = AsyncStream<AudioData>.makeStream()

        service.start(audioStream: stream, provider: .fluidAudio)
        XCTAssertTrue(service.isActive)

        service.stop()

        XCTAssertFalse(service.isActive)
        continuation.finish()
    }

    func testCurrentTranscriptCombinesFinalizedAndVolatile() {
        let service = LiveTranscriptionService()

        service.finalizedTranscript = "Hello world"
        service.volatileTranscript = "how are you"

        XCTAssertEqual(service.currentTranscript, "Hello world how are you")
    }

    func testCurrentTranscriptReturnsFinalizedOnlyWhenNoVolatile() {
        let service = LiveTranscriptionService()

        service.finalizedTranscript = "Hello world"
        service.volatileTranscript = ""

        XCTAssertEqual(service.currentTranscript, "Hello world")
    }

    func testCurrentTranscriptReturnsVolatileOnlyWhenNoFinalized() {
        let service = LiveTranscriptionService()

        service.finalizedTranscript = ""
        service.volatileTranscript = "typing..."

        XCTAssertEqual(service.currentTranscript, "typing...")
    }

    func testStopResetsTranscripts() async throws {
        let service = LiveTranscriptionService()

        service.finalizedTranscript = "some text"
        service.volatileTranscript = "volatile"

        service.stop()

        XCTAssertFalse(service.isActive)
    }
}
