import Foundation
import Observation
import os.log
import FluidAudio

@Observable
@MainActor
internal final class FluidAudioModelManager {
    static let shared = FluidAudioModelManager()
    
    var isDownloaded: Bool = false
    var isDownloading: Bool = false
    var downloadProgress: String = ""
    
    private let logger = Logger(subsystem: "com.audiowhisper.app", category: "FluidAudioModelManager")
    
    private init() {
        Task {
            await checkStatus()
        }
    }
    
    func checkStatus() async {
        let exists = AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3)
        await MainActor.run {
            self.isDownloaded = exists
        }
    }
    
    func downloadModel() async {
        guard !isDownloading else { return }
        
        await MainActor.run {
            isDownloading = true
            downloadProgress = "Downloading Parakeet TDT v3..."
        }
        
        do {
            logger.info("Starting FluidAudio model download")
            
            // Perform the download in a background task
            try await Task.detached(priority: .userInitiated) {
                // The force parameter is false, so it skips if already exists
                _ = try await AsrModels.download(force: true, version: .v3)
            }.value
            
            await MainActor.run {
                isDownloading = false
                downloadProgress = ""
                isDownloaded = true
            }
            logger.info("FluidAudio model download completed")
        } catch {
            logger.error("FluidAudio model download failed: \(error.localizedDescription)")
            await MainActor.run {
                isDownloading = false
                downloadProgress = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    func deleteModel() async {
        let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
        let parentDir = cacheDir.deletingLastPathComponent()
        
        do {
            if FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.removeItem(at: parentDir)
                logger.info("Deleted FluidAudio models at \(parentDir.path)")
            }
            
            await MainActor.run {
                isDownloaded = false
                downloadProgress = ""
            }
            
            // Re-check just to be sure
            await checkStatus()
        } catch {
            logger.error("Failed to delete FluidAudio models: \(error.localizedDescription)")
        }
    }
}
