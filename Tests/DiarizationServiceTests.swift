import XCTest
@testable import AudioWhisper

final class DiarizationServiceTests: XCTestCase {
    private var mockDiarization: MockDiarizationService!

    override func setUp() {
        super.setUp()
        mockDiarization = MockDiarizationService()
    }

    override func tearDown() {
        mockDiarization = nil
        super.tearDown()
    }

    // MARK: - Mock behavior

    func testMockDiarizationReturnsConfiguredSegments() async throws {
        mockDiarization.mockSegments = [
            (speakerId: "spk_0", start: 0.0, end: 2.0),
            (speakerId: "spk_1", start: 2.0, end: 4.0),
        ]
        let segments = try await mockDiarization.diarize(audioURL: URL(fileURLWithPath: "/tmp/test.m4a"))
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].speakerId, "spk_0")
        XCTAssertTrue(mockDiarization.diarizeCalled)
    }

    func testMockDiarizationThrowsWhenConfigured() async {
        mockDiarization.shouldThrow = true
        do {
            _ = try await mockDiarization.diarize(audioURL: URL(fileURLWithPath: "/tmp/test.m4a"))
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is DiarizationError)
        }
    }

    func testPrepareModelsTracked() async throws {
        XCTAssertFalse(mockDiarization.prepareModelsCalled)
        try await mockDiarization.prepareModels()
        XCTAssertTrue(mockDiarization.prepareModelsCalled)
    }

    func testPrepareModelsThrowsWhenConfigured() async {
        mockDiarization.shouldThrow = true
        do {
            try await mockDiarization.prepareModels()
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is DiarizationError)
            XCTAssertTrue(mockDiarization.prepareModelsCalled)
        }
    }

    func testMockReset() async throws {
        mockDiarization.shouldThrow = true
        mockDiarization.prepareModelsCalled = true
        mockDiarization.diarizeCalled = true
        mockDiarization.mockSegments = [(speakerId: "x", start: 0, end: 1)]

        mockDiarization.reset()
        XCTAssertFalse(mockDiarization.shouldThrow)
        XCTAssertFalse(mockDiarization.prepareModelsCalled)
        XCTAssertFalse(mockDiarization.diarizeCalled)
        XCTAssertTrue(mockDiarization.mockSegments.isEmpty)
    }

    // MARK: - DiarizationError descriptions

    func testErrorDescriptions() {
        let errors: [DiarizationError] = [
            .modelPreparationFailed("test"),
            .diarizationFailed("test"),
            .notAppleSilicon,
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    // MARK: - Static helpers

    func testAreModelsOnDiskReturnsFalseWithoutModels() {
        XCTAssertFalse(DiarizationService.areModelsOnDisk())
    }

    func testAreModelsPreparedDefaultsFalse() {
        let service = DiarizationService()
        XCTAssertFalse(service.areModelsPrepared)
    }

    func testDiarizationConfigDoesNotForceSpeakerCount() {
        let config = DiarizationService.makeDiarizationConfig()
        XCTAssertNil(config.clustering.numSpeakers)
        XCTAssertNil(config.clustering.minSpeakers)
        XCTAssertNil(config.clustering.maxSpeakers)
    }

    func testDiarizationConfigUsesCommunityThreshold() {
        let config = DiarizationService.makeDiarizationConfig()
        XCTAssertEqual(config.clustering.threshold, 0.6, accuracy: 1e-9)
        XCTAssertEqual(config.clustering.warmStartFa, 0.07, accuracy: 1e-9)
        XCTAssertEqual(config.clustering.warmStartFb, 0.8, accuracy: 1e-9)
    }

    func testDiarizationConfigWithExactSpeakerCount() {
        let config = DiarizationService.makeDiarizationConfig(speakerCount: 5)
        XCTAssertEqual(config.clustering.numSpeakers, 5)
        XCTAssertEqual(config.clustering.threshold, 0.6, accuracy: 1e-9)
    }

    func testDiarizationConfigZeroSpeakerCountMeansAuto() {
        let config = DiarizationService.makeDiarizationConfig(speakerCount: 0)
        XCTAssertNil(config.clustering.numSpeakers)
    }
}
