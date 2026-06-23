import SwiftUI
import Charts
import SwiftData

/// "Where it's going" donut card (OVR-05/06).
///
/// Renders a DonutChart with up to 4 top-spend categories (legend rows are tappable).
/// Tapping a legend row fires `onCategoryTap` with the category UUID (nil for "Others"),
/// enabling the caller to navigate to Activity pre-filtered to that category (OVR-06).
///
/// Pre-conditions:
/// - `ranked` must already be trimmed to top-4 (or fewer) by the caller.
/// - Colors resolved via `CategoryStyle.color(for:)` → `DesignTokens.cat*` (14-01 rewrite).
///
/// Pitfall guards:
/// - 2: No clip on outer container — shadow must remain visible (Pitfall 2).
/// - 5: Does NOT use the 46pt hero money text component; uses 21pt stat Text pattern instead (Pitfall 5).
///
/// Threat mitigations:
/// - T-14-03: Total from SpendDonutAggregation (self-transfer-excluded). No raw amounts.
/// - T-14-04: `onCategoryTap` is in-process closure; binding cleared after consumption by caller.
struct SpendDonutCard: View {

    /// Top-4 (or fewer) ranked categories with their monthly spend.
    let ranked: [(category: Category, spent: Decimal)]
    /// Total spend for the month (self-transfer-excluded) — shown in the donut center.
    let total: Decimal
    /// Called when a legend row is tapped. `nil` = "Others" roll-up.
    let onCategoryTap: (UUID?) -> Void

    // MARK: - Body

    var body: some View {
        if ranked.isEmpty {
            emptyState
        } else {
            donutContent
        }
    }

    // MARK: - Donut + legend content

    private var donutContent: some View {
        // WHOOP-style 3-up: one thick glowing ring per top category, bold % centre, name +
        // amount below. Each tile is tappable → Activity pre-filtered to that category (OVR-06).
        HStack(spacing: 12) {
            ForEach(legendItems) { item in
                Button { Haptics.tap(); onCategoryTap(item.categoryID) } label: {
                    categoryRingTile(item)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.label): \(item.sharePct) percent, \(item.amount.formattedINRWhole())")
            }
        }
        .neuSurface(.raised, padding: 18)
        // NOTE: no clip modifier here — shadow must remain visible (Pitfall 2)
    }

    @ViewBuilder
    private func categoryRingTile(_ item: LegendItem) -> some View {
        VStack(spacing: 9) {
            ActivityRing(
                progress: Double(item.sharePct) / 100.0,
                colors: [item.color.opacity(0.5), item.color],
                size: 86,
                lineWidth: 11,
                showTip: false,
                roundCap: false
            ) {
                Text("\(item.sharePct)%")
                    .font(.system(size: 19, weight: .bold, design: .default))
                    .foregroundStyle(DesignTokens.label)
                    .monospacedDigit()
            }
            .neonGlow(item.color, radius: 8)
            Text(item.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.label)
                .lineLimit(1)
            Text(item.amount.formattedINRWords())
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.label2)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DesignTokens.spacing8) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 40))
                .foregroundStyle(DesignTokens.label3)
            Text("No spend this month")
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.label2)
        }
        .frame(maxWidth: .infinity)
        .neuSurface(.raised, padding: 18)
    }

    // MARK: - Ring + legend data (top-3, so rings and legend stay in lock-step)

    private var topRanked: [(category: Category, spent: Decimal)] { Array(ranked.prefix(3)) }

    private struct LegendItem: Identifiable {
        let id: String
        let label: String
        let color: Color
        let amount: Decimal
        let sharePct: Int
        let categoryID: UUID?  // nil = Others row
    }

    private var legendItems: [LegendItem] {
        topRanked.map { item in
            LegendItem(
                id: item.category.id.uuidString,
                label: item.category.name ?? "—",
                color: CategoryStyle.color(for: item.category),
                amount: item.spent,
                sharePct: Int((shareFraction(item.spent) * 100).rounded()),
                categoryID: item.category.id
            )
        }
    }

    // MARK: - Helpers

    /// Share of total spend (0…1), guarded against a zero total.
    private func shareFraction(_ v: Decimal) -> Double {
        let t = toDouble(total)
        guard t > 0 else { return 0 }
        return toDouble(v) / t
    }

    /// Safe Decimal → Double conversion (T-11-13 pattern from NetWorthCard lines 130-132).
    private func toDouble(_ v: Decimal) -> Double {
        NSDecimalNumber(decimal: max(v, .zero)).doubleValue
    }
}
