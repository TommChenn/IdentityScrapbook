import Foundation
import SwiftData
import AVFoundation

@main
struct VideosSmoke {
    @MainActor static func main() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mov")
        try await fixture(source, duration: 1)
        let root = folder.appendingPathComponent("assets")
        let url = folder.appendingPathComponent("test.store")
        try seed(url)
        try await exercise(url, source: source, root: root)
        try FileManager.default.removeItem(at: source)
        let store = try container(url)
        let context = ModelContext(store)
        let videos = try context.fetch(FetchDescriptor<VideoEntry>())
        let notes = try context.fetch(FetchDescriptor<TextEntry>())
        precondition(videos.count == 1 && notes.count == 1)
        precondition(videos[0].sequence == 0 && notes[0].sequence == 1)
        precondition(videos[0].linkedVoteID != nil)
        let saved = root.appendingPathComponent(videos[0].videoKey)
        let media = try await VideoFiles.inspect(saved)
        precondition(media.duration > 0 && media.width == 64)
        precondition(FileManager.default.fileExists(atPath: root.appendingPathComponent(videos[0].thumbnailKey).path))
        let long = folder.appendingPathComponent("long.mov")
        try await fixture(long, duration: 61)
        do { _ = try await VideoFiles.inspect(long); preconditionFailure("Oversized duration accepted") }
        catch VideoFiles.ImportError.tooLong { }
        print("PASS: video migration, playable local copy after source removal, thumbnail, deduplication, vote link, mixed order, invalid media rejection, 60-second limit, database reopen")
    }

    @MainActor static func container(_ url: URL, legacy: Bool = false) throws -> ModelContainer {
        let schema = legacy ? Schema([Identity.self, HabitAction.self, Scrapbook.self, Vote.self, TextEntry.self, PhotoEntry.self])
            : Schema([Identity.self, HabitAction.self, Scrapbook.self, Vote.self, TextEntry.self, PhotoEntry.self, VideoEntry.self, AudioEntry.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    }
    @MainActor static func seed(_ url: URL) throws {
        try IdentityStore.create(name: "読む自分", minimum: "1ページ", normal: "20分", in: container(url, legacy: true))
    }
    @MainActor static func exercise(_ url: URL, source: URL, root: URL) async throws {
        let store = try container(url)
        let context = ModelContext(store)
        let identity = try context.fetch(FetchDescriptor<Identity>()).first!
        let book = identity.scrapbook!.id
        let vote = try VoteStore.cast(identityID: identity.id, actionID: identity.actions[0].id, submissionID: UUID(), in: store)
        let id = UUID()
        for _ in 0..<2 { _ = try await VideoStore.add(source, bookID: book, voteID: vote.id, submissionID: id, in: store, root: root) }
        _ = try EntryStore.addText("after video", bookID: book, voteID: nil, submissionID: UUID(), in: store)
        let invalid = root.appendingPathComponent("invalid.mov")
        try Data("not a video".utf8).write(to: invalid)
        do {
            _ = try await VideoStore.add(invalid, bookID: book, voteID: nil, submissionID: UUID(), in: store, root: root)
            preconditionFailure("Invalid video accepted")
        } catch { }
    }

    static func fixture(_ url: URL, duration: Double) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        precondition(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for time in [0.0, duration] {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pixels = buffer!
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), 100, CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            precondition(adaptor.append(pixels, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        precondition(writer.status == .completed)
    }
}
