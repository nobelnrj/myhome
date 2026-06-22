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

// MARK: - ActivityRing (Apple / WHOOP-style animated ring)

/// A single animated progress ring: recessed track + angular-gradient stroke with a rounded
/// cap that sweeps up from zero on appear (spring), plus a leading-tip shadow near completion
/// that gives the iconic Apple-Activity "overlap" depth.
///
/// `progress` may exceed 1.0 (e.g. over budget); the arc clamps at a full turn while the
/// caller's colour conveys the overflow. Honors Reduce Motion (snaps instead of sweeping).
struct ActivityRing<Center: View>: View {
    /// Target fill 0…1+ (clamped to 1 for the arc).
    var progress: Double
    /// Gradient colours swept around the ring (low → high). Pass `[base.opacity(0.5), base]`
    /// for a single-hue brightness fade, or distinct colours for a spectrum.
    var colors: [Color]
    var size: CGFloat = 170
    var lineWidth: CGFloat = 16
    /// Show the bright glowing leading tip ("comet head") — the WHOOP luminous edge.
    var showTip: Bool = true
    /// Render the blurred bloom behind the arc for the luminous WHOOP glow.
    var glow: Bool = true
    /// Rounded end caps. Set `false` (butt caps) to avoid the small "dot" the round cap leaves
    /// at the arc start on thin rings.
    var roundCap: Bool = true
    @ViewBuilder var center: () -> Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: Double = 0

    private var clamped: Double { min(max(progress, 0), 1) }
    private var lineCap: CGLineCap { roundCap ? .round : .butt }

    private var ringGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: colors),
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360)
        )
    }

    private var radius: CGFloat { size / 2 - lineWidth / 2 }
    private var tipColor: Color { colors.last ?? .white }

    var body: some View {
        ZStack {
            Circle()
                .stroke(DesignTokens.fillRecessed2, lineWidth: lineWidth)

            // Luminous bloom — a blurred copy of the arc behind the crisp stroke.
            if glow {
                Circle()
                    .trim(from: 0, to: max(0.0001, animated))
                    .stroke(ringGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
                    .rotationEffect(.degrees(-90))
                    .blur(radius: lineWidth * 0.6)
                    .opacity(0.85)
            }

            // Crisp arc.
            Circle()
                .trim(from: 0, to: max(0.0001, animated))
                .stroke(ringGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
                .rotationEffect(.degrees(-90))

            // Bright glowing leading tip (comet head) at the arc's leading edge.
            if showTip && animated > 0.02 {
                Circle()
                    .fill(tipColor)
                    .frame(width: lineWidth * 0.92, height: lineWidth * 0.92)
                    .shadow(color: tipColor.opacity(0.9), radius: 9)
                    .shadow(color: tipColor.opacity(0.5), radius: 18)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(360 * animated))
            }

            center()
        }
        .frame(width: size, height: size)
        .onAppear { animate(to: clamped) }
        .onChange(of: progress) { _, _ in animate(to: clamped) }
        .accessibilityElement(children: .combine)
    }

    private func animate(to value: Double) {
        if reduceMotion {
            animated = value
        } else {
            withAnimation(.spring(response: 0.85, dampingFraction: 0.85)) {
                animated = value
            }
        }
    }
}

extension ActivityRing where Center == EmptyView {
    init(progress: Double, colors: [Color], size: CGFloat = 170, lineWidth: CGFloat = 16, showTip: Bool = true, glow: Bool = true) {
        self.progress = progress
        self.colors = colors
        self.size = size
        self.lineWidth = lineWidth
        self.showTip = showTip
        self.glow = glow
        self.center = { EmptyView() }
    }
}

// MARK: - GlowParticleRing (WHOOP-age-style particle sphere)

/// Deterministic xorshift RNG so the particle field is stable across redraws (no reshuffle).
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// A luminous two-tone particle sphere (à la WHOOP "Whoop Age"): a Canvas-drawn full orb whose
/// particles are split by `incomeShare` — `incomeColor` (green) for the income portion,
/// `expenseColor` (red) for the expense portion. Always a full sphere (no gap). The dots twinkle
/// and slowly drift (TimelineView) so the orb feels alive. Fades up on appear.
struct GlowParticleRing<Center: View>: View {
    /// Fraction of the orb coloured as income (0…1); the remainder is expense.
    var incomeShare: Double
    var incomeColor: Color
    var expenseColor: Color
    var size: CGFloat = 208
    @ViewBuilder var center: () -> Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: Double = 0

