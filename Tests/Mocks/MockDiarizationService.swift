import Foundation
@testable import AudioWhisper

final class MockDiarizationService: DiarizationServiceProtocol, @unchecked Sendable {
    var mockSegments: [(speakerId: String, start: TimeInterval, end: TimeInterval)] = []
    var shouldThrow = false
    var prepareModelsCalled = false
    var diarizeCalled = false
    private(set) var areModelsPrepared: Bool = true

    func prepareModels() async throws {
        prepareModelsCalled = true
        if shouldThrow {
            throw DiarizationError.modelPreparationFailed("mock error")
        }
    }

    func diarize(audioURL: URL) async throws -> [(speakerId: String, start: TimeInterval, end: TimeInterval)] {
        diarizeCalled = true
        if shouldThrow {
            throw DiarizationError.diarizationFailed("mock error")
        }
        return mockSegments
    }

    func reset() {
        mockSegments = []
        shouldThrow = false
        prepareModelsCalled = false
        diarizeCalled = false
        areModelsPrepared = true
    }
}
