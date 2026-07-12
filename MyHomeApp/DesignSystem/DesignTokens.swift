// DesignTokens.swift
// Single source of truth for all neumorphic visual tokens.
// Translated from design/design_handoff_myhome_neumorphic/src/tokens.jsx (neuro branch).
// Phase 13: DS-01

import SwiftUI
import UIKit

enum DesignTokens {

    // MARK: - Canvas & Surface
    // D-04: every color token is now an adaptive light/dark pair. The DARK branch is the
    // pre-refactor hex VERBATIM, so dark rendering stays byte-identical (D-06, enforced by
    // DarkBitIdentityTests). Light values are directional starting points, tuned on device
    // in Plans 04-07; only the dark branches are LOCKED.
    static let bgCanvas               = Color.adaptive(light: "#E3E6EE", dark: "#1C1C23")
    static let surfaceRaised          = Color.adaptive(light: "#E9ECF3", dark: "#1F1F27")
    static let surfaceRaisedStrong    = Color.adaptive(light: "#EDF0F6", dark: "#22222C")
    // Curvature gradient endpoints — raised/floating surfaces are lit from the top-left,
    // so their fill runs lighter (topLeading) → darker (bottomTrailing), averaging to the
    // flat surface colors above. This diagonal falloff is what sells the convex "pillow"
    // read; a flat fill looks like a sticker no matter how strong the outer shadows are.
    static let surfaceRaisedTop          = Color.adaptive(light: "#EFF2F8", dark: "#24242D")
    static let surfaceRaisedBottom       = Color.adaptive(light: "#E2E5ED", dark: "#1B1B21")
    static let surfaceRaisedStrongTop    = Color.adaptive(light: "#F3F5FA", dark: "#282833")
    static let surfaceRaisedStrongBottom = Color.adaptive(light: "#E6E9F1", dark: "#1E1E26")
    static let surfaceElevatedControl = Color.adaptive(light: "#EDEFF6", dark: "#262630")
    static let fillRecessed           = Color.adaptive(light: "#D7DBE6", dark: "#16161C")
    static let fillRecessed2          = Color.adaptive(light: "#DADEE8", dark: "#191920")
    static let fillRecessed3          = Color.adaptive(light: "#D4D8E3", dark: "#15151B")

    /// D-13 instrument-window dish interior. Deep slate in light, `fillRecessed3` VERBATIM in
    /// dark (the dish fill today). Consumed by Plans 05/06 for the force-dark dish chrome so a
    /// dish reads as a deliberate deep instrument well on light surfaces — never a "hole into
    /// dark mode" (#15151B charcoal) that D-13 forbids on a light canvas.
    static let dishSlate              = Color.adaptive(light: "#3E4250", dark: "#15151B")

    // MARK: - Accent & Semantic
    // D-08: `accent` stays canary in BOTH schemes — it governs FILLS (canary chips, active
    // pills, gauge sheens) which read correctly on light and dark alike. Text/icon roles use
    // the deepened `accentText` twin below.
    static let accent        = Color.adaptive(light: "#FFD60A", dark: "#FFD60A")
    static let accentSoft    = Color.adaptive(light: "#FFD60A", lightAlpha: 0.22,
                                              dark: "#FFD60A", darkAlpha: 0.16)
    static let accentOnYellow = Color.adaptive(light: "#1A1404", dark: "#1A1404")
    // D-10: deepened semantic light twins with preserved hue; dark = luminous verbatim.
    // Light twins deepened to clear the WCAG 4.5:1 small-text floor on #E3E6EE
    // (positive 5.25:1, negative 5.18:1, orange 5.03:1) — locked by ContrastTests.
    static let positive      = Color.adaptive(light: "#036B4A", dark: "#34E29B")
    static let negative      = Color.adaptive(light: "#B91C1C", dark: "#FF6B6B")
    static let orange        = Color.adaptive(light: "#A34209", dark: "#FFB020")

    /// D-08 role split — text/icon accent (NOT a fill). Dark amber on light (5.12:1 on the
    /// #E3E6EE canvas per the RESEARCH WCAG table); canary in dark. The dark branch is
    /// identical to `accent` so dark rendering cannot shift when call sites migrate a text/icon
    /// tint from `accent` to `accentText`.
    static let accentText    = Color.adaptive(light: "#755C00", dark: "#FFD60A")

