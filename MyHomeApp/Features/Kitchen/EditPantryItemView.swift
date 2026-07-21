import SwiftUI
import SwiftData

/// Add / edit sheet for a pantry item (KTCH-01, KTCH-02).
///
/// Matches `20-REF-edit-sheet.png`: name field with a DERIVED icon tile, a UNIT chip row, and
/// three labelled stepper cards — "In stock", "Low when at or below", "Restock by" (relabelled
/// from the mockup's "Restock to" per the user's binding decision: restock is ADDITIVE) — plus a
/// destructive "Remove from pantry" footer in edit mode.
///
/// Sync hygiene (18-04): an edit of an EXISTING row calls `touch()` before save so LWW resolves in
/// favour of the newest human edit; delete goes through `deleteSynced(_, kind: .pantryItem)` so the
/// other phone cannot resurrect the row. Bare `context.delete` is never used here.
///
/// Threat T-20-06: name/unit/category/notes are trimmed free text stored as plain `String`
/// properties and rendered with plain `Text` — no markdown parsing, no query interpolation.
struct EditPantryItemView: View {

    /// `nil` → add mode.
    let item: PantryItem?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var unit: String = ""
    @State private var quantity: Double = 0
    @State private var lowStockThreshold: Double = 1
    @State private var restockQuantity: Double = 1
    @State private var category: String = ""
    @State private var notes: String = ""
    @State private var showDeleteConfirmation = false
    @State private var didLoad = false

    /// The mockup's chip set. The model stores free text, so a value already saved that is not in
    /// this set is preserved and shown as an extra chip (never silently rewritten).
    private static let unitChips = ["kg", "g", "L", "ml", "pcs", "pack", "pkt", "btl"]

