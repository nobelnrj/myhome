import SwiftUI
import SwiftData

/// Triage row for ingested expenses in the "Needs Review" section of the Expenses tab.
///
/// D7-04/05/06/07/14/15:
/// - Shows parsed fields: amount, normalized merchant (note), date, and sourceLabel (caption).
/// - Possible-duplicate: renders "Possible duplicate of <existing summary>" line (D7-14).
/// - Swipe trailing: "Accept" (promotes to normal expense) and "Discard" (dismisses message ID + deletes).
/// - Tap: opens EditExpenseView for tap-to-edit (D7-06).
///
/// Layout mirrors ExpenseRow's HStack skeleton (PATTERNS.md §ReviewInboxRow).
///
/// No UI-SPEC was produced for this phase (planned with --skip-ui).
/// Uses the existing Expenses-tab visual baseline from Phases 1–2.
struct ReviewInboxRow: View {

    let expense: Expense
    @Environment(\.modelContext) private var context

    private var category: Category? { expense.categories.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                // Colored category tile (mirrors the design's review card)
                IconTile(category: category, size: 38, cornerRadius: 10)

                // Merchant (note) + source — leading column
                VStack(alignment: .leading, spacing: 2) {
                    if let note = expense.note, !note.isEmpty {
                        // T-01-06: plain Text() — never AttributedString(markdown:) on user input
                        Text(note)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Amount + triage badge — trailing column
                VStack(alignment: .trailing, spacing: 4) {
                    Text(expense.amount.formattedINR())
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(expense.amount < 0 ? DesignTokens.positive : DesignTokens.negative)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if expense.ingestionStateRaw == "possibleDuplicate" {
                        Text("Duplicate")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignTokens.orange, in: Capsule())
                    } else {
                        Text("Review")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignTokens.accent, in: Capsule())
                    }
                }
            }

            // Possible-duplicate line (D7-14): shows existing expense summary side-by-side
            if expense.ingestionStateRaw == "possibleDuplicate" {
                Text("Possible duplicate — review before accepting")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.orange)
                    .lineLimit(2)
            }

            // Inline triage buttons — the row lives in a ScrollView card (neumorphic v2),
            // where swipeActions don't fire; these are the primary Accept/Discard affordance.
            HStack(spacing: 10) {
                Button {
                    discardExpense()
                } label: {
                    Label("Discard", systemImage: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.label2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DesignTokens.fillRecessed3, in: Capsule())
                }
                Button {
                    acceptExpense()
                } label: {
                    Label("Accept", systemImage: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.positive)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DesignTokens.positive.opacity(0.14), in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Subtitle

    /// "Category · Account" when both are known, otherwise whichever is available, falling back
    /// to the parsed date so the row is never label-less.
    private var subtitleText: String {
        var parts: [String] = []
        if let name = category?.name, !name.isEmpty { parts.append(name) }
        if let source = expense.sourceLabel, !source.isEmpty { parts.append(source) }
        if parts.isEmpty { parts.append(expense.date.formattedForExpenseList()) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    /// Promotes the expense to a normal expense by clearing ingestionStateRaw (D7-06).
    private func acceptExpense() {
        expense.ingestionStateRaw = nil
        expense.updatedAt = Date()
        do {
            try context.save()
        } catch {
            print("ReviewInboxRow: failed to accept expense: \(error)")
        }
    }

    /// Dismisses the Gmail message ID and deletes the expense (D7-06/07).
    private func discardExpense() {
        if let messageID = expense.gmailMessageID {
            // D7-07: Persist the dismissed message ID so future syncs skip this email
            DismissedMessageStore.dismiss(messageID)
        }
        context.deleteSynced(expense, kind: .expense)
        do {
            try context.save()
        } catch {
            print("ReviewInboxRow: failed to discard expense: \(error)")
        }
    }
}
