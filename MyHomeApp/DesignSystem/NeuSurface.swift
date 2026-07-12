// NeuSurface.swift
// Neumorphic surface ViewModifier — raised / floating / recessed states.
// Replaces CardStyle entirely for v1.2 screens.
// Phase 13: DS-02

import SwiftUI

/// State of a neumorphic surface.
enum NeuSurfaceState {
    /// Standard extruded card — dual outer shadow (light top-left, dark bottom-right) + inner rim.
    case raised
    /// Hero-tier card / floating element — deeper dual outer shadow + inner rim.
    case floating
    /// Sunken well — overlay-gradient inset approximation; no outer shadow, no rim.
    case recessed
}

/// ViewModifier that wraps any content in a neumorphic surface.
///
/// Usage:
/// ```swift
/// Text("Hello")
///     .neuSurface(.raised)
///
/// // Interactive (tappable) card adds a glassBorder boundary affordance (DS-06):
/// Button("Tap") { ... }
///     .neuSurface(.raised, isInteractive: true)
/// ```
struct NeuSurface: ViewModifier {
    var state: NeuSurfaceState
    var radius: CGFloat = DesignTokens.radiusCard
    var padding: CGFloat? = 16
    /// When `true`, adds a 0.5pt `DesignTokens.glassBorder` stroke overlay to satisfy
    /// WCAG 1.4.11 (3:1) non-text contrast: shadow depth is never the sole boundary affordance (DS-06).
    var isInteractive: Bool = false

    // MARK: - Fill

