import SwiftUI
import Charts
import SwiftData

// MARK: - NetWorthCard

/// Overview card: net-worth total + 4-class allocation donut + legend + trend chart.
///
/// Layout: Section header + tappable card wrapping:
///   - HStack: DonutChart (132 pt) left | legend VStack right
///   - NetWorthTrendChart below (140 pt height)
///
/// Tapping the card navigates to AssetsListView (mirrors WhereItsGoingCard pattern).
///
/// Safety guarantees:
///   - Cash segment is clamped max(cashValue, 0) to prevent SectorMark crash (T-11-12)
///   - All Decimal→Double conversions go through NSDecimalNumber (Pitfall B / T-11-13)
///   - True (possibly negative) totalNetWorth displayed in center and NOT clamped
struct NetWorthCard: View {

    let allAssets: [Asset]
    let allAccounts: [Account]
    let allExpenses: [Expense]
    let snapshots: [NetWorthSnapshot]

    var body: some View {
        let breakdown = NetWorthCalculator.breakdown(
            assets: allAssets,
            accounts: allAccounts,
            expenses: allExpenses
        )
        let segs = NetWorthCard.allocationSegments(
            mf: breakdown.mfValue,
            stock: breakdown.stockValue,
            nps: breakdown.npsValue,
            cash: breakdown.cashValue
        )

        NavigationLink(destination: AssetsListView()) {
            cardContent(breakdown: breakdown, segments: segs)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card content

    @ViewBuilder
    private func cardContent(breakdown: NetWorthBreakdown, segments: [DonutSegment]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                // Donut — .accessibilityHidden(true) is built into DonutChart
                DonutChart(segments: segments, size: 132) {
                    donutCenter(total: breakdown.totalNetWorth)
                }

                // Legend
                legend(breakdown: breakdown)
            }

            // Trend chart below the donut+legend row — only once there are ≥2 days
            // of history. A single snapshot (e.g. the day the first holding is added)
            // draws a blank plot with no line, so the whole trend row is hidden until
            // a real trend exists.
            if snapshots.count >= 2 {
                NetWorthTrendChart(snapshots: snapshots)
            }
        }
        .cardStyle(cornerRadius: 16, padding: 18)
    }

    // MARK: - Donut center overlay

    @ViewBuilder
    private func donutCenter(total: Decimal) -> some View {
        VStack(spacing: 0) {
            Text("NET WORTH")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(total.formattedINRWhole())
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // Accessibility: expose the full formatted value for VoiceOver
                .accessibilityValue(total.formattedINR())
        }
    }

    // MARK: - Legend

    @ViewBuilder
    private func legend(breakdown: NetWorthBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            legendRow(label: "Mutual Funds", color: Color(.systemBlue),  value: breakdown.mfValue)
            legendRow(label: "Stocks",       color: Color(.systemGreen), value: breakdown.stockValue)
            legendRow(label: "NPS",          color: Color(.systemOrange), value: breakdown.npsValue)
            legendRow(label: "Cash",         color: Color(.systemTeal),  value: breakdown.cashValue)
        }
    }

    @ViewBuilder
    private func legendRow(label: String, color: Color, value: Decimal) -> some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(value.formattedINRWhole())
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Allocation segment builder (testable static func)

    /// Build 4 `DonutSegment`s from the four Decimal sub-totals.
    ///
    /// The cash segment value is `max(cashValue, 0)` — negative cash (CC debt > savings)
    /// would crash `SectorMark`; the true total is displayed via a separate Text overlay (T-11-12).
    /// All other segments are also clamped for safety (a bug upstream that produces negative mf/stock/nps
    /// should not crash the chart).
    ///
    /// Decimal→Double via `NSDecimalNumber(decimal:).doubleValue` — never `Double(truncating:)` (T-11-13).
    static func allocationSegments(mf: Decimal, stock: Decimal, nps: Decimal, cash: Decimal) -> [DonutSegment] {
        func toDouble(_ v: Decimal) -> Double {
            NSDecimalNumber(decimal: max(v, 0)).doubleValue
        }
        return [
            DonutSegment(id: "mf",    label: "Mutual Funds", value: toDouble(mf),    color: Color(.systemBlue)),
            DonutSegment(id: "stock", label: "Stocks",       value: toDouble(stock), color: Color(.systemGreen)),
            DonutSegment(id: "nps",   label: "NPS",          value: toDouble(nps),   color: Color(.systemOrange)),
            DonutSegment(id: "cash",  label: "Cash",         value: toDouble(cash),  color: Color(.systemTeal)),
        ]
    }
}
