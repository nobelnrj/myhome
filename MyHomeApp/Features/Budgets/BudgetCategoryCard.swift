import SwiftUI

/// Card row showing a category's budget progress for the viewed month (EXP-08, EXP-09).
///
/// Displays: SF Symbol icon, category name, month spend, edit pencil, and BudgetProgressView.
/// The "Edit" pencil presents EditBudgetSheet via .sheet.
///
/// Layout (UI-SPEC Screen 3 BudgetCategoryCard):
/// - Row 1: icon + name + spent + edit pencil (HStack)
/// - Row 2/3: BudgetProgressView (bar + ₹-remaining + % OR "No budget set")
///
/// Accessibility: .accessibilityElement(children: .combine) on the card so VoiceOver
/// reads the card as a single element. Pencil button has explicit .accessibilityLabel.
struct BudgetCategoryCard: View {

    let progressData: BudgetProgressData
    @State private var showEditBudget: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: icon + name + spent + edit button
            HStack {
                if let symbol = progressData.category.symbolName {
                    Image(systemName: symbol)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                }
                Text(progressData.category.name ?? "")
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                Text(progressData.spent.formattedINR())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: { showEditBudget = true }) {
                    Image(systemName: "pencil")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Edit budget for \(progressData.category.name ?? "category")")
            }
            // Row 2/3: progress bar + ₹-remaining + % used, or "No budget set"
            BudgetProgressView(data: progressData)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .accessibilityElement(children: .combine)
        .sheet(isPresented: $showEditBudget) {
            EditBudgetSheet(category: progressData.category)
        }
    }
}
