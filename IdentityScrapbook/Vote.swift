import Foundation
import SwiftData

@Model
final class Vote {
    // The ID is generated before submission and reused on retry.
    @Attribute(.unique) var id: UUID
    var identityID: UUID
    var actionID: UUID
    var identityNameSnapshot: String
    var actionTextSnapshot: String
    var levelSnapshot: ActionLevel
    var recordedAt: Date
    var performedOn: String
    var timeZoneID: String
    var undoneAt: Date?

    init(id: UUID, identity: Identity, action: HabitAction, now: Date, timeZone: TimeZone) {
        self.id = id
        identityID = identity.id
        actionID = action.id
        identityNameSnapshot = identity.name
        actionTextSnapshot = action.actionText
        levelSnapshot = action.level
        recordedAt = now
        timeZoneID = timeZone.identifier
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        performedOn = formatter.string(from: now)
    }
}

struct VoteReceipt {
    let id: UUID
    let identityName: String
    let actionText: String

    init(_ vote: Vote) {
        id = vote.id
        identityName = vote.identityNameSnapshot
        actionText = vote.actionTextSnapshot
    }
}

@MainActor
enum VoteStore {
    enum StoreError: Error { case missingRecord, mismatchedSubmission, alreadyUndone }

    static func cast(identityID: UUID, actionID: UUID, submissionID: UUID,
                     in container: ModelContainer, now: Date = Date(),
                     timeZone: TimeZone = .current) throws -> VoteReceipt {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        if let existing = try context.fetch(FetchDescriptor<Vote>(
            predicate: #Predicate { $0.id == submissionID }
        )).first {
            guard existing.identityID == identityID, existing.actionID == actionID else {
                throw StoreError.mismatchedSubmission
            }
            guard existing.undoneAt == nil else { throw StoreError.alreadyUndone }
            return VoteReceipt(existing)
        }
        guard let identity = try context.fetch(FetchDescriptor<Identity>(
            predicate: #Predicate { $0.id == identityID }
        )).first,
              let action = identity.actions.first(where: { $0.id == actionID }) else {
            throw StoreError.missingRecord
        }
        let vote = Vote(id: submissionID, identity: identity, action: action, now: now, timeZone: timeZone)
        context.insert(vote)
        do {
            try context.save()
            return VoteReceipt(vote)
        } catch {
            context.rollback()
            throw error
        }
    }

    static func undo(id: UUID, in container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        guard let vote = try context.fetch(FetchDescriptor<Vote>(
            predicate: #Predicate { $0.id == id }
        )).first else { throw StoreError.missingRecord }
        guard vote.undoneAt == nil else { return }
        vote.undoneAt = Date()
        do { try context.save() } catch {
            context.rollback()
            throw error
        }
    }
}
