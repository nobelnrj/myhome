import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: OVR-01 (aggregate threshold math), OVR-02 (top-3 sort + tie-break),
//               OVR-03 (pinned/checklist-fallback/empty note resolution)
// Validation command: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/OverviewAggregationTests

// Disambiguation: Objective-C runtime also defines `Category`.
private typealias Cat = MyHome.Category

// MARK: - Expected function signatures (Plan 04-02 must implement these verbatim)
//
// namespace OverviewAggregation {
//
//   /// OVR-01: Compute aggregate fractionUsed and BudgetColor from total spend / total budget.
//   /// Returns (fractionUsed: nil, color: .normal) when totalBudget == 0.
//   static func aggregateThreshold(
//       totalSpend: Decimal,
//       totalBudget: Decimal
//   ) -> (fractionUsed: Double?, color: BudgetColor)
//
//   /// OVR-02: Sort categories by descending spend, tie-break alphabetically by name,
//   /// return at most 3 with spend > 0.
//   static func topCategories(
//       spendByCategory: [PersistentIdentifier: Decimal],
//       categories: [Category]
//   ) -> [(category: Category, spent: Decimal)]
//
//   /// OVR-03: Return the display note for the Overview pinned-note card.
//   /// Priority: pinned note (via NoteListOrganizer) → checklist note → nil (empty state).
//   static func pinnedOrChecklistNote(from notes: [Note]) -> Note?
// }

/// OverviewAggregationTests — pure-logic tests for the three OVR helper functions.
///
/// OVR-01: aggregate fractionUsed and color thresholds (mirrors BudgetProgressData boundaries: 0.8 / 1.0)
/// OVR-02: top-3 category sort (descending spend, alphabetical tie-break, only spend > 0)
/// OVR-03: pinned-note resolution (pinned → checklist fallback → nil)
///
/// These symbols do NOT exist until Plan 04-02. This file is expected to fail to compile/run
/// (RED) until the production helpers are written.
@MainActor
struct OverviewAggregationTests {

