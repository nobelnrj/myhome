import SwiftUI
import Charts
import SwiftData

// MARK: - NetWorthCard

/// Overview card: net-worth total + 4-class allocation donut + legend + trend chart.
///
/// Layout (neumorphic v2 — mirrors SpendDonutCard): Section header + tappable card wrapping:
///   - NeuCircularWell (236) + NeuDonutRing (198/22) + NeuCircularPuck (132) centre readout
///   - Legend rows (7pt dot · label · amount) with hairline dividers
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
        VStack(alignment: .leading, spacing: 16) {
            // Circular well + rounded-cap allocation ring + raised centre puck —
            // same chart language as the "Where it's going" donut (SpendDonutCard).
            NeuCircularWell(size: 236) {
                NeuDonutRing(segments: segments, size: 198, lineWidth: 22)
                NeuCircularPuck(size: 132) {
                    donutCenter(total: breakdown.totalNetWorth)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            // Legend rows with hairline dividers (SpendDonutCard row recipe)
            legend(breakdown: breakdown)

            // Trend chart below the donut+legend row — only once there are ≥2 days
            // of history. A single snapshot (e.g. the day the first holding is added)
            // draws a blank plot with no line, so the whole trend row is hidden until
            // a real trend exists.
            if snapshots.count >= 2 {
                NetWorthTrendChart(snapshots: snapshots)
            }
        }
        .neuSurface(.floating, radius: 26, padding: 18)
    }

    // MARK: - Donut center overlay

    @ViewBuilder
    private func donutCenter(total: Decimal) -> some View {
        VStack(spacing: 3) {
            Text("NET WORTH")
                .font(.system(size: 11, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(DesignTokens.label2)
            Text(total.formattedINRWhole())
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DesignTokens.label)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: 108)
                // Accessibility: expose the full formatted value for VoiceOver
                .accessibilityValue(total.formattedINR())
        }
    }

    // MARK: - Legend

    @ViewBuilder
    private func legend(breakdown: NetWorthBreakdown) -> some View {
        let rows: [(label: String, color: Color, value: Decimal)] = [
            ("Mutual Funds", DesignTokens.catSubscriptions, breakdown.mfValue),
            ("Stocks",       DesignTokens.positive,         breakdown.stockValue),
            ("NPS",          DesignTokens.orange,           breakdown.npsValue),
            ("Cash",         DesignTokens.catAuto,          breakdown.cashValue),
        ]
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                legendRow(label: row.label, color: row.color, value: row.value)
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(DesignTokens.separatorHairline)
                        .frame(height: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func legendRow(label: String, color: Color, value: Decimal) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.label)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value.formattedINRWhole())
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.label)
                .monospacedDigit()
        }
        .padding(.vertical, 12)
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
            DonutSegment(id: "mf",    label: "Mutual Funds", value: toDouble(mf),    color: DesignTokens.catSubscriptions),
            DonutSegment(id: "stock", label: "Stocks",       value: toDouble(stock), color: DesignTokens.positive),
            DonutSegment(id: "nps",   label: "NPS",          value: toDouble(nps),   color: DesignTokens.orange),
            DonutSegment(id: "cash",  label: "Cash",         value: toDouble(cash),  color: DesignTokens.catAuto),
        ]
    }
}
