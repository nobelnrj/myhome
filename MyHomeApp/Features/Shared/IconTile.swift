import SwiftUI

/// Rounded-square category tile — a colored background with a white SF Symbol centered.
/// Mirrors the design's `IconTile`. Presentation-only; used in expense rows, budget cards,
/// the Overview budget glance, settings rows, and the review banner.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30
    var cornerRadius: CGFloat? = nil

    init(symbol: String, color: Color, size: CGFloat = 30, cornerRadius: CGFloat? = nil) {
        self.symbol = symbol
        self.color = color
        self.size = size
        self.cornerRadius = cornerRadius
    }

    /// Convenience: tile styled from a `Category` (color + symbol derived via `CategoryStyle`).
    init(category: Category?, size: CGFloat = 30, cornerRadius: CGFloat? = nil) {
        self.symbol = CategoryStyle.symbol(for: category)
        self.color = CategoryStyle.color(for: category)
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.28, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}