    // MARK: - Container

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Cat.self, Note.self, NoteBlock.self,
                                  configurations: config)
    }

    // MARK: - OVR-01: Aggregate threshold — fractionUsed 0.5 → .normal

    @Test("aggregateThreshold_normal: totalSpend / totalBudget = 0.5 → fractionUsed ≈ 0.5, color .normal")
    func aggregateThresholdNormal() throws {
        let result = OverviewAggregation.aggregateThreshold(
            totalSpend: Decimal(500),
            totalBudget: Decimal(1000)
        )

        if let fraction = result.fractionUsed {
            #expect(fraction > 0.49 && fraction < 0.51,
                    "fractionUsed at 500/1000 should be ≈ 0.5, got \(fraction)")
        } else {
            Issue.record("fractionUsed must not be nil when totalBudget is 1000")
        }
        #expect(result.color == .normal,
                "fractionUsed 0.5 must map to .normal")
    }

    // MARK: - OVR-01: fractionUsed 0.85 → .warning (boundary case)

    @Test("aggregateThreshold_warning: totalSpend / totalBudget = 0.85 → color .warning")
    func aggregateThresholdWarning() throws {
        let result = OverviewAggregation.aggregateThreshold(
            totalSpend: Decimal(850),
            totalBudget: Decimal(1000)
        )

        if let fraction = result.fractionUsed {
            #expect(fraction > 0.84 && fraction < 0.86,
                    "fractionUsed at 850/1000 should be ≈ 0.85, got \(fraction)")
        } else {
            Issue.record("fractionUsed must not be nil when totalBudget is 1000")
        }
        #expect(result.color == .warning,
                "fractionUsed 0.85 must map to .warning (boundary matches BudgetProgressData)")
    }

    // MARK: - OVR-01: fractionUsed 1.1 → .overBudget (over-budget case)

    @Test("aggregateThreshold_overBudget: totalSpend / totalBudget = 1.1 → color .overBudget")
    func aggregateThresholdOverBudget() throws {
        let result = OverviewAggregation.aggregateThreshold(
            totalSpend: Decimal(1100),
            totalBudget: Decimal(1000)
        )

        if let fraction = result.fractionUsed {
            #expect(fraction > 1.09 && fraction < 1.11,
                    "fractionUsed at 1100/1000 should be ≈ 1.1, got \(fraction)")
        } else {
            Issue.record("fractionUsed must not be nil when totalBudget is 1000")
        }
        #expect(result.color == .overBudget,
                "fractionUsed 1.1 must map to .overBudget")
    }

    // MARK: - OVR-01: totalBudget == 0 → fractionUsed nil → "no budget" branch

    @Test("aggregateThreshold_noBudget: totalBudget 0 → fractionUsed nil, color .normal (no divide-by-zero)")
    func aggregateThresholdNoBudget() throws {
        let result = OverviewAggregation.aggregateThreshold(
            totalSpend: Decimal(500),
            totalBudget: Decimal(0)
        )

        #expect(result.fractionUsed == nil,
                "fractionUsed must be nil when totalBudget is 0 (no budget set)")
        #expect(result.color == .normal,
                "color must be .normal in the no-budget branch")
    }

    // MARK: - OVR-01: totalSpend includes uncategorized (Open Question #1)

    @Test("aggregateThreshold_includesUncategorized: totalSpend is caller-computed sum of categorized + uncategorized")
    func aggregateThresholdIncludesUncategorized() throws {
        // This test verifies that the helper accepts any totalSpend value including uncategorized.
        // The caller (OverviewView) must pass:
        //   totalSpend = spendMap.values.reduce(.zero, +) + BudgetCalculator.uncategorizedSpend(for: expenses)
        let categorizedSpend = Decimal(600)
        let uncategorizedSpend = Decimal(200)
        let totalSpend = categorizedSpend + uncategorizedSpend   // 800
        let totalBudget = Decimal(1000)

        let result = OverviewAggregation.aggregateThreshold(
            totalSpend: totalSpend,
            totalBudget: totalBudget
        )

        // 800/1000 = 0.8 → warning boundary (inclusive)
        #expect(result.color == .warning,
                "800/1000 = 0.8 is the .warning boundary (inclusive); got \(result.color)")
    }

    // MARK: - OVR-02: Top-3 sort — 4 categories with spend → exactly 3 returned, descending

    @Test("topCategories_top3Descending: 4 categories with spend → exactly 3 returned, sorted descending by spend")
    func topCategories_top3Descending() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let catA = Cat(name: "Groceries", symbolName: "cart")
        let catB = Cat(name: "Dining", symbolName: "fork.knife")
        let catC = Cat(name: "Fuel", symbolName: "fuelpump")
        let catD = Cat(name: "Shopping", symbolName: "bag")
        context.insert(catA)
        context.insert(catB)
        context.insert(catC)
        context.insert(catD)
        try context.save()

        // Spend: Dining (500) > Groceries (300) > Fuel (200) > Shopping (100)
        let spendMap: [PersistentIdentifier: Decimal] = [
            catA.persistentModelID: Decimal(300),
            catB.persistentModelID: Decimal(500),
            catC.persistentModelID: Decimal(200),
            catD.persistentModelID: Decimal(100),
        ]

        let top3 = OverviewAggregation.topCategories(
            spendByCategory: spendMap,
            categories: [catA, catB, catC, catD]
        )

        #expect(top3.count == 3,
                "Top-3 with 4 spending categories must return exactly 3 rows, got \(top3.count)")

        // Must be in descending order: Dining (500), Groceries (300), Fuel (200)
        #expect(top3[0].spent == Decimal(500),
                "First entry should be Dining (500), got \(top3[0].spent)")
        #expect(top3[1].spent == Decimal(300),
                "Second entry should be Groceries (300), got \(top3[1].spent)")
        #expect(top3[2].spent == Decimal(200),
                "Third entry should be Fuel (200), got \(top3[2].spent)")
    }

    // MARK: - OVR-02: Alphabetical tie-break when spend is equal

    @Test("topCategories_alphabeticalTieBreak: equal-spend pair → tie-broken alphabetically by category.name")
    func topCategories_alphabeticalTieBreak() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // "Dining" < "Groceries" alphabetically — same spend → Dining should rank higher
        let catDining = Cat(name: "Dining", symbolName: "fork.knife")
        let catGroceries = Cat(name: "Groceries", symbolName: "cart")
        let catFuel = Cat(name: "Fuel", symbolName: "fuelpump")
        context.insert(catDining)
        context.insert(catGroceries)
        context.insert(catFuel)
        try context.save()

        // Dining and Groceries both have spend 300 (tie); Fuel has 200
        let spendMap: [PersistentIdentifier: Decimal] = [
            catDining.persistentModelID: Decimal(300),
            catGroceries.persistentModelID: Decimal(300),
            catFuel.persistentModelID: Decimal(200),
        ]

        let top3 = OverviewAggregation.topCategories(
            spendByCategory: spendMap,
            categories: [catDining, catGroceries, catFuel]
        )

        #expect(top3.count == 3,
                "All 3 spending categories should be included")

        // "Dining" < "Groceries" alphabetically → Dining ranks first in the tie
        let firstTwoNames = top3.prefix(2).compactMap { $0.category.name }
        #expect(firstTwoNames.contains("Dining"),
                "Dining (alphabetically first) must appear in the top 2 tied positions")
        #expect(firstTwoNames.contains("Groceries"),
                "Groceries must appear in the top 2 tied positions")

        // Alphabetical order among the tied pair: "Dining" < "Groceries"
        if let diningIndex = top3.firstIndex(where: { $0.category.name == "Dining" }),
           let groceriesIndex = top3.firstIndex(where: { $0.category.name == "Groceries" }) {
            #expect(diningIndex < groceriesIndex,
                    "Dining (D) should rank before Groceries (G) alphabetically when spend is equal")
        } else {
            Issue.record("Both Dining and Groceries must appear in top-3 result")
        }
    }

    // MARK: - OVR-02: Only categories with spend > 0 included; fewer than 3 → fewer rows returned

    @Test("topCategories_sparseSpend: only 1 category with spend > 0 → returns 1 row (no placeholders)")
    func topCategories_sparseSpend() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let catA = Cat(name: "Groceries", symbolName: "cart")
        let catB = Cat(name: "Dining", symbolName: "fork.knife")
        context.insert(catA)
        context.insert(catB)
        try context.save()

        // Only catA has spend; catB has zero (not in the map)
        let spendMap: [PersistentIdentifier: Decimal] = [
            catA.persistentModelID: Decimal(400),
        ]

        let top3 = OverviewAggregation.topCategories(
            spendByCategory: spendMap,
            categories: [catA, catB]
        )

        #expect(top3.count == 1,
                "Only 1 category has spend > 0; should return 1 row, not 2 (no placeholders)")
        #expect(top3.first?.spent == Decimal(400),
                "The single row must have spend 400")
    }

    // MARK: - OVR-03: Pinned note present → returns that note (routes through NoteListOrganizer)

    @Test("pinnedOrChecklistNote_pinned: pinned note present → returned as display note")
    func pinnedOrChecklistNote_pinned() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let pinnedNote = Note(title: "Pinned note")
        pinnedNote.isPinned = true
        let otherNote = Note(title: "Other note")
        context.insert(pinnedNote)
        context.insert(otherNote)
        try context.save()

        let result = OverviewAggregation.pinnedOrChecklistNote(from: [pinnedNote, otherNote])

        #expect(result?.title == "Pinned note",
                "Pinned note must be returned when one exists")
    }

    // MARK: - OVR-03: No pinned, but checklist note exists → returns checklist note (fallback)

    @Test("pinnedOrChecklistNote_checklistFallback: no pinned, checklist note present → returns checklist note")
    func pinnedOrChecklistNote_checklistFallback() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // A non-pinned note with a checkbox block
        let checklistNote = Note(title: "Shopping list")
        checklistNote.isPinned = false
        context.insert(checklistNote)

        let checkboxBlock = NoteBlock(kindRaw: "checkbox", text: "Milk", order: 0)
        checkboxBlock.note = checklistNote
        context.insert(checkboxBlock)
        checklistNote.blocks = [checkboxBlock]

        // A plain text note (no checkbox blocks)
        let textNote = Note(title: "Random note")
        textNote.isPinned = false
        context.insert(textNote)
        textNote.blocks = []

        try context.save()

        let result = OverviewAggregation.pinnedOrChecklistNote(from: [checklistNote, textNote])

        #expect(result?.title == "Shopping list",
                "Checklist note should be returned as fallback when no note is pinned")
    }

    // MARK: - OVR-03: Verify routing through NoteListOrganizer (not note.isPinned directly — Pitfall E)

    @Test("pinnedOrChecklistNote_usesNoteListOrganizer: dailyRoutine-and-pinned note is excluded from pinned card")
    func pinnedOrChecklistNote_usesNoteListOrganizer() throws {
        // A note that is both isPinned AND daily-recurring must NOT appear in the pinned card.
        // NoteListOrganizer.organize correctly excludes daily-recurring notes from .pinned.
        // This test verifies the routing goes through NoteListOrganizer.organize, not note.isPinned directly.
        let container = try makeContainer()
        let context = container.mainContext

        // Daily-recurring pinned note (should NOT appear in OVR-03 via NoteListOrganizer)
        let dailyRoutineNote = Note(title: "Daily routine note")
        dailyRoutineNote.isPinned = true
        // Set recurrence to daily so NoteListOrganizer places it in .dailyRoutine, not .pinned
        let recurrence = ReminderRecurrence(type: .daily, interval: 1)
        dailyRoutineNote.reminderRecurrenceData = try? JSONEncoder().encode(recurrence)
        context.insert(dailyRoutineNote)

        // Non-pinned checklist note (should appear as fallback)
        let checklistNote = Note(title: "Grocery list")
        checklistNote.isPinned = false
        context.insert(checklistNote)
        let block = NoteBlock(kindRaw: "checkbox", text: "Eggs", order: 0)
        block.note = checklistNote
        context.insert(block)
        checklistNote.blocks = [block]

        try context.save()

        // Verify NoteListOrganizer.organize correctly classifies the daily-routine note
        let sections = NoteListOrganizer.organize([dailyRoutineNote, checklistNote])
        #expect(sections.pinned.isEmpty,
                "dailyRoutine note must NOT appear in NoteListOrganizer.organize pinned section (Pitfall E)")

        // OverviewAggregation.pinnedOrChecklistNote must use NoteListOrganizer, not note.isPinned
        let result = OverviewAggregation.pinnedOrChecklistNote(from: [dailyRoutineNote, checklistNote])
        #expect(result?.title == "Grocery list",
                "Daily-routine-pinned note must be excluded; checklist note should be the fallback")
    }

    // MARK: - OVR-03: No pinned, no checklist → returns nil (empty state)

    @Test("pinnedOrChecklistNote_emptyState: no pinned, no checklist → nil")
    func pinnedOrChecklistNote_emptyState() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Only plain text notes, none pinned
        let note1 = Note(title: "Note 1")
        note1.isPinned = false
        note1.blocks = []
        let note2 = Note(title: "Note 2")
        note2.isPinned = false
        note2.blocks = []
        context.insert(note1)
        context.insert(note2)
        try context.save()

        let result = OverviewAggregation.pinnedOrChecklistNote(from: [note1, note2])

        #expect(result == nil,
                "nil must be returned (empty state) when no note is pinned and no note has a checkbox block")
    }

    // MARK: - OVR-03: Empty notes array → nil

    @Test("pinnedOrChecklistNote_emptyArray: empty notes array → nil")
    func pinnedOrChecklistNote_emptyArray() throws {
        let result = OverviewAggregation.pinnedOrChecklistNote(from: [])
        #expect(result == nil,
                "nil must be returned when notes array is empty")
    }
}