    private struct Particle { let angle, radialT, dot, opacity, phase: Double }

    private let particles: [Particle] = {
        var rng = SeededRNG(seed: 0xC0FFEE)
        return (0..<300).map { _ in
            Particle(
                angle: Double.random(in: 0...1, using: &rng),
                radialT: pow(Double.random(in: 0...1, using: &rng), 0.55), // bias toward the outer band
                dot: Double.random(in: 0.5...2.3, using: &rng),
                opacity: Double.random(in: 0.18...1.0, using: &rng),
                phase: Double.random(in: 0...(2 * .pi), using: &rng)
            )
        }
    }()

    /// Direction of peak brightness (top-right, like the WHOOP orb).
    private let brightDir = -Double.pi / 4

    var body: some View {
        let share = min(max(incomeShare, 0), 1)

        return ZStack {
            // Dark well so the centred readout stays legible over the glow.
            Circle()
                .fill(RadialGradient(
                    colors: [Color.black.opacity(0.55), .clear],
                    center: .center, startRadius: 0, endRadius: size * 0.30
                ))

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let drift = t * 0.05  // slow orbital drift (radians)

                Canvas { ctx, sz in
                    let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                    let outer = sz.width / 2 - 2
                    let well = outer * 0.30
                    let grow = max(animated, 0.0001)

                    for p in particles {
                        let ang = p.angle * 2 * .pi - .pi / 2 + drift
                        let r = well + (outer - well) * CGFloat(p.radialT)
                        let pt = CGPoint(x: c.x + r * CGFloat(cos(ang)), y: c.y + r * CGFloat(sin(ang)))

                        // Income (green) vs expense (red), split by share.
                        let col = p.angle < share ? incomeColor : expenseColor
                        // Aesthetic brightness gradient + a per-particle twinkle so the field feels alive.
                        let dir = 0.5 + 0.5 * (0.5 + 0.5 * cos(ang - brightDir))
                        let twinkle = reduceMotion ? 1.0 : (0.78 + 0.22 * sin(t * 1.7 + p.phase))
                        let op = p.opacity * dir * twinkle * Double(grow)
                        let dot = CGFloat(p.dot)

                        let halo = dot * 2.8
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: pt.x - halo, y: pt.y - halo, width: halo * 2, height: halo * 2)),
                            with: .color(col.opacity(op * 0.16))
                        )
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: pt.x - dot, y: pt.y - dot, width: dot * 2, height: dot * 2)),
                            with: .color(col.opacity(op))
                        )
                    }
                }
                .blur(radius: 0.4)
            }

            center()
        }
        .frame(width: size, height: size)
        .onAppear { animate() }
        .accessibilityElement(children: .combine)
    }

    private func animate() {
        if reduceMotion {
            animated = 1
        } else {
            animated = 0
            withAnimation(.easeOut(duration: 1.2)) { animated = 1 }
        }
    }
}

// MARK: - CategoryRings (concentric activity rings)

/// Concentric activity rings — one per item, largest item outermost. Each ring's fill is the
/// item's share of the whole, so the rings read as "how the spend splits" without a pie.
struct CategoryRings: View {
    /// Pre-sorted (largest first) colour + share-of-total (0…1) pairs. Up to 3 are drawn.
    let items: [(color: Color, fraction: Double)]
    var size: CGFloat = 150
    var lineWidth: CGFloat = 13
    var gap: CGFloat = 5

    var body: some View {
        ZStack {
            ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { index, item in
                ActivityRing(
                    progress: item.fraction,
                    colors: [item.color.opacity(0.5), item.color],
                    size: size - CGFloat(index) * (lineWidth * 2 + gap),
                    lineWidth: lineWidth,
                    showTip: false
                )
            }
        }
        .frame(width: size, height: size)
    }
}
