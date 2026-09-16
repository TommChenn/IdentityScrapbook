import Foundation
import SwiftData

@Model
final class TextEntry {
    @Attribute(.unique) var id: UUID
    var scrapbookID: UUID
    var linkedVoteID: UUID?
    var body: String
    var addedAt: Date
    var entryDate: String
    var timeZoneID: String
    var sequence: Int
    var paperStyle: Int

    init(id: UUID, bookID: UUID, voteID: UUID?, body: String, sequence: Int,
         paperStyle: Int, now: Date, timeZone: TimeZone) {
        self.id = id
        scrapbookID = bookID
        linkedVoteID = voteID
        self.body = body
        self.sequence = sequence
        self.paperStyle = paperStyle
        addedAt = now
        timeZoneID = timeZone.identifier
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        entryDate = formatter.string(from: now)
    }
}

@MainActor
enum EntryStore {
    enum SaveError: Error { case blank, missingBook, invalidVote, conflictingSubmission }

    static func addText(_ body: String, bookID: UUID, voteID: UUID?, submissionID: UUID,
                        in container: ModelContainer, now: Date = Date(),
                        timeZone: TimeZone = .current) throws -> UUID {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SaveError.blank }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        if let existing = try context.fetch(FetchDescriptor<TextEntry>(
            predicate: #Predicate { $0.id == submissionID }
        )).first {
            guard existing.scrapbookID == bookID, existing.linkedVoteID == voteID else {
                throw SaveError.conflictingSubmission
            }
            return existing.id
        }
        guard let book = try context.fetch(FetchDescriptor<Scrapbook>(
            predicate: #Predicate { $0.id == bookID }
        )).first else { throw SaveError.missingBook }
        if let voteID {
            guard let vote = try context.fetch(FetchDescriptor<Vote>(
                predicate: #Predicate { $0.id == voteID }
            )).first, vote.identityID == book.identity?.id else { throw SaveError.invalidVote }
        }
        var latest = FetchDescriptor<TextEntry>(predicate: #Predicate { $0.scrapbookID == bookID },
                                               sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        latest.fetchLimit = 1
        let previous = try context.fetch(latest).first
        let entry = TextEntry(id: submissionID, bookID: bookID, voteID: voteID, body: body,
                              sequence: (previous?.sequence ?? -1) + 1,
                              paperStyle: ((previous?.paperStyle ?? -1) + 1) % 3,
                              now: now, timeZone: timeZone)
        context.insert(entry)
        do { try context.save() } catch { context.rollback(); throw error }
        return entry.id
    }
}
