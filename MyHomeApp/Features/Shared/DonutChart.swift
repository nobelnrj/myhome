import SwiftUI
import Charts
import UIKit

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

    private var donut: some View {
        Chart(segments) { seg in
            // Borderless: no angular inset / corner radius, so segments butt into one seamless
            // ring (the older "gapped slices" look is gone).
            SectorMark(
                angle: .value(seg.label, seg.value),
                innerRadius: .ratio(innerRatio)
            )
            // WHOOP-style depth: each segment fades from its full colour to a darker shade.
            .foregroundStyle(seg.color.gradient)
        }
        .chartLegend(.hidden)
        .frame(width: size, height: size)
    }

    var body: some View {
        // Neon donut: a blurred copy behind the crisp ring blooms each segment in its OWN colour
        // (a single drop-shadow can't — it would muddy multi-colour rings). Matches the orb vibe.
        ZStack {
            donut
                .blur(radius: size * 0.045)
                .opacity(0.9)
            donut
        }
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

// MARK: - NeuDonutRing (v2 handoff donut — rounded caps, gaps, per-segment glow)

/// The v2 neumorphic donut: each segment is a rounded-cap arc with a ~4pt gap on either
/// side and a soft glow in its own colour (`drop-shadow(0 3px 9px color@0.45)` in the mock).
/// Cap allowance is baked into the trim range so round caps never overlap the gaps.
/// Sweeps in over ~500ms ease-out on appear; honors Reduce Motion (snaps visible).
struct NeuDonutRing: View {
    /// Segments in display order. `value`s are relative weights (fractions computed internally).
    let segments: [DonutSegment]
    var size: CGFloat = 198
    var lineWidth: CGFloat = 22

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: Double = 0

    private struct Arc: Identifiable {
        let id: String
        let color: Color
        let from: Double
        let to: Double
    }

    private var arcs: [Arc] {
        // Zero-value segments draw nothing (a zero slice must not occupy arc space).
        let visible = segments.filter { $0.value > 0 }
        let total = visible.reduce(0) { $0 + $1.value }
        guard total > 0 else { return [] }
        let radius = (size - lineWidth) / 2
        let circumference = 2 * .pi * Double(radius)
        let capFraction = Double(lineWidth / 2) / circumference   // round-cap overhang per end
        let gapFraction = 4.0 / circumference                     // ~4pt visual gap per side
        let inset = capFraction + gapFraction / 2

        // Every arc needs room for its two rounded caps + gaps plus a sliver of body.
        // A trim span narrower than the cap renders as a full-lineWidth dot that spills
        // far beyond its angular share — adjacent 1–2% slices then pile up and overlap
        // their neighbours. Instead, grant small segments this minimum span and shrink
        // the larger ones proportionally, so the ring stays gap-accurate and cap-safe.
        let minSpan = inset * 2 + 0.006
        var spans = visible.map { $0.value / total }
        if minSpan * Double(spans.count) < 1 {
            let deficit = spans.reduce(0) { $0 + max(0, minSpan - $1) }
            if deficit > 0 {
                let shrinkable = spans.reduce(0) { $0 + max(0, $1 - minSpan) }
                spans = spans.map { span in
                    span < minSpan
                        ? minSpan
                        : span - deficit * (span - minSpan) / shrinkable
                }
            }
        } else {
            // Degenerate: more segments than the ring can seat — equal spans.
            spans = Array(repeating: 1 / Double(spans.count), count: spans.count)
        }

        var cursor = 0.0
        return zip(visible, spans).map { seg, span in
            let from = cursor + inset
            let to = max(from, cursor + span - inset)
            cursor += span
            return Arc(id: seg.id, color: seg.color, from: from, to: to)
        }
    }

    var body: some View {
        ZStack {
            ForEach(arcs) { arc in
                Circle()
                    .trim(from: arc.from, to: max(arc.from, arc.from + (arc.to - arc.from) * reveal))
                    .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: arc.color.opacity(0.45), radius: 9, y: 3)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            if reduceMotion { reveal = 1 }
            else { withAnimation(.easeOut(duration: 0.5)) { reveal = 1 } }
        }
        .accessibilityHidden(true)
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

/// Linear-interpolation helpers for blending the two-tone rim colour by income share.
private extension Color {
    func rgba() -> (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    /// Linear blend from `c1` (t=0) toward `c2` (t=1).
    static func blend(_ c1: Color, _ c2: Color, t: Double) -> Color {
        let a = c1.rgba(), b = c2.rgba()
        let k = min(max(t, 0), 1)
        return Color(red: a.r + (b.r - a.r) * k,
                     green: a.g + (b.g - a.g) * k,
                     blue: a.b + (b.b - a.b) * k)
    }

    /// Push the colour toward white by `amount` — the bright inner rim highlight.
    func lightened(_ amount: Double = 0.45) -> Color {
        let c = rgba()
        return Color(red: c.r + (1 - c.r) * amount,
                     green: c.g + (1 - c.g) * amount,
                     blue: c.b + (1 - c.b) * amount)
    }
}

/// A luminous two-tone particle sphere (à la WHOOP "Whoop Age"). Ported from the `Whoop Age Orb`
/// dc-runtime sample into native SwiftUI Canvas:
/// - An organic **morphing blob** outline (16 control points, three layered sines + a breathing
///   scale, Catmull-Rom→Bézier smoothed) replaces the plain circle.
/// - Particles **flow outward** from the centre to the rim and respawn (size grows, opacity fades
///   in at the core / out at the rim) while the whole field **rotates 360°** + drifts + shimmers.
/// - The field is **clipped to the blob**, sat over a dark radial fill + centre vignette (keeps the
///   readout legible), and ringed by a **blurred glow rim + thin bright rim**.
///
/// Two-tone meaning is preserved: particles are split by `incomeShare` — `incomeColor` for the
/// income portion, `expenseColor` for the expense portion (always a full sphere, no gap). The rim
/// blends the two by share. Honors Reduce Motion (freezes the clock) and fades up on appear.
struct GlowParticleRing<Center: View>: View {
    /// Fraction of the orb coloured as income (0…1); the remainder is expense.
    var incomeShare: Double
    var incomeColor: Color
    var expenseColor: Color
    var size: CGFloat = 208
    /// When true (e.g. over budget), the aura bloom breathes to draw attention.
    var pulse: Bool = false
    @ViewBuilder var center: () -> Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var animated: Double = 0
    @State private var pulsing = false

    // MARK: Particle field (outward-flow emission model, ported from the sample)

    private struct Particle {
        let baseAng, radSpeed, radPhase, maxSize, baseOp, angDrift: Double
        let samp, sax, say, spx, spy: Double
        let big: Bool
    }

    private let particles: [Particle] = {
        var rng = SeededRNG(seed: 0xC0FFEE)
        func r() -> Double { Double.random(in: 0...1, using: &rng) }
        return (0..<720).map { _ in
            let big = r() > 0.93
            return Particle(
                baseAng: r() * 2 * .pi,
                radSpeed: 0.07 + r() * 0.17,           // outward progress per second
                radPhase: r(),                         // staggered start so the flow is continuous
                maxSize: 1.6 + pow(r(), 1.5) * 3.2 + (big ? 2.6 : 0),
                baseOp: 0.5 + r() * 0.5,
                angDrift: (r() - 0.5) * 0.10,          // per-dot drift atop the global spin
                samp: 0.8 + r() * 1.8,                 // shimmer amplitude
                sax: 6 + r() * 12,
                say: 6 + r() * 12,
                spx: r() * 2 * .pi,
                spy: r() * 2 * .pi,
                big: big
            )
        }
    }()

    // MARK: Blob outline phases (stable per-instance)

    private let blobPhase: (a: [Double], b: [Double], c: [Double]) = {
        var rng = SeededRNG(seed: 0x5EED)
        func r() -> Double { Double.random(in: 0...1, using: &rng) }
        var a = [Double](), b = [Double](), c = [Double]()
        for _ in 0..<16 { a.append(r() * 2 * .pi); b.append(r() * 2 * .pi); c.append(r() * 2 * .pi) }
        return (a, b, c)
    }()

    /// Organic, slowly-morphing orb edge. `t` is seconds; `dim` is the square side in points.
    private func blobPath(t: Double, dim: Double) -> Path {
        let n = 16
        let half = dim / 2
        let baseR = half * 0.80
        let breathe = 1 + 0.014 * sin(t * 0.45)
        var pts = [CGPoint]()
        for i in 0..<n {
            let ang = Double(i) / Double(n) * 2 * .pi
            var r = baseR * (1
                + 0.058 * sin(t * 0.55 + blobPhase.a[i])
                + 0.040 * sin(t * 0.40 + Double(i) * 1.7 + blobPhase.b[i])
                + 0.024 * sin(t * 0.92 - Double(i) * 1.1 + blobPhase.c[i]))
            r *= breathe
            pts.append(CGPoint(x: half + cos(ang) * r, y: half + sin(ang) * r))
        }
        var path = Path()
        path.move(to: pts[0])
        for i in 0..<n {
            let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }

    var body: some View {
        let share = min(max(incomeShare, 0), 1)
        // Luminous single-hue rim in the dominant tone (avoids the muddy red+green average) —
        // glows green when income-led, red when spend-led, echoing the status chip.
        let rimAccent = share >= 0.5 ? incomeColor : expenseColor
        let rimBright = rimAccent.lightened(0.55)
        // D-13 light neumorphism: the orb's dark radial body + vignette are built for a dark
        // dish; on a LIGHT dish they smear grey, so soften them in light while keeping DARK
        // byte-identical. The dark-ink readout carries its own legibility on light.
        let isDark = colorScheme == .dark

        return ZStack {
            // Colored aura bloom so the orb glows off the card and pulls the eye. Breathes when
            // `pulse` is set (over budget) to draw attention.
            Circle()
                .fill(rimAccent.opacity(isDark ? (pulse ? 0.30 : 0.22) : (pulse ? 0.16 : 0.10)))
                .blur(radius: size * 0.18)
                .frame(width: size * 0.96, height: size * 0.96)
                .scaleEffect(pulsing ? 1.07 : 1.0)
                .opacity(animated)

            // Contact shadow — pools below the sphere (light source top-left), the cue
            // that the orb is resting in its dish rather than floating over it.
            Ellipse()
                .fill(Color.black.opacity(isDark ? 0.45 : 0.10))
                .frame(width: size * 0.70, height: size * 0.18)
                .blur(radius: size * 0.05)
                .offset(x: size * 0.02, y: size * 0.37)
                .opacity(animated)

            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

                Canvas { ctx, sz in
                    let dim = Double(min(sz.width, sz.height))
                    let half = dim / 2
                    let center = CGPoint(x: half, y: half)
                    let outerR = sz.width / 2
                    let scale = dim / 600.0       // sample magnitudes are in a 600pt viewBox
                    let grow = max(animated, 0.0001)
                    let blob = blobPath(t: t, dim: dim)

                    // 1. Dark radial body — gives the orb depth without colour bias.
                    ctx.fill(blob, with: .radialGradient(
                        Gradient(stops: [
                            .init(color: .black.opacity(isDark ? 0.45 : 0.05), location: 0),
                            .init(color: .black.opacity(isDark ? 0.30 : 0.03), location: 0.55),
                            .init(color: .black.opacity(0.0), location: 1.0)
                        ]),
                        center: center, startRadius: 0, endRadius: outerR))

                    // 2. Particles + centre vignette, clipped to the blob.
                    ctx.drawLayer { layer in
                        layer.clip(to: blob)
                        let dotRmax = half * 0.96

                        for p in particles {
                            var prog = (p.radPhase + t * p.radSpeed).truncatingRemainder(dividingBy: 1)
                            if prog < 0 { prog += 1 }
                            let radius = dotRmax * pow(prog, 0.62)
                            let ang = p.baseAng + t * (0.22 + p.angDrift)
                            let x = half + cos(ang) * radius + p.samp * scale * sin(t * p.sax + p.spx)
                            let y = half + sin(ang) * radius + p.samp * scale * cos(t * p.say + p.spy)
                            let dot = (0.4 + p.maxSize * pow(prog, 0.8)) * scale
                            let fadeIn = prog < 0.12 ? prog / 0.12 : 1
                            let fadeOut = prog > 0.9 ? (1 - prog) / 0.10 : 1
                            let op = min(p.baseOp * fadeIn * fadeOut * (0.45 + 0.55 * prog) * grow, 1)
                            let col = p.baseAng < share * 2 * .pi ? incomeColor : expenseColor
                            let pt = CGPoint(x: x, y: y)

                            if p.big {
                                let halo = dot * 2.8
                                layer.fill(
                                    Path(ellipseIn: CGRect(x: pt.x - halo, y: pt.y - halo, width: halo * 2, height: halo * 2)),
                                    with: .color(col.opacity(op * 0.18)))
                            }
                            layer.fill(
                                Path(ellipseIn: CGRect(x: pt.x - dot, y: pt.y - dot, width: dot * 2, height: dot * 2)),
                                with: .color(col.opacity(op)))
                        }

                        // Centre vignette — tight, dark core just behind the readout, clearing
                        // quickly so the surrounding particle field stays bright and visible.
                        layer.fill(blob, with: .radialGradient(
                            Gradient(stops: [
                                .init(color: isDark ? .black.opacity(0.88) : .white.opacity(0.75), location: 0),
                                .init(color: isDark ? .black.opacity(0.62) : .white.opacity(0.45), location: 0.24),
                                .init(color: .black.opacity(0.0), location: 0.46)
                            ]),
                            center: center, startRadius: 0, endRadius: outerR))
                    }

                    // 2.5 Sphere shading — light from the top-left (same light source as the
                    // neumorphic surfaces): a soft highlight up-left and a darkened far limb
                    // down-right turn the flat particle disc into a convex ball.
                    let lightCenter = CGPoint(x: dim * 0.38, y: dim * 0.36)
                    ctx.drawLayer { layer in
                        layer.clip(to: blob)
                        layer.fill(blob, with: .radialGradient(
                            Gradient(stops: [
                                .init(color: .white.opacity(0.07), location: 0),
                                .init(color: .white.opacity(0.0), location: 0.5)
                            ]),
                            center: lightCenter, startRadius: 0, endRadius: outerR * 1.1))
                        layer.fill(blob, with: .radialGradient(
                            Gradient(stops: [
                                .init(color: .black.opacity(0.0), location: 0.60),
                                .init(color: .black.opacity(0.32), location: 1.0)
                            ]),
                            center: lightCenter, startRadius: 0, endRadius: outerR * 1.55))
                    }

                    // 3. Blurred glow rim.
                    var glow = ctx
                    glow.addFilter(.blur(radius: CGFloat(7 * scale)))
                    glow.stroke(blob, with: .color(rimAccent.opacity(0.7)), lineWidth: CGFloat(6 * scale))

                    // 4. Thin bright rim.
                    ctx.stroke(blob, with: .color(rimBright.opacity(0.95)), lineWidth: max(1, CGFloat(1.6 * scale)))
                }
            }

            center()
        }
        .frame(width: size, height: size)
        .onAppear { animate(); startPulse() }
        .onChange(of: pulse) { _, _ in startPulse() }
        .accessibilityElement(children: .combine)
    }

    private func startPulse() {
        guard pulse, !reduceMotion else { pulsing = false; return }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulsing = true
        }
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
