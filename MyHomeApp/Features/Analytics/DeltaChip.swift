import SwiftUI

// MARK: - DeltaChip

/// Period-over-period delta indicator chip with INVERTED color semantics (ANL-05).
///
/// **Color inversion rule (ANL-05 / Pitfall 6):**
/// - `delta > 0`  = spent MORE than prior period → BAD → coral (`DesignTokens.negative`)
/// - `delta <= 0` = spent LESS than prior period → GOOD → green (`DesignTokens.positive`)
///
/// The chip is a tappable Button (for drill-down). Pass an empty closure to make it
/// non-interactive (e.g., inside DeltaDrillDownSheet per-category rows).
struct DeltaChip: View {

    // MARK: - Inputs

    /// Signed delta: currentPeriodSpend − priorPeriodSpend.
    /// Positive = more spend (coral); negative = less spend (green).
    let delta: Decimal

    /// Total spend in the prior period, used for percentage computation.
    let priorTotal: Decimal

    /// Called when the chip is tapped. Pass `{}` for a non-interactive chip.
    let onTap: () -> Void

    // MARK: - Derived

    /// True when spend INCREASED (delta > 0) — mapped to the "bad" / coral color.
    private var isPositive: Bool { delta > 0 }

    /// ANL-05 / Pitfall 6: inverted color — green when delta <= 0 (spent LESS); coral when delta > 0 (spent MORE).
    private var chipColor: Color { delta > 0 ? DesignTokens.negative : DesignTokens.positive }

    /// Arrow direction: up when spent more, down when spent less.
    private var arrowName: String { isPositive ? "arrow.up" : "arrow.down" }

    // MARK: - Percentage label

    /// Formatted percentage change, zero-guarded.
    /// Pitfall 7: the division stays in Decimal until the NSDecimalNumber conversion —
    /// do NOT cast delta or priorTotal to Double before dividing (float precision error).
    private var pctLabel: String {
        guard priorTotal > 0 else { return "—" }
        let pct = abs(NSDecimalNumber(decimal: delta / priorTotal).doubleValue) * 100
        return String(format: "%.0f%%", pct)
    }

    // MARK: - Body

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: arrowName)
                    .font(.caption.weight(.bold))
                Text(pctLabel)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(chipColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(chipColor.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        let direction = isPositive ? "up" : "down"
        return "Spending \(direction) \(pctLabel) vs prior period. Tap to see category breakdown."
    }
}
