import Foundation
import os.log
import FluidAudio

internal enum DiarizationError: Error, LocalizedError {
    case modelPreparationFailed(String)
    case diarizationFailed(String)
    case notAppleSilicon

    var errorDescription: String? {
        switch self {
        case .modelPreparationFailed(let msg):
            return "Diarization model preparation failed: \(msg)"
        case .diarizationFailed(let msg):
            return "Speaker diarization failed: \(msg)"
        case .notAppleSilicon:
            return "Speaker diarization requires an Apple Silicon Mac."
        }
    }
}

internal protocol DiarizationServiceProtocol: Sendable {
    func prepareModels() async throws
    var areModelsPrepared: Bool { get }
    func diarize(audioURL: URL) async throws -> [(speakerId: String, start: TimeInterval, end: TimeInterval)]
}

internal final class DiarizationService: DiarizationServiceProtocol, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.audiowhisper.app", category: "DiarizationService")
    private let lock = NSLock()
    private var _manager: OfflineDiarizerManager?
    private var _modelsPrepared = false

    func prepareModels() async throws {
        guard Arch.isAppleSilicon else { throw DiarizationError.notAppleSilicon }
        do {
            let mgr = OfflineDiarizerManager(config: OfflineDiarizerConfig())
            try await mgr.prepareModels()
            lock.withLock {
                _manager = mgr
                _modelsPrepared = true
            }
            logger.info("Diarization models prepared successfully")
        } catch {
            logger.error("Failed to prepare diarization models: \(error.localizedDescription)")
            throw DiarizationError.modelPreparationFailed(error.localizedDescription)
        }
    }

    var areModelsPrepared: Bool { lock.withLock { _modelsPrepared } }

    func diarize(audioURL: URL) async throws -> [(speakerId: String, start: TimeInterval, end: TimeInterval)] {
        guard Arch.isAppleSilicon else { throw DiarizationError.notAppleSilicon }
        do {
            let needsPrepare = lock.withLock { _manager == nil }
            if needsPrepare {
                try await prepareModels()
            }
            let mgr: OfflineDiarizerManager? = lock.withLock { _manager }
            guard let mgr else {
                throw DiarizationError.diarizationFailed("Manager not initialized")
            }
            let result = try await mgr.process(audioURL)
            return result.segments.map { seg in
                (speakerId: seg.speakerId, start: TimeInterval(seg.startTimeSeconds), end: TimeInterval(seg.endTimeSeconds))
            }
        } catch let error as DiarizationError {
            throw error
        } catch {
            logger.error("Diarization failed: \(error.localizedDescription)")
            throw DiarizationError.diarizationFailed(error.localizedDescription)
        }
    }

    // MARK: - Model availability

    static func areModelsOnDisk() -> Bool {
        let modelsDir = OfflineDiarizerModels.defaultModelsDirectory()
            .appendingPathComponent(Repo.diarizer.folderName, isDirectory: true)
        return ModelNames.OfflineDiarizer.requiredModels.allSatisfy { name in
            FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent(name).path)
        }
    }

    // MARK: - Alignment

    static func align(
        asrSegments: [(text: String, start: Float, end: Float)],
        diarSegments: [(speakerId: String, start: TimeInterval, end: TimeInterval)]
    ) -> [SpeakerTurn] {
        guard !asrSegments.isEmpty else { return [] }

        var speakerMap: [String: String] = [:]
        var speakerCounter = 0

        func displayId(for rawId: String) -> String {
            if let existing = speakerMap[rawId] { return existing }
            speakerCounter += 1
            let name = "Speaker \(speakerCounter)"
            speakerMap[rawId] = name
            return name
        }

        var assigned: [(speakerId: String, text: String, start: Float, end: Float)] = []

        for seg in asrSegments {
            var bestSpeaker = ""
            var bestOverlap: Double = -1

            for diar in diarSegments {
                let overlapStart = max(Double(seg.start), diar.start)
                let overlapEnd = min(Double(seg.end), diar.end)
                let overlap = max(0, overlapEnd - overlapStart)
                if overlap > bestOverlap || (overlap == bestOverlap && diar.start < (diarSegments.first(where: { $0.speakerId == bestSpeaker })?.start ?? .infinity)) {
                    bestOverlap = overlap
                    bestSpeaker = diar.speakerId
                }
            }

            if bestSpeaker.isEmpty {
                bestSpeaker = "unknown"
            }

            let id = displayId(for: bestSpeaker)
            assigned.append((speakerId: id, text: seg.text, start: seg.start, end: seg.end))
        }

        // Merge contiguous segments with the same speaker
        var turns: [SpeakerTurn] = []
        for item in assigned {
            if let last = turns.last, last.speakerId == item.speakerId {
                let merged = SpeakerTurn(
                    speakerId: last.speakerId,
                    start: last.start,
                    end: TimeInterval(item.end),
                    text: last.text + " " + item.text.trimmingCharacters(in: .whitespaces)
                )
                turns[turns.count - 1] = merged
            } else {
                turns.append(SpeakerTurn(
                    speakerId: item.speakerId,
                    start: TimeInterval(item.start),
                    end: TimeInterval(item.end),
                    text: item.text.trimmingCharacters(in: .whitespaces)
                ))
            }
        }

        return turns
    }
}
