import XCTest
@testable import AudioWhisper

final class SpeakerTurnTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let turn = SpeakerTurn(speakerId: "Speaker 1", displayName: "Bob", start: 1.5, end: 3.7, text: "Test text")
        let data = try JSONEncoder().encode(turn)
        let decoded = try JSONDecoder().decode(SpeakerTurn.self, from: data)
        XCTAssertEqual(turn, decoded)
    }

    func testCodableArrayRoundTrip() throws {
        let turns = [
            SpeakerTurn(speakerId: "Speaker 1", start: 0, end: 1, text: "A"),
            SpeakerTurn(speakerId: "Speaker 2", displayName: "Eve", start: 1, end: 2, text: "B"),
        ]
        let data = try JSONEncoder().encode(turns)
        let decoded = try JSONDecoder().decode([SpeakerTurn].self, from: data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[1].displayName, "Eve")
    }

    func testCodableNilDisplayName() throws {
        let turn = SpeakerTurn(speakerId: "Speaker 1", start: 0, end: 1, text: "A")
        let data = try JSONEncoder().encode(turn)
        let decoded = try JSONDecoder().decode(SpeakerTurn.self, from: data)
        XCTAssertNil(decoded.displayName)
        XCTAssertEqual(decoded.speakerId, "Speaker 1")
    }

    func testHashableForSets() {
        let a = SpeakerTurn(speakerId: "S1", start: 0, end: 1, text: "A")
        let b = SpeakerTurn(speakerId: "S1", start: 0, end: 1, text: "A")
        let c = SpeakerTurn(speakerId: "S2", start: 0, end: 1, text: "A")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(Set([a, b]).count, 1)
    }
}