    // MARK: - AI Insight accent (Phase 16 — localized; not a general accent)
    // Scoped exclusively to AIInsightCard. DO NOT use on any other surface.
    // The primary app accent (#FFD60A canary) is unchanged and continues to govern
    // all Overview, tab bar, and budget UI.
    // D-15: deepened violet light twins with preserved hue; dark = current luminous verbatim.
    static let aiVioletTop    = Color.adaptive(light: "#6D28D9", dark: "#C4A6FF")  // edge gradient — top
    static let aiVioletBottom = Color.adaptive(light: "#4C1D95", dark: "#7C5CFF")  // edge gradient — bottom
    static let aiVioletGlow   = Color.adaptive(light: "#6D28D9", dark: "#8B5CF6")  // shadow / orb / wash

    /// D-15 text/sparkle violet — deepened light twin passing 4.5:1 (7.19:1 on the light
    /// canvas). Dark branch == current `aiVioletTop` (violet text uses aiVioletTop today), so
    /// dark rendering is unchanged. Violet stays AI-only.
    static let aiVioletText   = Color.adaptive(light: "#5B21B6", dark: "#C4A6FF")

    // MARK: - Labels
    // Base: #ECEDF4 for primary; #DCDFEE (rgb 220,223,238) with opacity for secondary tiers
    // Label tiers carry per-scheme baked alpha (dark = current #DCDFEE composite verbatim;
    // light = deep ink #23252E at matching tier opacities).
    static let label  = Color.adaptive(light: "#23252E", dark: "#ECEDF4")
    static let label2 = Color.adaptive(light: "#23252E", lightAlpha: 0.62,
                                       dark: "#DCDFEE", darkAlpha: 0.56)
    static let label3 = Color.adaptive(light: "#23252E", lightAlpha: 0.40,
                                       dark: "#DCDFEE", darkAlpha: 0.32)
    static let label4 = Color.adaptive(light: "#23252E", lightAlpha: 0.22,
                                       dark: "#DCDFEE", darkAlpha: 0.16)

    // MARK: - Separators & Borders
    // Dark branches = current white/black baked-opacity values verbatim; light branches invert
    // to faint black hairlines that read on a bright canvas.
    static let separatorHairline = Color.adaptive(light: "#000000", lightAlpha: 0.07,
                                                  dark: "#FFFFFF", darkAlpha: 0.05)
    static let separatorEdge     = Color.adaptive(light: "#000000", lightAlpha: 0.12,
                                                  dark: "#000000", darkAlpha: 0.30)
    static let glassBorder       = Color.adaptive(light: "#000000", lightAlpha: 0.04,
                                                  dark: "#FFFFFF", darkAlpha: 0.025)

    // MARK: - Category Palette
    // D-09/D-10: deepened light twins with preserved hue identity; dark = luminous verbatim.
    // D-09/D-11 note: these light twins apply on light SURFACES. Inside force-dark instrument
    // windows (dishes, Plans 05/06) the same tokens auto-resolve to their original luminous
    // dark values — no per-call-site conditional needed.
    static let catGroceries     = Color.adaptive(light: "#0F766E", dark: "#2DD4BF")
    static let catDining        = Color.adaptive(light: "#C2410C", dark: "#FB923C")
    static let catFuel          = Color.adaptive(light: "#BE185D", dark: "#F472B6")
    static let catUtilities     = Color.adaptive(light: "#0369A1", dark: "#7DD3FC")
    static let catRent          = Color.adaptive(light: "#4338CA", dark: "#818CF8")
    static let catAuto          = Color.adaptive(light: "#0284C7", dark: "#38BDF8")
    static let catShopping      = Color.adaptive(light: "#A21CAF", dark: "#E879F9")
    static let catHealth        = Color.adaptive(light: "#6D28D9", dark: "#A78BFA")
    static let catSubscriptions = Color.adaptive(light: "#0E7490", dark: "#22D3EE")
    static let catEntertainment = Color.adaptive(light: "#7E22CE", dark: "#C084FC")
    static let catOther         = Color.adaptive(light: "#475569", dark: "#94A3B8")

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

