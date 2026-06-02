import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: ING-14, D7-13
// Threat ref: none (pure logic against an in-memory store)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/DedupCheckerTests
// Plan 07-01 — RED phase: DedupChecker is unimplemented (plan 03).
// Tests FAIL RED via Issue.record until plan 03 provides DedupChecker.

// Disambiguate from the Objective-C runtime's `Category` typedef.
private typealias Cat = MyHome.Category

/// DedupCheckerTests — unit tests for DedupChecker duplicate-detection logic.
///
/// ING-14: Duplicate detection prevents double-insertion of the same transaction.
/// D7-13:  Match criteria: same amount + overlapping merchant substring + date within ±1 day.
@MainActor
struct DedupCheckerTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Cat.self, Note.self, NoteBlock.self,
                                  configurations: config)
    }

    // MARK: - ING-14: Exact match within ±1 day returns existing expense

    @Test("findDuplicate: same amount + overlapping merchant + date within ±1 day → returns match — ING-14, D7-13")
    func findsDuplicateWithinOneDay() throws {
        Issue.record("DedupChecker unimplemented — plan 03")
        // let container = try makeContainer()
        // let context = container.mainContext
        // let existing = Expense(amount: Decimal(1250), date: Date())
        // existing.note = "Amazon"
        // context.insert(existing)
        // try context.save()
        //
        // let candidate = ParsedExpense(
        //     amount: Decimal(1250),
        //     rawMerchant: "AMAZON IN BLR",
        //     normalizedMerchant: "Amazon",
        //     categoryHint: nil,
        //     date: Date(),
        //     rawSourceLabel: "HDFC CC",
        //     isReversal: false,
        //     fingerprintScore: 1.0,
        //     extractionScore: 1.0
        // )
        // let allExpenses = try context.fetch(FetchDescriptor<Expense>())
        // let match = DedupChecker.findDuplicate(of: candidate, in: allExpenses)
        // #expect(match != nil, "Should find duplicate for same amount + merchant + date — ING-14")
    }

    // MARK: - D7-13: Outside ±1 day returns nil

    @Test("findDuplicate: same amount + merchant but date > 1 day apart → no match — D7-13")
    func noDuplicateOutsideOneDay() throws {
        Issue.record("DedupChecker unimplemented — plan 03")
        // let container = try makeContainer()
        // let context = container.mainContext
        // let oldDate = Date().addingTimeInterval(-2 * 24 * 3600)  // 2 days ago
        // let existing = Expense(amount: Decimal(1250), date: oldDate)
        // existing.note = "Amazon"
        // context.insert(existing)
        // try context.save()
        //
        // let candidate = ParsedExpense(
        //     amount: Decimal(1250),
        //     rawMerchant: "AMAZON IN BLR",
        //     normalizedMerchant: "Amazon",
        //     categoryHint: nil,
        //     date: Date(),
        //     rawSourceLabel: "HDFC CC",
        //     isReversal: false,
        //     fingerprintScore: 1.0,
        //     extractionScore: 1.0
        // )
        // let allExpenses = try context.fetch(FetchDescriptor<Expense>())
        // let match = DedupChecker.findDuplicate(of: candidate, in: allExpenses)
        // #expect(match == nil, "Different date (>1 day) should not match — D7-13")
    }

    // MARK: - D7-13: Different amount returns nil

    @Test("findDuplicate: different amount + same merchant + same date → no match — D7-13")
    func noDuplicateForDifferentAmount() throws {
        Issue.record("DedupChecker unimplemented — plan 03")
        // let container = try makeContainer()
        // let context = container.mainContext
        // let existing = Expense(amount: Decimal(2500), date: Date())
        // existing.note = "Amazon"
        // context.insert(existing)
        // try context.save()
        //
        // let candidate = ParsedExpense(
        //     amount: Decimal(1250),   // different amount
        //     rawMerchant: "AMAZON IN BLR",
        //     normalizedMerchant: "Amazon",
        //     categoryHint: nil,
        //     date: Date(),
        //     rawSourceLabel: "HDFC CC",
        //     isReversal: false,
        //     fingerprintScore: 1.0,
        //     extractionScore: 1.0
        // )
        // let allExpenses = try context.fetch(FetchDescriptor<Expense>())
        // let match = DedupChecker.findDuplicate(of: candidate, in: allExpenses)
        // #expect(match == nil, "Different amount should not match — D7-13")
    }
}
