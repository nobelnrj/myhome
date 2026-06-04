import SwiftUI

/// Overview hero card — "spent this month" + remaining + stacked category bar (OVR-01, D4-02).
///
/// Restyled to the `MyHome.html` design: a large spend figure on the left, a green/red
/// remaining (or "over budget") figure on the right, a `StackBar` of category spend, and a
/// "of ₹X budget · N% used" footer (or a "Set a budget" prompt when no budget is set).
///
/// Dumb/value-driven: consumes pre-computed totals + segments from the parent. No @Query.
///
/// Threat mitigations:
/// - T-04-07: selectedTab assignment is a plain integer @Binding; no URL parsing, no external input.
struct SpendBudgetCard: View {

    let totalSpend: Decimal
    let totalBudget: Decimal
    /// Category spend segments (value, color) for the stacked bar — already sorted descending.
    let segments: [(value: Double, color: Color)]
    @Binding var selectedTab: Int

    // MARK: - Computed thresholds

    /// Fraction of budget consumed (nil when no budget is set; guarded against divide-by-zero).
    private var fractionUsed: Double? {
        guard totalBudget > 0 else { return nil }
        return Double(truncating: (totalSpend / totalBudget) as NSDecimalNumber)
    }

    private var colorThreshold: BudgetColor {
        guard let f = fractionUsed else { return .normal }
        if f >= 1.0 { return .overBudget }
        if f >= 0.8 { return .warning }
        return .normal
    }

    /// Remaining-amount color: green when under, red when over.
    private var remainingTextColor: Color {
        (totalBudget - totalSpend) >= 0 ? Color(.systemGreen) : Color(.systemRed)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Top row — spent (left) + remaining/over (right)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SPENT THIS MONTH")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Text(totalSpend.formattedINRWhole())
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 12)
                if totalBudget > 0 {
                    let remaining = totalBudget - totalSpend
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(remaining >= 0 ? "REMAINING" : "OVER BUDGET")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Text(abs(remaining).formattedINRWhole())
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(remainingTextColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }

            // Stacked category bar
            StackBar(segments: segments, height: 12)

            // Footer — budget context or "set a budget" prompt
            if let fraction = fractionUsed {
                HStack {
                    Text("of \(totalBudget.formattedINRWhole()) budget")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(fraction >= 1.0 ? "100%+ used" : "\(Int(fraction * 100))% used")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    selectedTab = 2
                } label: {
                    Text("Set a budget to track your spending →")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .tint(.accentColor)
            }
        }
        .cardStyle(cornerRadius: 16, padding: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Accessibility label

    private var accessibilityLabel: String {
        guard totalBudget > 0 else {
            return "\(totalSpend.formattedINR()) spent this month. No budget set."
        }
        let pct = fractionUsed.map { Int($0 * 100) } ?? 0
        return "\(totalSpend.formattedINR()) spent this month, \(pct)% of \(totalBudget.formattedINR()) budget"
    }
}

// MARK: - Preview

#Preview("Normal — 60%") {
    @Previewable @State var tab = 0
    SpendBudgetCard(
        totalSpend: Decimal(6000),
        totalBudget: Decimal(10000),
        segments: [(3000, Color(.systemGreen)), (2000, Color(.systemOrange)), (1000, Color(.systemPink))],
        selectedTab: $tab
    )
    .padding()
}

#Preview("Over budget — 110%") {
    @Previewable @State var tab = 0
    SpendBudgetCard(
        totalSpend: Decimal(11000),
        totalBudget: Decimal(10000),
        segments: [(7000, Color(.systemRed)), (4000, Color(.systemOrange))],
        selectedTab: $tab
    )
    .padding()
}

#Preview("No budget set") {
    @Previewable @State var tab = 0
    SpendBudgetCard(
        totalSpend: Decimal(3000),
        totalBudget: Decimal(0),
        segments: [(2000, Color(.systemGreen)), (1000, Color(.systemPink))],
        selectedTab: $tab
    )
    .padding()
}
