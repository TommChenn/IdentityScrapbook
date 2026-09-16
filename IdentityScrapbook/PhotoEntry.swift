import Foundation
import SwiftData
import ImageIO
import UniformTypeIdentifiers

@Model
final class PhotoEntry {
    @Attribute(.unique) var id: UUID
    var scrapbookID: UUID
    var linkedVoteID: UUID?
    var caption: String
    var addedAt: Date
    var entryDate: String
    var timeZoneID: String
    var sequence: Int
    var originalKey: String
    var thumbnailKey: String
    var pixelWidth: Int
    var pixelHeight: Int
    var stickerKey: String? = nil

    var isSticker: Bool { stickerKey != nil }

    init(id: UUID, bookID: UUID, voteID: UUID?, caption: String, sequence: Int,
         width: Int, height: Int, now: Date, timeZone: TimeZone, isSticker: Bool = false) {
        self.id = id
        scrapbookID = bookID
        linkedVoteID = voteID
        self.caption = caption
        self.sequence = sequence
        pixelWidth = width
        pixelHeight = height
        addedAt = now
        timeZoneID = timeZone.identifier
        originalKey = "\(id.uuidString)/original"
        thumbnailKey = "\(id.uuidString)/preview.jpg"
        if isSticker { stickerKey = "\(id.uuidString)/sticker.png"; thumbnailKey = "\(id.uuidString)/preview.png" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        entryDate = formatter.string(from: now)
    }
}

// Image decoding and file writes run off the main actor. Original bytes are preserved.
nonisolated enum PhotoFiles {
    enum FileError: Error { case invalidImage, encodingFailed }

    static var root: URL {
        URL.applicationSupportDirectory.appendingPathComponent("ScrapbookPhotos", isDirectory: true)
    }

    static func preview(_ data: Data, maxPixels: Int = 1600, preserveAlpha: Bool = false) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw FileError.invalidImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, (preserveAlpha ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil)
        else { throw FileError.encodingFailed }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FileError.encodingFailed }
        return output as Data
    }

    static func prepare(original: Data, id: UUID, root: URL, sticker: Data? = nil) throws -> (width: Int, height: Int) {
        let thumbnail = try preview(sticker ?? original, preserveAlpha: sticker != nil)
        guard let source = CGImageSourceCreateWithData(thumbnail as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw FileError.invalidImage }
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try original.write(to: folder.appendingPathComponent("original"), options: .atomic)
        if let sticker { try sticker.write(to: folder.appendingPathComponent("sticker.png"), options: .atomic) }
        try thumbnail.write(to: folder.appendingPathComponent(sticker == nil ? "preview.jpg" : "preview.png"), options: .atomic)
        return (width, height)
    }
}

@MainActor
enum PhotoStore {
    private static var inFlight: Set<UUID> = []
    static func addPhoto(_ original: Data, caption: String, bookID: UUID, voteID: UUID?,
                         submissionID: UUID, in container: ModelContainer,
                         root: URL = PhotoFiles.root, sticker: Data? = nil) async throws -> UUID {
        guard inFlight.insert(submissionID).inserted else { throw EntryStore.SaveError.conflictingSubmission }
        defer { inFlight.remove(submissionID) }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        if let existing = try context.fetch(FetchDescriptor<PhotoEntry>(predicate: #Predicate { $0.id == submissionID })).first {
            guard existing.scrapbookID == bookID, existing.linkedVoteID == voteID, existing.isSticker == (sticker != nil) else {
                throw EntryStore.SaveError.conflictingSubmission
            }
            // Never overwrite a committed original on a retry.
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent(existing.originalKey).path)
                || !FileManager.default.fileExists(atPath: root.appendingPathComponent(existing.thumbnailKey).path) {
                throw EntryStore.SaveError.missingAsset
            }
            return existing.id
        }
        guard let book = try context.fetch(FetchDescriptor<Scrapbook>(predicate: #Predicate { $0.id == bookID })).first else {
            throw EntryStore.SaveError.missingBook
        }
        if let voteID {
            guard let vote = try context.fetch(FetchDescriptor<Vote>(predicate: #Predicate { $0.id == voteID })).first,
                  vote.identityID == book.identity?.id else { throw EntryStore.SaveError.invalidVote }
        }
        let size = try await Task.detached {
            try PhotoFiles.prepare(original: original, id: submissionID, root: root, sticker: sticker)
        }.value
        // Refresh after the asynchronous work; another insertion may have completed meanwhile.
        if let existing = try context.fetch(FetchDescriptor<PhotoEntry>(predicate: #Predicate { $0.id == submissionID })).first {
            guard existing.scrapbookID == bookID, existing.linkedVoteID == voteID, existing.isSticker == (sticker != nil) else {
                throw EntryStore.SaveError.conflictingSubmission
            }
            return existing.id
        }
        let entry = PhotoEntry(id: submissionID, bookID: bookID, voteID: voteID,
                               caption: caption, sequence: try EntryStore.nextSequence(bookID: bookID, context: context),
                               width: size.width, height: size.height, now: Date(), timeZone: .current, isSticker: sticker != nil)
        context.insert(entry)
        do { try context.save() } catch { context.rollback(); throw error }
        // Uncommitted files are retained on failure so retries never remove committed media.
        return entry.id
    }
}
