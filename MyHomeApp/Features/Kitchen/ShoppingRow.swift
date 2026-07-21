import SwiftUI
import SwiftData

/// One row of the shopping list (KTCH-03), serving BOTH list identities through a single enum so
/// the two can never be confused at a call site.
///
/// - `.derived(PantryItem)` — an auto row computed from pantry state. It is never a stored
///   `ShoppingListItem` (20-01 locked design). Checking it off calls `KitchenLogic.markRestocked`,
///   so the trailing "↻ + N unit" pill states the consequence BEFORE the tap.
/// - `.manual(ShoppingListItem)` — a user-typed extra. Checking it off only flips its own state;
///   it has no pantry row to restock, which is exactly why the two sections are separate.
///
/// Matches `20-REF-shopping.png`: recessed leading check circle on both kinds, icon tile +
/// LOW/OUT badge + "N unit left" + restock pill on derived rows, plain name on extras.
/// Accessibility: 44pt check target, explicit labels, colour never the sole indicator.
/// Threat T-20-06: names render through plain `Text`, never `AttributedString(markdown:)`.
struct ShoppingRow: View {

    enum Kind {
        case derived(PantryItem)
        case manual(ShoppingListItem)
    }

    let kind: Kind
    /// Row body tap (edit sheet for manual extras; no-op for derived rows).
    var onTap: (() -> Void)? = nil

    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 12) {
            CheckCircle(isChecked: isChecked, action: toggle)
                .accessibilityLabel(checkAccessibilityLabel)

            switch kind {
            case .derived(let item):
                derivedBody(item)
            case .manual(let item):
                manualBody(item)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // P22-D4/P22-D6: same shared resolver as PantryItemRow, so a name present in both the
        // pantry list and this list is classified exactly once. `nil` for manual extras, which
        // carry no icon tile — the resolver no-ops on a nil name.
        .task(id: derivedItemName) {
            await PantryIconResolver.shared.classifyIfNeeded(name: derivedItemName)
        }
    }

    /// The pantry name whose icon this row draws, or `nil` for a manual extra.
    private var derivedItemName: String? {
        switch kind {
        case .derived(let item): return item.name
        case .manual: return nil
        }
    }

    // MARK: - Bodies

    @ViewBuilder
    private func derivedBody(_ item: PantryItem) -> some View {
        // Synchronous tile (AI-SPEC §4.4) — see PantryItemRow. Upgrades in place via the `.task`.
        let icon = PantryIconResolver.shared.presentation(for: item)
        IconTile(symbol: icon.symbol, color: icon.color, size: 38, cornerRadius: 11)

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(item.name ?? "—")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DesignTokens.label)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                StockBadge(status: KitchenLogic.stockStatus(for: item))
                    .fixedSize()
            }
            Text(leftLine(item))
                .font(.subheadline)
                .foregroundStyle(DesignTokens.label2)
                .lineLimit(1)
        }
        Spacer(minLength: 4)

        // States the check-off consequence before the tap: restock is ADDITIVE.
        RestockPill(text: restockText(item))
            .fixedSize()
    }

    @ViewBuilder
    private func manualBody(_ item: ShoppingListItem) -> some View {
        // Extras carry NO icon tile (mockup) — they are not pantry staples.
        Button(action: { onTap?() }) {
            HStack(spacing: 8) {
                Text(item.name ?? "—")
                    .font(.system(size: 17, weight: item.isChecked ? .regular : .semibold))
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? DesignTokens.label3 : DesignTokens.label)
                    .lineLimit(2)
                if let detail = quantityDetail(item) {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.label2)
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name ?? "Item")
        .accessibilityHint("Edit item")
    }

    // MARK: - State

    private var isChecked: Bool {
        switch kind {
        case .derived: return false          // a derived row leaves the list instead of staying checked
        case .manual(let item): return item.isChecked
        }
    }

    private func toggle() {
        switch kind {
        case .derived(let item):
            // The pantry↔shopping link: one restock = one purchase (additive).
            withAnimation(.easeInOut(duration: 0.25)) {
                KitchenLogic.markRestocked(item)
            }
        case .manual(let item):
            withAnimation(.easeInOut(duration: 0.2)) {
                KitchenLogic.toggleChecked(item)
            }
        }
        try? context.save()   // CR-01: explicit save
        Haptics.selection()
    }

    // MARK: - Text

    private func leftLine(_ item: PantryItem) -> String {
        let unit = (item.unit ?? "").trimmingCharacters(in: .whitespaces)
        let qty = KitchenFormat.quantity(item.quantity)
        return unit.isEmpty ? "\(qty) left" : "\(qty) \(unit) left"
    }

    private func restockText(_ item: PantryItem) -> String {
        let unit = (item.unit ?? "").trimmingCharacters(in: .whitespaces)
        let qty = KitchenFormat.quantity(item.restockQuantity)
        return unit.isEmpty ? "+ \(qty)" : "+ \(qty) \(unit)"
    }

    private func quantityDetail(_ item: ShoppingListItem) -> String? {
        let unit = (item.unit ?? "").trimmingCharacters(in: .whitespaces)
        if item.quantity == 1 && unit.isEmpty { return nil }
        let qty = KitchenFormat.quantity(item.quantity)
        return unit.isEmpty ? "· \(qty)" : "· \(qty) \(unit)"
    }

    private var checkAccessibilityLabel: String {
        switch kind {
        case .derived(let item):
            return "Restock \(item.name ?? "item"), adds \(restockText(item)) to the pantry"
        case .manual(let item):
            return item.isChecked ? "Uncheck \(item.name ?? "item")" : "Check off \(item.name ?? "item")"
        }
    }
}

// MARK: - Check circle

/// 44pt leading check target: recessed empty circle → filled checkmark on the positive twin.
struct CheckCircle: View {
    let isChecked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Fill with the canvas colour explicitly: a bare `Circle()` paints the inherited
                // foreground style (black) over the recessed well, and `Color.clear` has no
                // intrinsic aspect so the well stretches to an oval.
                Circle()
                    .fill(DesignTokens.bgCanvas)
                    .frame(width: 28, height: 28)
                    .neuSurface(.recessed, radius: 14, padding: nil)
                    .fixedSize()
                if isChecked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(DesignTokens.positive)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 44, height: 44)   // ≥44pt hit target
            .fixedSize()
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Restock pill

/// Trailing "↻ + 3 L" capsule on derived rows (mockup) — the amount a check-off ADDS.
struct RestockPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(DesignTokens.accentText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .neuSurface(.recessed, radius: 16, padding: nil)
        .accessibilityHidden(true)   // the check circle's label already states the amount
    }
}
