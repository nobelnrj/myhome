import SwiftUI

/// Overview hero card — NET CASH FLOW: income vs spent split (D-04, OVR-01).
///
/// Layout (UI-SPEC Screen 1 hero):
/// - `.neuSurface(.floating)` outer card (hero tier)
/// - "NET CASH FLOW" header + status chip (right-aligned)
/// - Income tile + Spent tile: each `.neuSurface(.recessed, radius: DesignTokens.radiusInner)`
/// - `RollingMoneyText` for the net total (positive color when net >= 0, negative when net < 0)
/// - Flat budget progress strip (track `fillRecessed2`, fill `positive`/`negative`)
///
/// Dumb/value-driven: consumes pre-computed income + spent from OverviewMonthContent. No @Query.
///
/// Threat mitigations:
/// - T-04-07: selectedTab assignment is a plain integer @Binding; no URL parsing.
struct SpendBudgetCard: View {

    /// Total income this month (sum of |expense.amount| where amount < 0 and not a transfer).
    let income: Decimal
    /// Total spend this month (sum of expense.amount where amount > 0, self-transfer-excluded).
    let spent: Decimal
    /// Total monthly budget across all budgeted categories (0 when no budget is set).
    let totalBudget: Decimal
    @Binding var selectedTab: Int

    /// Live frames of the orb + the two tiles (in the "heroFlow" space), used to animate
    /// particles streaming from the orb into the INCOME / SPENT boxes.
    @State private var anchors: [String: CGRect] = [:]

    // MARK: - Computed

    private var net: Decimal { income - spent }

    /// Fraction of budget consumed (nil when no budget set; guarded against divide-by-zero).
    private var fractionUsed: Double? {
        guard totalBudget > 0 else { return nil }
        return NSDecimalNumber(decimal: min(spent / totalBudget, Decimal(2))).doubleValue
    }

    private var netIsPositive: Bool { net >= 0 }

    private var statusChipLabel: String { netIsPositive ? "Positive" : "Negative" }
    private var statusColor: Color { netIsPositive ? DesignTokens.positive : DesignTokens.negative }

    /// Budget-health colour for the ring (independent of net sign): green under budget,
    /// orange near the limit, red once over.
    private var ringColor: Color {
        if spent > totalBudget { return DesignTokens.negative }
        if let f = fractionUsed, f >= 0.85 { return DesignTokens.orange }
        return DesignTokens.positive
    }

    private var percentUsedLabel: String {
        guard let f = fractionUsed else { return "" }
        return f >= 1.0 ? "100%+ used" : "\(Int(f * 100))% used"
    }

    /// Fraction of the orb coloured as income (green); the rest is expense (red).
    /// Falls back to a half-and-half split when there's no activity yet.
    private var incomeShare: Double {
        let i = NSDecimalNumber(decimal: max(income, 0)).doubleValue
        let s = NSDecimalNumber(decimal: max(spent, 0)).doubleValue
        let total = i + s
        return total > 0 ? i / total : 0.5
    }

    /// Expense share of cash flow as a percent — the red portion of the orb. The single
    /// centred readout (user asked for just the spend percentage, nothing else).
    private var spendPct: Int { Int(((1 - incomeShare) * 100).rounded()) }

    // MARK: - Body

    var body: some View {
        ZStack {
            heroContent

            // Particle stream: green dots flow from the orb into INCOME, red into SPENT.
            if let orb = anchors["orb"], let inc = anchors["income"], let exp = anchors["spent"] {
                MoneyFlowCanvas(
                    source: CGPoint(x: orb.midX, y: orb.maxY - orb.height * 0.16),
                    incomeTarget: CGPoint(x: inc.midX, y: inc.minY + 8),
                    expenseTarget: CGPoint(x: exp.midX, y: exp.minY + 8),
                    incomeColor: DesignTokens.positive,
                    expenseColor: DesignTokens.negative
                )
                .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "heroFlow")
        .onPreferenceChange(HeroAnchorKey.self) { anchors = $0 }
        .neuSurface(.floating, padding: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacing16) {
            // Header row: "NET CASH FLOW" + status chip
            HStack {
                Text("NET CASH FLOW")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(DesignTokens.label2)
                Spacer()
                // Status chip
                Text(statusChipLabel)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(statusColor.opacity(0.40), lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }

            // Two-tone WHOOP orb: green particles = income share, red = expense share (always a
            // full sphere, no gap). Centre frames the net outcome as SAVED / OVERSPENT (no minus).
            GlowParticleRing(
                incomeShare: incomeShare,
                incomeColor: DesignTokens.positive,
                expenseColor: DesignTokens.negative,
                size: 208
            ) {
                VStack(spacing: 2) {
                    Text("\(spendPct)%")
                        .font(.system(size: 44, weight: .bold, design: .default))
                        .foregroundStyle(DesignTokens.label)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .animation(.smooth(duration: 0.6), value: spendPct)
                        .frame(width: 140)
                    Text("spent")
                        .font(.system(size: 12.5, weight: .medium))
                        .tracking(0.5)
                        .foregroundStyle(DesignTokens.label2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .heroAnchor("orb")

            // Income + Spent split tiles
            HStack(spacing: DesignTokens.spacing12) {
                splitTile(label: "INCOME", amount: income, color: DesignTokens.positive)
                    .heroAnchor("income")
                splitTile(label: "SPENT", amount: spent, color: DesignTokens.negative)
                    .heroAnchor("spent")
            }

            // Budget context (secondary): a thin strip when a budget exists, else a CTA.
            if let fraction = fractionUsed {
                budgetStrip(fraction: fraction)
            } else {
                Button {
                    selectedTab = 2
                } label: {
                    Text("Set a budget to track your spending →")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .tint(DesignTokens.accent)
            }
        }
    }

    // MARK: - Split tile

    @ViewBuilder
    private func splitTile(label: String, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(DesignTokens.label2)
            // Stat pattern (not RollingMoneyText — Pitfall 5). Solid system face to match
            // the heavier hero numeral above.
            Text(amount.formattedINRWhole())
                .font(.system(size: 20, weight: .semibold, design: .default))
                .foregroundStyle(color)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.78), value: amount)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuSurface(.recessed, radius: DesignTokens.radiusInner)
    }

    // MARK: - Budget strip (secondary context)

    @ViewBuilder
    private func budgetStrip(fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DesignTokens.fillRecessed2)
                    Capsule()
                        .fill(ringColor)
                        .frame(width: max(0, min(CGFloat(fraction), 1)) * geo.size.width)
                }
            }
            .frame(height: 7)

            HStack {
                Text("of \(totalBudget.formattedINRWhole()) budget")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.label3)
                Spacer()
                Text(percentUsedLabel)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.label3)
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        let netStr = abs(net).formattedINR()
        let direction = netIsPositive ? "positive" : "negative"
        return "Net cash flow \(netStr) \(direction). Income \(income.formattedINR()), spent \(spent.formattedINR())."
    }
}

