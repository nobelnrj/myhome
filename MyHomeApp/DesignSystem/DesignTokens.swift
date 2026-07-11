// DesignTokens.swift
// Single source of truth for all neumorphic visual tokens.
// Translated from design/design_handoff_myhome_neumorphic/src/tokens.jsx (neuro branch).
// Phase 13: DS-01

import SwiftUI
import UIKit

enum DesignTokens {

    // MARK: - Canvas & Surface
    static let bgCanvas               = Color(hex: "#1C1C23")
    static let surfaceRaised          = Color(hex: "#1F1F27")
    static let surfaceRaisedStrong    = Color(hex: "#22222C")
    // Curvature gradient endpoints — raised/floating surfaces are lit from the top-left,
    // so their fill runs lighter (topLeading) → darker (bottomTrailing), averaging to the
    // flat surface colors above. This diagonal falloff is what sells the convex "pillow"
    // read; a flat fill looks like a sticker no matter how strong the outer shadows are.
    static let surfaceRaisedTop          = Color(hex: "#24242D")
    static let surfaceRaisedBottom       = Color(hex: "#1B1B21")
    static let surfaceRaisedStrongTop    = Color(hex: "#282833")
    static let surfaceRaisedStrongBottom = Color(hex: "#1E1E26")
    static let surfaceElevatedControl = Color(hex: "#262630")
    static let fillRecessed           = Color(hex: "#16161C")
    static let fillRecessed2          = Color(hex: "#191920")
    static let fillRecessed3          = Color(hex: "#15151B")

    // MARK: - Accent & Semantic
    static let accent        = Color(hex: "#FFD60A")
    static let accentSoft    = Color(hex: "#FFD60A").opacity(0.16)
    static let accentOnYellow = Color(hex: "#1A1404")
    static let positive      = Color(hex: "#34E29B")
    static let negative      = Color(hex: "#FF6B6B")
    static let orange        = Color(hex: "#FFB020")

    // MARK: - AI Insight accent (Phase 16 — localized; not a general accent)
    // Scoped exclusively to AIInsightCard. DO NOT use on any other surface.
    // The primary app accent (#FFD60A canary) is unchanged and continues to govern
    // all Overview, tab bar, and budget UI.
    static let aiVioletTop    = Color(hex: "#C4A6FF")  // edge gradient — top
    static let aiVioletBottom = Color(hex: "#7C5CFF")  // edge gradient — bottom
    static let aiVioletGlow   = Color(hex: "#8B5CF6")  // shadow / orb / wash

    // MARK: - Labels
    // Base: #ECEDF4 for primary; #DCDFEE (rgb 220,223,238) with opacity for secondary tiers
    static let label  = Color(hex: "#ECEDF4")
    static let label2 = Color(hex: "#DCDFEE").opacity(0.56)
    static let label3 = Color(hex: "#DCDFEE").opacity(0.32)
    static let label4 = Color(hex: "#DCDFEE").opacity(0.16)

    // MARK: - Separators & Borders
    static let separatorHairline = Color.white.opacity(0.05)
    static let separatorEdge     = Color.black.opacity(0.30)
    static let glassBorder       = Color.white.opacity(0.025)

    // MARK: - Category Palette
    static let catGroceries     = Color(hex: "#2DD4BF")
    static let catDining        = Color(hex: "#FB923C")
    static let catFuel          = Color(hex: "#F472B6")
    static let catUtilities     = Color(hex: "#7DD3FC")
    static let catRent          = Color(hex: "#818CF8")
    static let catAuto          = Color(hex: "#38BDF8")
    static let catShopping      = Color(hex: "#E879F9")
    static let catHealth        = Color(hex: "#A78BFA")
    static let catSubscriptions = Color(hex: "#22D3EE")
    static let catEntertainment = Color(hex: "#C084FC")
    static let catOther         = Color(hex: "#94A3B8")

    // MARK: - Corner Radii
    static let radiusCard:   CGFloat = 26
    static let radiusInner:  CGFloat = 20   // mid-range of 16–22 spec
    static let radiusPill:   CGFloat = 999
    static let radiusTabBar: CGFloat = 34
    static let radiusSheet:  CGFloat = 20
    // radiusIconTile is computed per-component: size * 0.28

