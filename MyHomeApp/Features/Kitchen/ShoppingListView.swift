import SwiftUI
import SwiftData

/// The Shopping segment of the Kitchen surface (KTCH-03) — matches `20-REF-shopping.png`.
///
/// Two sections with two different identities, deliberately never mixed:
///
/// - **RESTOCK (derived)** — `KitchenLogic.deriveShoppingItems` over the live pantry `@Query`.
///   These rows are computed at render time and are NEVER written as `ShoppingListItem` rows
///   (20-01 locked sync design, T-20-08): materialised auto rows would let two phones mint
///   duplicates the merge engine could not reconcile. Checking one off calls
///   `KitchenLogic.markRestocked`, so the row restocks its pantry item and simply stops being
///   derived — the pantry↔shopping link is one object.
/// - **EXTRAS (manual)** — real `ShoppingListItem` rows added by hand, synced via 20-02's DTOs.
///   Checking a manual extra off deliberately does NOT touch the pantry: an extra has no pantry
///   staple behind it, so there is nothing to restock. Only derived rows restock.
///
/// Every delete goes through `context.deleteSynced(_:kind:)` (T-20-09) so the other phone learns
/// about it — a bare SwiftData delete never appears anywhere in `Features/Kitchen`.
struct ShoppingListView: View {

    @Query(sort: \PantryItem.name) private var pantry: [PantryItem]
    @Query(sort: \ShoppingListItem.createdAt) private var extras: [ShoppingListItem]

    @Environment(\.modelContext) private var context

    @State private var newItemName: String = ""
    @State private var editingExtra: ShoppingListItem?
    @FocusState private var addFieldFocused: Bool

    private var restockItems: [PantryItem] { KitchenLogic.deriveShoppingItems(from: pantry) }

    /// Unchecked first (in creation order), then the checked ones struck through below.
    private var sortedExtras: [ShoppingListItem] {
        extras.filter { !$0.isChecked } + extras.filter { $0.isChecked }
    }

    private var checkedExtras: [ShoppingListItem] { extras.filter { $0.isChecked } }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: DesignTokens.spacing16) {
                if restockItems.isEmpty && extras.isEmpty {
                    emptyState
                        .entrance(0)
                } else {
                    if !restockItems.isEmpty {
                        sectionHeader("Restock", count: restockItems.count)
                        restockCard
                            .entrance(0)
                        derivedFootnote
                    }
                    extrasHeader
                    extrasCard
                        .entrance(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(DesignTokens.bgCanvas)
        .sheet(item: $editingExtra) { item in
            EditShoppingItemView(item: item)
        }
    }

    // MARK: - Restock (derived)

    @ViewBuilder
    private var restockCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(restockItems.enumerated()), id: \.element.id) { index, item in
                ShoppingRow(kind: .derived(item))
                if index < restockItems.count - 1 {
                    Divider().padding(.leading, 64)
                }
            }
        }
        .neuSurface(.raised, padding: nil)
    }

    /// The user-facing statement of the derived-not-materialised design (UI-REFERENCE item 5).
    @ViewBuilder
    private var derivedFootnote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
            Text("Pulled live from your pantry — never saved as tasks. Check one to restock it and it leaves the list.")
                .font(.footnote)
        }
        .foregroundStyle(DesignTokens.label3)
        .padding(.horizontal, 6)
        .padding(.top, -8)
    }

    // MARK: - Extras (manual)

    @ViewBuilder
    private var extrasHeader: some View {
        HStack {
            Text("Extras").eyebrow()
            Spacer()
            if checkedExtras.isEmpty {
                Text("\(extras.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.label3)
                    .monospacedDigit()
            } else {
                Button("Clear checked") { clearChecked() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.accentText)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, -8)
    }

    @ViewBuilder
    private var extrasCard: some View {
        VStack(spacing: 0) {
            ForEach(sortedExtras, id: \.id) { item in
                ShoppingRow(kind: .manual(item)) { editingExtra = item }
                    .contextMenu {
                        Button("Edit") { editingExtra = item }
                        Button("Delete", role: .destructive) { delete(item) }
                    }
                Divider().padding(.leading, 64)
            }
            addRow
        }
        .neuSurface(.raised, padding: nil)
    }

    @ViewBuilder
    private var addRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignTokens.label3)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle().strokeBorder(
                        DesignTokens.label3.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])
                    )
                )
                .frame(width: 44, height: 44)
                .fixedSize()

            TextField("Add item…", text: $newItemName)
                .font(.system(size: 17))
                .foregroundStyle(DesignTokens.label)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($addFieldFocused)
                .onSubmit(addItem)
            if !newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Add", action: addItem)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.accentText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { addFieldFocused = true }
        .accessibilityLabel("Add a shopping item")
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "basket")
                .font(.system(size: 30))
                .foregroundStyle(DesignTokens.label2)
                .frame(width: 82, height: 82)
                .neuSurface(.raised, radius: 24, padding: nil)
                .fixedSize()   // stay a rounded square instead of stretching across the canvas
            Text("Nothing to buy")
                .font(.title3.bold())
                .foregroundStyle(DesignTokens.label)
            Text("Pantry looks stocked. Items land here the moment something runs low.")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.label2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            TextField("Add item…", text: $newItemName)
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .submitLabel(.done)
                .onSubmit(addItem)
                .neuSurface(.recessed, radius: 16, padding: 12)
                .padding(.horizontal, 32)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).eyebrow()
            Spacer()
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.label3)
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, -8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) items")
    }

    // MARK: - Actions

    private func addItem() {
        let trimmed = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            context.insert(ShoppingListItem(name: trimmed))
        }
        try? context.save()   // CR-01: explicit save
        newItemName = ""
        Haptics.selection()
    }

    /// T-20-09: manual deletes are tombstoned so the other phone drops the row too.
    private func delete(_ item: ShoppingListItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            context.deleteSynced(item, kind: .shoppingListItem)
        }
        try? context.save()
        Haptics.selection()
    }

    private func clearChecked() {
        withAnimation(.easeInOut(duration: 0.25)) {
            for item in checkedExtras {
                context.deleteSynced(item, kind: .shoppingListItem)
            }
        }
        try? context.save()
        Haptics.selection()
    }
}