    // MARK: - Neumorphic shadow colors (adaptive)
    // D-05/D-06: every promoted inline surface/button/puck shadow, rim, and hairline color is a
    // named adaptive pair. The DARK branch is the pre-refactor white/black opacity VERBATIM
    // (byte-identical, enforced by DarkBitIdentityTests). The LIGHT branch is a top-left bright
    // white highlight + a gray-blue shade/rim so light surfaces read as the same physical object
    // under different lighting (tuned on device in Task 2 of Plan 04). Geometry never adapts —
    // only these colors do.

    /// Outer top-left highlight for a raised card / puck (was `.white.opacity(0.05)`).
    static let neuOuterHighlight      = Color.adaptive(light: "#FFFFFF", lightAlpha: 0.80,
                                                       dark: "#FFFFFF", darkAlpha: 0.05)
    /// Outer bottom-right depth for a raised card / puck (was `.black.opacity(0.55)`).
    static let neuOuterShade          = Color.adaptive(light: "#8E97AD", lightAlpha: 0.50,
                                                       dark: "#000000", darkAlpha: 0.55)
    /// Outer top-left highlight for a floating/hero card (was `.white.opacity(0.055)`).
    static let neuOuterHighlightFloat = Color.adaptive(light: "#FFFFFF", lightAlpha: 0.90,
                                                       dark: "#FFFFFF", darkAlpha: 0.055)
    /// Outer bottom-right depth for a floating/hero card (was `.black.opacity(0.62)`).
    static let neuOuterShadeFloat     = Color.adaptive(light: "#8E97AD", lightAlpha: 0.60,
                                                       dark: "#000000", darkAlpha: 0.62)

    /// Inner-rim catch-light (top-left) for raised/secondary/puck rims (was `.white.opacity(0.07)`).
    static let neuRimTop              = Color.adaptive(light: "#FFFFFF", lightAlpha: 0.90,
                                                       dark: "#FFFFFF", darkAlpha: 0.07)
    /// Inner-rim shade (bottom-right) for raised/secondary/puck rims (was `.black.opacity(0.35)`).
    static let neuRimBottom           = Color.adaptive(light: "#9BA3B8", lightAlpha: 0.55,
                                                       dark: "#000000", darkAlpha: 0.35)

    /// Recessed-well dark inner arc, top-left pressed in (was `.black.opacity(0.55)`).
    static let neuInnerShade          = Color.adaptive(light: "#99A1B5", lightAlpha: 0.70,
                                                       dark: "#000000", darkAlpha: 0.55)
    /// Recessed-well light inner rim, bottom-right rising (was `.white.opacity(0.05)`).
    static let neuInnerRise           = Color.adaptive(light: "#FFFFFF", lightAlpha: 0.85,
                                                       dark: "#FFFFFF", darkAlpha: 0.05)

    /// Crisp well-boundary hairline, dark end (was `.black.opacity(0.45)`).
    static let neuHairlineDark        = Color.adaptive(light: "#9BA3B8", lightAlpha: 0.50,
                                                       dark: "#000000", darkAlpha: 0.45)
    /// Crisp well-boundary hairline, light end (was `.white.opacity(0.04)`).
    static let neuHairlineLight       = Color.adaptive(light: "#FFFFFF", lightAlpha: 0.70,
                                                       dark: "#FFFFFF", darkAlpha: 0.04)

