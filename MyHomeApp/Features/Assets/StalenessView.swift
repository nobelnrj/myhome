import SwiftUI
import Foundation

// MARK: - AssetValuation (pure-logic helper, no View dependency)

/// Pure-logic gain/loss and staleness calculations for Asset holdings.
///
/// All math uses Decimal (never Double) per RESEARCH Pitfall 17.
/// Extracted as a standalone enum (no stored state) so tests can verify every case
/// without a ModelContainer or SwiftUI environment.
///
/// Threat mitigations:
/// - T-11-11: percentGain returns nil when totalCost <= 0 (no divide-by-zero)
enum AssetValuation {

    // MARK: - Staleness (ASSET-09, D-10)

    /// Returns true when navAsOfDate is more than 1 IST calendar day before today.
    ///
    /// Threshold: diff > 1 (D-10 — ignores weekends/holidays; calendar-day only).
    /// - today (diff 0) → false
    /// - yesterday (diff 1) → false
    /// - 2 days ago (diff 2) → true
    /// - nil → false (badge hidden; "price not set" shown elsewhere)
    ///
    /// Takes an explicit referenceDate for testability (tests inject a fixed date).
    static func isStale(navAsOfDate: Date?, referenceDate: Date = Date()) -> Bool {
        guard let navDate = navAsOfDate else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let startOfTodayIST = cal.startOfDay(for: referenceDate)
        let diff = cal.dateComponents([.day], from: navDate, to: startOfTodayIST).day ?? 0
        return diff > 1
    }

    // MARK: - Value helpers

    /// Current value = units × currentNAV (nil treated as 0).
    static func currentValue(units: Decimal?, currentNAV: Decimal?) -> Decimal {
        (units ?? 0) * (currentNAV ?? 0)
    }

    /// Total cost = units × costBasisPerUnit (nil treated as 0).
    static func totalCost(units: Decimal?, costBasisPerUnit: Decimal?) -> Decimal {
        (units ?? 0) * (costBasisPerUnit ?? 0)
    }

    /// Absolute gain = currentValue − totalCost.
    static func absoluteGain(units: Decimal?, costBasisPerUnit: Decimal?, currentNAV: Decimal?) -> Decimal {
        currentValue(units: units, currentNAV: currentNAV) - totalCost(units: units, costBasisPerUnit: costBasisPerUnit)
    }

    /// Percent gain = (absoluteGain / totalCost) × 100.
    ///
    /// Returns nil when totalCost <= 0 (T-11-11: zero/nil cost basis — no divide-by-zero crash).
    static func percentGain(units: Decimal?, costBasisPerUnit: Decimal?, currentNAV: Decimal?) -> Decimal? {
        let cost = totalCost(units: units, costBasisPerUnit: costBasisPerUnit)
        guard cost > 0 else { return nil }
        let abs = absoluteGain(units: units, costBasisPerUnit: costBasisPerUnit, currentNAV: currentNAV)
        return (abs / cost) * 100
    }
}

// MARK: - StalenessView

/// Inline staleness badge — shows an orange clock icon + "Stale" when navAsOfDate is
/// older than 1 IST calendar day. Renders EmptyView when fresh or when navAsOfDate is nil.
///
/// Surface 7 — ASSET-09, D-10.
///
/// Threat mitigations:
/// - T-11-09: No user input — display-only component
struct StalenessView: View {

    let navAsOfDate: Date?

    private var isStale: Bool {
        AssetValuation.isStale(navAsOfDate: navAsOfDate)
    }

    private var accessibilityDateString: String {
        guard let date = navAsOfDate else { return "unknown" }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    var body: some View {
        if isStale {
            HStack(spacing: 2) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(Color(.systemOrange))
                Text("Stale")
                    .foregroundStyle(Color(.systemOrange))
            }
            .font(.caption)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Price is stale. Last updated \(accessibilityDateString).")
        }
    }
}
