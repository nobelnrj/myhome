import SwiftUI

/// Single row in the expense list.
///
/// Layout (UI-SPEC Screen 1):
/// - Leading: amount formatted with en-IN lakh grouping (headline weight, ~100pt column)
/// - Trailing: note (Body, one line, truncated) over date (Label/subheadline, secondary)
/// - Negative amounts: systemGreen color AND leading minus from formattedINR (color never sole differentiator)
struct ExpenseRow: View {

    let expense: Expense

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Amount — fixed leading column, right-aligned (UI-SPEC headline weight)
            Text(expense.amount.formattedINR())
                .font(.headline)
                .foregroundStyle(expense.amount < 0 ? Color(.systemGreen) : Color(.label))
                .frame(width: 100, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // Note + date — trailing column
            VStack(alignment: .leading, spacing: 2) {
                if let note = expense.note, !note.isEmpty {
                    // T-01-06: plain Text() — never AttributedString(markdown:) on user input
                    Text(note)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(expense.date.formattedForExpenseList())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
