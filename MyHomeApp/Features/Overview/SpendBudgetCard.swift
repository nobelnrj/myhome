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

    /// Budget-health colour for the ring (independent of net sign): green under budget,
    /// orange near the limit, red once over.
    private var ringColor: Color {
        if spent > totalBudget { return DesignTokens.negative }
        if let f = fractionUsed, f >= 0.85 { return DesignTokens.orange }
        return DesignTokens.positive
    }

    private var percentUsedLabel: String {
        guard let f = fractionUsed else { return "" }
        return f >= 1.0 ? "100%+ of budget" : "\(Int(f * 100))% of budget"
    }

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

            if fractionUsed != nil {
                // WHOOP-style budget ring hero: ring fill = budget consumed (green→orange→red);
                // centre shows the net cash flow (solid semibold) + % of budget used.
                BudgetRing(fraction: fractionUsed ?? 0, color: ringColor, size: 172, lineWidth: 16) {
                    VStack(spacing: 3) {
                        Text(netIsPositive ? "NET +" : "NET −")
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(DesignTokens.label2)
                        Text(abs(net).formattedINRWhole())
                            .font(.system(size: 25, weight: .semibold, design: .default))
                            .foregroundStyle(statusColor)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                            .animation(.smooth(duration: 0.78), value: net)
                            .frame(width: 172 - 2 * 16 - 14)
                        Text(percentUsedLabel)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.label3)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)

                // Income + Spent split tiles
                HStack(spacing: DesignTokens.spacing12) {
                    splitTile(label: "INCOME", amount: income, color: DesignTokens.positive)
                    splitTile(label: "SPENT", amount: spent, color: DesignTokens.negative)
                }
            } else {
                // No budget set — keep the solid-number hero the user preferred.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if !netIsPositive {
                        Text("−")
                            .font(.system(size: 30, weight: .semibold, design: .default))
                            .foregroundStyle(statusColor)
                    }
                    RollingMoneyText(amount: abs(net), color: statusColor, weight: .semibold, design: .default)
                }

                HStack(spacing: DesignTokens.spacing12) {
                    splitTile(label: "INCOME", amount: income, color: DesignTokens.positive)
                    splitTile(label: "SPENT", amount: spent, color: DesignTokens.negative)
                }

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
            // Stat pattern (not RollingMoneyText — Pitfall 5). Solid system face to match
            // the heavier hero numeral above.
            Text(amount.formattedINRWhole())
                .font(.system(size: 20, weight: .semibold, design: .default))
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

// MARK: - Budget ring (WHOOP-style)

/// A single-value progress ring with a recessed track, gradient stroke, and rounded cap.
/// `fraction` may exceed 1.0 (over budget); the ring trims at a full turn while the caller's
/// colour/label convey the overflow.
private struct BudgetRing<Center: View>: View {
    let fraction: Double
    let color: Color
    var size: CGFloat = 172
    var lineWidth: CGFloat = 16
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(DesignTokens.fillRecessed2, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(fraction, 1)))
                .stroke(
                    color.gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.7), value: fraction)
            center()
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
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
