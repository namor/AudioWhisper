import XCTest
import SwiftData
@testable import AudioWhisper

final class TranscriptionRecordTests: XCTestCase {
    
    func testTranscriptionRecordInitialization() {
        // Test basic initialization
        let record = TranscriptionRecord(
            text: "Hello, world!",
            provider: .openai,
            duration: 5.5,
            modelUsed: "whisper-1"
        )
        
        XCTAssertEqual(record.text, "Hello, world!")
        XCTAssertEqual(record.provider, "openai")
        XCTAssertEqual(record.duration, 5.5)
        XCTAssertEqual(record.modelUsed, "whisper-1")
        XCTAssertNotNil(record.id)
        XCTAssertNotNil(record.date)
    }
    
    func testTranscriptionRecordWithAllProviders() {
        // Test that all TranscriptionProvider cases work
        for provider in TranscriptionProvider.allCases {
            let record = TranscriptionRecord(
                text: "Test transcription",
                provider: provider
            )
            
            XCTAssertEqual(record.provider, provider.rawValue)
            XCTAssertEqual(record.transcriptionProvider, provider)
        }
    }
    
    func testTranscriptionRecordWithWhisperModels() {
        // Test that all WhisperModel cases work
        for model in WhisperModel.allCases {
            let record = TranscriptionRecord(
                text: "Test transcription",
                provider: .local,
                modelUsed: model.rawValue
            )
            
            XCTAssertEqual(record.modelUsed, model.rawValue)
            XCTAssertEqual(record.whisperModel, model)
        }
    }
    
    func testFormattedDateIsNotEmpty() {
        let record = TranscriptionRecord(
            text: "Test",
            provider: .openai
        )
        
        XCTAssertFalse(record.formattedDate.isEmpty)
    }
    
    func testFormattedDurationFormatting() {
        // Test short duration (less than 1 minute)
        let shortRecord = TranscriptionRecord(
            text: "Short",
            provider: .openai,
            duration: 30.5
        )
        XCTAssertEqual(shortRecord.formattedDuration, "30.5s")
        
        // Test medium duration (minutes)
        let mediumRecord = TranscriptionRecord(
            text: "Medium",
            provider: .openai,
            duration: 125.0 // 2 minutes 5 seconds
        )
        XCTAssertEqual(mediumRecord.formattedDuration, "2m 5s")
        
        // Test long duration (hours)
        let longRecord = TranscriptionRecord(
            text: "Long",
            provider: .openai,
            duration: 3900.0 // 1 hour 5 minutes
        )
        XCTAssertEqual(longRecord.formattedDuration, "1h 5m")
        
        // Test nil duration
        let noDurationRecord = TranscriptionRecord(
            text: "No duration",
            provider: .openai
        )
        XCTAssertNil(noDurationRecord.formattedDuration)
    }
    
    func testPreviewTextTruncation() {
        // Test short text (no truncation)
        let shortRecord = TranscriptionRecord(
            text: "Short text",
            provider: .openai
        )
        XCTAssertEqual(shortRecord.preview, "Short text")
        
        // Test long text (should be truncated)
        let longText = String(repeating: "a", count: 150)
        let longRecord = TranscriptionRecord(
            text: longText,
            provider: .openai
        )
        XCTAssertTrue(longRecord.preview.hasSuffix("..."))
        XCTAssertTrue(longRecord.preview.count < longText.count)
    }
    
    func testSearchMatching() {
        let record = TranscriptionRecord(
            text: "This is a test transcription about Swift programming",
            provider: .openai,
            modelUsed: "whisper-1"
        )
        
        // Test text matching
        XCTAssertTrue(record.matches(searchQuery: "Swift"))
        XCTAssertTrue(record.matches(searchQuery: "swift")) // Case insensitive
        XCTAssertTrue(record.matches(searchQuery: "test"))
        
        // Test provider matching
        XCTAssertTrue(record.matches(searchQuery: "openai"))
        XCTAssertTrue(record.matches(searchQuery: "OpenAI")) // Case insensitive
        
        // Test model matching
        XCTAssertTrue(record.matches(searchQuery: "whisper"))
        
        // Test no match
        XCTAssertFalse(record.matches(searchQuery: "Python"))
        
        // Test empty query (should match all)
        XCTAssertTrue(record.matches(searchQuery: ""))
    }
    
