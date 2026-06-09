import SwiftUI
import SwiftData

/// Category CRUD management sheet (EXP-05, D2-11).
///
/// Presented as a .sheet from BudgetsView "Manage Categories" toolbar button.
/// Supports: add (lookup-before-insert, no @Attribute(.unique)), rename, delete
/// (confirmationDialog + CR-01 explicit save + .nullify cascade).
///
/// Threat mitigations:
/// - T-02-12: Lookup-before-insert (case-insensitive FetchDescriptor) prevents duplicates.
/// - T-02-13: confirmationDialog gates accidental delete; .nullify clears expense links.
/// - T-02-15: Plain Text() everywhere — never AttributedString(markdown:) on user input.
struct ManageCategoriesView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var newCategoryName: String = ""
    @State private var showAddField: Bool = false
    @State private var categoryToDelete: Category? = nil
    @State private var showDeleteConfirmation: Bool = false
    @State private var nameError: String? = nil
    @State private var renamingCategory: Category? = nil
    @State private var renameText: String = ""

    var body: some View {
        NavigationStack {
            List {
                // Existing categories
                ForEach(categories) { category in
                    categoryRow(category)
                }
                .onDelete { offsets in
                    if let index = offsets.first {
                        categoryToDelete = categories[index]
                        showDeleteConfirmation = true
                    }
                }

                // Add new category row (shown when + is tapped)
                if showAddField {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "tag")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            TextField("Category name", text: $newCategoryName)
                                .font(.body)
                                .submitLabel(.done)
                                .onSubmit {
                                    addCategory(name: newCategoryName)
                                }
                            Button("Done") {
                                addCategory(name: newCategoryName)
                            }
                            .font(.body)
                            .tint(.accentColor)
                        }
                        .frame(minHeight: 44)
                        if let error = nameError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(Color(.systemRed))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        nameError = nil
                        newCategoryName = ""
                        showAddField = true
                        renamingCategory = nil
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Category")
                }
            }
            .confirmationDialog(
                "Delete Category?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Category", role: .destructive) {
                    if let cat = categoryToDelete {
                        deleteCategory(cat)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All expenses in this category will become uncategorized. Any budget set for this category will also be removed.")
            }
        }
    }

    // MARK: - Category Row

    @ViewBuilder
    private func categoryRow(_ category: Category) -> some View {
        if renamingCategory?.persistentModelID == category.persistentModelID {
            // Rename mode: inline TextField
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let symbol = category.symbolName {
                        Image(systemName: symbol)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                    }
                    TextField("Category name", text: $renameText)
                        .font(.body)
                        .submitLabel(.done)
                        .onSubmit {
                            saveRename(for: category)
                        }
                    Button("Done") {
                        saveRename(for: category)
                    }
                    .font(.body)
                    .tint(.accentColor)
                }
                .frame(minHeight: 44)
                if let error = nameError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color(.systemRed))
                }
            }
        } else {
            // Normal row: tap to rename
            Button(action: {
                renamingCategory = category
                renameText = category.name ?? ""
                nameError = nil
                showAddField = false
            }) {
                HStack {
                    if let symbol = category.symbolName {
                        Image(systemName: symbol)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                    }
                    Text(category.name ?? "")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    /// Adds a new category with uniqueness check (lookup-before-insert, T-02-12).
    /// Rejects empty names and case-insensitive duplicates with inline errors.
    private func addCategory(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            nameError = "Category name cannot be empty."
            return
        }
        // Lookup-before-insert: fetch all and compare case-insensitively
        // Note: #Predicate doesn't support .lowercased() — fetch all and compare in-memory
        let lower = trimmed.lowercased()
        do {
            let all = try context.fetch(FetchDescriptor<Category>())
            let duplicate = all.first { ($0.name ?? "").lowercased() == lower }
            guard duplicate == nil else {
                nameError = "A category with that name already exists."
                return
            }
            // Prepend before the lowest existing sortOrder so new categories surface at the
            // TOP of the @Query(sort: \Category.sortOrder) ascending list (STAB-03 / user direction).
            let nextSortOrder = (all.map(\.sortOrder).min() ?? 0) - 1
            let category = Category(name: trimmed, symbolName: "tag", sortOrder: nextSortOrder)
            context.insert(category)
            try context.save()  // CR-01: explicit save
            nameError = nil
            newCategoryName = ""
            showAddField = false
        } catch {
            assertionFailure("Failed to save new category: \(error)")
            print("Failed to save new category: \(error)")
        }
    }

    /// Saves a rename, running the same uniqueness check (T-02-12).
    private func saveRename(for category: Category) {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            nameError = "Category name cannot be empty."
            return
        }
        let lower = trimmed.lowercased()
        // Allow saving with the same name (no false duplicate on self)
        if (category.name ?? "").lowercased() != lower {
            do {
                let all = try context.fetch(FetchDescriptor<Category>())
                let duplicate = all.first {
                    $0.persistentModelID != category.persistentModelID &&
                    ($0.name ?? "").lowercased() == lower
                }
                guard duplicate == nil else {
                    nameError = "A category with that name already exists."
                    return
                }
            } catch {
                assertionFailure("Failed to fetch categories for rename check: \(error)")
                return
            }
        }
        category.name = trimmed
        do {
            try context.save()  // CR-01: explicit save
            nameError = nil
            renamingCategory = nil
        } catch {
            assertionFailure("Failed to save rename: \(error)")
            print("Failed to save rename: \(error)")
        }
    }

    /// Deletes a category and persists (CR-01). .nullify delete rule clears expense.categories links.
    private func deleteCategory(_ category: Category) {
        context.delete(category)
        do {
            try context.save()  // CR-01: explicit save
        } catch {
            assertionFailure("Failed to save after deleting category: \(error)")
            print("Failed to save after deleting category: \(error)")
        }
    }
}
