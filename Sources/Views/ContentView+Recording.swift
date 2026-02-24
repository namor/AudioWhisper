import SwiftUI
import AppKit
import os.log

internal extension ContentView {
    func startRecording() {
        if !audioRecorder.hasPermission {
            permissionManager.requestPermissionWithEducation()
            return
        }

        if transcriptionProvider == .local {
            startWhisperModelDownloadIfNeeded(selectedWhisperModel)
        }
        
        lastAudioURL = nil
        
        let success = audioRecorder.startRecording()
        if success, liveTranscriptionProvider != .off, let stream = audioRecorder.audioDataStream {
            liveTranscriptionService.start(audioStream: stream, provider: liveTranscriptionProvider)
        }
        if !success {
            errorMessage = LocalizedStrings.Errors.failedToStartRecording
            showError = true
        }
    }
    
    func stopAndProcess() {
        liveTranscriptionService.stop()
        processingTask?.cancel()
        NotificationCenter.default.post(name: .recordingStopped, object: nil)
        
        let shouldHintThisRun = !hasShownFirstModelUseHint && isLocalModelInvocationPlanned()
        if shouldHintThisRun { showFirstModelUseHint = true }

        processingTask = Task {
            isProcessing = true
            transcriptionStartTime = Date()
            progressMessage = "Preparing audio..."
            
            do {
                try Task.checkCancellation()
                guard let audioURL = audioRecorder.stopRecording() else {
                    throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: LocalizedStrings.Errors.failedToGetRecordingURL])
                }
                let sessionDuration = audioRecorder.lastRecordingDuration
                
                guard !audioURL.path.isEmpty else {
                    throw NSError(domain: "AudioRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: LocalizedStrings.Errors.recordingURLEmpty])
                }
                
                lastAudioURL = audioURL
                try Task.checkCancellation()

                try await ensureModelReadyIfLocal()
                let result = try await transcribeWithPipeline(audioURL: audioURL)
                try Task.checkCancellation()

                let finalText = try await correctAndCommit(
                    result: result, duration: sessionDuration
                )

                transcriptionStartTime = nil
                showConfirmationAndPaste(text: finalText)
                dismissHintIfNeeded(shouldHintThisRun)
            } catch is CancellationError {
                resetProcessingState()
                dismissHintIfNeeded(shouldHintThisRun)
            } catch {
                handleTranscriptionError(error)
                dismissHintIfNeeded(shouldHintThisRun)
            }
        }
    }

    func transcribeExternalAudioFile(_ audioURL: URL) {
        processingTask?.cancel()

        let shouldHintThisRun = !hasShownFirstModelUseHint && isLocalModelInvocationPlanned()
        if shouldHintThisRun { showFirstModelUseHint = true }

        processingTask = Task {
            isProcessing = true
            transcriptionStartTime = Date()
            progressMessage = "Transcribing file..."

            do {
                try Task.checkCancellation()
                lastAudioURL = audioURL
                try Task.checkCancellation()

                try await ensureModelReadyIfLocal()
                let result = try await transcribeWithPipeline(audioURL: audioURL)
                try Task.checkCancellation()

                let estimatedDuration = Self.estimateDuration(for: audioURL)
                let finalText = try await correctAndCommit(
                    result: result, duration: estimatedDuration
                )

                transcriptionStartTime = nil
                showConfirmationAndPaste(text: finalText)
                dismissHintIfNeeded(shouldHintThisRun)
            } catch is CancellationError {
                resetProcessingState()
                dismissHintIfNeeded(shouldHintThisRun)
            } catch {
                handleTranscriptionError(error)
                dismissHintIfNeeded(shouldHintThisRun)
            }
        }
    }

    func retryLastTranscription() {
        guard !isProcessing else { return }
        
        guard let audioURL = lastAudioURL else {
            errorMessage = "No audio file available to retry. Please record again."
            showError = true
            return
        }
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            errorMessage = "Audio file no longer exists. Please record again."
            showError = true
            lastAudioURL = nil
            return
        }
        
        processingTask?.cancel()
        
        processingTask = Task {
            isProcessing = true
            transcriptionStartTime = Date()
            progressMessage = "Retrying transcription..."
            
            do {
                try Task.checkCancellation()

                try await ensureModelReadyIfLocal()
                let result = try await transcribeWithPipeline(audioURL: audioURL, isRetry: true)
                try Task.checkCancellation()

                if pipeline.shouldAwaitCorrectionForPaste(provider: transcriptionProvider) {
                    awaitingSemanticPaste = true
                    progressMessage = "Semantic correction..."

                    let capturedProvider = transcriptionProvider
                    let capturedModel: String? = (capturedProvider == .local)
                        ? selectedWhisperModel.rawValue : nil
                    let sourceInfo = currentSourceAppInfo()
                    let sourceBundleId = sourceInfo.bundleIdentifier
                    let speakerTurns = result.speakerTurns

                    Task.detached { [pipeline] in
                        let correction = await pipeline.applyCorrection(
                            text: result.text, provider: capturedProvider,
                            sourceAppBundleId: sourceBundleId
                        )
                        let corrected = correction.text
                        let metrics = await pipeline.commitResult(
                            text: corrected, provider: capturedProvider,
                            duration: nil, modelUsed: capturedModel,
                            sourceInfo: sourceInfo, speakerTurns: speakerTurns
                        )
                        await MainActor.run { [self] in
                            if let w = correction.warning { progressMessage = w }
                            UsageMetricsStore.shared.recordSession(
                                duration: nil, wordCount: metrics.wordCount,
                                characterCount: metrics.characterCount
                            )
                            recordSourceUsage(
                                words: metrics.wordCount,
                                characters: metrics.characterCount
                            )
                            transcriptionStartTime = nil
                            isProcessing = false
                            showConfirmationAndPaste(text: corrected)
                            if awaitingSemanticPaste {
                                performUserTriggeredPaste()
                                awaitingSemanticPaste = false
                            }
                        }
                    }
                } else {
                    transcriptionStartTime = nil
                    showConfirmationAndPaste(text: result.text)

                    let capturedProvider = transcriptionProvider
                    let capturedModel: String? = (capturedProvider == .local)
                        ? selectedWhisperModel.rawValue : nil
                    let sourceInfo = currentSourceAppInfo()
                    let sourceBundleId = sourceInfo.bundleIdentifier
                    let speakerTurns = result.speakerTurns

                    Task.detached { [pipeline] in
                        let correction = await pipeline.applyCorrection(
                            text: result.text, provider: capturedProvider,
                            sourceAppBundleId: sourceBundleId
                        )
                        let _ = await pipeline.commitResult(
                            text: correction.text, provider: capturedProvider,
                            duration: nil, modelUsed: capturedModel,
                            sourceInfo: sourceInfo, speakerTurns: speakerTurns
                        )
                    }
                }
            } catch is CancellationError {
                resetProcessingState()
            } catch {
                handleTranscriptionError(error)
            }
        }
    }

    // MARK: - Shared Pipeline Helpers

    /// Route transcription through the pipeline with progress updates.
    private func transcribeWithPipeline(
        audioURL: URL, isRetry: Bool = false
    ) async throws -> TranscriptionResult {
        let diarizationEnabled = UserDefaults.standard.bool(
            forKey: AppDefaults.Keys.diarizationEnabled
        )
        let useDiarization = diarizationEnabled && transcriptionProvider == .local

        if useDiarization {
            await MainActor.run {
                progressMessage = isRetry
                    ? "Retrying with speaker detection..."
                    : "Transcribing with speaker detection..."
            }
        }

        return try await pipeline.transcribe(
            audioURL: audioURL,
            provider: transcriptionProvider,
            model: (transcriptionProvider == .local) ? selectedWhisperModel : nil,
            diarizationEnabled: useDiarization
        )
    }

    /// Apply correction, commit to pasteboard/history, record metrics. Returns final text.
    private func correctAndCommit(
        result: TranscriptionResult,
        duration: TimeInterval?
    ) async throws -> String {
        try Task.checkCancellation()

        var finalText = result.text
        let sourceBundleId: String? = currentSourceAppInfo().bundleIdentifier
        if pipeline.isCorrectionEnabled {
            progressMessage = "Semantic correction..."
            let correction = await pipeline.applyCorrection(
                text: result.text, provider: transcriptionProvider,
                sourceAppBundleId: sourceBundleId
            )
            if let warning = correction.warning { progressMessage = warning }
            finalText = correction.text
        }

        let modelUsed: String? = (transcriptionProvider == .local)
            ? selectedWhisperModel.rawValue : nil
        let sourceInfo = currentSourceAppInfo()
        let metrics = await pipeline.commitResult(
            text: finalText,
            provider: transcriptionProvider,
            duration: duration,
            modelUsed: modelUsed,
            sourceInfo: sourceInfo,
            speakerTurns: result.speakerTurns
        )

        UsageMetricsStore.shared.recordSession(
            duration: duration ?? 0,
            wordCount: metrics.wordCount,
            characterCount: metrics.characterCount
        )
        recordSourceUsage(words: metrics.wordCount, characters: metrics.characterCount)

        return finalText
    }

    /// Ensure the local Whisper model is downloaded before transcription begins.
    private func ensureModelReadyIfLocal() async throws {
        guard transcriptionProvider == .local else { return }
        try await ensureWhisperModelIsReadyForTranscription(selectedWhisperModel)
    }

    // MARK: - Error Handling

    private func handleTranscriptionError(_ error: Error) {
        if case let SpeechToTextError.localTranscriptionFailed(inner) = error,
           let lwError = inner as? LocalWhisperError,
           lwError == .modelNotDownloaded {
            errorMessage = "Local Whisper model not downloaded. Opening Settings\u{2026}"
            showError = true
            isProcessing = false
            transcriptionStartTime = nil
            DashboardWindowManager.shared.showDashboardWindow(selectedNav: .providers)
        } else if let pe = error as? ParakeetError, pe == .modelNotReady {
            errorMessage = "Parakeet model not downloaded. Opening Settings\u{2026}"
            showError = true
            isProcessing = false
            transcriptionStartTime = nil
            DashboardWindowManager.shared.showDashboardWindow(selectedNav: .providers)
        } else {
            errorMessage = error.localizedDescription
            showError = true
            isProcessing = false
            transcriptionStartTime = nil
        }
    }

    private func resetProcessingState() {
        isProcessing = false
        transcriptionStartTime = nil
    }

    private func dismissHintIfNeeded(_ shouldHint: Bool) {
        guard shouldHint else { return }
        hasShownFirstModelUseHint = true
        showFirstModelUseHint = false
    }

    // MARK: - Utilities

    private static func estimateDuration(for audioURL: URL) -> TimeInterval {
        let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
        let fileSize = (attrs?[.size] as? Int64) ?? 0
        return TimeInterval(fileSize) / 16000.0
    }

    func showConfirmationAndPaste(text: String) {
        showSuccess = true
        isProcessing = false
        soundManager.playCompletionSound()
        
        let enableSmartPaste = UserDefaults.standard.bool(forKey: "enableSmartPaste")
        if enableSmartPaste {
            if !awaitingSemanticPaste {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    performUserTriggeredPaste()
                }
            }
        } else {
            NotificationCenter.default.post(name: .restoreFocusToPreviousApp, object: nil)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let recordWindow = NSApp.windows.first { window in
                    window.title == "AudioWhisper Recording"
                }
                
                if let window = recordWindow {
                    window.orderOut(nil)
                } else {
                    NSApplication.shared.keyWindow?.orderOut(nil)
                }
                
                NotificationCenter.default.post(name: .restoreFocusToPreviousApp, object: nil)
                showSuccess = false
            }
        }
    }
    
    func retryLastTranscriptionIfAvailable() {
        retryLastTranscription()
    }

    func showLastAudioFile() {
        guard let audioURL = lastAudioURL else {
            errorMessage = "No audio file available to show."
            showError = true
            return
        }
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            errorMessage = "Audio file no longer exists."
            showError = true
            lastAudioURL = nil
            return
        }
        
        NSWorkspace.shared.selectFile(audioURL.path, inFileViewerRootedAtPath: audioURL.deletingLastPathComponent().path)
    }
    
    private func isLocalModelInvocationPlanned() -> Bool {
        if transcriptionProvider == .local || transcriptionProvider == .parakeet { return true }
        let modeRaw = UserDefaults.standard.string(forKey: AppDefaults.Keys.semanticCorrectionMode) ?? SemanticCorrectionMode.off.rawValue
        let mode = SemanticCorrectionMode(rawValue: modeRaw) ?? .off
        if mode == .localMLX { return true }
        return false
    }

    func startWhisperModelDownloadIfNeeded(_ model: WhisperModel) {
        let onDisk = WhisperKitStorage.isModelDownloaded(model)
        if onDisk { return }
        guard !(modelManager.downloadStages[model]?.isActive ?? false) else { return }
        guard !modelManager.downloadingModels.contains(model) else { return }

        Logger.app.info("startWhisperModelDownloadIfNeeded: model \(model.rawValue) not on disk, triggering download")
        Task {
            do {
                try await modelManager.downloadModel(model)
                await modelManager.refreshModelStates()
            } catch {
                Logger.app.error("Background model download failed: \(error.localizedDescription)")
            }
        }
    }

    private func ensureWhisperModelIsReadyForTranscription(_ model: WhisperModel) async throws {
        if WhisperKitStorage.isModelDownloaded(model) { return }

        await MainActor.run {
            progressMessage = "Downloading \(model.displayName) model\u{2026}"
        }

        do {
            try await modelManager.downloadModel(model)
            await modelManager.refreshModelStates()
        } catch let err as ModelError where err == .alreadyDownloading {
            try await waitForWhisperModelDownload(model)
        }

        if !WhisperKitStorage.isModelDownloaded(model) {
            throw LocalWhisperError.modelNotDownloaded
        }
    }

    private func waitForWhisperModelDownload(_ model: WhisperModel) async throws {
        let timeout: TimeInterval = 20 * 60
        let startedAt = Date()
        var didRetry = false

        while true {
            try Task.checkCancellation()

            if WhisperKitStorage.isModelDownloaded(model) { return }

            if Date().timeIntervalSince(startedAt) > timeout {
                throw ModelError.downloadTimeout
            }

            let stage = await MainActor.run { modelManager.downloadStages[model] }
            if let stage {
                await MainActor.run {
                    switch stage {
                    case .preparing:
                        progressMessage = "Preparing \(model.displayName) model\u{2026}"
                    case .downloading:
                        progressMessage = "Downloading \(model.displayName) model\u{2026}"
                    case .processing:
                        progressMessage = "Processing \(model.displayName) model\u{2026}"
                    case .completing:
                        progressMessage = "Finalizing \(model.displayName) model\u{2026}"
                    case .ready:
                        progressMessage = "Model ready"
                    case .failed(let message):
                        progressMessage = "Download failed: \(message)"
                    }
                }

                if case .failed(let message) = stage {
                    throw SpeechToTextError.transcriptionFailed(message)
                }
            } else {
                if !didRetry {
                    didRetry = true
                    do {
                        try await modelManager.downloadModel(model)
                        continue
                    } catch { }
                }
                await MainActor.run {
                    progressMessage = "Downloading \(model.displayName) model\u{2026}"
                }
            }

            try await Task.sleep(for: .milliseconds(250))
        }
    }
}
