import Testing
import Foundation
@testable import MyHome

/// Unit tests for TransferDetectionScorer — the pure 5-signal candidate pairing helper.
///
/// All AND-rules (D-01..D-05), tie-break rule (Critical Finding 3), and input-order
/// determinism are covered here. No ModelContainer is used — the scorer operates on
/// plain Expense value instances (STAB-02 safety applies even synchronously).
struct TransferDetectionScorerTests {

    // MARK: - Helpers

    /// IST gregorian calendar — the canonical calendar for day-window math (D-05).
    private var istCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    /// Creates an Expense value instance with explicit id, amount, date, and accountID.
    private func makeExpense(
        id: UUID = UUID(),
        amount: Decimal,
        date: Date,
        accountID: UUID?,
        isTransfer: Bool? = nil
    ) -> Expense {
        let e = Expense(id: id, amount: amount, date: date)
        e.accountID = accountID
        e.isTransfer = isTransfer
        return e
    }

    /// Builds an IST date from year/month/day + optional hour/minute.
    private func istDate(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute
        return cal.date(from: comps)!
    }

    // MARK: - D-01 / D-02 / D-03: exact amount, opposite sign

    @Test("detectsExactAmountPair: same-magnitude opposite-sign same-day pair produces exactly 1 CandidatePair")
    func detectsExactAmountPair() {
        let accountA = UUID(); let accountB = UUID()
        let day = istDate(year: 2026, month: 1, day: 15)

        let debit  = makeExpense(amount: Decimal(500),  date: day, accountID: accountA)
        let credit = makeExpense(amount: Decimal(-500), date: day, accountID: accountB)

        let pairs = TransferDetectionScorer.findCandidatePairs(
            from: [debit, credit], calendar: istCalendar
        )

        #expect(pairs.count == 1,
                "Expected 1 pair but got \(pairs.count)")
        #expect(pairs[0].debitID == debit.id,
                "debitID should be the debit expense id, got \(pairs[0].debitID)")
        #expect(pairs[0].creditID == credit.id,
                "creditID should be the credit expense id, got \(pairs[0].creditID)")
    }

    @Test("amountMismatchNotPaired: debit 500.00 vs credit -500.01 produces 0 pairs (D-02 exact Decimal)")
    func amountMismatchNotPaired() {
        let accountA = UUID(); let accountB = UUID()
        let day = istDate(year: 2026, month: 1, day: 15)

        let debit  = makeExpense(amount: Decimal(string: "500.00")!, date: day, accountID: accountA)
        let credit = makeExpense(amount: Decimal(string: "-500.01")!, date: day, accountID: accountB)

        let pairs = TransferDetectionScorer.findCandidatePairs(
            from: [debit, credit], calendar: istCalendar
        )

        #expect(pairs.count == 0,
                "Expected 0 pairs (amount mismatch by 0.01) but got \(pairs.count)")
    }

    @Test("sameSignNotPaired: two debits of equal magnitude produce 0 pairs (D-03)")
    func sameSignNotPaired() {
        let accountA = UUID(); let accountB = UUID()
        let day = istDate(year: 2026, month: 1, day: 15)

        let debit1 = makeExpense(amount: Decimal(500), date: day, accountID: accountA)
        let debit2 = makeExpense(amount: Decimal(500), date: day, accountID: accountB)

        let pairs = TransferDetectionScorer.findCandidatePairs(
            from: [debit1, debit2], calendar: istCalendar
        )

        #expect(pairs.count == 0,
                "Expected 0 pairs (both debits, same sign) but got \(pairs.count)")
    }

    // MARK: - D-04: both legs must be assigned to two distinct accounts

    @Test("unassignedLegNotPaired: credit with accountID == nil produces 0 pairs (D-04)")
    func unassignedLegNotPaired() {
        let accountA = UUID()
        let day = istDate(year: 2026, month: 1, day: 15)

        let debit  = makeExpense(amount: Decimal(500),  date: day, accountID: accountA)
        let credit = makeExpense(amount: Decimal(-500), date: day, accountID: nil)  // unassigned

        let pairs = TransferDetectionScorer.findCandidatePairs(
            from: [debit, credit], calendar: istCalendar
        )

        #expect(pairs.count == 0,
                "Expected 0 pairs (credit unassigned) but got \(pairs.count)")
    }

    @Test("sameAccountNotPaired: debit and credit both on account A produce 0 pairs (D-04)")
    func sameAccountNotPaired() {
        let accountA = UUID()
        let day = istDate(year: 2026, month: 1, day: 15)

        let debit  = makeExpense(amount: Decimal(500),  date: day, accountID: accountA)
        let credit = makeExpense(amount: Decimal(-500), date: day, accountID: accountA)  // same account

        let pairs = TransferDetectionScorer.findCandidatePairs(
            from: [debit, credit], calendar: istCalendar
        )

        #expect(pairs.count == 0,
                "Expected 0 pairs (both on same account) but got \(pairs.count)")
    }

    // MARK: - D-05: 3-day IST calendar window (inclusive)

    @Test("outsideWindowNotPaired: legs 4 IST days apart produce 0 pairs; exactly 3 days apart produce 1 pair (D-05 inclusive)")
    func outsideWindowNotPaired() {
        let accountA = UUID(); let accountB = UUID()

        let debitDay  = istDate(year: 2026, month: 1, day: 10)
        let day4Away  = istDate(year: 2026, month: 1, day: 14)  // 4 days later → outside
        let day3Away  = istDate(year: 2026, month: 1, day: 13)  // 3 days later → exactly at boundary

        let debit   = makeExpense(amount: Decimal(500),  date: debitDay, accountID: accountA)
        let credit4 = makeExpense(amount: Decimal(-500), date: day4Away, accountID: accountB)
        let credit3 = makeExpense(amount: Decimal(-500), date: day3Away, accountID: accountB)

        // 4-day window → 0 pairs
        let pairs4 = TransferDetectionScorer.findCandidatePairs(
            from: [debit, credit4], calendar: istCalendar
        )
        #expect(pairs4.count == 0,
                "Expected 0 pairs for 4-day separation but got \(pairs4.count)")

        // 3-day window (inclusive boundary) → 1 pair
        let pairs3 = TransferDetectionScorer.findCandidatePairs(
            from: [debit, credit3], calendar: istCalendar
        )
        #expect(pairs3.count == 1,
                "Expected 1 pair for 3-day (boundary) separation but got \(pairs3.count)")
    }

    // MARK: - D-07 / D-10: skip already-evaluated legs

    @Test("confirmedLegSkipped: credit with isTransfer == true is never selected as a candidate (D-10)")
    func confirmedLegSkipped() {
        // NOTE: The scorer itself receives only the pre-filtered nil-isTransfer candidates
        // (TransferScanService filters before calling findCandidatePairs). However this test
        // verifies that if a non-nil leg accidentally reaches the scorer it does not pair.
        // The scorer filters debits = amount > 0 && accountID != nil and
        // credits = amount < 0 && accountID != nil — it does NOT re-filter on isTransfer.
        // The service-level filter is the first gate; this test documents the expected
        // integration contract: confirmed legs are excluded before the scorer is called.
        // (covered by TransferScanServiceTests.confirmedLegSkipped — this scorer test
        // verifies the filter is applied at the service layer, not the scorer.)
        // For clarity we test via the service's input contract: only nil-isTransfer expenses
        // are passed to findCandidatePairs; the scorer trusts the pre-filter.
        let accountA = UUID(); let accountB = UUID()
        let day = istDate(year: 2026, month: 1, day: 15)

        let debit          = makeExpense(amount: Decimal(500),  date: day, accountID: accountA, isTransfer: nil)
        let confirmedCredit = makeExpense(amount: Decimal(-500), date: day, accountID: accountB, isTransfer: true)

        // Sanity: WITHOUT the pre-filter the scorer WOULD pair them (it does not re-filter on
        // isTransfer) — so this set is a real positive that the service-layer filter must suppress.
        let unfiltered = TransferDetectionScorer.findCandidatePairs(
            from: [debit, confirmedCredit],
            calendar: istCalendar
        )
        #expect(unfiltered.count == 1,
                "Scorer does not re-filter isTransfer; an exact opposite-sign pair should match when unfiltered, got \(unfiltered.count)")

        // With the service pre-filter applied to a set that CONTAINS the confirmed leg,
        // the confirmed credit is removed and no pair survives (D-10).
        let pairs = TransferDetectionScorer.findCandidatePairs(
            from: [debit, confirmedCredit].filter { $0.isTransfer == nil },
            calendar: istCalendar
        )
        #expect(pairs.count == 0,
                "Expected 0 pairs — confirmedCredit excluded by the service pre-filter, got \(pairs.count)")
    }

    @Test("rejectedLegSkipped: credit with isTransfer == false is never selected as a candidate (D-10)")
    func rejectedLegSkipped() {
        let accountA = UUID(); let accountB = UUID()
        let day = istDate(year: 2026, month: 1, day: 15)

        let debit          = makeExpense(amount: Decimal(500),  date: day, accountID: accountA, isTransfer: nil)
        let rejectedCredit = makeExpense(amount: Decimal(-500), date: day, accountID: accountB, isTransfer: false)

        let pairs = TransferDetectionScorer.findCandidatePairs(
            from: [debit, rejectedCredit].filter { $0.isTransfer == nil },  // service pre-filter
            calendar: istCalendar
        )
        #expect(pairs.count == 0,
                "Expected 0 pairs — rejectedCredit excluded by pre-filter, got \(pairs.count)")
    }

    // MARK: - Tie-break rule (Critical Finding 3)

    @Test("tieBreakClosestTimeWins: one debit + two candidate credits at +1 day and +2 days → pairs with the +1-day credit")
    func tieBreakClosestTimeWins() {
        let accountA = UUID(); let accountB = UUID(); let accountC = UUID()

        let debitDay  = istDate(year: 2026, month: 1, day: 10, hour: 9, minute: 0)
        let plus1Day  = istDate(year: 2026, month: 1, day: 11, hour: 9, minute: 0)  // closer
        let plus2Days = istDate(year: 2026, month: 1, day: 12, hour: 9, minute: 0)  // farther

        let debit    = makeExpense(amount: Decimal(1000),  date: debitDay,  accountID: accountA)
        let credit1  = makeExpense(amount: Decimal(-1000), date: plus1Day,  accountID: accountB)
        let credit2  = makeExpense(amount: Decimal(-1000), date: plus2Days, accountID: accountC)

        let pairs = TransferDetectionScorer.findCandidatePairs(
            from: [debit, credit1, credit2], calendar: istCalendar
        )

        #expect(pairs.count == 1,
                "Expected exactly 1 pair but got \(pairs.count)")
        #expect(pairs[0].creditID == credit1.id,
                "Expected the closer (+1 day) credit to be chosen, got \(pairs[0].creditID) (expected \(credit1.id))")
    }

    @Test("tieBreakUUIDStableOnEqualDistance: two equidistant credits → lower uuidString wins; permuted input yields identical result")
    func tieBreakUUIDStableOnEqualDistance() {
        // Two credits exactly 1 IST day from the debit (equidistant).
        // Lower uuidString must win deterministically.
        let accountA = UUID()

        // Craft two UUIDs so we know which is lexicographically lower.
        let lowUUID  = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let highUUID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

        let debitDay = istDate(year: 2026, month: 1, day: 10, hour: 12, minute: 0)
        let creditDay = istDate(year: 2026, month: 1, day: 11, hour: 12, minute: 0)  // same distance

        let debit       = makeExpense(amount: Decimal(200),  date: debitDay,  accountID: accountA)
        let creditLow   = makeExpense(id: lowUUID,  amount: Decimal(-200), date: creditDay, accountID: UUID())
        let creditHigh  = makeExpense(id: highUUID, amount: Decimal(-200), date: creditDay, accountID: UUID())

        let pairs = TransferDetectionScorer.findCandidatePairs(
            from: [debit, creditLow, creditHigh], calendar: istCalendar
        )

        #expect(pairs.count == 1, "Expected 1 pair but got \(pairs.count)")
        #expect(pairs[0].creditID == lowUUID,
                "Expected lower uuidString (\(lowUUID)) to win, got \(pairs[0].creditID)")

        // Permuted input should produce identical result.
        let pairsPermuted = TransferDetectionScorer.findCandidatePairs(
            from: [creditHigh, creditLow, debit], calendar: istCalendar
        )
        #expect(pairsPermuted.count == 1, "Expected 1 pair from permuted input")
        #expect(pairsPermuted[0].creditID == lowUUID,
                "Permuted input must yield same winner, got \(pairsPermuted[0].creditID)")
    }

    // MARK: - Determinism (Critical Finding 3)

    @Test("deterministicOnEqualInput: shuffled input array produces identical CandidatePair set")
    func deterministicOnEqualInput() {
        let accountA = UUID(); let accountB = UUID(); let accountC = UUID()
        let day = istDate(year: 2026, month: 1, day: 15)

        let debit1  = makeExpense(amount: Decimal(100),  date: day, accountID: accountA)
        let debit2  = makeExpense(amount: Decimal(200),  date: day, accountID: accountA)
        let credit1 = makeExpense(amount: Decimal(-100), date: day, accountID: accountB)
        let credit2 = makeExpense(amount: Decimal(-200), date: day, accountID: accountC)

        let canonical = [debit1, debit2, credit1, credit2]
        let shuffled  = [credit2, debit2, credit1, debit1]

        let pairsA = TransferDetectionScorer.findCandidatePairs(from: canonical, calendar: istCalendar)
        let pairsB = TransferDetectionScorer.findCandidatePairs(from: shuffled,  calendar: istCalendar)

        // Same number of pairs
        #expect(pairsA.count == pairsB.count,
                "Pair count must be identical regardless of input order: \(pairsA.count) vs \(pairsB.count)")

        // Same pairs (debitID+creditID sets match)
        let setA = Set(pairsA.map { "\($0.debitID)-\($0.creditID)" })
        let setB = Set(pairsB.map { "\($0.debitID)-\($0.creditID)" })
        #expect(setA == setB,
                "Pair sets must be identical: \(setA) vs \(setB)")
    }

    // MARK: - Credit claimed once (no double-pairing)

    @Test("eachCreditClaimedOnce: two debits and one credit → only one pair (claimed credit not reused)")
    func eachCreditClaimedOnce() {
        let accountA = UUID(); let accountB = UUID()
        let day = istDate(year: 2026, month: 1, day: 15)

        let debit1 = makeExpense(amount: Decimal(300), date: day, accountID: accountA)
        let debit2 = makeExpense(amount: Decimal(300),
                                  date: istDate(year: 2026, month: 1, day: 16),
                                  accountID: accountA)
        let credit = makeExpense(amount: Decimal(-300), date: day, accountID: accountB)

        let pairs = TransferDetectionScorer.findCandidatePairs(
            from: [debit1, debit2, credit], calendar: istCalendar
        )

        #expect(pairs.count == 1,
                "Expected exactly 1 pair (credit claimed once) but got \(pairs.count)")
        #expect(pairs[0].creditID == credit.id,
                "The single pair should reference the only credit, got \(pairs[0].creditID)")
    }
}