    func testTranscriptionProviderComputed() {
        // Test valid provider
        let validRecord = TranscriptionRecord(
            text: "Test",
            provider: .gemini
        )
        XCTAssertEqual(validRecord.transcriptionProvider, .gemini)
        
        // Test invalid provider (should return nil)
        let invalidRecord = TranscriptionRecord(
            text: "Test",
            provider: .openai
        )
        // Manually set an invalid provider to test edge case
        invalidRecord.provider = "invalid_provider"
        XCTAssertNil(invalidRecord.transcriptionProvider)
    }
    
    func testWhisperModelComputed() {
        // Test valid model
        let validRecord = TranscriptionRecord(
            text: "Test",
            provider: .local,
            modelUsed: WhisperModel.small.rawValue
        )
        XCTAssertEqual(validRecord.whisperModel, .small)
        
        // Test invalid model (should return nil)
        let invalidRecord = TranscriptionRecord(
            text: "Test",
            provider: .local,
            modelUsed: "invalid_model"
        )
        XCTAssertNil(invalidRecord.whisperModel)
        
        // Test no model (should return nil)
        let noModelRecord = TranscriptionRecord(
            text: "Test",
            provider: .openai
        )
        XCTAssertNil(noModelRecord.whisperModel)
    }

    // MARK: - Speaker Turn Encoding

    func testSpeakerTurnsRoundTrip() {
        let turns = [
            SpeakerTurn(speakerId: "Speaker 1", displayName: "Alice", start: 0.0, end: 2.5, text: "Hello"),
            SpeakerTurn(speakerId: "Speaker 2", displayName: nil, start: 2.5, end: 5.0, text: "Hi there"),
        ]
        let record = TranscriptionRecord(text: "Hello Hi there", provider: .local, speakerTurns: turns)

        XCTAssertNotNil(record.speakerTurnsData)
        XCTAssertEqual(record.numSpeakers, 2)

        let decoded = record.speakerTurns
        XCTAssertEqual(decoded?.count, 2)
        XCTAssertEqual(decoded?[0].displayName, "Alice")
        XCTAssertEqual(decoded?[1].text, "Hi there")
    }

    func testSpeakerTurnsNilByDefault() {
        let record = TranscriptionRecord(text: "Plain text", provider: .openai)
        XCTAssertNil(record.speakerTurnsData)
        XCTAssertNil(record.numSpeakers)
        XCTAssertNil(record.speakerTurns)
    }

    func testSpeakerTurnsSetterUpdatesNumSpeakers() {
        let record = TranscriptionRecord(text: "Test", provider: .local)
        record.speakerTurns = [
            SpeakerTurn(speakerId: "Speaker 1", start: 0, end: 1, text: "A"),
            SpeakerTurn(speakerId: "Speaker 2", start: 1, end: 2, text: "B"),
            SpeakerTurn(speakerId: "Speaker 1", start: 2, end: 3, text: "C"),
        ]
        XCTAssertEqual(record.numSpeakers, 2)
    }

    func testSpeakerTurnsClearable() {
        let record = TranscriptionRecord(text: "Test", provider: .local, speakerTurns: [
            SpeakerTurn(speakerId: "Speaker 1", start: 0, end: 1, text: "A"),
        ])
        XCTAssertNotNil(record.speakerTurns)

        record.speakerTurns = nil
        XCTAssertNil(record.speakerTurnsData)
        XCTAssertNil(record.numSpeakers)
    }
}