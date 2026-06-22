import SwiftUI

/// Overview hero card — NET CASH FLOW: income vs spent split (D-04, OVR-01).
///
/// Layout (UI-SPEC Screen 1 hero):
/// - `.neuSurface(.floating)` outer card (hero tier)
/// - "NET CASH FLOW" header + status chip (right-aligned)
/// - Income tile + Spent tile: each `.neuSurface(.recessed, radius: DesignTokens.radiusInner)`
/// - `RollingMoneyText` for the net total (positive color when net >= 0, negative when net < 0)
/// - Flat budget progress strip (track `fillRecessed2`, fill `positive`/`negative`)
///
/// Dumb/value-driven: consumes pre-computed income + spent from OverviewMonthContent. No @Query.
///
/// Threat mitigations:
/// - T-04-07: selectedTab assignment is a plain integer @Binding; no URL parsing.
struct SpendBudgetCard: View {

    /// Total income this month (sum of |expense.amount| where amount < 0 and not a transfer).
    let income: Decimal
    /// Total spend this month (sum of expense.amount where amount > 0, self-transfer-excluded).
    let spent: Decimal
    /// Total monthly budget across all budgeted categories (0 when no budget is set).
    let totalBudget: Decimal
    @Binding var selectedTab: Int

    // MARK: - Computed

    private var net: Decimal { income - spent }

    /// Fraction of budget consumed (nil when no budget set; guarded against divide-by-zero).
    private var fractionUsed: Double? {
        guard totalBudget > 0 else { return nil }
        return NSDecimalNumber(decimal: min(spent / totalBudget, Decimal(2))).doubleValue
    }

    private var netIsPositive: Bool { net >= 0 }

    private var statusChipLabel: String { netIsPositive ? "Positive" : "Negative" }
    private var statusColor: Color { netIsPositive ? DesignTokens.positive : DesignTokens.negative }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing16) {
            // Header row: "NET CASH FLOW" + status chip
            HStack {
                Text("NET CASH FLOW")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(DesignTokens.label2)
                Spacer()
                // Status chip
                Text(statusChipLabel)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(statusColor.opacity(0.40), lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }

            // Net total — RollingMoneyText 46pt (hero)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if !netIsPositive {
                    Text("−")
                        .font(.system(size: 28, weight: .ultraLight, design: .rounded))
                        .foregroundStyle(statusColor)
                }
                RollingMoneyText(amount: abs(net), color: statusColor)
            }

            // Income + Spent split tiles
            HStack(spacing: DesignTokens.spacing12) {
                splitTile(label: "INCOME", amount: income, color: DesignTokens.positive)
                splitTile(label: "SPENT", amount: spent, color: DesignTokens.negative)
            }

            // Budget progress strip (only when budget is set)
            if let fraction = fractionUsed {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(DesignTokens.fillRecessed2)
                            Capsule()
                                .fill(spent > totalBudget ? DesignTokens.negative : DesignTokens.positive)
                                .frame(width: max(0, min(CGFloat(fraction), 1)) * geo.size.width)
                        }
                    }
                    .frame(height: 8)

                    HStack {
                        Text("of \(totalBudget.formattedINRWhole()) budget")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.label3)
                        Spacer()
                        Text(fraction >= 1.0 ? "100%+ used" : "\(Int(fraction * 100))% used")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.label3)
                    }
                }
            } else {
                Button {
                    selectedTab = 2
                } label: {
                    Text("Set a budget to track your spending →")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .tint(DesignTokens.accent)
            }
        }
        .neuSurface(.floating, padding: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Split tile

    @ViewBuilder
    private func splitTile(label: String, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(DesignTokens.label3)
            // 21pt stat pattern (not RollingMoneyText — Pitfall 5)
            Text(amount.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN"))))
                .font(.system(size: 21, weight: .light, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.78), value: amount)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuSurface(.recessed, radius: DesignTokens.radiusInner)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        let netStr = abs(net).formattedINR()
        let direction = netIsPositive ? "positive" : "negative"
        return "Net cash flow \(netStr) \(direction). Income \(income.formattedINR()), spent \(spent.formattedINR())."
    }
}

// MARK: - Preview

#Preview("Positive net — has budget") {
    @Previewable @State var tab = 0
    SpendBudgetCard(
        income: Decimal(45000),
        spent: Decimal(32000),
        totalBudget: Decimal(40000),
        selectedTab: $tab
    )
    .padding()
    .background(DesignTokens.bgCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Negative net — no budget") {
    @Previewable @State var tab = 0
    SpendBudgetCard(
        income: Decimal(20000),
        spent: Decimal(35000),
        totalBudget: Decimal(0),
        selectedTab: $tab
    )
    .padding()
    .background(DesignTokens.bgCanvas)
    .preferredColorScheme(.dark)
}
