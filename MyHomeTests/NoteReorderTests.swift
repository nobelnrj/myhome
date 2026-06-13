import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Unit tests for NoteBlock drag-to-reorder (NOTE-04, D-11, Phase 12).
///
/// Verifies that the onMove re-index pattern (set block.order values and save)
/// persists the new order across a save/refetch cycle.
@MainActor
struct NoteReorderTests {

    // MARK: - Test Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Note.self, NoteBlock.self, configurations: config)
    }

    // MARK: - Tests

    @Test("onMove re-indexes order and persists across save")
    func reorderPersists() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let note = Note(title: "Checklist")
        note.isDailyRoutine = false
        context.insert(note)

        let b0 = NoteBlock(kindRaw: "checkbox", text: "A", order: 0)
        b0.note = note
        context.insert(b0)

        let b1 = NoteBlock(kindRaw: "checkbox", text: "B", order: 1)
        b1.note = note
        context.insert(b1)

        let b2 = NoteBlock(kindRaw: "checkbox", text: "C", order: 2)
        b2.note = note
        context.insert(b2)

        try context.save()

        // Simulate onMove: move index 2 (C) to index 0 → expected result: [C, A, B]
        var ordered = [b0, b1, b2]
        ordered.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        for (idx, b) in ordered.enumerated() { b.order = idx }
        try context.save()

        let refetched = try context.fetch(FetchDescriptor<NoteBlock>(sortBy: [SortDescriptor(\.order)]))
        #expect(refetched.map(\.text) == ["C", "A", "B"],
                "After moving index 2 to 0, order must be [C, A, B]")
    }
}
