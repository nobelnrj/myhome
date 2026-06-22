import SwiftUI

/// Horizontal stacked spend bar — proportional colored segments. Mirrors the design's
/// `StackBar`, used in the Overview hero. Presentation-only.
struct StackBar: View {
    /// (value, color) pairs; zero / negative values are ignored.
    let segments: [(value: Double, color: Color)]
    var height: CGFloat = 12
    var spacing: CGFloat = 2

    var body: some View {
        let positives = segments.filter { $0.value > 0 }
        let total = positives.reduce(0) { $0 + $1.value }
        GeometryReader { geo in
            if total <= 0 {
                RoundedRectangle(cornerRadius: 3)
                    .fill(DesignTokens.fillRecessed)
            } else {
                let gaps = CGFloat(max(positives.count - 1, 0)) * spacing
                let usable = max(geo.size.width - gaps, 0)
                HStack(spacing: spacing) {
                    ForEach(Array(positives.enumerated()), id: \.offset) { _, seg in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(seg.color)
                            .frame(width: usable * CGFloat(seg.value / total))
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityHidden(true)
    }
}
