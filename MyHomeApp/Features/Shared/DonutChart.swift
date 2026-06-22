import SwiftUI
import Charts

/// A single donut segment.
struct DonutSegment: Identifiable {
    let id: String
    let label: String
    let value: Double
    let color: Color
}

/// Native donut ring (Swift Charts `SectorMark`) with an optional center overlay.
///
/// Replaces the design's hand-rolled SVG donut with the platform-native chart. Used by the
/// Overview "Where it's going" card and the Budgets summary ring (where the remainder segment
/// is passed as a track-colored slice).
struct DonutChart<Center: View>: View {
    let segments: [DonutSegment]
    var innerRatio: CGFloat = 0.62
    var size: CGFloat = 132
    @ViewBuilder var center: () -> Center

    var body: some View {
        Chart(segments) { seg in
            SectorMark(
                angle: .value(seg.label, seg.value),
                innerRadius: .ratio(innerRatio),
                angularInset: 1.5
            )
            .cornerRadius(5)
            // WHOOP-style depth: each segment fades from its full colour to a darker shade.
            .foregroundStyle(seg.color.gradient)
        }
        .chartLegend(.hidden)
        .frame(width: size, height: size)
        .overlay { center() }
        .accessibilityHidden(true)
    }
}

extension DonutChart where Center == EmptyView {
    init(segments: [DonutSegment], innerRatio: CGFloat = 0.62, size: CGFloat = 132) {
        self.segments = segments
        self.innerRatio = innerRatio
        self.size = size
        self.center = { EmptyView() }
    }
}
