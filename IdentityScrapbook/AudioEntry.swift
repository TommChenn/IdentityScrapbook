import Foundation
import SwiftData
import AVFoundation

@Model
final class AudioEntry {
    @Attribute(.unique) var id: UUID
    var scrapbookID: UUID
    var linkedVoteID: UUID?
    var sequence: Int
    var addedAt: Date
    var timeZoneID: String
    var entryDate: String
    var audioKey: String
    var duration: Double
    var waveform: [Double]

    init(id: UUID, bookID: UUID, voteID: UUID?, sequence: Int, duration: Double, waveform: [Double]) {
        self.id = id
        scrapbookID = bookID
        linkedVoteID = voteID
        self.sequence = sequence
        let now = Date()
        addedAt = now
        timeZoneID = TimeZone.current.identifier
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        entryDate = formatter.string(from: now)
        audioKey = "\(id.uuidString)/recording.m4a"
        self.duration = duration
        self.waveform = waveform
    }
}

nonisolated enum AudioFiles {
    static let maxDuration = 300.0
    static var root: URL { URL.applicationSupportDirectory.appendingPathComponent("ScrapbookAudio", isDirectory: true) }
    enum AudioError: Error { case invalidRecording, tooLong }

    static func duration(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration.isFinite, duration > 0.1 else { throw AudioError.invalidRecording }
        guard duration <= maxDuration + 0.25 else { throw AudioError.tooLong }
        // Confirm that actual audio frames are readable, not just a container header.
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1024) else {
            throw AudioError.invalidRecording
        }
        try file.read(into: buffer)
        guard buffer.frameLength > 0 else { throw AudioError.invalidRecording }
        return duration
    }

    static func compactWaveform(_ samples: [Double]) -> [Double] {
        let valid = samples.map { $0.isFinite ? min(1, max(0, $0)) : 0 }
        guard valid.count > 60 else { return valid }
        return (0..<60).map { index in
            let start = index * valid.count / 60
            let end = (index + 1) * valid.count / 60
            return valid[start..<end].max() ?? 0
        }
    }

    static func prepare(_ source: URL, id: UUID, root: URL) throws -> Double {
        let duration = try duration(of: source)
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("recording.m4a")
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.copyItem(at: source, to: target)
        return duration
    }
}

@MainActor
enum AudioStore {
    private static var inFlight: Set<UUID> = []
    static func add(_ source: URL, waveform: [Double], bookID: UUID, voteID: UUID?, submissionID: UUID,
                    in container: ModelContainer, root: URL = AudioFiles.root) async throws -> UUID {
        guard inFlight.insert(submissionID).inserted else { throw EntryStore.SaveError.conflictingSubmission }
        defer { inFlight.remove(submissionID) }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        if let existing = try context.fetch(FetchDescriptor<AudioEntry>(predicate: #Predicate { $0.id == submissionID })).first {
            guard existing.scrapbookID == bookID, existing.linkedVoteID == voteID else { throw EntryStore.SaveError.conflictingSubmission }
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent(existing.audioKey).path) else { throw EntryStore.SaveError.missingAsset }
            return existing.id
        }
        guard let book = try context.fetch(FetchDescriptor<Scrapbook>(predicate: #Predicate { $0.id == bookID })).first else { throw EntryStore.SaveError.missingBook }
        if let voteID {
            guard let vote = try context.fetch(FetchDescriptor<Vote>(predicate: #Predicate { $0.id == voteID })).first,
                  vote.identityID == book.identity?.id else { throw EntryStore.SaveError.invalidVote }
        }
        let duration = try await Task.detached { try AudioFiles.prepare(source, id: submissionID, root: root) }.value
        let entry = AudioEntry(id: submissionID, bookID: bookID, voteID: voteID,
                               sequence: try EntryStore.nextSequence(bookID: bookID, context: context),
                               duration: duration, waveform: AudioFiles.compactWaveform(waveform))
        context.insert(entry)
        do { try context.save() } catch { context.rollback(); throw error }
        return entry.id
    }
}
