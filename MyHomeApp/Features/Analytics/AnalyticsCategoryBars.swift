import SwiftUI

// MARK: - AnalyticsCategoryBars

/// By-category breakdown for the Analytics screen (ANL-04) — neumorphic v2, Screen 5:
/// a vertical pill bar chart. Each column is a recessed vertical pill well with a glowing
/// category-colour fill pill inside (inset from the well's sides and bottom); the category
/// label and amount sit below. Fill heights are proportional to spend.
///
/// Categories beyond the top 4 fold into a single "Other" column so the chart always fits
/// one row of 5 columns without losing any spend from the totals (ANL-04 full coverage).
///
/// PITFALL A GUARD: this view never receives raw expenses; only pre-aggregated items.
/// PITFALL B GUARD: amounts display from `item.spentDecimal` (Decimal), never `item.spent` (Double).
struct AnalyticsCategoryBars: View {

    // MARK: - Input

    /// Pre-aggregated category spend items, sorted descending by spend. Pass the entire
    /// `SpendSummary.categoryBreakdown` — the fold to 5 columns happens here.
    let items: [CategorySpendItem]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: Double = 0

    // MARK: - Geometry (handoff: well 42×150 r999, fill inset 9 each side/bottom)

    private let wellHeight: CGFloat = 150
    private let wellWidth: CGFloat = 42
    private let fillInset: CGFloat = 9
    private let minFillHeight: CGFloat = 24

    // MARK: - Column data

    private struct Column: Identifiable {
        let id: String
        let name: String
        let color: Color
        let amountDecimal: Decimal
        let amount: Double
    }

    private var columns: [Column] {
        let top: [CategorySpendItem]
        let rest: [CategorySpendItem]
        if items.count > 5 {
            top = Array(items.prefix(4))
            rest = Array(items.dropFirst(4))
        } else {
            top = items
            rest = []
        }
        var cols: [Column] = top.map {
            Column(id: "\($0.id)", name: $0.name, color: $0.color,
                   amountDecimal: $0.spentDecimal, amount: $0.spent)
        }
        if !rest.isEmpty {
            let restDecimal = rest.reduce(Decimal.zero) { $0 + $1.spentDecimal }
            let restDouble = rest.reduce(0.0) { $0 + $1.spent }
            cols.append(Column(id: "other-rollup", name: "Other", color: DesignTokens.catOther,
                               amountDecimal: restDecimal, amount: restDouble))
        }
        return cols
    }

    /// Largest spend value; fills scale relative to this. Guarded against zero (safe division).
    private var maxAmount: Double { max(columns.map(\.amount).max() ?? 0, 1) }

    // MARK: - Body

    var body: some View {
        if columns.isEmpty {
            // Empty state — calm, no crash (ANL-04 edge case)
            Text("No spend this range.")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.label2)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        } else {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(columns) { column in
                    pillColumn(column)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)
            .onAppear {
                if reduceMotion { reveal = 1 }
                else { withAnimation(.easeOut(duration: 0.5)) { reveal = 1 } }
            }
        }
    }

    // MARK: - Pill column

    @ViewBuilder
    private func pillColumn(_ column: Column) -> some View {
        let fraction = column.amount / maxAmount
        let maxFill = wellHeight - fillInset * 2
        let fillHeight = (minFillHeight + (maxFill - minFillHeight) * fraction) * reveal

        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                // Recessed vertical well
                Capsule()
                    .fill(DesignTokens.fillRecessed3)
                    .overlay(
                        Capsule().stroke(
                            LinearGradient(colors: [.black.opacity(0.45), .white.opacity(0.03)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )
                        .blur(radius: 0.5)
                        .clipShape(Capsule())
                    )
                    .frame(width: wellWidth, height: wellHeight)

                // Glowing inner fill pill — light→base vertical gradient of the category colour
                Capsule()
                    .fill(
                        LinearGradient(colors: [column.color, column.color], startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(
                        Capsule().fill(
                            LinearGradient(colors: [.white.opacity(0.35), .clear],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    )
                    .frame(width: wellWidth - fillInset * 2,
                           height: max(minFillHeight * reveal, fillHeight))
                    .padding(.bottom, fillInset)
                    .shadow(color: column.color.opacity(0.45), radius: 8)
            }

            VStack(spacing: 2) {
                Text(column.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.label2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                // Display from Decimal (Pitfall B guard — no float drift)
                Text(column.amountDecimal.formattedINRWords())
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DesignTokens.label)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(column.name), \(column.amountDecimal.formattedINR())")
    }
}
