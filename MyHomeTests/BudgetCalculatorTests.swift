import Testing
import SwiftData
import Foundation
@testable import MyHome

// Disambiguate from the Objective-C runtime's `Category` typedef.
private typealias Cat = MyHome.Category

/// BudgetCalculator and BudgetProgressData tests — verifies EXP-08 (color thresholds,
/// remaining, fractionUsed) and EXP-09 (monthly aggregation, uncategorized bucket).
///
/// Uses an in-memory ModelContainer per test (FND-06, Pitfall 16) because
/// BudgetProgressData holds a Category @Model instance (requires PersistentIdentifier).
@MainActor
struct BudgetCalculatorTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Cat.self, configurations: config)
    }

    // MARK: - BudgetProgressData: color thresholds (EXP-08, D2-09)

    @Test("colorThreshold: budget 1000, spent 700 → fractionUsed 0.7, .normal, remaining 300")
    func colorThresholdNormal() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cat = Cat(name: "Groceries", symbolName: "cart")
        cat.monthlyBudget = Decimal(1000)
        context.insert(cat)
        try context.save()

        let data = BudgetProgressData(category: cat, spent: Decimal(700), budget: Decimal(1000))
        #expect(data.colorThreshold == .normal)
        #expect(data.remaining == Decimal(300))
        if let f = data.fractionUsed {
            #expect(f > 0.69 && f < 0.71, "Expected fractionUsed ≈ 0.7, got \(f)")
        } else {
            Issue.record("fractionUsed must not be nil when budget is 1000")
        }
    }

    @Test("colorThreshold: budget 1000, spent 850 → fractionUsed 0.85, .warning")
    func colorThresholdWarning() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cat = Cat(name: "Dining", symbolName: "fork.knife")
        context.insert(cat)
        try context.save()

        let data = BudgetProgressData(category: cat, spent: Decimal(850), budget: Decimal(1000))
        #expect(data.colorThreshold == .warning)
    }

    @Test("colorThreshold: budget 1000, spent 1200 → .overBudget, remaining -200")
    func colorThresholdOverBudget() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cat = Cat(name: "Shopping", symbolName: "bag")
        context.insert(cat)
        try context.save()

        let data = BudgetProgressData(category: cat, spent: Decimal(1200), budget: Decimal(1000))
        #expect(data.colorThreshold == .overBudget)
        #expect(data.remaining == Decimal(-200))
    }

    @Test("exactly80: budget 1000, spent 800 → fractionUsed 0.8 → .warning (boundary inclusive)")
    func exactly80() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cat = Cat(name: "Fuel", symbolName: "fuelpump")
        context.insert(cat)
        try context.save()

        let data = BudgetProgressData(category: cat, spent: Decimal(800), budget: Decimal(1000))
        #expect(data.colorThreshold == .warning,
                "fractionUsed == 0.8 must map to .warning (boundary is inclusive)")
    }

    @Test("exactly100: budget 1000, spent 1000 → .overBudget (boundary inclusive)")
    func exactly100() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cat = Cat(name: "Utilities", symbolName: "bolt")
        context.insert(cat)
        try context.save()

        let data = BudgetProgressData(category: cat, spent: Decimal(1000), budget: Decimal(1000))
        #expect(data.colorThreshold == .overBudget,
                "fractionUsed == 1.0 must map to .overBudget (boundary inclusive)")
    }

    @Test("noBudget: budget nil → fractionUsed nil, remaining nil, colorThreshold .normal")
    func noBudget() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cat = Cat(name: "Misc", symbolName: "tray")
        context.insert(cat)
        try context.save()

        let data = BudgetProgressData(category: cat, spent: Decimal(500), budget: nil)
        #expect(data.fractionUsed == nil, "fractionUsed must be nil when budget is nil")
        #expect(data.remaining == nil, "remaining must be nil when budget is nil")
        #expect(data.colorThreshold == .normal,
                "colorThreshold must be .normal when fractionUsed is nil")
    }

    @Test("zeroBudgetGuard: budget 0 → fractionUsed nil (no divide-by-zero)")
    func zeroBudgetGuard() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cat = Cat(name: "Rent", symbolName: "house")
        context.insert(cat)
        try context.save()

        let data = BudgetProgressData(category: cat, spent: Decimal(100), budget: Decimal(0))
        #expect(data.fractionUsed == nil, "fractionUsed must be nil when budget is 0 (T-02-05)")
    }

    // MARK: - BudgetCalculator.monthlySpend (EXP-09)

    @Test("monthlyAggregation: expenses across two categories sum per category; refund reduces total")
    func monthlyAggregation() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let cat1 = Cat(name: "Groceries", symbolName: "cart")
        let cat2 = Cat(name: "Dining", symbolName: "fork.knife")
        context.insert(cat1)
        context.insert(cat2)
        try context.save()

        // Create expenses: cat1 = 300 + 200 - 50 (refund) = 450; cat2 = 100
        let e1 = Expense(amount: Decimal(300))
        e1.categories = [cat1]
        let e2 = Expense(amount: Decimal(200))
        e2.categories = [cat1]
        let e3 = Expense(amount: Decimal(-50))  // refund reduces cat1 spend
        e3.categories = [cat1]
        let e4 = Expense(amount: Decimal(100))
        e4.categories = [cat2]
        context.insert(e1)
        context.insert(e2)
        context.insert(e3)
        context.insert(e4)
        try context.save()

        let expenses = [e1, e2, e3, e4]
        let categories = [cat1, cat2]
        let totals = BudgetCalculator.monthlySpend(for: expenses, categories: categories)

        let total1 = totals[cat1.persistentModelID]
        let total2 = totals[cat2.persistentModelID]
        #expect(total1 == Decimal(450), "cat1 total must be 300+200-50=450, got \(String(describing: total1))")
        #expect(total2 == Decimal(100), "cat2 total must be 100, got \(String(describing: total2))")
    }

    @Test("uncategorizedBucket: expense with empty categories sums into uncategorized total, not per-category")
    func uncategorizedBucket() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let cat = Cat(name: "Groceries", symbolName: "cart")
        context.insert(cat)
        try context.save()

        let categorized = Expense(amount: Decimal(200))
        categorized.categories = [cat]
        let uncategorized = Expense(amount: Decimal(150))
        // uncategorized.categories is [] by default
        context.insert(categorized)
        context.insert(uncategorized)
        try context.save()

        let expenses = [categorized, uncategorized]
        let totals = BudgetCalculator.monthlySpend(for: expenses, categories: [cat])
        let uncategorizedTotal = BudgetCalculator.uncategorizedSpend(for: expenses)

        // The uncategorized expense must NOT appear in any category key
        #expect(totals[cat.persistentModelID] == Decimal(200),
                "Only categorized expense should be in the category total")
        #expect(totals.keys.count == 1, "Only one key (cat) should be in totals dict")
        #expect(uncategorizedTotal == Decimal(150),
                "Uncategorized spend must be 150, got \(uncategorizedTotal)")
    }

    // MARK: - BudgetCalculator.monthBoundaries (P2-05)

    @Test("monthBoundaries: start is first instant of month, end is last second — timezone-correct")
    func monthBoundaries() throws {
        // Use a known month: January 2026
        let components = DateComponents(year: 2026, month: 1)
        guard let bounds = BudgetCalculator.monthBoundaries(for: components) else {
            Issue.record("monthBoundaries must return a non-nil result for year/month components")
            return
        }

        var cal = Calendar.current
        cal.timeZone = .current

        // start must be the first instant of January 2026 in the user's timezone
        let startComps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: bounds.start)
        #expect(startComps.year == 2026)
        #expect(startComps.month == 1)
        #expect(startComps.day == 1)
        #expect(startComps.hour == 0)
        #expect(startComps.minute == 0)
        #expect(startComps.second == 0)

        // end must be the last second of January 2026 (January 31, 23:59:59)
        let endComps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: bounds.end)
        #expect(endComps.year == 2026)
        #expect(endComps.month == 1)
        #expect(endComps.day == 31)
        #expect(endComps.hour == 23)
        #expect(endComps.minute == 59)
        #expect(endComps.second == 59)

        // end must be after start
        #expect(bounds.end > bounds.start)
    }
}
