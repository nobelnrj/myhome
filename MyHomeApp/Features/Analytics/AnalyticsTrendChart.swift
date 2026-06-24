import SwiftUI
import Charts

// MARK: - AnalyticsTrendChart

/// Area + line trend chart for the Analytics screen (ANL-03).
///
/// Accepts pre-aggregated `[SpendBucket]` from `SpendSummary.trendBuckets`.
/// PITFALL A GUARD: this view NEVER receives raw expenses — only value types from the aggregator.
/// The caller (AnalyticsView) computes buckets via AnalyticsAggregator.summarize at the top of
/// body, then passes them in. Chart DSL receives only pre-computed Doubles (Pitfall B guard:
/// Decimal→Double conversion happened once at the aggregation boundary).
///
/// For `.year` range the caller has already filtered out future months
/// (AnalyticsAggregator step d — no future zero-bars / ANL-03 success criterion 3).
struct AnalyticsTrendChart: View {

    // MARK: - Input

    /// Pre-aggregated spend buckets for the selected range. Already IST-bucketed and (for .year)
    /// filtered to months <= current month.
    let buckets: [SpendBucket]

    // MARK: - Body

    var body: some View {
        if buckets.isEmpty || buckets.allSatisfy({ $0.spent == 0 }) {
            // Calm empty state — no crash on zero data (ANL-03 empty guard)
            Text("No spend data for this period.")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.label2)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 200)
        } else {
            Chart(buckets) { point in
                // Area fill with vertical gradient (ANL-03)
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Spend", point.spent)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            DesignTokens.accent.opacity(0.35),
                            DesignTokens.accent.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                // Line stroke in accent (ANL-03)
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Spend", point.spent)
                )
                .foregroundStyle(DesignTokens.accent)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                        .foregroundStyle(DesignTokens.separatorHairline)
                    if let d = value.as(Double.self) {
                        // Pitfall B: Decimal used only for axis label formatting; Double already at
                        // chart DSL boundary. NSDecimalNumber lossy-from-Double is acceptable here
                        // because this is display-only axis text, not stored money.
                        AxisValueLabel {
                            Text(Decimal(d).formattedINRCompact())
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.label3)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                        .foregroundStyle(DesignTokens.separatorHairline)
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(xLabel(for: date))
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.label3)
                        }
                    }
                }
            }
            .frame(height: 200)
            .neonGlow(DesignTokens.accent, radius: 4, intensity: 0.4)
        }
    }

    // MARK: - Helpers

    private func xLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        // Auto-size labels based on bucket count: few buckets → day label; many → abbreviated
        if buckets.count <= 7 {
            formatter.dateFormat = "EEE"
        } else if buckets.count <= 12 {
            formatter.dateFormat = "MMM"
        } else {
            formatter.dateFormat = "d"
        }
        return formatter.string(from: date)
    }
}
