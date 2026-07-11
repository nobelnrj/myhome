import SwiftUI
import SwiftData

/// "Where it's going" donut card (OVR-05/06) — neumorphic v2, Screen 2.
///
/// A circular recessed well holds the rounded-cap donut (`NeuDonutRing`); a raised centre
/// puck shows the "SPENT" eyebrow + month total. Below, legend rows: 7pt colour dot, name,
/// share % (tertiary), amount (semibold), hairline dividers. Small categories beyond the
/// top 3 fold into a single "Other" segment so no arc is too small for its rounded caps.
///
/// Tapping a legend row fires `onCategoryTap` with the category UUID (nil for "Other"),
/// navigating to Activity pre-filtered to that category (OVR-06).
///
/// Pitfall guards:
/// - 2: No clip on outer container — shadow must remain visible (Pitfall 2).
/// - 5: Does NOT use the 46pt hero money text component (Pitfall 5).
///
/// Threat mitigations:
/// - T-14-03: Total from SpendDonutAggregation (self-transfer-excluded). No raw amounts.
/// - T-14-04: `onCategoryTap` is in-process closure; binding cleared after consumption by caller.
struct SpendDonutCard: View {

    /// Ranked categories with their monthly spend (descending). Card folds beyond top-3
    /// into "Other" itself — pass the full ranked list.
    let ranked: [(category: Category, spent: Decimal)]
    /// Total spend for the month (self-transfer-excluded) — shown in the donut centre puck.
    let total: Decimal
    /// Called when a legend row is tapped. `nil` = "Other" roll-up.
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
        VStack(spacing: 16) {
            // Circular well + donut + raised centre puck
            NeuCircularWell(size: 236) {
                NeuDonutRing(
                    segments: legendItems.map {
                        DonutSegment(id: $0.id, label: $0.label, value: $0.value, color: $0.color)
                    },
                    size: 198,
                    lineWidth: 22
                )
                NeuCircularPuck(size: 132) {
                    VStack(spacing: 3) {
                        Text("SPENT")
                            .font(.system(size: 11, weight: .semibold))
                            .kerning(1.2)
                            .foregroundStyle(DesignTokens.label2)
                        Text(total.formattedINRWhole())
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(DesignTokens.label)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: 108)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            // Legend rows with hairline dividers
            VStack(spacing: 0) {
                ForEach(Array(legendItems.enumerated()), id: \.element.id) { index, item in
                    Button {
                        Haptics.tap()
                        onCategoryTap(item.categoryID)
                    } label: {
                        legendRow(item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.label): \(item.sharePct) percent, \(item.amount.formattedINRWhole())")
                    if index < legendItems.count - 1 {
                        Rectangle()
                            .fill(DesignTokens.separatorHairline)
                            .frame(height: 1)
                    }
                }
            }
        }
        .neuSurface(.raised, padding: 18)
        // NOTE: no clip modifier here — shadow must remain visible (Pitfall 2)
    }

    @ViewBuilder
    private func legendRow(_ item: LegendItem) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(item.color)
                .frame(width: 7, height: 7)
            Text(item.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.label)
                .lineLimit(1)
            if let sub = item.sublabel {
                Text("· \(sub)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(DesignTokens.label3)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(item.sharePct)%")
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.label3)
                .monospacedDigit()
            Text(item.amount.formattedINRWhole())
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.label)
                .monospacedDigit()
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
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

    // MARK: - Segment + legend data (top-3 + Other roll-up)

    private struct LegendItem: Identifiable {
        let id: String
        let label: String
        let sublabel: String?
        let color: Color
        let amount: Decimal
        let value: Double
        let sharePct: Int
        let categoryID: UUID?  // nil = Other roll-up
    }

    private var legendItems: [LegendItem] {
        let top: [(category: Category, spent: Decimal)]
        let rest: [(category: Category, spent: Decimal)]
        if ranked.count > 4 {
            top = Array(ranked.prefix(3))
            rest = Array(ranked.dropFirst(3))
        } else {
            top = ranked
            rest = []
        }

        var items: [LegendItem] = top.map { item in
            LegendItem(
                id: item.category.id.uuidString,
                label: item.category.name ?? "—",
                sublabel: nil,
                color: CategoryStyle.color(for: item.category),
                amount: item.spent,
                value: toDouble(item.spent),
                sharePct: Int((shareFraction(item.spent) * 100).rounded()),
                categoryID: item.category.id
            )
        }

        if !rest.isEmpty {
            let restTotal = rest.reduce(Decimal.zero) { $0 + $1.spent }
            let names = rest.prefix(3).compactMap { $0.category.name }.joined(separator: ", ")
            items.append(LegendItem(
                id: "other-rollup",
                label: "Other",
                sublabel: names.isEmpty ? nil : names,
                color: DesignTokens.catOther,
                amount: restTotal,
                value: toDouble(restTotal),
                sharePct: Int((shareFraction(restTotal) * 100).rounded()),
                categoryID: nil
            ))
        }
        return items
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
