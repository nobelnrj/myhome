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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconTile(category: progressData.category, size: 38, cornerRadius: 11)

                VStack(alignment: .leading, spacing: 2) {
                    Text(progressData.category.name ?? "")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DesignTokens.label)
                        .lineLimit(1)
                    Text(subtitleText)
                        .font(.system(size: 13))
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(progressData.spent.formattedINRWhole())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DesignTokens.label)
                        .monospacedDigit()
                        .lineLimit(1)
                    if let budget = progressData.budget {
                        Text("of \(budget.formattedINRWhole())")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.label3)
                            .lineLimit(1)
                    } else {
                        Text("this month")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.label3)
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

            // Embossed progress bar — only when a budget is set (v2 recipe: recessed track,
            // embossed category-colour fill; solid red at full width once over budget)
            if hasBudget, let fraction = progressData.fractionUsed {
                EmbossedBar(fraction: fraction, fill: barColor, height: 10, minWidth: 10)
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
