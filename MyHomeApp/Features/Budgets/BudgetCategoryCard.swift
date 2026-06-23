import SwiftUI

/// Card row showing a category's budget progress for the viewed month (EXP-08, EXP-09).
///
/// Restyled to the `MyHome.html` design: a colored category `IconTile`, the name, a
/// "₹X left / ₹X over / No budget set" subtitle, the month spend (with "of ₹limit") trailing,
/// an edit pencil, and a progress bar that uses the category color, turning **orange** at ≥85%
/// and **red** when over budget. Color is never the sole signal — the subtitle text carries the
/// left/over state (D2-09).
///
/// The "Edit" pencil presents EditBudgetSheet via .sheet (kept `.plain` so it doesn't trigger
/// the enclosing NavigationLink).
struct BudgetCategoryCard: View {

    let progressData: BudgetProgressData
    @State private var showEditBudget: Bool = false

    private var hasBudget: Bool { progressData.budget != nil }
    private var isOver: Bool {
        if let r = progressData.remaining { return r < 0 }
        return false
    }

    /// Progress-bar fill: category color normally, orange ≥85%, red when over.
    private var barColor: Color {
        switch progressData.colorThreshold {
        case .overBudget: return DesignTokens.negative
        case .warning:    return DesignTokens.orange
        case .normal:     return CategoryStyle.color(for: progressData.category)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                IconTile(category: progressData.category, size: 34, cornerRadius: 9)

                VStack(alignment: .leading, spacing: 1) {
                    Text(progressData.category.name ?? "")
                        .font(.headline)
                        .lineLimit(1)
                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(progressData.spent.formattedINRWhole())
                        .font(.headline)
                        .foregroundStyle(DesignTokens.label)
                        .lineLimit(1)
                    if let budget = progressData.budget {
                        Text("of \(budget.formattedINRWhole())")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.label3)
                            .lineLimit(1)
                    }
                }

                Button(action: { showEditBudget = true }) {
                    Image(systemName: "pencil")
                        .foregroundStyle(DesignTokens.label3)
                        .frame(width: 28, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit budget for \(progressData.category.name ?? "category")")
            }

            // Progress bar — only when a budget is set
            if hasBudget, let fraction = progressData.fractionUsed {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DesignTokens.fillRecessed2)
                        Capsule().fill(barColor)
                            .frame(width: max(0, min(CGFloat(fraction), 1)) * geo.size.width)
                            .neonGlow(barColor, radius: 6)
                            .animation(.easeInOut(duration: 0.3), value: fraction)
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)
            }
        }
        .neuSurface(.raised, radius: 20, padding: 15, isInteractive: true)
        .accessibilityElement(children: .combine)
        .sheet(isPresented: $showEditBudget) {
            EditBudgetSheet(category: progressData.category)
        }
    }

    // MARK: - Subtitle

    private var subtitleText: String {
        guard let remaining = progressData.remaining else { return "No budget set" }
        if remaining < 0 {
            return "\((-remaining).formattedINRWhole()) over"
        }
        return "\(remaining.formattedINRWhole()) left"
    }

    private var subtitleColor: Color {
        guard hasBudget else { return DesignTokens.label3 }
        return isOver ? DesignTokens.negative : DesignTokens.label2
    }
}
