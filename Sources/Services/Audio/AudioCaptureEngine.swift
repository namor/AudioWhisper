import AVFoundation
import CoreAudio
import AudioToolbox

/// Abstracts audio engine operations to enable testing without hardware access.
internal protocol AudioCaptureEngine: AnyObject {
    var inputFormat: AVAudioFormat { get }
    func setInputDevice(uniqueID: String) throws
    func installTap(
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    )
    func removeTap()
    func prepare()
    func start() throws
    func stop()
    var configurationChangeNotification: NotificationCenter.Publisher { get }
}

extension AudioCaptureEngine {
    func setInputDevice(uniqueID: String) throws { }
    var configurationChangeNotification: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: .init("no-op"))
    }
}

/// Production implementation backed by AVAudioEngine.
internal final class AVAudioEngineCaptureEngine: AudioCaptureEngine {
    private let engine = AVAudioEngine()

    var inputFormat: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    func setInputDevice(uniqueID: String) throws {
        guard !uniqueID.isEmpty else { return }
        guard let deviceID = Self.audioDeviceID(for: uniqueID) else {
            throw AudioCaptureError.deviceNotFound(uniqueID)
        }
        var mutableID = deviceID
        let status = AudioUnitSetProperty(
            engine.inputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioCaptureError.deviceSelectionFailed(status)
        }
    }

    func installTap(
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
    ) {
        engine.inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format, block: block)
    }

    func removeTap() {
        engine.inputNode.removeTap(onBus: 0)
    }

    func prepare() {
        engine.prepare()
    }

    func start() throws {
        try engine.start()
    }

    func stop() {
        engine.stop()
    }

    var configurationChangeNotification: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(
            for: .AVAudioEngineConfigurationChange, object: engine
        )
    }

    // MARK: - CoreAudio device lookup

    private static func audioDeviceID(for uniqueID: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return nil }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
        ) == noErr else { return nil }

        for device in devices {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uid: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(
                device, &uidAddress, 0, nil, &uidSize, &uid
            ) == noErr, let cfUID = uid?.takeUnretainedValue() else { continue }
            if (cfUID as String) == uniqueID { return device }
        }
        return nil
    }
}

internal enum AudioCaptureError: Error, LocalizedError {
    case deviceNotFound(String)
    case deviceSelectionFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound(let id):
            return "Audio input device not found: \(id)"
        case .deviceSelectionFailed(let status):
            return "Failed to select audio device (OSStatus \(status))"
        }
    }
}
