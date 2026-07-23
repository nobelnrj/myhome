import SwiftUI
import Charts
import SwiftData

// MARK: - CategorySpendItem

/// Pre-aggregated value type for by-category spend charts (EXP-10).
///
/// Consumed by `AnalyticsCategoryBars` (the vertical pill-well chart used on the Analytics
/// screen). Phase 23 (OVF-04): the Overview screen's own "By category" section — which showed
/// this same chart with the identical per-category totals as the "Where it's going" donut
/// directly above it — was removed to consolidate Overview onto a single spend-by-category
/// presentation (the donut, which already had tap-to-filter-into-Activity).
///
/// `spent` is `Double` (not `Decimal`) because Swift Charts requires `Plottable` conformance.
/// The Decimal→Double conversion happens at the aggregation boundary (caller's body),
/// never inside the Chart DSL (Pitfall B guard).
struct CategorySpendItem: Identifiable {
    /// Stable identity for SwiftUI diffing — the category's persistentModelID.
    let id: PersistentIdentifier
    /// Category display name.
    let name: String
    /// Total spend converted from Decimal at the caller's aggregation boundary.
    /// Used ONLY as the Chart plot value (Plottable requires Double).
    let spent: Double
    /// Original Decimal spend, carried alongside `spent` so display strings format from
    /// the exact value — never reconstruct `Decimal(spent)` from the lossy Double (WR-03,
    /// Pitfall B: no float drift in displayed money).
    let spentDecimal: Decimal
    /// Category accent color (CategoryStyle.color) — bars match the donut legend so the two
    /// charts read as one palette instead of a flat single-hue bar list.
    var color: Color = DesignTokens.accent
}