// MARK: - Money flow overlay (dots stream from the orb into the boxes)

/// Captures named child frames in the "heroFlow" coordinate space.
private struct HeroAnchorKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private extension View {
    /// Publishes this view's frame (in the "heroFlow" space) under `id` for the flow overlay.
    func heroAnchor(_ id: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: HeroAnchorKey.self, value: [id: proxy.frame(in: .named("heroFlow"))])
            }
        )
    }
}

/// Continuously streams small glowing dots from `source` (the orb) down into the two target
/// boxes — green toward income, red toward spend — along a gentle curve, fading in and out.
private struct MoneyFlowCanvas: View {
    let source: CGPoint
    let incomeTarget: CGPoint
    let expenseTarget: CGPoint
    let incomeColor: Color
    let expenseColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Streamer { let lane: Int; let phase, curve, speed: Double; let spread, dot: CGFloat }

    private let streamers: [Streamer] = {
        var rng = SeededRNG2(seed: 0xBEEF)
        return (0..<28).map { i in
            Streamer(
                lane: i % 2,
                phase: Double.random(in: 0...1, using: &rng),
                curve: Double.random(in: -1...1, using: &rng),
                speed: Double.random(in: 0.16...0.28, using: &rng),
                spread: CGFloat.random(in: -16...16, using: &rng),
                dot: CGFloat.random(in: 1.3...2.6, using: &rng)
            )
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, _ in
                for s in streamers {
                    let frac = reduceMotion ? 0.5 : (t * s.speed + s.phase).truncatingRemainder(dividingBy: 1)
                    let target = s.lane == 0 ? incomeTarget : expenseTarget
                    let col = s.lane == 0 ? incomeColor : expenseColor
                    let src = CGPoint(x: source.x + s.spread, y: source.y)
                    let mid = CGPoint(x: (src.x + target.x) / 2, y: (src.y + target.y) / 2)
                    let ctrl = CGPoint(x: mid.x + CGFloat(s.curve) * 34, y: mid.y - 10)
                    let pt = quadBezier(src, ctrl, target, frac)

                    let op = sin(frac * .pi) * 0.9   // fade in near the orb, out at the box
                    let halo = s.dot * 2.6
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: pt.x - halo, y: pt.y - halo, width: halo * 2, height: halo * 2)),
                        with: .color(col.opacity(op * 0.18))
                    )
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: pt.x - s.dot, y: pt.y - s.dot, width: s.dot * 2, height: s.dot * 2)),
                        with: .color(col.opacity(op))
                    )
                }
            }
        }
    }

    private func quadBezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ tt: Double) -> CGPoint {
        let u = 1 - tt
        let x = u * u * Double(p0.x) + 2 * u * tt * Double(p1.x) + tt * tt * Double(p2.x)
        let y = u * u * Double(p0.y) + 2 * u * tt * Double(p1.y) + tt * tt * Double(p2.y)
        return CGPoint(x: x, y: y)
    }
}

/// Local deterministic RNG (mirrors the one in DonutChart.swift, which is fileprivate there).
private struct SeededRNG2: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - Preview

#Preview("Positive net — has budget") {
    @Previewable @State var tab = 0
    SpendBudgetCard(
        income: Decimal(45000),
        spent: Decimal(32000),
        totalBudget: Decimal(40000),
        selectedTab: $tab
    )
    .padding()
    .background(DesignTokens.bgCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Negative net — no budget") {
    @Previewable @State var tab = 0
    SpendBudgetCard(
        income: Decimal(20000),
        spent: Decimal(35000),
        totalBudget: Decimal(0),
        selectedTab: $tab
    )
    .padding()
    .background(DesignTokens.bgCanvas)
    .preferredColorScheme(.dark)
}
