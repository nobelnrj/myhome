import SwiftUI

/// Single row in the Activity (expense) list — neumorphic v2, Screen 4 dense row.
///
/// 36pt category `IconTile`, merchant (note) 15/500 title, "Category · time" tertiary
/// subtitle (with an envelope glyph for email-ingested rows), amount trailing 15/600.
/// Income rows (negative amounts) get a tinted green tile with an up-arrow and a green
/// `+₹` amount; spend amounts stay in the primary label colour per the handoff.
struct ExpenseRow: View {

    let expense: Expense

    private var category: Category? { expense.categories.first }
    private var isIncome: Bool { expense.amount < 0 }

    var body: some View {
        HStack(spacing: 12) {
            if isIncome {
                // Income tile: soft green fill + green up-arrow (handoff income row)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DesignTokens.positive.opacity(0.16))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DesignTokens.positive)
                    )
                    .accessibilityHidden(true)
            } else {
                IconTile(category: category, size: 36)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DesignTokens.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    Text(subtitle)
                        .lineLimit(1)
                    if expense.ingestionStateRaw == "autoSaved" {
                        Image(systemName: "envelope")
                            .imageScale(.small)
                    }
                }
                .font(.system(size: 12.5))
                .foregroundStyle(DesignTokens.label3)
            }

            Spacer(minLength: 8)

            Text(amountText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isIncome ? DesignTokens.positive : DesignTokens.label)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    /// Title prefers the free-form note/payee, falling back to the category name.
    private var title: String {
        if let note = expense.note, !note.isEmpty { return note }
        return category?.name ?? "Expense"
    }

    /// Subtitle is "Category · time" (handoff row spec), keeping the account source label
    /// when present: "Category · Account · 1:12 PM".
    private var subtitle: String {
        var parts = [category?.name ?? "Uncategorized"]
        if let source = expense.sourceLabel, !source.isEmpty {
            parts.append(source)
        }
        parts.append(timeText)
        return parts.joined(separator: " · ")
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: expense.date)
    }

    /// Income shows an explicit `+` (design: `+₹14,000`); spends show the plain amount.
    private var amountText: String {
        isIncome ? "+\(abs(expense.amount).formattedINRWhole())" : expense.amount.formattedINRWhole()
    }
}
