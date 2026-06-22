import SwiftUI

/// Custom always-visible 3-column decimal keypad.
///
/// Replaces the system keyboard for amount entry (Pitfall 6 — no .keyboardType(.decimalPad)).
/// The keypad is always part of the layout, so there is no keyboard animation or avoidance thrash.
///
/// Input rules enforced:
/// - Only one decimal point allowed
/// - Maximum 2 decimal places (paise optional, D-04)
/// - Backspace removes the last character
struct DecimalKeypadView: View {

    @Binding var displayString: String

    private let keys: [[String]] = [
        ["7", "8", "9"],
        ["4", "5", "6"],
        ["1", "2", "3"],
        [".", "0", "⌫"],
    ]

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible()), count: 3),
            spacing: 8
        ) {
            ForEach(keys.flatMap { $0 }, id: \.self) { key in
                Button(action: { handleKey(key) }) {
                    Group {
                        if key == "⌫" {
                            Image(systemName: "delete.backward")
                                .font(.title2)
                                .fontWeight(.medium)
                        } else {
                            Text(key)
                                .font(.title2)
                                .fontWeight(.medium)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(DesignTokens.surfaceElevatedControl)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(keyAccessibilityLabel(key))
            }
        }
    }

    // MARK: - Key handling

    private func handleKey(_ key: String) {
        switch key {
        case "⌫":
            if !displayString.isEmpty {
                displayString.removeLast()
            }
        case ".":
            // Only one decimal point allowed
            if !displayString.contains(".") {
                // If string is empty, prefix with "0"
                if displayString.isEmpty {
                    displayString = "0."
                } else {
                    displayString += "."
                }
            }
        default:
            // Prevent more than 2 decimal places (D-04 paise-optional)
            if let dotIndex = displayString.firstIndex(of: ".") {
                let afterDot = displayString.index(after: dotIndex)
                let decimalCount = displayString.distance(from: afterDot, to: displayString.endIndex)
                if decimalCount >= 2 { return }
            }
            displayString += key
        }
    }

    // MARK: - Accessibility

    private func keyAccessibilityLabel(_ key: String) -> String {
        switch key {
        case "⌫": return "Delete"
        case ".": return "Decimal point"
        default:  return key
        }
    }
}
