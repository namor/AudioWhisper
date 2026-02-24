import XCTest
import Foundation
@testable import AudioWhisper

final class TranscriptionPipelineTests: XCTestCase {
    private var mockKeychain: MockKeychainService!
    private var pipeline: TranscriptionPipeline!

    override func setUp() {
        super.setUp()
        mockKeychain = MockKeychainService()
        let speechService = SpeechToTextService(keychainService: mockKeychain)
        pipeline = TranscriptionPipeline(speechService: speechService)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppDefaults.Keys.semanticCorrectionMode)
        UserDefaults.standard.removeObject(forKey: "enableSmartPaste")
        pipeline = nil
        mockKeychain = nil
        super.tearDown()
    }

    // MARK: - isCorrectionEnabled

    func testIsCorrectionEnabledReturnsFalseWhenOff() {
        UserDefaults.standard.set(
            SemanticCorrectionMode.off.rawValue,
            forKey: AppDefaults.Keys.semanticCorrectionMode
        )

        XCTAssertFalse(pipeline.isCorrectionEnabled)
    }

    func testIsCorrectionEnabledReturnsTrueForLocalMLX() {
        UserDefaults.standard.set(
            SemanticCorrectionMode.localMLX.rawValue,
            forKey: AppDefaults.Keys.semanticCorrectionMode
        )

        XCTAssertTrue(pipeline.isCorrectionEnabled)
    }

    func testIsCorrectionEnabledReturnsTrueForCloud() {
        UserDefaults.standard.set(
            SemanticCorrectionMode.cloud.rawValue,
            forKey: AppDefaults.Keys.semanticCorrectionMode
        )

        XCTAssertTrue(pipeline.isCorrectionEnabled)
    }

    func testIsCorrectionEnabledReturnsFalseForMissingDefault() {
        UserDefaults.standard.removeObject(forKey: AppDefaults.Keys.semanticCorrectionMode)

        XCTAssertFalse(pipeline.isCorrectionEnabled)
    }

    // MARK: - shouldAwaitCorrectionForPaste

    func testShouldAwaitCorrectionForPasteWhenSmartPasteOff() {
        UserDefaults.standard.set(false, forKey: "enableSmartPaste")
        UserDefaults.standard.set(
            SemanticCorrectionMode.localMLX.rawValue,
            forKey: AppDefaults.Keys.semanticCorrectionMode
        )

        XCTAssertFalse(pipeline.shouldAwaitCorrectionForPaste(provider: .openai))
    }

    func testShouldAwaitCorrectionForLocalMLXWithSmartPaste() {
        UserDefaults.standard.set(true, forKey: "enableSmartPaste")
        UserDefaults.standard.set(
            SemanticCorrectionMode.localMLX.rawValue,
            forKey: AppDefaults.Keys.semanticCorrectionMode
        )

        XCTAssertTrue(pipeline.shouldAwaitCorrectionForPaste(provider: .openai))
        XCTAssertTrue(pipeline.shouldAwaitCorrectionForPaste(provider: .local))
        XCTAssertTrue(pipeline.shouldAwaitCorrectionForPaste(provider: .parakeet))
    }

    func testShouldAwaitCorrectionForCloudWithCloudProviders() {
        UserDefaults.standard.set(true, forKey: "enableSmartPaste")
        UserDefaults.standard.set(
            SemanticCorrectionMode.cloud.rawValue,
            forKey: AppDefaults.Keys.semanticCorrectionMode
        )

        XCTAssertTrue(pipeline.shouldAwaitCorrectionForPaste(provider: .openai))
        XCTAssertTrue(pipeline.shouldAwaitCorrectionForPaste(provider: .gemini))
        XCTAssertFalse(pipeline.shouldAwaitCorrectionForPaste(provider: .local))
        XCTAssertFalse(pipeline.shouldAwaitCorrectionForPaste(provider: .parakeet))
    }

    func testShouldAwaitCorrectionWhenCorrectionOff() {
        UserDefaults.standard.set(true, forKey: "enableSmartPaste")
        UserDefaults.standard.set(
            SemanticCorrectionMode.off.rawValue,
            forKey: AppDefaults.Keys.semanticCorrectionMode
        )

        XCTAssertFalse(pipeline.shouldAwaitCorrectionForPaste(provider: .openai))
    }

    // MARK: - applyCorrection (when off)

    func testApplyCorrectionPassesThroughWhenOff() async {
        UserDefaults.standard.set(
            SemanticCorrectionMode.off.rawValue,
            forKey: AppDefaults.Keys.semanticCorrectionMode
        )

        let result = await pipeline.applyCorrection(
            text: "hello world", provider: .openai, sourceAppBundleId: nil
        )

        XCTAssertEqual(result.text, "hello world")
        XCTAssertNil(result.warning)
    }

    // MARK: - transcribe routing

    func testTranscribeOpenAIRequiresAPIKey() async {
        do {
            _ = try await pipeline.transcribe(
                audioURL: URL(fileURLWithPath: "/tmp/test.wav"),
                provider: .openai, model: nil, diarizationEnabled: false
            )
            XCTFail("Expected error")
        } catch let error as SpeechToTextError {
            if case .apiKeyMissing = error {
                // Expected
            } else if case .transcriptionFailed = error {
                // Also acceptable (validation may fail first)
            } else {
                XCTFail("Unexpected error variant: \(error)")
            }
        } catch {
            // Audio validation errors are acceptable for a non-audio file
        }
    }

    func testTranscribeLocalRequiresModel() async {
        do {
            _ = try await pipeline.transcribe(
                audioURL: URL(fileURLWithPath: "/tmp/test.wav"),
                provider: .local, model: nil, diarizationEnabled: false
            )
            XCTFail("Expected error for missing model")
        } catch let error as SpeechToTextError {
            if case .transcriptionFailed(let msg) = error {
                XCTAssertTrue(msg.contains("Whisper model required"))
            } else {
                XCTFail("Unexpected error variant: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - commitResult

    @MainActor
    func testCommitResultReturnCorrectMetrics() async {
        UserDefaults.standard.set(false, forKey: AppDefaults.Keys.transcriptionHistoryEnabled)

        let sourceInfo = SourceAppInfo.unknown
        let metrics = await pipeline.commitResult(
            text: "one two three four five",
            provider: .openai,
            duration: 5.0,
            modelUsed: nil,
            sourceInfo: sourceInfo,
            speakerTurns: nil
        )

        XCTAssertEqual(metrics.wordCount, 5)
        XCTAssertEqual(metrics.characterCount, 23)
    }

    @MainActor
    func testCommitResultSetsPasteboard() async {
        UserDefaults.standard.set(false, forKey: AppDefaults.Keys.transcriptionHistoryEnabled)

        let _ = await pipeline.commitResult(
            text: "paste this text",
            provider: .local,
            duration: nil,
            modelUsed: "base",
            sourceInfo: SourceAppInfo.unknown,
            speakerTurns: nil
        )

        let pasteboardContent = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(pasteboardContent, "paste this text")
    }
}
