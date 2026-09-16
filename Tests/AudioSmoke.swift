import Foundation
import SwiftData
import AVFoundation

@main
struct AudioSmoke {
    @MainActor static func main() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.m4a")
        try fixture(source)
        let root = folder.appendingPathComponent("assets")
        let url = folder.appendingPathComponent("test.store")
        try seed(url)
        try await exercise(url, source: source, root: root)
        try FileManager.default.removeItem(at: source)
        let store = try container(url)
        let context = ModelContext(store)
        let audio = try context.fetch(FetchDescriptor<AudioEntry>(sortBy: [SortDescriptor(\.sequence)]))
        let notes = try context.fetch(FetchDescriptor<TextEntry>())
        precondition(audio.count == 2 && notes.count == 1)
        precondition(audio.map(\.sequence) == [0, 2] && notes[0].sequence == 1)
        precondition(audio[0].linkedVoteID != nil && audio[1].linkedVoteID == nil)
        precondition(audio[0].waveform.count == 60)
        precondition(audio[0].waveform.allSatisfy { $0.isFinite && (0...1).contains($0) })
        for entry in audio {
            let saved = root.appendingPathComponent(entry.audioKey)
            precondition(tryDuration(saved) > 0.9)
            let player = try AVAudioPlayer(contentsOf: saved)
            precondition(player.duration > 0.9)
        }
        let votes = try context.fetch(FetchDescriptor<Vote>())
        precondition(votes.count == 1)
        print("PASS: audio migration, readable local recording after draft removal, duration, waveform, deduplication, independent/linkable memories, mixed order, invalid-file rejection, database reopen")
    }

    static func tryDuration(_ url: URL) -> Double { try! AudioFiles.duration(of: url) }
    @MainActor static func container(_ url: URL, legacy: Bool = false) throws -> ModelContainer {
        let schema = legacy ? Schema([Identity.self, HabitAction.self, Scrapbook.self, Vote.self, TextEntry.self, PhotoEntry.self, VideoEntry.self])
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
        let waveform = (0..<120).map { abs(sin(Double($0) / 10)) }
        for _ in 0..<2 { _ = try await AudioStore.add(source, waveform: waveform, bookID: book, voteID: vote.id, submissionID: id, in: store, root: root) }
        _ = try EntryStore.addText("after audio", bookID: book, voteID: nil, submissionID: UUID(), in: store)
        _ = try await AudioStore.add(source, waveform: waveform, bookID: book, voteID: nil, submissionID: UUID(), in: store, root: root)
        let invalid = root.appendingPathComponent("invalid.m4a")
        try Data("not audio".utf8).write(to: invalid)
        do {
            _ = try await AudioStore.add(invalid, waveform: [], bookID: book, voteID: nil, submissionID: UUID(), in: store, root: root)
            preconditionFailure("Invalid audio accepted")
        } catch { }
    }

    static func fixture(_ url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000])
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        for frame in 0..<44_100 { buffer.floatChannelData![0][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 44_100) * 0.2) }
        try file.write(from: buffer)
    }
}
