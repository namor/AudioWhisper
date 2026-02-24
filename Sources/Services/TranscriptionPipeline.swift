import Foundation
import AppKit
import os.log

internal struct TranscriptionResult {
    let text: String
    let speakerTurns: [SpeakerTurn]?
}

/// Encapsulates the post-recording transcription pipeline: STT routing, semantic
/// correction, and result persistence. Eliminates duplication across the three
/// entry points in ContentView+Recording (stop, external file, retry).
internal final class TranscriptionPipeline {
    let speechService: SpeechToTextService
    let correctionService: SemanticCorrectionService

    init(
        speechService: SpeechToTextService,
        correctionService: SemanticCorrectionService = SemanticCorrectionService()
    ) {
        self.speechService = speechService
        self.correctionService = correctionService
    }

    // MARK: - Transcription

    func transcribe(
        audioURL: URL,
        provider: TranscriptionProvider,
        model: WhisperModel?,
        diarizationEnabled: Bool
    ) async throws -> TranscriptionResult {
        if provider == .local {
            guard let model else {
                throw SpeechToTextError.transcriptionFailed(
                    "Whisper model required for local transcription"
                )
            }
            if diarizationEnabled {
                let result = try await speechService.transcribeRawWithDiarization(
                    audioURL: audioURL, model: model
                ) { progress in
                    NotificationCenter.default.post(
                        name: .transcriptionProgress, object: progress
                    )
                }
                return TranscriptionResult(
                    text: result.text, speakerTurns: result.speakerTurns
                )
            }
            let text = try await speechService.transcribeRaw(
                audioURL: audioURL, provider: provider, model: model
            )
            return TranscriptionResult(text: text, speakerTurns: nil)
        }

        let text = try await speechService.transcribeRaw(
            audioURL: audioURL, provider: provider
        )
        return TranscriptionResult(text: text, speakerTurns: nil)
    }

    // MARK: - Semantic Correction

    func applyCorrection(
        text: String,
        provider: TranscriptionProvider,
        sourceAppBundleId: String?
    ) async -> (text: String, warning: String?) {
        guard isCorrectionEnabled else { return (text, nil) }

        let outcome = await correctionService.correctWithWarning(
            text: text, providerUsed: provider,
            sourceAppBundleId: sourceAppBundleId
        )
        let trimmed = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? text : outcome.text, outcome.warning)
    }

    var isCorrectionEnabled: Bool {
        let raw = UserDefaults.standard.string(
            forKey: AppDefaults.Keys.semanticCorrectionMode
        ) ?? SemanticCorrectionMode.off.rawValue
        return (SemanticCorrectionMode(rawValue: raw) ?? .off) != .off
    }

    /// Whether SmartPaste should block until correction finishes.
    func shouldAwaitCorrectionForPaste(
        provider: TranscriptionProvider
    ) -> Bool {
        let smartPaste = UserDefaults.standard.bool(forKey: "enableSmartPaste")
        guard smartPaste, isCorrectionEnabled else { return false }
        let raw = UserDefaults.standard.string(
            forKey: AppDefaults.Keys.semanticCorrectionMode
        ) ?? SemanticCorrectionMode.off.rawValue
        let mode = SemanticCorrectionMode(rawValue: raw) ?? .off
        switch mode {
        case .localMLX: return true
        case .cloud: return provider == .openai || provider == .gemini
        case .off: return false
        }
    }

    // MARK: - Commit (pasteboard + history + metrics)

    @MainActor
    func commitResult(
        text: String,
        provider: TranscriptionProvider,
        duration: TimeInterval?,
        modelUsed: String?,
        sourceInfo: SourceAppInfo,
        speakerTurns: [SpeakerTurn]?
    ) async -> (wordCount: Int, characterCount: Int) {
        let wordCount = UsageMetricsStore.estimatedWordCount(for: text)
        let characterCount = text.count

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        if DataManager.shared.isHistoryEnabled {
            let record = TranscriptionRecord(
                text: text,
                provider: provider,
                duration: duration,
                modelUsed: modelUsed,
                wordCount: wordCount,
                characterCount: characterCount,
                sourceAppBundleId: sourceInfo.bundleIdentifier,
                sourceAppName: sourceInfo.displayName,
                sourceAppIconData: sourceInfo.iconData,
                speakerTurns: speakerTurns
            )
            await DataManager.shared.saveTranscriptionQuietly(record)
        }

        return (wordCount, characterCount)
    }
}
