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
        HStack(spacing: 18) {
            DonutChart(segments: segments, size: 132) {
                VStack(spacing: 2) {
                    Text("SPENT")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(DesignTokens.label2)
                    // Stat pattern (Pitfall 5: hero money text is 46pt only; use Text here).
                    // Whole-rupee + width cap + scale-to-fit so the total stays inside the
                    // donut hole and never spills over the ring (fixes center overflow).
                    Text(total.formattedINRWhole())
                        .font(.system(size: 19, weight: .semibold, design: .default))
                        .foregroundStyle(DesignTokens.label)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.78), value: total)
                }
                .frame(width: 132 * 0.62 - 6)
            }

            VStack(alignment: .leading, spacing: 11) {
                ForEach(legendItems) { item in
                    Button {
                        onCategoryTap(item.categoryID)
                    } label: {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(item.color)
                                .frame(width: 9, height: 9)
                                .shadow(color: item.color.opacity(0.6), radius: 5)
                            Text(item.label)
                                .font(.system(size: 14))
                                .foregroundStyle(DesignTokens.label)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(item.amount.formattedINRWhole())
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(DesignTokens.label2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.label): \(item.amount.formattedINRWhole())")
                }
            }
        }
        .neuSurface(.raised, padding: 18)
        // NOTE: no clip modifier here — shadow must remain visible (Pitfall 2)
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

    // MARK: - Segment builder

    private var segments: [DonutSegment] {
        ranked.map { item in
            DonutSegment(
                id: item.category.id.uuidString,
                label: item.category.name ?? "—",
                value: toDouble(item.spent),
                color: CategoryStyle.color(for: item.category)
            )
        }
    }

    // MARK: - Legend items

    private struct LegendItem: Identifiable {
        let id: String
        let label: String
        let color: Color
        let amount: Decimal
        let categoryID: UUID?  // nil = Others row
    }

    private var legendItems: [LegendItem] {
        ranked.map { item in
            LegendItem(
                id: item.category.id.uuidString,
                label: item.category.name ?? "—",
                color: CategoryStyle.color(for: item.category),
                amount: item.spent,
                categoryID: item.category.id
            )
        }
    }

    // MARK: - Helpers

    /// Safe Decimal → Double conversion (T-11-13 pattern from NetWorthCard lines 130-132).
    private func toDouble(_ v: Decimal) -> Double {
        NSDecimalNumber(decimal: max(v, .zero)).doubleValue
    }
}
