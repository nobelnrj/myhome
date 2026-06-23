import SwiftUI
import Charts

// MARK: - NetWorthTrendChart

/// AreaMark + LineMark trend chart over daily NetWorthSnapshot history.
///
/// Mirrors SpendOverTimeChart pattern:
///   - Decimal→Double conversion at the boundary (NSDecimalNumber) — never raw Decimal in .value() (T-11-13)
///   - chartYAxis: compact INR labels (formattedINRCompact)
///   - chartXAxis: abbreviated month labels
///   - frame(height: 140) — compact, inline-card sizing (per UI-SPEC Surface 6)
///   - Empty state: "No history yet." at frame height 80
///   - .accessibilityLabel("Net worth trend chart")
struct NetWorthTrendChart: View {

    let snapshots: [NetWorthSnapshot]

    var body: some View {
        // A trend needs at least two points; a single snapshot renders a blank
        // plot (no line). Show the empty state until there are ≥2 data points.
        if snapshots.count < 2 {
            emptyStateView
        } else {
            chartView
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartView: some View {
        // Pitfall B guard: convert Decimal→Double at the boundary, outside the Chart DSL
        let points: [(date: Date, value: Double)] = snapshots.map { snap in
            (snap.date, NSDecimalNumber(decimal: snap.totalNetWorth).doubleValue)
        }

        Chart(points, id: \.date) { point in
            // Neon area+line — same emitted-light vibe as the Overview orb and spend trend.
            AreaMark(
                x: .value("Date", point.date),
                y: .value("Net Worth", point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(LinearGradient(
                colors: [DesignTokens.positive.opacity(0.35), DesignTokens.positive.opacity(0.02)],
                startPoint: .top, endPoint: .bottom))

            LineMark(
                x: .value("Date", point.date),
                y: .value("Net Worth", point.value)
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            .foregroundStyle(DesignTokens.positive.opacity(0.18))   // glow underlay

            LineMark(
                x: .value("Date", point.date),
                y: .value("Net Worth", point.value)
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .foregroundStyle(DesignTokens.positive)                 // crisp neon line
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(Decimal(d).formattedINRCompact())
                            .font(.caption)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(.caption)
            }
        }
        .frame(height: 140)
        .accessibilityLabel("Net worth trend chart")
        .accessibilityHidden(true)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyStateView: some View {
        Text("No history yet.")
            .font(.subheadline)
            .foregroundStyle(DesignTokens.label2)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 80)
    }
}
