import Foundation

internal enum WhisperKitStorage {
    // WhisperKit downloads CoreML bundles into a model folder. During download, the folder may exist with
    // partial contents (e.g. config JSON), so "is downloaded" must check for the required CoreML bundles
    // and tokenizer artifacts rather than any single file extension.
    private static let requiredCoreMLBundles = [
        "AudioEncoder.mlmodelc",
        "MelSpectrogram.mlmodelc",
        "TextDecoder.mlmodelc",
    ]

    private static func baseDirectory(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml", isDirectory: true)
    }

    static func storageDirectory(fileManager: FileManager = .default) -> URL? {
        baseDirectory(fileManager: fileManager)
    }

    static func modelDirectory(for model: WhisperModel, fileManager: FileManager = .default) -> URL? {
        baseDirectory(fileManager: fileManager)?
            .appendingPathComponent(model.whisperKitModelName, isDirectory: true)
    }

    static func isModelDownloaded(_ model: WhisperModel, fileManager: FileManager = .default) -> Bool {
        guard let modelDirectory = modelDirectory(for: model, fileManager: fileManager) else { return false }

        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: modelDirectory.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else { return false }

        let requiredFiles = ["config.json", "generation_config.json"]
        for file in requiredFiles {
            if !fileManager.fileExists(atPath: modelDirectory.appendingPathComponent(file).path) {
                return false
            }
        }

        // WhisperKit 0.15+ compiles CoreML bundles with coremldata.bin as a sentinel
        // for each required model component.
        for bundle in requiredCoreMLBundles {
            let bundleURL = modelDirectory.appendingPathComponent(bundle, isDirectory: true)
            var isBundleDir: ObjCBool = false
            guard fileManager.fileExists(atPath: bundleURL.path, isDirectory: &isBundleDir),
                  isBundleDir.boolValue else {
                return false
            }

            let sentinel = bundleURL.appendingPathComponent("coremldata.bin")
            if !fileManager.fileExists(atPath: sentinel.path) {
                return false
            }
        }

        return true
    }

    static func localModelPath(for model: WhisperModel, fileManager: FileManager = .default) -> String? {
        guard isModelDownloaded(model, fileManager: fileManager),
              let url = modelDirectory(for: model, fileManager: fileManager) else {
            return nil
        }
        return url.path
    }

    static func ensureBaseDirectoryExists(fileManager: FileManager = .default) {
        guard let baseDirectory = baseDirectory(fileManager: fileManager) else { return }
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }
}
