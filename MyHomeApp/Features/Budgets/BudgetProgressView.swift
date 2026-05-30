import SwiftUI

/// Pure progress bar component for budget visualization (EXP-08, D2-09).
///
/// Consumes `BudgetProgressData` (pure value type from BudgetCalculator.swift).
/// No @Bindable, no @Query — pure display component.
///
/// Accessibility: bar RoundedRectangle uses .accessibilityElement(children: .ignore);
/// the parent card row is the accessibility element (combining icon + name + amounts).
/// Color is never the sole signal — every threshold is paired with ₹-remaining + % text (D2-09).
struct BudgetProgressView: View {

    let data: BudgetProgressData

    // MARK: - Color mapping (BudgetColor → SwiftUI Color, UI-SPEC § Color)

    private var fillColor: Color {
        switch data.colorThreshold {
        case .normal:     return .accentColor
        case .warning:    return Color(.systemOrange)
        case .overBudget: return Color(.systemRed)
        }
    }

    // MARK: - Body

    var body: some View {
        if data.budget == nil {
            // No-budget branch: single label + edit affordance provided by the parent card
            Text("No budget set")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                // Progress bar — GeometryReader caps fill at 100% track width (D2-09)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track (always rendered — secondarySystemBackground, 8pt, cornerRadius 4)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.secondarySystemBackground))
                            .frame(height: 8)
                        // Fill — only rendered when fractionUsed is available
                        if let fraction = data.fractionUsed {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(fillColor)
                                .frame(
                                    width: min(CGFloat(fraction), 1.0) * geo.size.width,
                                    height: 8
                                )
                                .animation(.easeInOut(duration: 0.3), value: fraction)
                        }
                    }
                }
                .frame(height: 8)
                .accessibilityElement(children: .ignore)

                // Row 3: ₹-remaining + % used — color paired with text (D2-09, never color-only)
                if let remaining = data.remaining, let fraction = data.fractionUsed {
                    HStack {
                        // ₹-remaining or ₹-over-budget label
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
                        // % used — "100%+" when fully consumed, integer % otherwise
                        Text(fraction >= 1.0 ? "100%+" : "\(Int(fraction * 100))% used")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Remaining text color (matches BudgetColor threshold — D2-09)

    private var remainingTextColor: Color {
        switch data.colorThreshold {
        case .normal:     return .secondary
        case .warning:    return Color(.systemOrange)
        case .overBudget: return Color(.systemRed)
        }
    }
}