    private var isEditing: Bool { item != nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var chips: [String] {
        let extra = unit.trimmingCharacters(in: .whitespaces)
        if !extra.isEmpty, !Self.unitChips.contains(extra) { return Self.unitChips + [extra] }
        return Self.unitChips
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    nameCard
                    unitPicker
                    stepperCard(
                        title: "In stock",
                        subtitle: nil,
                        value: $quantity
                    )
                    stepperCard(
                        title: "Low when at or below",
                        subtitle: "Shows a LOW badge and adds it to Shopping.",
                        value: $lowStockThreshold
                    )
                    stepperCard(
                        title: "Restock by",
                        subtitle: "Adds this much when you check it off in Shopping.",
                        value: $restockQuantity
                    )
                    detailsCard

                    if isEditing {
                        deleteButton
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.bgCanvas)
            .navigationTitle(isEditing ? "Edit item" : "New item")
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
            .confirmationDialog(
                "Remove from pantry?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) { deleteItem() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This item will be removed from your pantry on every synced device.")
            }
            .onAppear(perform: load)
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private var nameCard: some View {
        HStack(spacing: 12) {
            let icon = KitchenLogic.icon(forName: name)
            IconTile(symbol: icon.symbol, color: icon.color, size: 42, cornerRadius: 12)
            TextField("Item name", text: $name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DesignTokens.label)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
        }
        .neuSurface(.raised, radius: 20, padding: 14)
    }

    @ViewBuilder
    private var unitPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unit").eyebrow()
            FlowChips(items: chips, selected: unit) { chip in
                unit = (unit == chip) ? "" : chip
                Haptics.selection()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func stepperCard(title: String, subtitle: String?, value: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignTokens.label)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)

            // Fixed-width trailing group so all three cards' steppers line up even when a title wraps.
            HStack(spacing: 8) {
                StepperCircle(symbol: "minus", enabled: value.wrappedValue > 0) {
                    value.wrappedValue = max(0, value.wrappedValue - 1)
                    Haptics.selection()
                }
                .accessibilityLabel("Decrease \(title)")

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(KitchenFormat.quantity(value.wrappedValue))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(DesignTokens.label)
                        .monospacedDigit()
                    if !unit.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(unit)
                            .font(.footnote)
                            .foregroundStyle(DesignTokens.label2)
                    }
                }
                .frame(width: 56)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                StepperCircle(symbol: "plus", enabled: true) {
                    value.wrappedValue += 1
                    Haptics.selection()
                }
                .accessibilityLabel("Increase \(title)")
            }
            .fixedSize()
        }
        .neuSurface(.raised, radius: 20, padding: 14)
    }

    @ViewBuilder
    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Category (optional)", text: $category)
                .font(.body)
                .textInputAutocapitalization(.words)
            Divider()
            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .font(.body)
                .lineLimit(1...3)
        }
        .foregroundStyle(DesignTokens.label)
        .neuSurface(.raised, radius: 20, padding: 14)
    }

    @ViewBuilder
    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                Text("Remove from pantry")
                    .fontWeight(.semibold)
            }
            .font(.system(size: 16))
            .foregroundStyle(DesignTokens.negative)
            .frame(maxWidth: .infinity)
            .neuSurface(.raised, radius: 20, padding: 14, isInteractive: true)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    // MARK: - Load / Save / Delete

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let item else { return }
        name = item.name ?? ""
        unit = item.unit ?? ""
        quantity = item.quantity
        lowStockThreshold = item.lowStockThreshold
        restockQuantity = item.restockQuantity
        category = item.category ?? ""
        notes = item.notes ?? ""
    }

    private func save() {
        let cleanName = trimmedName
        guard !cleanName.isEmpty else { return }
        let cleanUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let item {
            item.name = cleanName
            item.unit = cleanUnit.isEmpty ? nil : cleanUnit
            item.quantity = max(0, quantity)
            item.lowStockThreshold = max(0, lowStockThreshold)
            item.restockQuantity = max(0, restockQuantity)
            item.category = cleanCategory.isEmpty ? nil : cleanCategory
            item.notes = cleanNotes.isEmpty ? nil : cleanNotes
            item.touch()   // SYNC-02 / 18-04: user edit carries an honest LWW clock
        } else {
            let new = PantryItem(
                name: cleanName,
                quantity: max(0, quantity),
                unit: cleanUnit.isEmpty ? nil : cleanUnit,
                lowStockThreshold: max(0, lowStockThreshold),
                restockQuantity: max(0, restockQuantity)
            )
            new.category = cleanCategory.isEmpty ? nil : cleanCategory
            new.notes = cleanNotes.isEmpty ? nil : cleanNotes
            context.insert(new)
        }

        do {
            try context.save()   // CR-01: explicit save
        } catch {
            assertionFailure("Failed to save pantry item: \(error)")
        }
        Haptics.success()
        dismiss()
    }

    private func deleteItem() {
        guard let item else { return }
        // T-20-07: the ONLY delete path — a bare context.delete would let a peer resurrect the row.
        context.deleteSynced(item, kind: .pantryItem)
        do {
            try context.save()   // CR-01: explicit save
        } catch {
            assertionFailure("Failed to delete pantry item: \(error)")
        }
        dismiss()
    }
}

// MARK: - Unit chip row

/// Wrapping row of neumorphic unit chips; the selected chip fills with the app accent
/// (`20-REF-edit-sheet.png`). Uses the native flow layout so long chip sets wrap.
private struct FlowChips: View {
    let items: [String]
    let selected: String
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(items, id: \.self) { chip in
                let isOn = chip == selected
                Button { onTap(chip) } label: {
                    Text(chip)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isOn ? DesignTokens.accentOnYellow : DesignTokens.label2)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(
                            Group {
                                if isOn {
                                    Capsule().fill(DesignTokens.accent)
                                } else {
                                    Capsule().fill(LinearGradient(
                                        colors: [DesignTokens.surfaceRaisedTop, DesignTokens.surfaceRaisedBottom],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ))
                                }
                            }
                        )
                        .overlay(Capsule().strokeBorder(DesignTokens.glassBorder, lineWidth: 0.5))
                        .shadow(color: DesignTokens.neuOuterHighlight, radius: 5, x: -4, y: -4)
                        .shadow(color: DesignTokens.neuOuterShade, radius: 6, x: 4, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Unit \(chip)")
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
    }
}

/// Minimal wrapping layout (iOS 16+ `Layout`) — chips flow onto the next line when they run out
/// of width. No third-party packages (T-20-SC).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
