import Foundation
import SwiftData

enum ActionLevel: String, Codable {
    case minimum, normal
}

@Model
final class Identity {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \HabitAction.identity)
    var actions: [HabitAction] = []
    @Relationship(deleteRule: .cascade, inverse: \Scrapbook.identity)
    var scrapbook: Scrapbook?

    init(name: String) {
        id = UUID()
        self.name = name
        createdAt = Date()
    }
}

@Model
final class HabitAction {
    @Attribute(.unique) var id: UUID
    var actionText: String
    var level: ActionLevel
    var sortOrder: Int
    var identity: Identity?

    init(text: String, level: ActionLevel, sortOrder: Int) {
        id = UUID()
        actionText = text
        self.level = level
        self.sortOrder = sortOrder
    }
}

@Model
final class Scrapbook {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var coverStyleID: String
    var identity: Identity?

    init() {
        id = UUID()
        createdAt = Date()
        coverStyleID = ["sage", "peach", "lavender"].randomElement() ?? "sage"
    }
}

enum IdentityStore {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([Identity.self, HabitAction.self, Scrapbook.self, Vote.self, TextEntry.self])
        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // Isolate this save so rollback cannot discard changes from another screen.
    static func create(name: String, minimum: String, normal: String,
                       in container: ModelContainer) throws {
        let values = [name, minimum, normal].map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard values.allSatisfy({ !$0.isEmpty }) else { throw CreationError.blankFields }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let identity = Identity(name: values[0])
        context.insert(identity)
        identity.actions = [
            HabitAction(text: values[1], level: .minimum, sortOrder: 0),
            HabitAction(text: values[2], level: .normal, sortOrder: 1)
        ]
        identity.scrapbook = Scrapbook()
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private enum CreationError: Error { case blankFields }
}
