import Foundation
import AVFoundation
import Combine
import os.log

@MainActor
internal class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var hasPermission = false

    private var captureEngine: AudioCaptureEngine?
    private let engineFactory: () -> AudioCaptureEngine
    private var recordingURL: URL?
    private let volumeManager: MicrophoneVolumeManager
    private let dateProvider: () -> Date
    private(set) var currentSessionStart: Date?
    private(set) var lastRecordingDuration: TimeInterval?

    private(set) var audioDataStream: AsyncStream<AudioData>?

    // Accessed from the real-time audio tap thread; protected by fileLock.
    nonisolated(unsafe) private var audioFile: AVAudioFile?
    nonisolated(unsafe) private var audioDataContinuation: AsyncStream<AudioData>.Continuation?
    private let fileLock = NSLock()

    override init() {
        self.volumeManager = MicrophoneVolumeManager.shared
        self.engineFactory = { AVAudioEngineCaptureEngine() }
        self.dateProvider = { Date() }
        super.init()
        checkMicrophonePermission()
    }

    init(
        volumeManager: MicrophoneVolumeManager = .shared,
        engineFactory: @escaping () -> AudioCaptureEngine = { AVAudioEngineCaptureEngine() },
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        self.volumeManager = volumeManager
        self.engineFactory = engineFactory
        self.dateProvider = dateProvider
        super.init()
        checkMicrophonePermission()
    }

    func checkMicrophonePermission() {
        let permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        switch permissionStatus {
        case .authorized:
            self.hasPermission = true
        case .denied, .restricted:
            self.hasPermission = false
        case .notDetermined:
            guard !AppEnvironment.isRunningTests else {
                self.hasPermission = false
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor [weak self] in
                    self?.hasPermission = granted
                }
            }
        @unknown default:
            self.hasPermission = false
        }
    }

    func requestMicrophonePermission() {
        guard !AppEnvironment.isRunningTests else {
            hasPermission = false
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                self?.hasPermission = granted
            }
        }
    }

    func startRecording() -> Bool {
        guard hasPermission else { return false }
        guard captureEngine == nil else { return false }

        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task { await volumeManager.boostMicrophoneVolume() }
        }

        let tempPath = FileManager.default.temporaryDirectory
        let timestamp = dateProvider().timeIntervalSince1970
        let audioFilename = tempPath.appendingPathComponent("recording_\(timestamp).wav")
        recordingURL = audioFilename

        do {
            let engine = engineFactory()
            captureEngine = engine

            let inputFormat = engine.inputFormat

            let file = try AVAudioFile(forWriting: audioFilename, settings: inputFormat.settings)
            fileLock.lock()
            audioFile = file
            fileLock.unlock()

            let (stream, continuation) = AsyncStream<AudioData>.makeStream(bufferingPolicy: .unbounded)
            audioDataStream = stream
            fileLock.lock()
            audioDataContinuation = continuation
            fileLock.unlock()

            engine.installTap(bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
                guard let self else { return }
                self.handleCapturedBuffer(buffer, time: time)
            }

            engine.prepare()
            try engine.start()

            currentSessionStart = dateProvider()
            lastRecordingDuration = nil
            isRecording = true
            return true
        } catch {
            Logger.audioRecorder.error("Failed to start recording: \(error.localizedDescription)")
            tearDownEngine()
            if UserDefaults.standard.autoBoostMicrophoneVolume {
                Task { await volumeManager.restoreMicrophoneVolume() }
            }
            checkMicrophonePermission()
            return false
        }
    }

    func stopRecording() -> URL? {
        let now = dateProvider()
        let sessionDuration = currentSessionStart.map { now.timeIntervalSince($0) }
        lastRecordingDuration = sessionDuration
        currentSessionStart = nil

        tearDownEngine()

        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task { await volumeManager.restoreMicrophoneVolume() }
        }

        isRecording = false
        audioLevel = 0.0
        return recordingURL
    }

    func cleanupRecording() {
        guard let url = recordingURL else { return }

        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task { await volumeManager.restoreMicrophoneVolume() }
        }

        currentSessionStart = nil
        lastRecordingDuration = nil

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Logger.audioRecorder.error("Failed to cleanup recording file: \(error.localizedDescription)")
        }
        recordingURL = nil
    }

    func cancelRecording() {
        tearDownEngine()
        currentSessionStart = nil
        lastRecordingDuration = nil

        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task { await volumeManager.restoreMicrophoneVolume() }
        }

        isRecording = false
        audioLevel = 0.0
        cleanupRecording()
    }

    // MARK: - Buffer Handling (called from real-time audio thread)

    private nonisolated func handleCapturedBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        fileLock.lock()
        let file = audioFile
        let continuation = audioDataContinuation
        fileLock.unlock()

        if let file {
            do {
                try file.write(from: buffer)
            } catch {
                Logger.audioRecorder.error("Buffer write failed: \(error.localizedDescription)")
            }
        }

        continuation?.yield(AudioData(buffer: buffer, time: time))

        let level = Self.computeRMSLevel(buffer)
        Task { @MainActor [weak self] in
            self?.audioLevel = level
        }
    }

    nonisolated static func computeRMSLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let frames = Int(buffer.frameLength)
        let data = channelData[0]

        var sumOfSquares: Float = 0
        for i in 0..<frames {
            let sample = data[i]
            sumOfSquares += sample * sample
        }
        let rms = sqrtf(sumOfSquares / Float(frames))

        let minDb: Float = -60.0
        let db = 20 * log10f(max(rms, 1e-10))
        let clamped = max(minDb, min(0, db))
        return (clamped - minDb) / (0 - minDb)
    }

    // MARK: - Teardown

    private func tearDownEngine() {
        captureEngine?.removeTap()
        captureEngine?.stop()
        captureEngine = nil

        fileLock.lock()
        let continuation = audioDataContinuation
        audioDataContinuation = nil
        audioFile = nil
        fileLock.unlock()

        continuation?.finish()
        audioDataStream = nil
    }
}
