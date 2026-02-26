import XCTest
import AVFoundation
@testable import AudioWhisper

@MainActor
final class AudioRecorderTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "autoBoostMicrophoneVolume")
        super.tearDown()
    }

    func testStartRecordingSetsStateWhenPermissionGranted() {
        let startDate = Date(timeIntervalSince1970: 1_000)
        let sessionDate = Date(timeIntervalSince1970: 1_005)
        let mockEngine = MockAudioCaptureEngine()
        let recorder = makeRecorder(dates: [startDate, sessionDate], engine: mockEngine)
        recorder.hasPermission = true

        let didStart = recorder.startRecording()

        XCTAssertTrue(didStart)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.currentSessionStart, sessionDate)
        XCTAssertNil(recorder.lastRecordingDuration)
        XCTAssertTrue(mockEngine.prepareCalled)
        XCTAssertTrue(mockEngine.startCalled)
        XCTAssertTrue(mockEngine.tapInstalled)
    }

    func testStartRecordingReturnsFalseWithoutPermission() {
        var factoryCalled = false
        let recorder = makeRecorder(
            dates: [Date(), Date()],
            engineFactory: {
                factoryCalled = true
                return MockAudioCaptureEngine()
            }
        )
        recorder.hasPermission = false

        let didStart = recorder.startRecording()

        XCTAssertFalse(didStart)
        XCTAssertFalse(factoryCalled, "Engine factory should not be used without permission")
        XCTAssertFalse(recorder.isRecording)
    }

    func testStartRecordingPreventsReentrancy() {
        let mockEngine = MockAudioCaptureEngine()
        let recorder = makeRecorder(
            dates: [
                Date(timeIntervalSince1970: 2_000),
                Date(timeIntervalSince1970: 2_001),
                Date(timeIntervalSince1970: 2_002),
                Date(timeIntervalSince1970: 2_003)
            ],
            engine: mockEngine
        )
        recorder.hasPermission = true

        let firstStart = recorder.startRecording()
        XCTAssertTrue(firstStart, "First start should succeed")
        XCTAssertTrue(recorder.isRecording)

        let secondStart = recorder.startRecording()
        XCTAssertFalse(secondStart, "Second start should fail due to reentrancy guard")
        XCTAssertTrue(recorder.isRecording, "Should still be recording after failed reentrancy")
    }

    func testStopRecordingSetsDurationAndResetsState() {
        let startDate = Date(timeIntervalSince1970: 3_000)
        let sessionDate = Date(timeIntervalSince1970: 3_005)
        let endDate = Date(timeIntervalSince1970: 3_010)
        let mockEngine = MockAudioCaptureEngine()
        let recorder = makeRecorder(dates: [startDate, sessionDate, endDate], engine: mockEngine)
        recorder.hasPermission = true
        XCTAssertTrue(recorder.startRecording())

        let url = recorder.stopRecording()

        XCTAssertNotNil(url)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentSessionStart)
        XCTAssertEqual(recorder.lastRecordingDuration ?? -1, endDate.timeIntervalSince(sessionDate), accuracy: 0.001)
        XCTAssertTrue(mockEngine.stopCalled)
        XCTAssertTrue(mockEngine.tapRemoved)
    }

    func testStopRecordingWhenNotRecordingReturnsNil() {
        let recorder = makeRecorder(dates: [], engine: MockAudioCaptureEngine())

        let url = recorder.stopRecording()

        XCTAssertNil(url)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentSessionStart)
        XCTAssertNil(recorder.lastRecordingDuration)
    }

    func testCancelRecordingResetsState() {
        let mockEngine = MockAudioCaptureEngine()
        let recorder = makeRecorder(
            dates: [
                Date(timeIntervalSince1970: 4_000),
                Date(timeIntervalSince1970: 4_001)
            ],
            engine: mockEngine
        )
        recorder.hasPermission = true
        XCTAssertTrue(recorder.startRecording())

        recorder.cancelRecording()

        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentSessionStart)
        XCTAssertNil(recorder.lastRecordingDuration)
        XCTAssertTrue(mockEngine.stopCalled)
        XCTAssertTrue(mockEngine.tapRemoved)
    }

    func testStartRecordingReturnsFalseWhenEngineThrows() {
        let mockEngine = MockAudioCaptureEngine()
        mockEngine.shouldThrowOnStart = true
        let recorder = makeRecorder(dates: [Date(), Date()], engine: mockEngine)
        recorder.hasPermission = true

        let didStart = recorder.startRecording()

        XCTAssertFalse(didStart)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentSessionStart)
    }

    func testAudioDataStreamIsAvailableAfterStart() {
        let mockEngine = MockAudioCaptureEngine()
        let recorder = makeRecorder(dates: [Date(), Date()], engine: mockEngine)
        recorder.hasPermission = true

        XCTAssertNil(recorder.audioDataStream)
        XCTAssertTrue(recorder.startRecording())
        XCTAssertNotNil(recorder.audioDataStream)
    }

    func testAudioDataStreamIsNilAfterStop() {
        let mockEngine = MockAudioCaptureEngine()
        let recorder = makeRecorder(dates: [Date(), Date(), Date()], engine: mockEngine)
        recorder.hasPermission = true
        XCTAssertTrue(recorder.startRecording())

        _ = recorder.stopRecording()

        XCTAssertNil(recorder.audioDataStream)
    }

    func testComputeRMSLevelWithSilence() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) else {
            XCTFail("Failed to create buffer")
            return
        }
        buffer.frameLength = 1024
        if let data = buffer.floatChannelData {
            for i in 0..<1024 {
                data[0][i] = 0.0
            }
        }

        let level = AudioRecorder.computeRMSLevel(buffer)

        XCTAssertEqual(level, 0.0, accuracy: 0.01, "Silent buffer should produce near-zero level")
    }

    func testComputeRMSLevelWithLoudSignal() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) else {
            XCTFail("Failed to create buffer")
            return
        }
        buffer.frameLength = 1024
        if let data = buffer.floatChannelData {
            for i in 0..<1024 {
                data[0][i] = 0.5
            }
        }

        let level = AudioRecorder.computeRMSLevel(buffer)

        XCTAssertGreaterThan(level, 0.5, "Loud signal should produce a high level")
        XCTAssertLessThanOrEqual(level, 1.0)
    }

    // MARK: - Helpers

    private func makeRecorder(
        dates: [Date],
        engine: MockAudioCaptureEngine
    ) -> AudioRecorder {
        let dateProvider = StubDateProvider(dates: dates)
        return AudioRecorder(
            engineFactory: { engine },
            dateProvider: { dateProvider.nextDate() }
        )
    }

    private func makeRecorder(
        dates: [Date],
        engineFactory: @escaping () -> AudioCaptureEngine
    ) -> AudioRecorder {
        let dateProvider = StubDateProvider(dates: dates)
        return AudioRecorder(
            engineFactory: engineFactory,
            dateProvider: { dateProvider.nextDate() }
        )
    }
}

private final class StubDateProvider {
    private var dates: [Date]

    init(dates: [Date]) {
        self.dates = dates
    }

    func nextDate() -> Date {
        guard !dates.isEmpty else { return Date() }
        return dates.removeFirst()
    }
}
