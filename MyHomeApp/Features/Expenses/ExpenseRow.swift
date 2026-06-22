import SwiftUI

/// Single row in the expense list.
///
/// Restyled to the neumorphic design system: a colored category `IconTile`, the merchant (note) as
/// the title, a "category · account" subtitle (with an envelope glyph for email-ingested rows),
/// and the amount trailing. Income amounts (negative) show `DesignTokens.positive`; spend amounts
/// show `DesignTokens.negative` — both `.semibold` for legibility.
struct ExpenseRow: View {

    let expense: Expense

    private var category: Category? { expense.categories.first }

    var body: some View {
        HStack(spacing: 12) {
            IconTile(category: category, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
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
                .font(.subheadline)
                .foregroundStyle(DesignTokens.label2)
            }

            Spacer(minLength: 8)

            Text(expense.amount.formattedINR())
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(expense.amount < 0 ? DesignTokens.positive : DesignTokens.negative)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Title prefers the free-form note/payee, falling back to the category name.
    private var title: String {
        if let note = expense.note, !note.isEmpty { return note }
        return category?.name ?? "Expense"
    }

    /// Subtitle is "Category · Account" (account omitted when there's no source label).
    private var subtitle: String {
        let cat = category?.name ?? "Uncategorized"
        if let source = expense.sourceLabel, !source.isEmpty {
            return "\(cat) · \(source)"
        }
        return cat
    }
}
