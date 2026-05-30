import SwiftUI
import SwiftData

/// Sheet for picking (or clearing) a category on an expense.
///
/// Layout (UI-SPEC Screen 5):
/// - NavigationStack-in-sheet titled "Category" (inline)
/// - Toolbar: leading "Cancel" (dismiss with no change), trailing "Clear" (only when a category is
///   currently selected — sets nil + dismisses, .systemRed tint, .destructiveAction placement)
/// - List (.insetGrouped): "None" row at top, then ForEach over @Query-sorted categories
/// - Selection checkmark in .accentColor on the active row
///
/// Security: T-02-07 — plain Text(category.name ?? "") only; never AttributedString(markdown:).
struct CategoryPickerView: View {

    @Binding var selectedCategory: Category?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // "None" row — top of list (represents selectedCategory = nil)
                Button(action: {
                    selectedCategory = nil
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "circle.slash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                        Text("None")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedCategory == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)

                // Category rows — sorted by sortOrder via @Query
                ForEach(categories) { category in
                    Button(action: {
                        selectedCategory = category
                        dismiss()
                    }) {
                        HStack {
                            if let symbol = category.symbolName {
                                Image(systemName: symbol)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                                    .accessibilityHidden(true)
                            }
                            // T-02-07: plain Text — never AttributedString(markdown:)
                            Text(category.name ?? "")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedCategory?.persistentModelID == category.persistentModelID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                if selectedCategory != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear") {
                            selectedCategory = nil
                            dismiss()
                        }
                        .tint(Color(.systemRed))
                    }
                }
            }
        }
    }
}
