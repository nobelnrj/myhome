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
    /// Drives the cash-flow orb, the SPENT tile, and the net figure — NOT the budget strip.
    let spent: Decimal
    /// Spend that lands in budgeted categories only — the SAME numerator the per-category
    /// "Budgets" rows use (net per-category spend, summed over categories with a limit). The
    /// budget strip uses this so its "% used" reconciles with those rows, instead of counting
    /// unbudgeted/uncategorized spend against the budgeted-only total.
    let budgetedSpent: Decimal
    /// Total monthly budget across all budgeted categories (0 when no budget is set).
    let totalBudget: Decimal
    @Binding var selectedTab: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the count-up: amounts render as ₹0 until `appeared` flips true on first appear.
    @State private var appeared = false

    // MARK: - Computed

    private var net: Decimal { income - spent }

    /// Fraction of budget consumed (nil when no budget set; guarded against divide-by-zero).
    /// Uses `budgetedSpent` (budgeted-category spend) so it matches the per-category rows.
    private var fractionUsed: Double? {
        guard totalBudget > 0 else { return nil }
        return NSDecimalNumber(decimal: min(budgetedSpent / totalBudget, Decimal(2))).doubleValue
    }

    private var netIsPositive: Bool { net >= 0 }

    private var statusChipLabel: String { netIsPositive ? "Positive" : "Negative" }
    private var statusColor: Color { netIsPositive ? DesignTokens.positive : DesignTokens.negative }

    /// Budget-health colour for the ring (independent of net sign): green under budget,
    /// orange near the limit, red once over.
    private var ringColor: Color {
        if budgetedSpent > totalBudget { return DesignTokens.negative }
        if let f = fractionUsed, f >= 0.85 { return DesignTokens.orange }
        return DesignTokens.positive
    }

    private var percentUsedLabel: String {
        guard let f = fractionUsed else { return "" }
        return f >= 1.0 ? "100%+ used" : "\(Int(f * 100))% used"
    }

    /// Fraction of the orb coloured as income (green); the rest is expense (red).
    /// Falls back to a half-and-half split when there's no activity yet.
    private var incomeShare: Double {
        let i = NSDecimalNumber(decimal: max(income, 0)).doubleValue
        let s = NSDecimalNumber(decimal: max(spent, 0)).doubleValue
        let total = i + s
        return total > 0 ? i / total : 0.5
    }

    /// Expense share of cash flow as a percent — the red portion of the orb. The single
    /// centred readout (user asked for just the spend percentage, nothing else).
    private var spendPct: Int { Int(((1 - incomeShare) * 100).rounded()) }

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

            // Two-tone WHOOP orb: green particles = income share, red = expense share (always a
            // full sphere, no gap). Centre frames the net outcome as SAVED / OVERSPENT (no minus).
            GlowParticleRing(
                incomeShare: incomeShare,
                incomeColor: DesignTokens.positive,
                expenseColor: DesignTokens.negative,
                size: 280,
                pulse: totalBudget > 0 && budgetedSpent > totalBudget
            ) {
                VStack(spacing: 2) {
                    Text("\(spendPct)%")
                        .font(.system(size: 58, weight: .bold, design: .default))
                        .foregroundStyle(DesignTokens.label)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.6), value: spendPct)
                        .frame(width: 180)
                    Text("spent")
                        .font(.system(size: 14, weight: .medium))
                        .tracking(0.5)
                        .foregroundStyle(DesignTokens.label2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)

            // Income + Spent split tiles — count up from ₹0 on first appear.
            HStack(spacing: DesignTokens.spacing12) {
                splitTile(label: "INCOME", amount: appeared ? income : 0, color: DesignTokens.positive)
                splitTile(label: "SPENT", amount: appeared ? spent : 0, color: DesignTokens.negative)
            }

            // Budget context (secondary): a thin strip when a budget exists, else a CTA.
            if let fraction = fractionUsed {
                budgetStrip(fraction: fraction)
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
        .onAppear {
            guard !appeared else { return }
            if reduceMotion { appeared = true }
            else { withAnimation(.smooth(duration: 0.9)) { appeared = true } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Split tile

    @ViewBuilder
    private func splitTile(label: String, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(DesignTokens.label2)
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

    // MARK: - Budget strip (secondary context)

    @ViewBuilder
    private func budgetStrip(fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DesignTokens.fillRecessed2)
                    Capsule()
                        .fill(ringColor)
                        .frame(width: max(0, min(CGFloat(fraction), 1)) * geo.size.width)
                }
            }
            .frame(height: 7)

            HStack {
                Text("of \(totalBudget.formattedINRWhole()) budget")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.label3)
                Spacer()
                Text(percentUsedLabel)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.label3)
            }
        }
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
        budgetedSpent: Decimal(28000),
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
        budgetedSpent: Decimal(0),
        totalBudget: Decimal(0),
        selectedTab: $tab
    )
    .padding()
    .background(DesignTokens.bgCanvas)
    .preferredColorScheme(.dark)
}
