import Foundation
import SwiftData

@main
struct VotingSmoke {
    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        // Start with the previously shipped schema to exercise additive migration.
        try seedLegacy(at: url)
        let ids = try exercise(at: url)
        let reopened = try container(at: url)
        let context = ModelContext(reopened)
        let votes = try context.fetch(FetchDescriptor<Vote>())
        precondition(votes.count == 2)
        precondition(votes.first { $0.id == ids.0 }?.undoneAt != nil)
        precondition(votes.first { $0.id == ids.1 }?.undoneAt == nil)
        precondition(votes.allSatisfy { $0.actionTextSnapshot == "1ページ読む" })
        precondition(votes.allSatisfy { $0.performedOn == "2026-01-02" })
        let identityCount = try context.fetchCount(FetchDescriptor<Identity>())
        precondition(identityCount == 1)
        print("PASS: legacy migration, deduplication, separate completions, snapshots, local day, targeted/idempotent undo, disk reopen")
    }

    @MainActor
    static func container(at url: URL, legacy: Bool = false) throws -> ModelContainer {
        let schema = legacy ? Schema([Identity.self, HabitAction.self, Scrapbook.self])
            : Schema([Identity.self, HabitAction.self, Scrapbook.self, Vote.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        ])
    }

    @MainActor
    static func seedLegacy(at url: URL) throws {
        let store = try container(at: url, legacy: true)
        try IdentityStore.create(name: "読む自分", minimum: "1ページ読む", normal: "20分読む", in: store)
    }

    @MainActor
    static func exercise(at url: URL) throws -> (UUID, UUID) {
        let store = try container(at: url)
        let context = ModelContext(store)
        let identity = try context.fetch(FetchDescriptor<Identity>()).first!
        let action = identity.actions.first { $0.level == .minimum }!
        let first = UUID(), second = UUID()
        let instant = ISO8601DateFormatter().date(from: "2026-01-01T16:30:00Z")!
        for submission in [first, first, second] {
            _ = try VoteStore.cast(identityID: identity.id, actionID: action.id,
                                   submissionID: submission, in: store, now: instant,
                                   timeZone: TimeZone(identifier: "Asia/Taipei")!)
        }
        do {
            _ = try VoteStore.cast(identityID: UUID(), actionID: action.id, submissionID: UUID(), in: store)
            preconditionFailure("Accepted an action belonging to another identity")
        } catch { }
        action.actionText = "新しい行動"
        try context.save()
        try VoteStore.undo(id: first, in: store)
        try VoteStore.undo(id: first, in: store)
        do {
            _ = try VoteStore.cast(identityID: identity.id, actionID: action.id, submissionID: first, in: store)
            preconditionFailure("Reactivated an undone submission")
        } catch { }
        return (first, second)
    }
}
