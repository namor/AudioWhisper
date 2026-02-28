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
    private var _configuredSpeakerCount: Int = -1

    static func makeDiarizationConfig(speakerCount: Int = 0) -> OfflineDiarizerConfig {
        var config = OfflineDiarizerConfig(
            clustering: .init(
                threshold: 0.6,
                warmStartFa: 0.07,
                warmStartFb: 0.8
            )
        )
        if speakerCount > 0 {
            config.clustering.numSpeakers = speakerCount
        }
        return config
    }

    private func prepareManager(speakerCount: Int) async throws {
        guard Arch.isAppleSilicon else { throw DiarizationError.notAppleSilicon }
        do {
            let config = Self.makeDiarizationConfig(speakerCount: speakerCount)
            let mgr = OfflineDiarizerManager(config: config)
            try await mgr.prepareModels()
            lock.withLock {
                _manager = mgr
                _modelsPrepared = true
                _configuredSpeakerCount = speakerCount
            }
            let mode = speakerCount > 0 ? "exact=\(speakerCount)" : "auto"
            logger.info("Diarization models prepared (speakers: \(mode))")
        } catch {
            logger.error("Failed to prepare diarization models: \(error.localizedDescription)")
            throw DiarizationError.modelPreparationFailed(error.localizedDescription)
        }
    }

    func prepareModels() async throws {
        let speakerCount = UserDefaults.standard.integer(
            forKey: AppDefaults.Keys.diarizationSpeakerCount
        )
        try await prepareManager(speakerCount: speakerCount)
    }

    var areModelsPrepared: Bool { lock.withLock { _modelsPrepared } }

    func diarize(audioURL: URL) async throws -> [(speakerId: String, start: TimeInterval, end: TimeInterval)] {
        guard Arch.isAppleSilicon else { throw DiarizationError.notAppleSilicon }
        do {
            let desiredCount = UserDefaults.standard.integer(
                forKey: AppDefaults.Keys.diarizationSpeakerCount
            )
            let needsPrepare: Bool = lock.withLock {
                _manager == nil || _configuredSpeakerCount != desiredCount
            }
            if needsPrepare {
                try await prepareManager(speakerCount: desiredCount)
            }
            let mgr: OfflineDiarizerManager? = lock.withLock { _manager }
            guard let mgr else {
                throw DiarizationError.diarizationFailed("Manager not initialized")
            }
            let mode = desiredCount > 0 ? "exact=\(desiredCount)" : "auto"
            logger.info("Starting diarization (speakers: \(mode))")
            let result = try await mgr.process(audioURL)
            let uniqueSpeakers = Set(result.segments.map { $0.speakerId })
            logger.info("Diarization complete: \(result.segments.count) segments, \(uniqueSpeakers.count) unique speakers (\(uniqueSpeakers.sorted().joined(separator: ", ")))")
            for speaker in uniqueSpeakers.sorted() {
                let segs = result.segments.filter { $0.speakerId == speaker }
                let duration = segs.reduce(0.0) { $0 + Double($1.endTimeSeconds - $1.startTimeSeconds) }
                logger.info("  \(speaker): \(segs.count) segments, \(String(format: "%.1f", duration))s total")
            }
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
        guard !diarSegments.isEmpty else { return [] }

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
            let segStart = Double(seg.start)
            let segEnd = Double(seg.end)
            var bestSpeaker = ""
            var bestOverlap: Double = 0

            for diar in diarSegments {
                let overlapStart = max(segStart, diar.start)
                let overlapEnd = min(segEnd, diar.end)
                let overlap = overlapEnd - overlapStart
                guard overlap > 0 else { continue }
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestSpeaker = diar.speakerId
                }
            }

            if bestSpeaker.isEmpty {
                let segMid = (segStart + segEnd) / 2.0
                var bestDistance = Double.infinity
                for diar in diarSegments {
                    let diarMid = (diar.start + diar.end) / 2.0
                    let distance = abs(segMid - diarMid)
                    if distance < bestDistance {
                        bestDistance = distance
                        bestSpeaker = diar.speakerId
                    }
                }
            }

            if bestSpeaker.isEmpty { bestSpeaker = "unknown" }

            let id = displayId(for: bestSpeaker)
            assigned.append((speakerId: id, text: seg.text, start: seg.start, end: seg.end))
        }

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