    // MARK: - Spacing (on-grid 4-point multiples)
    static let spacing4:  CGFloat = 4
    static let spacing8:  CGFloat = 8
    static let spacing16: CGFloat = 16
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32
    static let spacing48: CGFloat = 48

    // MARK: - Spacing (handoff-sourced structural exceptions — see UI-SPEC spacing section)
    static let spacing2:  CGFloat = 2    // tab bar icon↔label micro-gap (ui.jsx TabItem gap: 2)
    static let spacing12: CGFloat = 12   // active pill vertical inset formula (ui.jsx pilH = tabBarHeight − 12)
    static let spacing22: CGFloat = 22   // inter-card vertical gap (ui.jsx card list gap: 22)

    // MARK: - Tab Bar Geometry
    static let tabBarHeight:       CGFloat = 62
    static let tabBarBottomOffset: CGFloat = 24
    static let tabBarClearance:    CGFloat = 100   // safeAreaInset height for content (TABBAR_H)
    static let tabItemWidth:       CGFloat = 58

    // MARK: - Shadow Helpers
    // NOTE: @ScaledMetric cannot be a static stored property on an enum (Swift compiler error:
    // "property wrappers are not allowed on static stored properties").
    // Group B font base sizes (heroMoney 46pt, statNumber 21pt, cardTitle 16pt, etc.) are
    // declared as @ScaledMetric instance properties in each consumer view — not here.
    struct ShadowSpec {
        let lightColor: Color
        let lightRadius: CGFloat
        let lightX: CGFloat
        let lightY: CGFloat
        let darkColor: Color
        let darkRadius: CGFloat
        let darkX: CGFloat
        let darkY: CGFloat
    }

    /// Standard raised card: dual outer shadow (light top-left, dark bottom-right).
    /// Light opacity runs hotter than the CSS token (0.035) because SwiftUI's gaussian
    /// shadow spreads thinner than a CSS box-shadow at the same radius — 0.05 lands at
    /// the handoff's perceived brightness.
    static let shadowRaised = ShadowSpec(
        lightColor: .white.opacity(0.05),  lightRadius: 7,  lightX: -6, lightY: -6,
        darkColor:  .black.opacity(0.55),  darkRadius:  9,  darkX:   7, darkY:   7
    )

    /// Floating element (hero card, tab bar capsule, bottom sheet): deeper dual outer shadow
    static let shadowFloat = ShadowSpec(
        lightColor: .white.opacity(0.055), lightRadius: 11, lightX: -9, lightY: -9,
        darkColor:  .black.opacity(0.62),  darkRadius:  14, darkX:  11, darkY:  11
    )

    // MARK: - Spring Animations
    /// Bouncy spring — matches handoff cubic-bezier(.34,1.32,.42,1); used for tab pill slide
    static let springBouncy: Animation = .spring(response: 0.4, dampingFraction: 0.65)
    /// Soft spring — matches handoff cubic-bezier(.32,.72,0,1); used for sheet slide-up / push
    static let springSoft:   Animation = .spring(response: 0.4, dampingFraction: 0.90)
}

// MARK: - Neon Glow

extension View {
    /// Layered coloured bloom — the neon vibe shared with the Overview orb. Two soft shadows in
    /// the source colour (tight + wide) make strokes, bars, and rings appear to emit light.
    func neonGlow(_ color: Color, radius: CGFloat = 8, intensity: Double = 1) -> some View {
        self
            .shadow(color: color.opacity(0.55 * intensity), radius: radius * 0.55)
            .shadow(color: color.opacity(0.32 * intensity), radius: radius * 1.5)
    }
}

// MARK: - Motion: staggered entrance

/// Fade + rise as the view appears, delayed by its position so a stack of cards cascades in.
/// Honors Reduce Motion (snaps visible). Theme-agnostic (no colour assumptions).
private struct EntranceModifier: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true; return }
                // Cap the cascade so far-down rows don't wait forever.
                let delay = Double(min(index, 6)) * 0.06
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Staggered fade+rise entrance; pass the item's position in its stack.
    func entrance(_ index: Int) -> some View { modifier(EntranceModifier(index: index)) }
}

// MARK: - Haptics

/// Thin wrapper over UIKit feedback generators for premium tactile micro-interactions.
enum Haptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
