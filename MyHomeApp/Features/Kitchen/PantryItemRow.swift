import SwiftUI
import SwiftData

/// A single pantry row: derived icon tile, name + LOW/OUT badge, "N unit in stock", and the
/// circular −/+ steppers (KTCH-01).
///
/// Matches `20-REF-pantry.png`. All stock math goes through `KitchenLogic` — the row never
/// computes "low" itself. Mutations stamp `touch()` inside the logic helpers, and the row saves.
///
/// Accessibility: colour is NEVER the sole indicator — the badge carries text ("LOW"/"OUT") and an
/// SF Symbol alongside the semantic tint, and each stepper has a 44pt hit target plus an explicit
/// label. Threat T-20-06: names render via plain `Text` — never `AttributedString(markdown:)`.
struct PantryItemRow: View {

    let item: PantryItem
    /// Row tap → open the edit sheet.
    let onEdit: () -> Void

    @Environment(\.modelContext) private var context

    private var status: StockStatus { KitchenLogic.stockStatus(for: item) }

    var body: some View {
        HStack(spacing: 12) {
            // Row body (tap → edit)
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    let icon = KitchenLogic.icon(for: item)
                    IconTile(symbol: icon.symbol, color: icon.color, size: 38, cornerRadius: 11)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(item.name ?? "—")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(DesignTokens.label)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            StockBadge(status: status)
                                .fixedSize()   // badge keeps its intrinsic width; the name shrinks first
                        }
                        Text(stockLine)
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.label2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Edit item")

            // Steppers
            HStack(spacing: 8) {
                StepperCircle(symbol: "minus", enabled: item.quantity > 0) { mutate(KitchenLogic.markUsed) }
                    .accessibilityLabel("Mark used")
                StepperCircle(symbol: "plus", enabled: true) { mutate(KitchenLogic.markRestocked) }
                    .accessibilityLabel("Mark restocked")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private var stockLine: String {
        let unit = (item.unit ?? "").trimmingCharacters(in: .whitespaces)
        let qty = KitchenFormat.quantity(item.quantity)
        return unit.isEmpty ? "\(qty) in stock" : "\(qty) \(unit) in stock"
    }

    private var accessibilityLabel: String {
        let name = item.name ?? "Item"
        switch status {
        case .out:     return "\(name), out of stock"
        case .low:     return "\(name), running low, \(stockLine)"
        case .inStock: return "\(name), \(stockLine)"
        }
    }

    private func mutate(_ action: @MainActor (PantryItem) -> Void) {
        action(item)
        try? context.save()   // CR-01: explicit save
        Haptics.selection()
    }
}

// MARK: - Stock badge

/// "LOW" / "OUT" pill — text + SF Symbol + semantic tint (never colour alone).
/// Uses the existing `orange` / `negative` adaptive twins; no new tokens (DesignTokens is READ ONLY).
struct StockBadge: View {
    let status: StockStatus

    var body: some View {
        switch status {
        case .inStock:
            EmptyView()
        case .low:
            badge(text: "LOW", symbol: "exclamationmark.triangle.fill", color: DesignTokens.orange)
        case .out:
            badge(text: "OUT", symbol: "minus.circle.fill", color: DesignTokens.negative)
        }
    }

    @ViewBuilder
    private func badge(text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .kerning(0.4)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
        .accessibilityHidden(true)   // the row's combined label already states the state
    }
}

// MARK: - Circular neumorphic stepper

/// 44pt circular −/+ puck. Raised when enabled, recessed + dimmed when not (the mockup's
/// disabled "−" at quantity 0).
struct StepperCircle: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: { if enabled { action() } }) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? DesignTokens.label : DesignTokens.label3)
                .frame(width: 44, height: 44)
                .neuSurface(enabled ? .raised : .recessed, radius: 22, padding: nil, isInteractive: enabled)
                .fixedSize()   // stay a 44pt circle instead of stretching to fill the row HStack
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Quantity formatting

/// Shared quantity formatting for the kitchen surface: drops a trailing ".0" so a whole number
/// reads "2", while fractional stock still reads "0.5".
enum KitchenFormat {
    static func quantity(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e9 {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: "0$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
}
