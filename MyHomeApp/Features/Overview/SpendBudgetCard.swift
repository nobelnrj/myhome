import SwiftUI

/// Overview Card 1: Aggregate spend vs. budget bar (OVR-01, D4-02).
///
/// Dumb/value-driven: consumes pre-computed `totalSpend` and `totalBudget` from
/// the parent's OverviewAggregation result. No @Query, no SwiftData.
///
/// Empty state semantics (D4-07):
/// - `totalBudget == 0`: replace bar + footer row with "Set a budget…" prompt + tab-switch button.
/// - `totalBudget == 0 && totalSpend == 0`: additionally show "No spend yet this month." where Row B hero would appear.
///
/// Accessibility: card uses .accessibilityElement(children: .combine); the bar geometry uses
/// .accessibilityElement(children: .ignore) — the combined card label carries the numeric value.
///
/// Threat mitigations:
/// - T-04-07: selectedTab assignment is a plain integer @Binding; no URL parsing, no external input.
struct SpendBudgetCard: View {

    let totalSpend: Decimal
    let totalBudget: Decimal
    @Binding var selectedTab: Int

    // MARK: - Computed thresholds (inline — no Category instance needed for aggregate bar)

    /// Fraction of budget consumed (nil when no budget is set; guarded against divide-by-zero).
    private var fractionUsed: Double? {
        guard totalBudget > 0 else { return nil }
        return Double(truncating: (totalSpend / totalBudget) as NSDecimalNumber)
    }

    /// BudgetColor classification mirroring BudgetProgressData.colorThreshold (D2-09).
    private var colorThreshold: BudgetColor {
        guard let f = fractionUsed else { return .normal }
        if f >= 1.0 { return .overBudget }
        if f >= 0.8 { return .warning }
        return .normal
    }

    /// Bar fill color mapped from BudgetColor (mirrors BudgetProgressView.swift lines 17–22).
    private var barFillColor: Color {
        switch colorThreshold {
        case .normal:     return .accentColor
        case .warning:    return Color(.systemOrange)
        case .overBudget: return Color(.systemRed)
        }
    }

    /// ₹ remaining / over-budget label text color (matches BudgetProgressView remainingTextColor).
    private var remainingTextColor: Color {
        switch colorThreshold {
        case .normal:     return .secondary
        case .warning:    return Color(.systemOrange)
        case .overBudget: return Color(.systemRed)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row A — Card title
            Text("This Month")
                .font(.title2)
                .bold()

            // Row B — Hero spend amount (always shown, even when no budget set)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(totalSpend.formattedINR())
                    .font(.largeTitle)
                    .bold()
                    .foregroundStyle(.primary)
                if totalBudget > 0 {
                    Text("of \(totalBudget.formattedINR())")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if totalBudget == 0 {
                // Empty state — no budget set
                if totalSpend == 0 {
                    // Also no spend yet
                    Text("No spend yet this month.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("Set a budget to track your spending.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Set a budget") {
                    selectedTab = 2
                }
                .font(.subheadline)
                .tint(.accentColor)
            } else {
                // Row C — Aggregate progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.tertiarySystemBackground))
                            .frame(height: 16)
                        // Fill
                        if let fraction = fractionUsed {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(barFillColor)
                                .frame(
                                    width: min(CGFloat(fraction), 1.0) * geo.size.width,
                                    height: 16
                                )
                                .animation(.easeInOut(duration: 0.3), value: fraction)
                        }
                    }
                }
                .frame(height: 16)
                .accessibilityElement(children: .ignore)

                // Row D — ₹ remaining/over-budget label + % used
                if let fraction = fractionUsed {
                    let remaining = totalBudget - totalSpend
                    HStack {
                        if remaining >= 0 {
                            Text("\(remaining.formattedINR()) remaining")
                                .font(.subheadline)
                                .foregroundStyle(remainingTextColor)
                        } else {
                            Text("\((-remaining).formattedINR()) over budget")
                                .font(.subheadline)
                                .foregroundStyle(Color(.systemRed))
                        }
                        Spacer()
                        Text(fraction >= 1.0 ? "100%+" : "\(Int(fraction * 100))% used")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
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
        selectedTab: $tab
    )
    .padding()
}

#Preview("Warning — 85%") {
    @Previewable @State var tab = 0
    SpendBudgetCard(
        totalSpend: Decimal(8500),
        totalBudget: Decimal(10000),
        selectedTab: $tab
    )
    .padding()
}

#Preview("Over budget — 110%") {
    @Previewable @State var tab = 0
    SpendBudgetCard(
        totalSpend: Decimal(11000),
        totalBudget: Decimal(10000),
        selectedTab: $tab
    )
    .padding()
}

#Preview("No budget set") {
    @Previewable @State var tab = 0
    SpendBudgetCard(
        totalSpend: Decimal(3000),
        totalBudget: Decimal(0),
        selectedTab: $tab
    )
    .padding()
}

#Preview("No spend, no budget") {
    @Previewable @State var tab = 0
    SpendBudgetCard(
        totalSpend: Decimal(0),
        totalBudget: Decimal(0),
        selectedTab: $tab
    )
    .padding()
}
