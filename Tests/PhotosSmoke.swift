import Foundation
import SwiftData
import ImageIO
import UniformTypeIdentifiers

@main
struct PhotosSmoke {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("test.store")
        let assets = folder.appendingPathComponent("assets")
        try seed(url)
        let bytes = fixture()
        try await exercise(url, assets: assets, bytes: bytes)
        let store = try container(url)
        let context = ModelContext(store)
        let photos = try context.fetch(FetchDescriptor<PhotoEntry>(sortBy: [SortDescriptor(\.sequence)]))
        let notes = try context.fetch(FetchDescriptor<TextEntry>(sortBy: [SortDescriptor(\.sequence)]))
        precondition(photos.count == 2 && notes.count == 2)
        precondition(notes.map(\.sequence) == [0, 2])
        precondition(photos.map(\.sequence) == [1, 3])
        precondition(notes.map(\.paperStyle) == [0, 1])
        precondition(photos[0].caption == "写真の思い出 🌱\n二行目")
        precondition(photos[0].linkedVoteID != nil && photos[1].linkedVoteID == nil)
        precondition(!photos[0].isSticker && photos[1].isSticker)
        let sticker = try Data(contentsOf: assets.appendingPathComponent(photos[1].stickerKey!))
        precondition(sticker == fixture(transparent: true))
        let stickerPreview = try Data(contentsOf: assets.appendingPathComponent(photos[1].thumbnailKey))
        let source = CGImageSourceCreateWithData(stickerPreview as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
        precondition(properties[kCGImagePropertyHasAlpha] as? Bool == true)
        for photo in photos {
            let original = try Data(contentsOf: assets.appendingPathComponent(photo.originalKey))
            precondition(original == bytes)
            let preview = try Data(contentsOf: assets.appendingPathComponent(photo.thumbnailKey))
            precondition(CGImageSourceCreateWithData(preview as CFData, nil) != nil)
        }
        let votes = try context.fetch(FetchDescriptor<Vote>())
        precondition(votes.count == 1)
        print("PASS: transparent sticker persistence, original preservation, readable previews, captions, mixed ordering, stable note colors, vote links, deduplication, invalid image/write failure rejection, disk reopen")
    }

    @MainActor static func container(_ url: URL, legacy: Bool = false) throws -> ModelContainer {
        let schema = legacy ? Schema([Identity.self, HabitAction.self, Scrapbook.self, Vote.self, TextEntry.self])
            : Schema([Identity.self, HabitAction.self, Scrapbook.self, Vote.self, TextEntry.self, PhotoEntry.self, VideoEntry.self, AudioEntry.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    }

    @MainActor static func seed(_ url: URL) throws {
        let store = try container(url, legacy: true)
        try IdentityStore.create(name: "読む自分", minimum: "1ページ", normal: "20分", in: store)
        let context = ModelContext(store)
        let book = try context.fetch(FetchDescriptor<Scrapbook>()).first!
        context.insert(TextEntry(id: UUID(), bookID: book.id, voteID: nil, body: "existing note", sequence: 0,
                                 paperStyle: 0, now: Date(), timeZone: .current))
        try context.save()
    }

    @MainActor static func exercise(_ url: URL, assets: URL, bytes: Data) async throws {
        let store = try container(url)
        let context = ModelContext(store)
        let person = try context.fetch(FetchDescriptor<Identity>()).first!
        let book = person.scrapbook!.id
        let vote = try VoteStore.cast(identityID: person.id, actionID: person.actions[0].id, submissionID: UUID(), in: store)
        let submission = UUID()
        for _ in 0..<2 {
            _ = try await PhotoStore.addPhoto(bytes, caption: "写真の思い出 🌱\n二行目", bookID: book,
                                             voteID: vote.id, submissionID: submission, in: store, root: assets)
        }
        _ = try EntryStore.addText("next note", bookID: book, voteID: nil, submissionID: UUID(), in: store)
        _ = try await PhotoStore.addPhoto(bytes, caption: "", bookID: book, voteID: nil, submissionID: UUID(), in: store, root: assets, sticker: fixture(transparent: true))
        do {
            _ = try await PhotoStore.addPhoto(Data("invalid".utf8), caption: "", bookID: book, voteID: nil,
                                             submissionID: UUID(), in: store, root: assets)
            preconditionFailure("Invalid image saved")
        } catch { }
        let blockedRoot = assets.appendingPathComponent("file-not-directory")
        try Data([0]).write(to: blockedRoot)
        do {
            _ = try await PhotoStore.addPhoto(bytes, caption: "", bookID: book, voteID: nil,
                                             submissionID: UUID(), in: store, root: blockedRoot)
            preconditionFailure("File failure created a record")
        } catch { }
    }

    static func fixture(transparent: Bool = false) -> Data {
        let context = CGContext(data: nil, width: 32, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.7, blue: 0.4, alpha: 1))
        context.clear(CGRect(x: 0, y: 0, width: 32, height: 48))
        context.fill(transparent ? CGRect(x: 8, y: 8, width: 16, height: 32) : CGRect(x: 0, y: 0, width: 32, height: 48))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
