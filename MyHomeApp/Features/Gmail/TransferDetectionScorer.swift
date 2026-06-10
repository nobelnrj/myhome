import Foundation

/// Pure 5-signal transfer detection helper (XFER-01).
///
/// Design (D-01..D-05, STAB-02):
/// - Operates on plain `[Expense]` arrays — no @Model refs held across any boundary.
/// - All outputs are `CandidatePair` value types containing only `UUID` scalars.
/// - No `import SwiftData` and no `@Model` references (verifiable via grep).
///
/// AND-rules for pairing (all five must hold — D-01..D-05):
/// - D-01: Hard AND-rules; a pair is surfaced only when ALL conditions hold.
/// - D-02: Exact `Decimal` amount match between the two legs (to the paisa). No tolerance.
/// - D-03: Opposite direction — debit (`amount > 0`), credit (`amount < 0`), equal magnitude.
/// - D-04: Both legs must be assigned to accounts (`accountID != nil`) and to two DIFFERENT own accounts.
/// - D-05: ≤3 IST calendar days apart (inclusive). Use `Asia/Kolkata` timezone.
///
/// Pending-pair encoding (D-07, no new schema field):
/// The scorer writes only `CandidatePair` UUIDs — it is the caller's (`TransferScanService`)
/// responsibility to write `transferPairID` onto the @Model objects (STAB-02 value-type safety).
///
/// Tie-break rule (Critical Finding 3 / Claude's discretion):
/// When one debit matches multiple candidate credits of the same magnitude:
/// 1. Primary: ascending `abs(credit.date.timeIntervalSince(debit.date))` (closest in time wins).
/// 2. Secondary: ascending `credit.id.uuidString` (stable UUID discriminator — mirrors OverviewAggregation.topCategories pattern).
///
/// Determinism (Critical Finding 3):
/// Debits are sorted ascending by `date` then `id.uuidString` before the pairing loop.
/// This gives the algorithm a total order on any input permutation.
enum TransferDetectionScorer {

    // MARK: - Public Types

    /// A candidate transfer pair identified by the scorer.
    ///
    /// Contains only UUID scalars — safe to capture before any `await` suspension (STAB-02).
    struct CandidatePair {
        let debitID: UUID
        let creditID: UUID
    }

    // MARK: - Public API

    /// Finds candidate transfer pairs from a pre-fetched array of expenses.
    ///
    /// The caller (`TransferScanService`) is responsible for pre-filtering to `isTransfer == nil`
    /// candidates (D-09/D-10 skip rule) before passing to this function — the scorer operates
    /// on whatever array it receives and does NOT re-filter on `isTransfer`.
    ///
    /// - Parameters:
    ///   - expenses: Pre-fetched expenses to score. Should contain only `isTransfer == nil` legs
    ///               (STAB-08 safe Swift filter applied by the caller).
    ///   - calendar: An IST gregorian Calendar injected for testability. Use
    ///               `Calendar(identifier: .gregorian)` with `timeZone = TimeZone(identifier: "Asia/Kolkata")!`.
    /// - Returns: Array of `CandidatePair` values; each credit appears at most once (claimed).
    static func findCandidatePairs(from expenses: [Expense], calendar: Calendar) -> [CandidatePair] {
        // D-03/D-04: Separate debits (amount > 0, accountID != nil) and credits (amount < 0, accountID != nil)
        let debits  = expenses.filter { $0.amount > 0 && $0.accountID != nil }
        let credits = expenses.filter { $0.amount < 0 && $0.accountID != nil }

        // Build credit lookup keyed by abs(credit.amount) == debit.amount (D-02 exact Decimal match)
        var creditsByAmount: [Decimal: [Expense]] = [:]
        for credit in credits {
            let key = abs(credit.amount)
            creditsByAmount[key, default: []].append(credit)
        }

        // Deterministic debit processing order: ascending date, then ascending UUID string (Critical Finding 3)
        let sortedDebits = debits.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var pairs: [CandidatePair] = []
        var claimedCreditIDs: Set<UUID> = []

        for debit in sortedDebits {
            // D-02: look up credits by exact debit amount (credit.amount == -debit.amount)
            guard var candidates = creditsByAmount[debit.amount] else { continue }

            // Apply D-04 and D-05 filters, and exclude already-claimed credits
            candidates = candidates.filter { credit in
                // D-04: different account
                credit.accountID != debit.accountID
                    // Not already claimed by an earlier debit in this run
                    && !claimedCreditIDs.contains(credit.id)
                    // D-05: ≤3 IST calendar days (inclusive)
                    && istDayDistance(debit.date, credit.date, calendar: calendar) <= 3
            }

            guard !candidates.isEmpty else { continue }

            // Tie-break: closest in time (primary), then lower uuidString (secondary) — Critical Finding 3
            let best = candidates.min { a, b in
                let dA = abs(a.date.timeIntervalSince(debit.date))
                let dB = abs(b.date.timeIntervalSince(debit.date))
                if dA != dB { return dA < dB }
                return a.id.uuidString < b.id.uuidString
            }!

            claimedCreditIDs.insert(best.id)
            pairs.append(CandidatePair(debitID: debit.id, creditID: best.id))
        }

        return pairs
    }

    // MARK: - Internal Helpers

    /// Returns the absolute IST calendar day distance between two dates.
    ///
    /// Both dates are converted to IST start-of-day before computing the integer day difference.
    /// The distance is the absolute number of calendar days between the two IST days.
    /// Used to implement the D-05 ≤3-day inclusive window check.
    static func istDayDistance(_ a: Date, _ b: Date, calendar: Calendar) -> Int {
        let dayA = calendar.startOfDay(for: a)
        let dayB = calendar.startOfDay(for: b)
        return abs(calendar.dateComponents([.day], from: dayA, to: dayB).day ?? Int.max)
    }
}
