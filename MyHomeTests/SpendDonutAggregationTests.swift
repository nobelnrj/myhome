import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: OVR-05 (top-4 spend + Others roll-up, self-transfer exclusion, zero-spend empty state)
// Validation command: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/SpendDonutAggregationTests

// Disambiguation: Objective-C runtime also defines `Category`.
private typealias Cat = MyHome.Category

/// SpendDonutAggregationTests — pure-logic tests for OVR-05 donut helper.
///
/// Covers: top-4 descending + Others roll-up, alphabetical tie-break, self-transfer exclusion,
/// fewer-than-5 categories (no Others), zero-sum Others (no Others entry), zero-spend empty state.
@MainActor
struct SpendDonutAggregationTests {

    // MARK: - Container

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Expense.self, Cat.self, Note.self, NoteBlock.self,
            configurations: config
        )
    }

    // MARK: - Helpers

    private func makeExpense(
        context: ModelContext,
        amount: Decimal,
        category: Cat?,
        isTransfer: Bool? = nil
    ) -> Expense {
        let e = Expense(amount: amount)
        if let cat = category {
            e.categories = [cat]
        } else {
            e.categories = []
        }
        e.isTransfer = isTransfer
        context.insert(e)
        return e
    }

    // MARK: - OVR-05: Top-4 + Others roll-up (6 categories → top-4 + Others)

    @Test("donutSegments_top4PlusOthers: 6 categories with spend → 4 named + 1 Others")
    func donutSegments_top4PlusOthers() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let catA = Cat(name: "Groceries", symbolName: "cart")
        let catB = Cat(name: "Dining", symbolName: "fork.knife")
        let catC = Cat(name: "Fuel", symbolName: "fuelpump")
        let catD = Cat(name: "Shopping", symbolName: "bag")
        let catE = Cat(name: "Health", symbolName: "cross.case")
        let catF = Cat(name: "Entertainment", symbolName: "film")
        [catA, catB, catC, catD, catE, catF].forEach { context.insert($0) }
        try context.save()

        // Spend: A=600, B=500, C=400, D=300, E=200, F=100
        let expenses = [
            makeExpense(context: context, amount: 600, category: catA),
            makeExpense(context: context, amount: 500, category: catB),
            makeExpense(context: context, amount: 400, category: catC),
            makeExpense(context: context, amount: 300, category: catD),
            makeExpense(context: context, amount: 200, category: catE),
            makeExpense(context: context, amount: 100, category: catF),
        ]
        try context.save()

        let segments = SpendDonutAggregation.donutSegments(
            expenses: expenses,
            categories: [catA, catB, catC, catD, catE, catF]
        )

        // Should have 5 entries: 4 named + 1 Others
        #expect(segments.count == 5,
                "6 categories → 4 named + 1 Others; got \(segments.count)")

        // First 4 are the top spenders (A=600, B=500, C=400, D=300)
        #expect(segments[0].spent == 600, "First segment should be A=600, got \(segments[0].spent)")
        #expect(segments[1].spent == 500, "Second segment should be B=500, got \(segments[1].spent)")
        #expect(segments[2].spent == 400, "Third segment should be C=400, got \(segments[2].spent)")
        #expect(segments[3].spent == 300, "Fourth segment should be D=300, got \(segments[3].spent)")

        // 5th is Others (E+F = 200+100 = 300)
        #expect(segments[4].category == nil, "Others entry must have nil category")
        #expect(segments[4].spent == 300, "Others = E(200)+F(100) = 300, got \(segments[4].spent)")
    }

    // MARK: - OVR-05: Alphabetical tie-break on equal spend

    @Test("donutSegments_alphabeticalTieBreak: equal spend → tie-broken alphabetically by category.name")
    func donutSegments_alphabeticalTieBreak() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // 5 categories all with spend 100 → "Dining" < "Fuel" < "Groceries" < "Health" < "Shopping"
        let catDining  = Cat(name: "Dining",  symbolName: "fork.knife")
        let catFuel    = Cat(name: "Fuel",    symbolName: "fuelpump")
        let catGroc    = Cat(name: "Groceries", symbolName: "cart")
        let catHealth  = Cat(name: "Health",  symbolName: "cross.case")
        let catShop    = Cat(name: "Shopping", symbolName: "bag")
        [catDining, catFuel, catGroc, catHealth, catShop].forEach { context.insert($0) }
        try context.save()

        let expenses = [
            makeExpense(context: context, amount: 100, category: catDining),
            makeExpense(context: context, amount: 100, category: catFuel),
            makeExpense(context: context, amount: 100, category: catGroc),
            makeExpense(context: context, amount: 100, category: catHealth),
            makeExpense(context: context, amount: 100, category: catShop),
        ]
        try context.save()

        let segments = SpendDonutAggregation.donutSegments(
            expenses: expenses,
            categories: [catDining, catFuel, catGroc, catHealth, catShop]
        )

        // All equal spend → 5th would be Others but Others total is 0, so only 4 named
        // (All have same spend, top-4 alphabetically: Dining, Fuel, Groceries, Health)
        // Shopping (alphabetically last) is rank 5 — othersTotal=100 > 0 → Others appears
        #expect(segments.count == 5, "5 equal-spend categories → 4 named + 1 Others; got \(segments.count)")
        #expect(segments[0].category?.name == "Dining",
                "Alphabetically first (Dining) should rank first, got \(segments[0].category?.name ?? "nil")")
        #expect(segments[1].category?.name == "Fuel",
                "Second alphabetically (Fuel) should rank second, got \(segments[1].category?.name ?? "nil")")
        #expect(segments[2].category?.name == "Groceries",
                "Third alphabetically (Groceries) should rank third, got \(segments[2].category?.name ?? "nil")")
        #expect(segments[3].category?.name == "Health",
                "Fourth alphabetically (Health) should rank fourth, got \(segments[3].category?.name ?? "nil")")
        #expect(segments[4].category == nil, "Shopping rolled into Others (nil category)")
        #expect(segments[4].spent == 100, "Others = Shopping(100), got \(segments[4].spent)")
    }

    // MARK: - OVR-05: Self-transfer exclusion — isTransfer==true contributes zero

    @Test("donutSegments_selfTransferExclusion: isTransfer==true expense contributes zero")
    func donutSegments_selfTransferExclusion() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let catA = Cat(name: "Groceries", symbolName: "cart")
        context.insert(catA)
        try context.save()

        // One normal expense + one transfer — transfer must be excluded
        let normalExpense   = makeExpense(context: context, amount: 500, category: catA, isTransfer: nil)
        let transferExpense = makeExpense(context: context, amount: 1000, category: catA, isTransfer: true)
        try context.save()

        let segments = SpendDonutAggregation.donutSegments(
            expenses: [normalExpense, transferExpense],
            categories: [catA]
        )

        #expect(segments.count == 1, "One category with spend; got \(segments.count)")
        #expect(segments[0].spent == 500,
                "Transfer must be excluded; only normal spend (500) counts, got \(segments[0].spent)")
    }

    // MARK: - OVR-05: isTransfer==nil is included (not a transfer)

    @Test("donutSegments_nilTransferIncluded: isTransfer==nil expense is included in totals")
    func donutSegments_nilTransferIncluded() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let catA = Cat(name: "Groceries", symbolName: "cart")
        context.insert(catA)
        try context.save()

        let e = makeExpense(context: context, amount: 300, category: catA, isTransfer: nil)
        try context.save()

        let segments = SpendDonutAggregation.donutSegments(
            expenses: [e],
            categories: [catA]
        )

        #expect(segments.count == 1, "isTransfer nil should be included")
        #expect(segments[0].spent == 300, "Amount should be 300, got \(segments[0].spent)")
    }

    // MARK: - OVR-05: Fewer than 5 categories → no Others entry

    @Test("donutSegments_fewerThan5_noOthers: 4 categories with spend → 4 entries, no Others")
    func donutSegments_fewerThan5_noOthers() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let catA = Cat(name: "Groceries",    symbolName: "cart")
        let catB = Cat(name: "Dining",       symbolName: "fork.knife")
        let catC = Cat(name: "Fuel",         symbolName: "fuelpump")
        let catD = Cat(name: "Shopping",     symbolName: "bag")
        [catA, catB, catC, catD].forEach { context.insert($0) }
        try context.save()

        let expenses = [
            makeExpense(context: context, amount: 400, category: catA),
            makeExpense(context: context, amount: 300, category: catB),
            makeExpense(context: context, amount: 200, category: catC),
            makeExpense(context: context, amount: 100, category: catD),
        ]
        try context.save()

        let segments = SpendDonutAggregation.donutSegments(
            expenses: expenses,
            categories: [catA, catB, catC, catD]
        )

        #expect(segments.count == 4, "4 categories → exactly 4 segments, no Others; got \(segments.count)")
        // Verify no nil-category entry
        let hasOthers = segments.contains { $0.category == nil }
        #expect(!hasOthers, "No Others entry should be emitted when fewer than 5 categories have spend")
    }

    // MARK: - OVR-05: 5th+ categories sum to zero → no Others entry

    @Test("donutSegments_othersZero_noOthersEntry: 5th+ category with zero spend → no Others emitted")
    func donutSegments_othersZero_noOthersEntry() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let catA = Cat(name: "Groceries",    symbolName: "cart")
        let catB = Cat(name: "Dining",       symbolName: "fork.knife")
        let catC = Cat(name: "Fuel",         symbolName: "fuelpump")
        let catD = Cat(name: "Shopping",     symbolName: "bag")
        let catE = Cat(name: "Health",       symbolName: "cross.case")
        [catA, catB, catC, catD, catE].forEach { context.insert($0) }
        try context.save()

        // Only 4 have spend; catE has no expenses (zero spend)
        let expenses = [
            makeExpense(context: context, amount: 400, category: catA),
            makeExpense(context: context, amount: 300, category: catB),
            makeExpense(context: context, amount: 200, category: catC),
            makeExpense(context: context, amount: 100, category: catD),
        ]
        try context.save()

        let segments = SpendDonutAggregation.donutSegments(
            expenses: expenses,
            categories: [catA, catB, catC, catD, catE]
        )

        // catE has zero spend → should not appear in top-4 or Others (Others total = 0)
        #expect(segments.count == 4, "Only 4 categories have spend > 0; catE zero spend → no Others; got \(segments.count)")
        let hasOthers = segments.contains { $0.category == nil }
        #expect(!hasOthers, "Zero-spend Others total must not emit an Others entry")
    }

    // MARK: - OVR-05: Zero-spend input → empty array, no crash

    @Test("donutSegments_zeroSpend_emptyArray: no expenses → returns empty array with no crash")
    func donutSegments_zeroSpend_emptyArray() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let catA = Cat(name: "Groceries", symbolName: "cart")
        context.insert(catA)
        try context.save()

        let segments = SpendDonutAggregation.donutSegments(
            expenses: [],
            categories: [catA]
        )

        #expect(segments.isEmpty, "Zero-spend input must return empty array (donut empty-state driver)")
    }

    // MARK: - OVR-05: Empty categories list → empty array, no crash

    @Test("donutSegments_emptyCategories_emptyArray: empty categories → returns empty array")
    func donutSegments_emptyCategories_emptyArray() throws {
        let segments = SpendDonutAggregation.donutSegments(expenses: [], categories: [])
        #expect(segments.isEmpty, "Empty input must return empty array with no crash")
    }
}
