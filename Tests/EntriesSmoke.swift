import Foundation
import SwiftData

@main
struct EntriesSmoke {
    @MainActor static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("test.store")
        try seed(url)
        try exercise(url)
        let store = try container(url)
        let context = ModelContext(store)
        let entries = try context.fetch(FetchDescriptor<TextEntry>(sortBy: [SortDescriptor(\.sequence)]))
        precondition(entries.count == 2)
        precondition(entries[0].paperStyle == 0 && entries[1].paperStyle == 1)
        precondition(entries[0].linkedVoteID != nil && entries[1].linkedVoteID == nil)
        precondition(entries[0].entryDate == "2026-01-02")
        precondition(entries[1].body == "日本語の思い出\n\n二つ目の段落 🌱")
        let votes = try context.fetch(FetchDescriptor<Vote>())
        precondition(votes.count == 1 && votes[0].undoneAt != nil)
        print("PASS: migration, linked/manual notes, deduplication, blank rejection, wrong-book rejection, stable colors/order, local date, full text and disk reopen; undo preserves notes")
    }

    @MainActor static func container(_ url: URL, legacy: Bool = false) throws -> ModelContainer {
        let schema = legacy ? Schema([Identity.self, HabitAction.self, Scrapbook.self, Vote.self])
            : Schema([Identity.self, HabitAction.self, Scrapbook.self, Vote.self, TextEntry.self, PhotoEntry.self, VideoEntry.self, AudioEntry.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    }

    @MainActor static func seed(_ url: URL) throws {
        let store = try container(url, legacy: true)
        try IdentityStore.create(name: "読む自分", minimum: "1ページ", normal: "20分", in: store)
        try IdentityStore.create(name: "走る自分", minimum: "1分", normal: "20分", in: store)
    }

    @MainActor static func exercise(_ url: URL) throws {
        let store = try container(url)
        let context = ModelContext(store)
        let identities = try context.fetch(FetchDescriptor<Identity>(sortBy: [SortDescriptor(\.createdAt)]))
        let person = identities[0], book = person.scrapbook!.id
        let vote = try VoteStore.cast(identityID: person.id, actionID: person.actions[0].id, submissionID: UUID(), in: store)
        let submission = UUID()
        let now = ISO8601DateFormatter().date(from: "2026-01-01T16:30:00Z")!
        for _ in 0..<2 {
            _ = try EntryStore.addText("今日の一歩", bookID: book, voteID: vote.id, submissionID: submission,
                                       in: store, now: now, timeZone: TimeZone(identifier: "Asia/Taipei")!)
        }
        _ = try EntryStore.addText("日本語の思い出\n\n二つ目の段落 🌱", bookID: book, voteID: nil, submissionID: UUID(), in: store)
        do {
            _ = try EntryStore.addText(" \n", bookID: book, voteID: nil, submissionID: UUID(), in: store)
            preconditionFailure("Blank saved")
        } catch { }
        do {
            _ = try EntryStore.addText("wrong book", bookID: identities[1].scrapbook!.id, voteID: vote.id, submissionID: UUID(), in: store)
            preconditionFailure("Cross-identity link saved")
        } catch { }
        try VoteStore.undo(id: vote.id, in: store)
    }
}