    /// CTA-button top-left float highlight, unpressed (was `.white.opacity(0.04)`).
    static let neuButtonHighlight     = Color.adaptive(light: "#FFFFFF", lightAlpha: 0.80,
                                                       dark: "#FFFFFF", darkAlpha: 0.04)
    /// CTA-button bottom-right float depth, unpressed (was `.black.opacity(0.62)`).
    static let neuButtonShade         = Color.adaptive(light: "#8E97AD", lightAlpha: 0.55,
                                                       dark: "#000000", darkAlpha: 0.62)
    /// CTA-button pressed float depth — primary style (was `.black.opacity(0.25)`).
    /// Dedicated token: NEVER multiply an adaptive token's alpha (that would shift the dark branch).
    static let neuButtonShadePressed  = Color.adaptive(light: "#8E97AD", lightAlpha: 0.25,
                                                       dark: "#000000", darkAlpha: 0.25)
    /// CTA-button pressed float depth — secondary style (was `.black.opacity(0.20)`).
    static let neuButtonShadePressedSoft = Color.adaptive(light: "#8E97AD", lightAlpha: 0.20,
                                                          dark: "#000000", darkAlpha: 0.20)

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
        lightColor: neuOuterHighlight,  lightRadius: 7,  lightX: -6, lightY: -6,
        darkColor:  neuOuterShade,      darkRadius:  9,  darkX:   7, darkY:   7
    )

    /// Floating element (hero card, tab bar capsule, bottom sheet): deeper dual outer shadow
    static let shadowFloat = ShadowSpec(
        lightColor: neuOuterHighlightFloat, lightRadius: 11, lightX: -9, lightY: -9,
        darkColor:  neuOuterShadeFloat,     darkRadius:  14, darkX:  11, darkY:  11
    )

    // MARK: - Spring Animations
    /// Bouncy spring — matches handoff cubic-bezier(.34,1.32,.42,1); used for tab pill slide
    static let springBouncy: Animation = .spring(response: 0.4, dampingFraction: 0.65)
    /// Soft spring — matches handoff cubic-bezier(.32,.72,0,1); used for sheet slide-up / push
    static let springSoft:   Animation = .spring(response: 0.4, dampingFraction: 0.90)
}

// MARK: - Appearance Theme

/// App appearance preference, persisted via `@AppStorage("appearanceTheme")`.
///
/// D-01: replaces the former hard-coded `.preferredColorScheme(.dark)` at the app root. The
/// raw string lives in plain `UserDefaults.standard` — no App Group suite, because no widget
/// or extension reads the theme (the App-Group store is a SwiftData concern only).
///
/// D-02: `colorScheme` maps `system → nil` so SwiftUI follows the phone appearance. A missing
/// or malformed persisted value resolves to `.system` at the call site
/// (`AppearanceTheme(rawValue: raw) ?? .system`), so the first launch after this update follows
/// the device appearance with zero migration and no opt-in gate. This optional-init fallback is
/// the T-17-03 input-validation mitigation (unit-tested with garbage input).
enum AppearanceTheme: String, CaseIterable {
    case system
    case light
    case dark

    /// SwiftUI `preferredColorScheme` argument: `system → nil` (follow the device appearance).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// Human-readable segment label for the Settings Appearance row (D-03).
    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

// MARK: - Neon Glow

/// Scheme-aware neon bloom.
///
/// In DARK it renders the EXACT two-layer bloom (tight + wide) the app has always used — the
/// source colour makes strokes, bars, and rings appear to emit light (D-06: dark path unchanged,
/// byte-for-byte). In LIGHT it collapses to a single faint tinted drop-shadow (D-14) — a whisper
/// of the neon language on the bright canvas, never a rendering smudge.
///
/// Synergy: inside force-dark dish subtrees (Plan 05) the environment reads `.dark`, so the full
/// two-layer bloom is preserved automatically (D-11/D-12) with no per-call-site branching.
///
/// This is one of only THREE legitimate `@Environment(\.colorScheme)` read sites in the app
/// (the others: the dish `content()` override and NeuSurface). Do NOT add scheme reads elsewhere.
private struct NeonGlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let intensity: Double
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if scheme == .dark {
            content
                .shadow(color: color.opacity(0.55 * intensity), radius: radius * 0.55)
                .shadow(color: color.opacity(0.32 * intensity), radius: radius * 1.5)
        } else {
            // D-14 — whisper of the neon language on light; never a rendering smudge.
            content
                .shadow(color: color.opacity(0.28 * intensity), radius: radius * 0.7, y: 2)
        }
    }
}

extension View {
    /// Layered coloured bloom — the neon vibe shared with the Overview orb. Scheme-aware: the
    /// full two-layer bloom in dark (verbatim), a single faint tinted drop-shadow in light (D-14).
    /// Signature is unchanged so all existing `.neonGlow(_:radius:intensity:)` call sites are
    /// untouched.
    func neonGlow(_ color: Color, radius: CGFloat = 8, intensity: Double = 1) -> some View {
        modifier(NeonGlowModifier(color: color, radius: radius, intensity: intensity))
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
