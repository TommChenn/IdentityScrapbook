import Foundation
import SwiftData
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

@Model
final class VideoEntry {
    @Attribute(.unique) var id: UUID
    var scrapbookID: UUID
    var linkedVoteID: UUID?
    var sequence: Int
    var addedAt: Date
    var timeZoneID: String
    var entryDate: String
    var videoKey: String
    var thumbnailKey: String
    var duration: Double
    var pixelWidth: Int
    var pixelHeight: Int

    init(id: UUID, bookID: UUID, voteID: UUID?, sequence: Int, media: VideoFiles.Info) {
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
        videoKey = "\(id.uuidString)/video.\(media.fileExtension)"
        thumbnailKey = "\(id.uuidString)/poster.jpg"
        duration = media.duration
        pixelWidth = media.width
        pixelHeight = media.height
    }
}

nonisolated enum VideoFiles {
    static let maxDuration = 60.0
    static let maxBytes = 250_000_000
    static var root: URL { URL.applicationSupportDirectory.appendingPathComponent("ScrapbookVideos", isDirectory: true) }
    enum ImportError: Error { case tooLarge, tooLong, unsupported }
    struct Info: Sendable {
        let duration: Double
        let width: Int
        let height: Int
        let fileExtension: String
        let poster: Data
    }

    static func inspect(_ url: URL) async throws -> Info {
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes > 0 else { throw ImportError.unsupported }
        guard bytes <= maxBytes else { throw ImportError.tooLarge }
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable), !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw ImportError.unsupported
        }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw ImportError.unsupported }
        guard duration <= maxDuration else { throw ImportError.tooLong }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        let result = try await generator.image(at: .zero)
        let image = result.image
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImportError.unsupported
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImportError.unsupported }
        let ext = url.pathExtension.lowercased()
        return Info(duration: duration, width: image.width, height: image.height,
                    fileExtension: ext.isEmpty ? "mov" : ext, poster: data as Data)
    }

    static func prepare(_ source: URL, id: UUID, root: URL) async throws -> Info {
        let media = try await inspect(source)
        try Task.checkCancellation()
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("video.\(media.fileExtension)")
        // Replace only this uncommitted submission's files, retaining the source draft for retry.
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: source, to: destination)
        try media.poster.write(to: folder.appendingPathComponent("poster.jpg"), options: .atomic)
        return media
    }
}

@MainActor
enum VideoStore {
    private static var inFlight: Set<UUID> = []
    static func add(_ source: URL, bookID: UUID, voteID: UUID?, submissionID: UUID,
                    in container: ModelContainer, root: URL = VideoFiles.root) async throws -> UUID {
        guard inFlight.insert(submissionID).inserted else { throw EntryStore.SaveError.conflictingSubmission }
        defer { inFlight.remove(submissionID) }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        if let existing = try context.fetch(FetchDescriptor<VideoEntry>(predicate: #Predicate { $0.id == submissionID })).first {
            guard existing.scrapbookID == bookID, existing.linkedVoteID == voteID else { throw EntryStore.SaveError.conflictingSubmission }
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent(existing.videoKey).path),
                  FileManager.default.fileExists(atPath: root.appendingPathComponent(existing.thumbnailKey).path) else { throw EntryStore.SaveError.missingAsset }
            return existing.id
        }
        guard let book = try context.fetch(FetchDescriptor<Scrapbook>(predicate: #Predicate { $0.id == bookID })).first else { throw EntryStore.SaveError.missingBook }
        if let voteID {
            guard let vote = try context.fetch(FetchDescriptor<Vote>(predicate: #Predicate { $0.id == voteID })).first,
                  vote.identityID == book.identity?.id else { throw EntryStore.SaveError.invalidVote }
        }
        let media = try await Task.detached { try await VideoFiles.prepare(source, id: submissionID, root: root) }.value
        let entry = VideoEntry(id: submissionID, bookID: bookID, voteID: voteID,
                               sequence: try EntryStore.nextSequence(bookID: bookID, context: context), media: media)
        context.insert(entry)
        do { try context.save() } catch { context.rollback(); throw error }
        return entry.id
    }
}
