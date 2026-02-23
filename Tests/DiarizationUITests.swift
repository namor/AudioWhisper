import XCTest
import SwiftUI
import SwiftData
@testable import AudioWhisper

@MainActor
final class DiarizationUITests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        modelContainer = try ModelContainer(
            for: TranscriptionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        modelContext = ModelContext(modelContainer)
    }

    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
        try await super.tearDown()
    }

    // MARK: - History detail rendering

    func testRecordWithSpeakerTurnsHasTurns() throws {
        let turns = [
            SpeakerTurn(speakerId: "Speaker 1", start: 0.0, end: 2.0, text: "Hello"),
            SpeakerTurn(speakerId: "Speaker 2", start: 2.0, end: 4.0, text: "Hi"),
        ]
        let record = TranscriptionRecord(
            text: "Hello Hi", provider: .local,
            duration: 4.0, speakerTurns: turns
        )
        modelContext.insert(record)
        try modelContext.save()

        XCTAssertNotNil(record.speakerTurns)
        XCTAssertEqual(record.speakerTurns?.count, 2)
        XCTAssertEqual(record.numSpeakers, 2)
    }

    func testRecordWithoutSpeakerTurnsIsNil() throws {
        let record = TranscriptionRecord(text: "Plain", provider: .openai)
        modelContext.insert(record)
        try modelContext.save()

        XCTAssertNil(record.speakerTurns)
        XCTAssertNil(record.numSpeakers)
    }

    // MARK: - Copy with speakers formatting

    func testCopyWithSpeakersFormat() {
        let turns = [
            SpeakerTurn(speakerId: "Speaker 1", displayName: "Alice", start: 0.0, end: 2.0, text: "Hello"),
            SpeakerTurn(speakerId: "Speaker 2", displayName: nil, start: 2.0, end: 4.0, text: "Hi there"),
        ]
        let formatted = formatWithSpeakers(turns)
        XCTAssertEqual(formatted, "Alice: Hello\nSpeaker 2: Hi there")
    }

    func testCopyWithSpeakersEmptyTurns() {
        let turns: [SpeakerTurn] = []
        let formatted = formatWithSpeakers(turns)
        XCTAssertEqual(formatted, "")
    }

    // MARK: - Diarization toggle state

    func testDiarizationDefaultDisabled() {
        UserDefaults.standard.removeObject(forKey: AppDefaults.Keys.diarizationEnabled)
        AppDefaults.register()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppDefaults.Keys.diarizationEnabled))
    }

    // MARK: - Persistence round-trip through SwiftData

    func testSpeakerTurnsPersistThroughSwiftData() throws {
        let turns = [
            SpeakerTurn(speakerId: "Speaker 1", displayName: "Bob", start: 0, end: 5, text: "Hello"),
            SpeakerTurn(speakerId: "Speaker 2", start: 5, end: 10, text: "World"),
        ]
        let record = TranscriptionRecord(text: "Hello World", provider: .local, speakerTurns: turns)
        modelContext.insert(record)
        try modelContext.save()

        let descriptor = FetchDescriptor<TranscriptionRecord>()
        let fetched = try modelContext.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)

        let fetchedRecord = fetched[0]
        XCTAssertEqual(fetchedRecord.numSpeakers, 2)
        let fetchedTurns = fetchedRecord.speakerTurns
        XCTAssertNotNil(fetchedTurns)
        XCTAssertEqual(fetchedTurns?.count, 2)
        XCTAssertEqual(fetchedTurns?[0].displayName, "Bob")
        XCTAssertEqual(fetchedTurns?[1].text, "World")
    }
}
