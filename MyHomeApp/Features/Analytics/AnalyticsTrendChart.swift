import SwiftUI
import Charts

// MARK: - AnalyticsTrendChart

/// Glowing trend chart for the Analytics screen (ANL-03) — neumorphic v2, Screen 5.
///
/// The plot sits inside a recessed "plot inset" (radius 18, well shadow). The spending line
/// is a 3.5pt smooth curve with a yellow→red gradient and a warm glow; the area under it
/// fades to transparent. The peak bucket gets a red marker dot + halo and a floating value
/// pill. Date labels render below the inset, outside the well.
///
/// Accepts pre-aggregated `[SpendBucket]` from `SpendSummary.trendBuckets`.
/// PITFALL A GUARD: this view NEVER receives raw expenses — only value types from the aggregator.
/// Chart DSL receives only pre-computed Doubles (Pitfall B guard: Decimal→Double conversion
/// happened once at the aggregation boundary).
///
/// For `.year` range the caller has already filtered out future months
/// (AnalyticsAggregator step d — no future zero-bars / ANL-03 success criterion 3).
struct AnalyticsTrendChart: View {

    // MARK: - Input

    /// Pre-aggregated spend buckets for the selected range. Already IST-bucketed and (for .year)
    /// filtered to months <= current month.
    let buckets: [SpendBucket]

    // MARK: - Derived

    /// Display buckets: future days/months carry no signal, so the line stops at "now"
    /// instead of dragging a flat zero-tail across the rest of the period (the aggregator
    /// already does this for .year; mirror it for week/month here, display-only).
    private var visibleBuckets: [SpendBucket] {
        let now = Date()
        let filtered = buckets.filter { $0.date <= now }
        return filtered.isEmpty ? buckets : filtered
    }

    /// Peak bucket — gets the marker dot + value pill. First occurrence wins on ties.
    private var peak: SpendBucket? {
        visibleBuckets.max(by: { $0.spent < $1.spent })
    }

    // MARK: - Body

    var body: some View {
        if buckets.isEmpty || buckets.allSatisfy({ $0.spent == 0 }) {
            // Calm empty state — no crash on zero data (ANL-03 empty guard)
            Text("No spend data for this period.")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.label2)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 180)
        } else {
            VStack(spacing: 8) {
                // Recessed plot inset holding the glowing line
                chart
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(DesignTokens.fillRecessed)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(
                                        LinearGradient(colors: [.black.opacity(0.45), .white.opacity(0.03)],
                                                       startPoint: .top, endPoint: .bottom),
                                        lineWidth: 1.5
                                    )
                                    .blur(radius: 1)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            )
                    )

                // Date labels below the inset
                axisLabels
            }
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            ForEach(visibleBuckets) { point in
                // Area fill fading to transparent under the line
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Spend", point.spent)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#FFB43C").opacity(0.26), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                // Smooth spending line — yellow→red gradient, 3.5pt
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Spend", point.spent)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [DesignTokens.accent, DesignTokens.negative],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }

            // Peak marker: red dot + halo + floating value pill
            if let peak {
                PointMark(
                    x: .value("Date", peak.date),
                    y: .value("Spend", peak.spent)
                )
                .symbol {
                    ZStack {
                        Circle()
                            .fill(DesignTokens.negative.opacity(0.30))
                            .frame(width: 18, height: 18)
                        Circle()
                            .fill(DesignTokens.negative)
                            .frame(width: 9, height: 9)
                    }
                }
                .annotation(position: .top, spacing: 6) {
                    // Pitfall B: display-only conversion for the pill label.
                    Text(Decimal(peak.spent).formattedINRWhole())
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.label)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(DesignTokens.surfaceElevatedControl)
                                .shadow(color: .black.opacity(0.5), radius: 5, y: 3)
                        )
                }
            }
        }
        // Faint horizontal gridlines only — no axis labels inside the inset
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.045))
            }
        }
        .chartXAxis(.hidden)
        .frame(height: 150)
        // Warm glow under the line (the area fades to clear, so the line carries it)
        .shadow(color: Color(hex: "#FFB43C").opacity(0.30), radius: 5, y: 5)
    }

    // MARK: - Axis labels (outside the inset)

    /// Up to 5 evenly-spaced bucket labels rendered below the plot inset.
    private var axisLabels: some View {
        let indices = labelIndices
        return HStack {
            ForEach(indices, id: \.self) { i in
                Text(xLabel(for: visibleBuckets[i].date))
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.label3)
                if i != indices.last { Spacer() }
            }
        }
        .padding(.horizontal, 10)
    }

    private var labelIndices: [Int] {
        let count = visibleBuckets.count
        guard count > 1 else { return count == 1 ? [0] : [] }
        let target = min(5, count)
        return (0..<target).map { Int(round(Double($0) * Double(count - 1) / Double(target - 1))) }
    }

    private func xLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        // Format by bucket *granularity* (spacing), not count — a month range trimmed to
        // 10 elapsed days must still label days, not month names.
        if bucketSpacingDays >= 25 {
            formatter.setLocalizedDateFormatFromTemplate("MMM")       // monthly buckets (year)
        } else if visibleBuckets.count <= 7 {
            formatter.setLocalizedDateFormatFromTemplate("EEE")       // daily buckets (week)
        } else {
            formatter.setLocalizedDateFormatFromTemplate("dMMM")      // daily buckets (month)
        }
        return formatter.string(from: date)
    }

    /// Days between the first two buckets (1 for daily, ~30 for monthly granularity).
    private var bucketSpacingDays: Double {
        guard visibleBuckets.count >= 2 else { return 1 }
        return visibleBuckets[1].date.timeIntervalSince(visibleBuckets[0].date) / 86_400
    }
}