    /// Raised/floating fills are diagonal curvature gradients (lit top-left → shaded
    /// bottom-right) so the surface reads convex; recessed stays a flat dark fill and
    /// gets its concavity from the inner shadow overlay.
    private var fill: AnyShapeStyle {
        switch state {
        case .raised:
            return AnyShapeStyle(LinearGradient(
                colors: [DesignTokens.surfaceRaisedTop, DesignTokens.surfaceRaisedBottom],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .floating:
            return AnyShapeStyle(LinearGradient(
                colors: [DesignTokens.surfaceRaisedStrongTop, DesignTokens.surfaceRaisedStrongBottom],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .recessed:
            return AnyShapeStyle(DesignTokens.fillRecessed3)
        }
    }

    // MARK: - Shadow spec (raised / floating only)

    private var shadowSpec: DesignTokens.ShadowSpec? {
        switch state {
        case .raised:    return DesignTokens.shadowRaised
        case .floating:  return DesignTokens.shadowFloat
        case .recessed:  return nil   // recessed uses overlay-gradient inset, no outer shadow
        }
    }

    // MARK: - Body

    func body(content: Content) -> some View {
        Group {
            if let padding {
                content.padding(padding)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        // --- Outer dual shadow (raised / floating only — light FIRST, dark SECOND per RESEARCH Pitfall 2)
        .modifier(OuterShadowModifier(spec: shadowSpec))
        // --- Inner rim overlay for raised / floating
        .modifier(RimOverlayModifier(state: state, radius: radius))
        // --- Recessed inset approximation (overlay gradient)
        .modifier(RecessedOverlayModifier(state: state, radius: radius))
        // --- WCAG 1.4.11 interactive boundary affordance (DS-06)
        .modifier(InteractiveBorderModifier(isInteractive: isInteractive, radius: radius))
    }
}

// MARK: - Outer shadow sub-modifier

/// Applies the dual outer shadow (light first, dark second) from a ShadowSpec.
/// Extracted to a separate modifier so the `body` chain stays readable.
private struct OuterShadowModifier: ViewModifier {
    let spec: DesignTokens.ShadowSpec?

    func body(content: Content) -> some View {
        if let spec {
            content
                // Light shadow first (top-left highlight)
                .shadow(color: spec.lightColor, radius: spec.lightRadius, x: spec.lightX, y: spec.lightY)
                // Dark shadow second (bottom-right depth)
                .shadow(color: spec.darkColor,  radius: spec.darkRadius,  x: spec.darkX,  y: spec.darkY)
        } else {
            content
        }
    }
}

// MARK: - Inner rim overlay (raised / floating)

/// Adds a strokeBorder rim gradient for raised/floating states.
/// The CSS token is white 4.5% → black 30%, but a 1pt SwiftUI stroke renders far softer
/// than a crisp CSS inset — white 7% / black 35% reproduces the handoff's visible
/// top-left catch-light edge without reading as an outline.
private struct RimOverlayModifier: ViewModifier {
    let state: NeuSurfaceState
    let radius: CGFloat

    private var showRim: Bool {
        state == .raised || state == .floating
    }

    func body(content: Content) -> some View {
        content.overlay {
            if showRim {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                DesignTokens.neuRimTop,
                                DesignTokens.neuRimBottom
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
    }
}

// MARK: - Recessed inset approximation

/// For `.recessed`, overlays a real inner shadow — the same stroke+blur+offset+mask
/// recipe as `NeuCircularWell` — so rectangular wells (stat tiles, input tracks) read
/// carved into the surface rather than tinted. A dark arc presses in from the top-left,
/// a soft light rim rises from the bottom-right, and a crisp hairline keeps the well
/// boundary defined under the blur.
private struct RecessedOverlayModifier: ViewModifier {
    let state: NeuSurfaceState
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            if state == .recessed {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                ZStack {
                    // Dark inner shadow — top-left, pressed in
                    shape
                        .stroke(DesignTokens.neuInnerShade, lineWidth: 8)
                        .blur(radius: 6)
                        .offset(x: 3, y: 4)
                        .mask(shape)

                    // Light inner rim — bottom-right, rising
                    shape
                        .stroke(DesignTokens.neuInnerRise, lineWidth: 6)
                        .blur(radius: 5)
                        .offset(x: -2, y: -3)
                        .mask(shape)

                    // Crisp hairline edge so the well boundary stays defined under the blur
                    shape.strokeBorder(
                        LinearGradient(colors: [DesignTokens.neuHairlineDark, DesignTokens.neuHairlineLight],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                }
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Interactive boundary affordance (DS-06)

/// When `isInteractive` is true, adds a 0.5pt `DesignTokens.glassBorder` stroke.
/// Ensures WCAG 1.4.11 (3:1) non-text contrast: the shadow alone is insufficient
/// as a boundary affordance because shadows at 3.5% white opacity are below threshold.
private struct InteractiveBorderModifier: ViewModifier {
    let isInteractive: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            if isInteractive {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DesignTokens.glassBorder, lineWidth: 0.5)
            }
        }
    }
}

// MARK: - View extension

extension View {
    /// Wraps the view in a neumorphic surface (padding + fill + clip + dual shadow + rim).
    ///
    /// - Parameters:
    ///   - state: `.raised` (standard card), `.floating` (hero/tab-bar), or `.recessed` (input/track).
    ///   - radius: Corner radius; defaults to `DesignTokens.radiusCard` (26pt).
    ///   - padding: Inner padding; pass `nil` if the caller handles padding.
    ///   - isInteractive: When `true`, adds a `glassBorder` stroke affordance (DS-06).
    func neuSurface(
        _ state: NeuSurfaceState,
        radius: CGFloat = DesignTokens.radiusCard,
        padding: CGFloat? = 16,
        isInteractive: Bool = false
    ) -> some View {
        modifier(NeuSurface(state: state, radius: radius, padding: padding, isInteractive: isInteractive))
    }
}

// MARK: - CTA button styles (neumorphic v2 handoff)

/// Primary CTA — extruded gradient-yellow pill with a soft yellow halo and a bright inner
/// top rim. Presses to a flatter, darker look (standard neumorphic pressed affordance).
/// One per screen at most — the single gradient accent of the CTA system.
struct NeuPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color(hex: "#231B00"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: configuration.isPressed
                            ? [Color(hex: "#E8C918"), Color(hex: "#D9B000")]
                            : [Color(hex: "#FFE04A"), Color(hex: "#F2C500")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            )
            // Bright inner top rim (inset 1.5px white 0.45 in the handoff recipe)
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(configuration.isPressed ? 0.15 : 0.45), .clear],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
            )
            // Float shadow + soft yellow halo — collapse when pressed
            .shadow(color: configuration.isPressed ? Color.clear : DesignTokens.neuButtonHighlight,
                    radius: 11, x: -9, y: -9)
            .shadow(color: configuration.isPressed ? DesignTokens.neuButtonShadePressed : DesignTokens.neuButtonShade,
                    radius: configuration.isPressed ? 4 : 14,
                    x: configuration.isPressed ? 2 : 11,
                    y: configuration.isPressed ? 2 : 11)
            .shadow(color: DesignTokens.accent.opacity(configuration.isPressed ? 0.10 : 0.22),
                    radius: 11, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// Secondary CTA — raised dark pill (`surfaceRaisedStrong`) with accent text and the
/// float + rim shadow pair. Presses to a sunken look.
struct NeuSecondaryButtonStyle: ButtonStyle {
    /// Fixed-width variant (e.g. a compact header pill) skips maxWidth expansion.
    var expands: Bool = true
    var accentHalo: Bool = false
    var fontSize: CGFloat = 15
    var verticalPadding: CGFloat = 14
    var horizontalPadding: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(DesignTokens.accentText)
            .frame(maxWidth: expands ? .infinity : nil)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .background(
                Capsule().fill(
                    configuration.isPressed
                        ? AnyShapeStyle(DesignTokens.fillRecessed3)
                        : AnyShapeStyle(LinearGradient(
                            colors: [DesignTokens.surfaceRaisedStrongTop,
                                     DesignTokens.surfaceRaisedStrongBottom],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                          ))
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: configuration.isPressed
                            ? [DesignTokens.neuRimBottom, DesignTokens.neuRimTop]
                            : [DesignTokens.neuRimTop, DesignTokens.neuRimBottom],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
            .shadow(color: configuration.isPressed ? Color.clear : DesignTokens.neuButtonHighlight,
                    radius: 11, x: -9, y: -9)
            .shadow(color: configuration.isPressed ? DesignTokens.neuButtonShadePressedSoft : DesignTokens.neuButtonShade,
                    radius: configuration.isPressed ? 4 : 14,
                    x: configuration.isPressed ? 2 : 11,
                    y: configuration.isPressed ? 2 : 11)
            .shadow(color: DesignTokens.accent.opacity(accentHalo && !configuration.isPressed ? 0.18 : 0),
                    radius: 8, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Embossed progress bar (handoff "embossed fill recipe")

/// Recessed pill track + embossed colored fill: the fill carries an inner top highlight and
/// bottom shade (`inset 0 1.5px 1px white/0.28, inset 0 -1.5px 2px black/0.28`) so it reads
/// as a physical bar seated in a well. Used by every horizontal progress bar in v2.
struct EmbossedBar<Fill: ShapeStyle>: View {
    /// 0…1+ (clamped to 1 for rendering).
    let fraction: Double
    /// Fill style — a flat category color or the yellow→green budget gradient.
    let fill: Fill
    var height: CGFloat = 10
    /// Minimum visible fill width so tiny fractions still render a nub.
    var minWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Recessed track — top shade band inside the well + a stronger dark top
                // edge so the track reads sunken at bar height (too shallow for the full
                // stroke-blur inner-shadow recipe).
                Capsule().fill(DesignTokens.fillRecessed3)
                    .overlay(
                        Capsule().fill(
                            LinearGradient(stops: [
                                .init(color: .black.opacity(0.35), location: 0),
                                .init(color: .clear, location: 0.55)
                            ], startPoint: .top, endPoint: .bottom)
                        )
                    )
                    .overlay(
                        Capsule().stroke(
                            LinearGradient(colors: [.black.opacity(0.55), .white.opacity(0.04)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )
                        .blur(radius: 0.5)
                        .clipShape(Capsule())
                    )
                // Embossed fill
                if fraction > 0 {
                    Capsule().fill(fill)
                        .overlay(
                            Capsule().fill(
                                LinearGradient(stops: [
                                    .init(color: .white.opacity(0.28), location: 0),
                                    .init(color: .clear, location: 0.35),
                                    .init(color: .clear, location: 0.65),
                                    .init(color: .black.opacity(0.28), location: 1)
                                ], startPoint: .top, endPoint: .bottom)
                            )
                        )
                        .frame(width: max(minWidth, min(CGFloat(fraction), 1) * geo.size.width))
                        .animation(.easeOut(duration: 0.5), value: fraction)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Vertical pill gauge (recessed well + glowing fill column)

/// The v2 chart column: a recessed vertical pill well with a glowing colour fill pill
/// inset from the sides and bottom. Used by the Analytics/Overview "By category" charts
/// (fraction = share of the largest value) and the Overview Budgets glance
/// (fraction = share of the category's budget).
struct VerticalPillGauge: View {
    /// 0…1 fill fraction of the well (clamped).
    var fraction: Double
    var color: Color
    var wellWidth: CGFloat = 42
    var wellHeight: CGFloat = 150
    /// Fill inset from the well's sides and bottom.
    var inset: CGFloat = 9
    /// Minimum fill height so tiny values still render a visible pill.
    var minFillHeight: CGFloat = 24
    /// Entrance multiplier (0…1) — callers animate this for the bar-rise effect.
    var reveal: Double = 1

    private var fillHeight: CGFloat {
        let maxFill = wellHeight - inset * 2
        let f = min(max(fraction, 0), 1)
        let target = minFillHeight + (maxFill - minFillHeight) * f
        return max(minFillHeight * reveal, target * reveal)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Recessed vertical well — shade band pressed in from the top plus a stronger
            // dark top edge, matching the EmbossedBar track depth treatment.
            Capsule()
                .fill(DesignTokens.fillRecessed3)
                .overlay(
                    Capsule().fill(
                        LinearGradient(stops: [
                            .init(color: .black.opacity(0.35), location: 0),
                            .init(color: .clear, location: 0.30)
                        ], startPoint: .top, endPoint: .bottom)
                    )
                )
                .overlay(
                    Capsule().stroke(
                        LinearGradient(colors: [.black.opacity(0.55), .white.opacity(0.04)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                    .blur(radius: 0.5)
                    .clipShape(Capsule())
                )
                .frame(width: wellWidth, height: wellHeight)

            // Glowing inner fill pill — light→base vertical gradient of the colour.
            // A zero fraction renders an empty well (no minimum nub implying usage).
            if fraction > 0 {
                Capsule()
                    .fill(color)
                    .overlay(
                        Capsule().fill(
                            LinearGradient(colors: [.white.opacity(0.35), .clear],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    )
                    .frame(width: wellWidth - inset * 2, height: fillHeight)
                    .padding(.bottom, inset)
                    .shadow(color: color.opacity(0.45), radius: 8)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Circular recessed well (chart dish)

/// A circular sunken dish that charts sit inside — donut, budget ring, hero orb.
/// Real inner-shadow depth (the CSS `--well` recipe): a wide blurred dark arc pressed in
/// from the top-left and a soft light rim rising from the bottom-right, both masked to the
/// circle so the dish reads as carved into the surface — same depth as the pill wells.
struct NeuCircularWell<Content: View>: View {
    var size: CGFloat
    @ViewBuilder var content: () -> Content

    /// Shadow geometry scales with the dish so small wells don't over-darken.
    private var depth: CGFloat { max(6, size * 0.035) }

    var body: some View {
        ZStack {
            // Dish chrome rasterized as one layer (drawingGroup) — the animated content
            // (e.g. the hero orb's TimelineView) stays live on top, outside the group.
            ZStack {
                Circle()
                    .fill(DesignTokens.fillRecessed3)

                // Dark inner shadow — top-left, pressed in
                Circle()
                    .stroke(Color.black.opacity(0.55), lineWidth: depth * 1.6)
                    .blur(radius: depth * 1.1)
                    .offset(x: depth * 0.55, y: depth * 0.7)
                    .mask(Circle())

                // Light inner rim — bottom-right, rising
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: depth)
                    .blur(radius: depth * 0.8)
                    .offset(x: -depth * 0.4, y: -depth * 0.55)
                    .mask(Circle())

                // Crisp hairline edge so the well boundary stays defined under the blur
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [.black.opacity(0.50), .white.opacity(0.04)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            }
            .drawingGroup()

            content()
        }
        .frame(width: size, height: size)
    }
}

/// A raised circular puck — the extruded disc that floats in the middle of a chart well
/// (donut center, budget-ring percentage). Card shadow + rim, `surfaceRaised` fill.
struct NeuCircularPuck<Content: View>: View {
    var size: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [DesignTokens.surfaceRaisedTop, DesignTokens.surfaceRaisedBottom],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .shadow(color: DesignTokens.neuOuterHighlight, radius: 7, x: -6, y: -6)
                .shadow(color: DesignTokens.neuOuterShade, radius: 9, x: 7, y: 7)
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(colors: [DesignTokens.neuRimTop, DesignTokens.neuRimBottom],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                )
            content()
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Eyebrow label (12/600, ls 1.2, uppercase, label2)

extension Text {
    /// The handoff's eyebrow style — section micro-labels like "NET CASH FLOW" / "AI INSIGHT".
    func eyebrow(_ color: Color = DesignTokens.label2) -> some View {
        self
            .font(.system(size: 12, weight: .semibold))
            .kerning(1.2)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

// MARK: - Preview

private struct NeuSurfacePreviewGallery: View {
    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.spacing22) {

                // Raised — standard card
                VStack(alignment: .leading, spacing: 8) {
                    Text("Raised").font(.caption).foregroundStyle(DesignTokens.label2)
                    Text("Standard card surface")
                        .foregroundStyle(DesignTokens.label)
                        .neuSurface(.raised)
                }

                // Floating — hero card
                VStack(alignment: .leading, spacing: 8) {
                    Text("Floating").font(.caption).foregroundStyle(DesignTokens.label2)
                    Text("Hero / tab-bar surface")
                        .foregroundStyle(DesignTokens.label)
                        .neuSurface(.floating)
                }

                // Recessed — input well
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recessed").font(.caption).foregroundStyle(DesignTokens.label2)
                    Text("Input / track surface")
                        .foregroundStyle(DesignTokens.label)
                        .neuSurface(.recessed)
                }

                // Interactive (raised + glassBorder DS-06 affordance)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Interactive (raised)").font(.caption).foregroundStyle(DesignTokens.label2)
                    Text("Tappable card — glassBorder visible at 0.5pt")
                        .foregroundStyle(DesignTokens.label)
                        .neuSurface(.raised, isInteractive: true)
                }

                // CTA button styles — both neumorphic button vocabularies
                VStack(alignment: .leading, spacing: 8) {
                    Text("CTA buttons").font(.caption).foregroundStyle(DesignTokens.label2)
                    Button("Primary CTA") {}.buttonStyle(NeuPrimaryButtonStyle())
                    Button("Secondary CTA") {}.buttonStyle(NeuSecondaryButtonStyle())
                }
            }
            .padding(DesignTokens.spacing16)
        }
        .background(DesignTokens.bgCanvas)
    }
}

#Preview("Dark") {
    NeuSurfacePreviewGallery()
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    NeuSurfacePreviewGallery()
        .preferredColorScheme(.light)
}