// MARK: - Compact edit sheet for a manual extra

/// Name / quantity / unit for a manually-added extra, plus a tombstoned remove.
/// Pantry staples keep their richer editor (`EditPantryItemView`) — an extra has no thresholds.
struct EditShoppingItemView: View {

    let item: ShoppingListItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var quantity: Double = 1
    @State private var unit: String = ""
    @State private var didLoad = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TextField("Item name", text: $name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DesignTokens.label)
                        .textInputAutocapitalization(.sentences)
                        .neuSurface(.raised, radius: 20, padding: 14)

                    HStack(spacing: 12) {
                        StepperCircle(symbol: "minus", enabled: quantity > 1) {
                            quantity = max(1, quantity - 1)
                            Haptics.selection()
                        }
                        VStack(spacing: 2) {
                            Text(KitchenFormat.quantity(quantity))
                                .font(.system(size: 22, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(DesignTokens.label)
                            Text("How many").eyebrow()
                        }
                        .frame(maxWidth: .infinity)
                        StepperCircle(symbol: "plus", enabled: true) {
                            quantity += 1
                            Haptics.selection()
                        }
                    }
                    .neuSurface(.raised, radius: 20, padding: 14)

                    TextField("Unit (optional)", text: $unit)
                        .font(.system(size: 16))
                        .foregroundStyle(DesignTokens.label)
                        .neuSurface(.raised, radius: 20, padding: 14)

                    Button("Remove from list", role: .destructive) {
                        context.deleteSynced(item, kind: .shoppingListItem)
                        try? context.save()
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignTokens.negative)
                    .frame(maxWidth: .infinity)
                    .neuSurface(.raised, radius: 20, padding: 14)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.bgCanvas)
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        name = item.name ?? ""
        quantity = item.quantity
        unit = item.unit ?? ""
    }

    private func save() {
        item.name = trimmedName
        item.quantity = quantity
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        item.unit = trimmedUnit.isEmpty ? nil : trimmedUnit
        item.touch()          // honest LWW clock (18-04)
        try? context.save()
        dismiss()
    }
}
