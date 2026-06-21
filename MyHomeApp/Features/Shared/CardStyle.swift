import SwiftUI

/// The app's standard "card" surface — a secondary-background rounded rectangle with a subtle
/// shadow. Extracts the pattern previously inlined across the Overview/Budgets cards so every
/// surface stays visually consistent with the refreshed design.
struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat = 16
    /// Inner padding applied before the background. Pass `nil` to skip (caller pads itself).
    var padding: CGFloat? = 16

    func body(content: Content) -> some View {
        Group {
            if let padding {
                content.padding(padding)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

extension View {
    /// Wraps the view in the standard card surface (padding + secondary bg + rounded + shadow).
    ///
    /// - Deprecated: Use `.neuSurface(.raised)` instead. `CardStyle` is removed in Phase 14.
    @available(*, deprecated, renamed: "neuSurface")
    func cardStyle(cornerRadius: CGFloat = 16, padding: CGFloat? = 16) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}
