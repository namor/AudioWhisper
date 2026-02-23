import XCTest
@testable import AudioWhisper

final class DiarizationAlignmentTests: XCTestCase {

    // MARK: - Basic alignment

    func testAlignSingleSpeaker() {
        let asr: [(text: String, start: Float, end: Float)] = [
            (text: "Hello world", start: 0.0, end: 2.0),
            (text: "how are you", start: 2.0, end: 4.0),
        ]
        let diar: [(speakerId: String, start: TimeInterval, end: TimeInterval)] = [
            (speakerId: "spk_0", start: 0.0, end: 4.0),
        ]
        let turns = DiarizationService.align(asrSegments: asr, diarSegments: diar)

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].speakerId, "Speaker 1")
        XCTAssertTrue(turns[0].text.contains("Hello world"))
        XCTAssertTrue(turns[0].text.contains("how are you"))
        XCTAssertEqual(turns[0].start, 0.0, accuracy: 0.01)
        XCTAssertEqual(turns[0].end, 4.0, accuracy: 0.01)
    }

    func testAlignTwoSpeakers() {
        let asr: [(text: String, start: Float, end: Float)] = [
            (text: "Hi there", start: 0.0, end: 1.5),
            (text: "Hello", start: 1.5, end: 3.0),
            (text: "Nice to meet you", start: 3.0, end: 5.0),
        ]
        let diar: [(speakerId: String, start: TimeInterval, end: TimeInterval)] = [
            (speakerId: "spk_0", start: 0.0, end: 2.0),
            (speakerId: "spk_1", start: 2.0, end: 5.0),
        ]
        let turns = DiarizationService.align(asrSegments: asr, diarSegments: diar)

        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].speakerId, "Speaker 1")
        XCTAssertEqual(turns[1].speakerId, "Speaker 2")
    }

    func testAlignMergesContiguousSameSpeaker() {
        let asr: [(text: String, start: Float, end: Float)] = [
            (text: "A", start: 0.0, end: 1.0),
            (text: "B", start: 1.0, end: 2.0),
            (text: "C", start: 2.0, end: 3.0),
        ]
        let diar: [(speakerId: String, start: TimeInterval, end: TimeInterval)] = [
            (speakerId: "spk_0", start: 0.0, end: 3.0),
        ]
        let turns = DiarizationService.align(asrSegments: asr, diarSegments: diar)

        XCTAssertEqual(turns.count, 1)
        XCTAssertTrue(turns[0].text.contains("A"))
        XCTAssertTrue(turns[0].text.contains("B"))
        XCTAssertTrue(turns[0].text.contains("C"))
    }

    // MARK: - Edge cases

    func testAlignEmptyASRSegments() {
        let diar: [(speakerId: String, start: TimeInterval, end: TimeInterval)] = [
            (speakerId: "spk_0", start: 0.0, end: 5.0),
        ]
        let turns = DiarizationService.align(asrSegments: [], diarSegments: diar)
        XCTAssertTrue(turns.isEmpty)
    }

    func testAlignEmptyDiarizationSegments() {
        let asr: [(text: String, start: Float, end: Float)] = [
            (text: "Hello", start: 0.0, end: 1.0),
        ]
        let turns = DiarizationService.align(asrSegments: asr, diarSegments: [])
        XCTAssertTrue(turns.isEmpty)
    }

    func testAlignSpeakerRenumberedByFirstAppearance() {
        let asr: [(text: String, start: Float, end: Float)] = [
            (text: "A", start: 0.0, end: 2.0),
            (text: "B", start: 2.0, end: 4.0),
        ]
        let diar: [(speakerId: String, start: TimeInterval, end: TimeInterval)] = [
            (speakerId: "spk_2", start: 0.0, end: 2.0),
            (speakerId: "spk_0", start: 2.0, end: 4.0),
        ]
        let turns = DiarizationService.align(asrSegments: asr, diarSegments: diar)

        XCTAssertEqual(turns[0].speakerId, "Speaker 1")
        XCTAssertEqual(turns[1].speakerId, "Speaker 2")
    }

    func testAlignPartialOverlap() {
        let asr: [(text: String, start: Float, end: Float)] = [
            (text: "First part", start: 0.0, end: 1.0),
            (text: "Overlap", start: 1.0, end: 3.0),
        ]
        let diar: [(speakerId: String, start: TimeInterval, end: TimeInterval)] = [
            (speakerId: "spk_0", start: 0.0, end: 1.5),
            (speakerId: "spk_1", start: 1.5, end: 4.0),
        ]
        let turns = DiarizationService.align(asrSegments: asr, diarSegments: diar)

        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].speakerId, "Speaker 1") // spk_0 appears first
        // spk_1 overlap with "Overlap": 1.5s vs spk_0 overlap: 0.5s
        XCTAssertEqual(turns[1].speakerId, "Speaker 2")
    }

    func testAlignSpeakerAlternation() {
        let asr: [(text: String, start: Float, end: Float)] = [
            (text: "First", start: 0.0, end: 1.0),
            (text: "Second", start: 1.0, end: 2.0),
            (text: "Third", start: 2.0, end: 3.0),
        ]
        let diar: [(speakerId: String, start: TimeInterval, end: TimeInterval)] = [
            (speakerId: "spk_0", start: 0.0, end: 1.0),
            (speakerId: "spk_1", start: 1.0, end: 2.0),
            (speakerId: "spk_0", start: 2.0, end: 3.0),
        ]
        let turns = DiarizationService.align(asrSegments: asr, diarSegments: diar)

        XCTAssertEqual(turns.count, 3)
        XCTAssertEqual(turns[0].speakerId, turns[2].speakerId)
        XCTAssertNotEqual(turns[0].speakerId, turns[1].speakerId)
    }

    func testAlignBothEmpty() {
        let turns = DiarizationService.align(
            asrSegments: [] as [(text: String, start: Float, end: Float)],
            diarSegments: [] as [(speakerId: String, start: TimeInterval, end: TimeInterval)]
        )
        XCTAssertTrue(turns.isEmpty)
    }

    func testAlignNoOverlapUsesNearestSegment() {
        let asr: [(text: String, start: Float, end: Float)] = [
            (text: "Gap speech", start: 5.0, end: 6.0),
        ]
        let diar: [(speakerId: String, start: TimeInterval, end: TimeInterval)] = [
            (speakerId: "spk_0", start: 0.0, end: 2.0),
            (speakerId: "spk_1", start: 8.0, end: 10.0),
        ]
        let turns = DiarizationService.align(asrSegments: asr, diarSegments: diar)

        XCTAssertEqual(turns.count, 1)
        // ASR midpoint 5.5 is closer to spk_0 midpoint (1.0) than spk_1 midpoint (9.0)
        XCTAssertEqual(turns[0].speakerId, "Speaker 1")
    }

    func testAlignNoOverlapNearerToSecondSpeaker() {
        let asr: [(text: String, start: Float, end: Float)] = [
            (text: "Gap speech", start: 7.0, end: 8.0),
        ]
        let diar: [(speakerId: String, start: TimeInterval, end: TimeInterval)] = [
            (speakerId: "spk_0", start: 0.0, end: 2.0),
            (speakerId: "spk_1", start: 8.0, end: 10.0),
        ]
        let turns = DiarizationService.align(asrSegments: asr, diarSegments: diar)

        XCTAssertEqual(turns.count, 1)
        // ASR midpoint 7.5 is closer to spk_1 midpoint (9.0) than spk_0 midpoint (1.0)
        XCTAssertEqual(turns[0].speakerId, "Speaker 1")
        XCTAssertEqual(turns[0].text, "Gap speech")
    }

    // MARK: - Performance

    func testAlignPerformanceWithManySegments() {
        let asr: [(text: String, start: Float, end: Float)] = (0..<1000).map { i in
            (text: "Segment \(i)", start: Float(i), end: Float(i + 1))
        }
        let diar: [(speakerId: String, start: TimeInterval, end: TimeInterval)] = (0..<500).map { i in
            (speakerId: "spk_\(i % 5)", start: TimeInterval(i * 2), end: TimeInterval(i * 2 + 2))
        }
        measure {
            _ = DiarizationService.align(asrSegments: asr, diarSegments: diar)
        }
    }
}
