import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: NOT-06 (search predicate matches title + block text)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/NoteSearchTests

/// NoteSearchTests — search predicate coverage for Note title + NoteBlock text.
///
/// NOT-06: The search predicate matches note title and all block text; non-matches are excluded.
///
/// Tests are PURE — no ModelContainer needed for search; Note/NoteBlock are constructed
/// in-memory and used directly with NoteSearchFilter.
@MainActor
struct NoteSearchTests {

    // MARK: - NOT-06: Search predicate

    @Test("matchesTitleAndBlockText: predicate matches title and block text; non-matches excluded — NOT-06")
    func matchesTitleAndBlockText() throws {
        // Arrange: a note with title "Groceries" and a checkbox block "buy milk"
        let container = try ModelContainer(for: Note.self, NoteBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext

        let groceriesNote = Note(title: "Groceries")
        ctx.insert(groceriesNote)

        let milkBlock = NoteBlock(kindRaw: "checkbox", text: "buy milk", order: 0)
        milkBlock.note = groceriesNote
        ctx.insert(milkBlock)

        groceriesNote.blocks = [milkBlock]

        let unrelatedNote = Note(title: "Meeting notes")
        ctx.insert(unrelatedNote)

        let cheeseBlock = NoteBlock(kindRaw: "text", text: "discuss budget", order: 0)
        cheeseBlock.note = unrelatedNote
        ctx.insert(cheeseBlock)

        unrelatedNote.blocks = [cheeseBlock]

        try ctx.save()

        // Act + Assert — case-insensitive match on block text
        #expect(NoteSearchFilter.matches(groceriesNote, query: "milk"),
                "Should match note whose block text contains 'milk'")
        #expect(NoteSearchFilter.matches(groceriesNote, query: "MILK"),
                "Search should be case-insensitive (uppercase)")
        #expect(NoteSearchFilter.matches(groceriesNote, query: "Milk"),
                "Search should be case-insensitive (mixed case)")

        // Match on title
        #expect(NoteSearchFilter.matches(groceriesNote, query: "Groceries"),
                "Should match on exact title")
        #expect(NoteSearchFilter.matches(groceriesNote, query: "grocer"),
                "Should match on partial title")

        // Non-match: note with neither title nor block containing "milk"
        #expect(!NoteSearchFilter.matches(unrelatedNote, query: "milk"),
                "Note with no title/block containing 'milk' must be excluded")

        // filter() convenience — returns only matching notes
        let allNotes = [groceriesNote, unrelatedNote]
        let results = NoteSearchFilter.filter(allNotes, query: "milk")
        #expect(results.count == 1, "filter should return exactly 1 match for 'milk'")
        #expect(results.first?.id == groceriesNote.id, "Only groceriesNote matches 'milk'")

        // Empty query matches everything
        let noFilter = NoteSearchFilter.filter(allNotes, query: "")
        #expect(noFilter.count == 2, "Empty query should return all notes")
    }
}
