import Foundation
import SwiftData

// Compile with Models.swift using the macOS SDK to exercise the actual store code.
@main
struct PersistenceSmoke {
    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IdentityScrapbook-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        let firstID = try createRecords(at: url)
        let reopened = try container(at: url)
        let context = ModelContext(reopened)
        let identities = try context.fetch(FetchDescriptor<Identity>())
        precondition(identities.count == 2)
        let reader = identities.first { $0.id == firstID }!
        precondition(reader.name == "本を読む自分")
        precondition(reader.actions.count == 2)
        precondition(Set(reader.actions.map(\.level.rawValue)) == ["minimum", "normal"])
        precondition(reader.actions.allSatisfy { $0.identity?.id == reader.id })
        precondition(reader.scrapbook?.identity?.id == reader.id)
        precondition(tryCount(HabitAction.self, context) == 4)
        precondition(tryCount(Scrapbook.self, context) == 2)
        print("PASS: validation, multiple identities, relationship integrity, and disk reopen")
    }

    @MainActor
    static func container(at url: URL) throws -> ModelContainer {
        let schema = Schema([Identity.self, HabitAction.self, Scrapbook.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        ])
    }

    @MainActor
    static func createRecords(at url: URL) throws -> UUID {
        let store = try container(at: url)
        for values in [(" \n", "one", "two"), ("name", " ", "two"), ("name", "one", "\n")] {
            do {
                try IdentityStore.create(name: values.0, minimum: values.1, normal: values.2, in: store)
                preconditionFailure("Blank input was accepted")
            } catch { }
        }
        precondition(tryCount(Identity.self, ModelContext(store)) == 0)
        try IdentityStore.create(name: " 本を読む自分 ", minimum: "1ページ読む", normal: "20分読む", in: store)
        let context = ModelContext(store)
        let reader = try context.fetch(FetchDescriptor<Identity>()).first!
        let id = reader.id
        try IdentityStore.create(name: "走る自分", minimum: "靴を履く", normal: "20分走る", in: store)
        return id
    }

    @MainActor
    static func tryCount<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) -> Int {
        try! context.fetchCount(FetchDescriptor<T>())
    }
}
