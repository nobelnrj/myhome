// DesignTokensTests.swift
// Value-assertion tests for DS-01 DesignTokens constants.
// Phase 13 Plan 01 — extended by Phase 17 Plan 01 (D-06 dark bit-identity gate).
//
// Phase 17 note: token assertions resolve colors explicitly with Color.resolve(in:)
// under an explicit dark EnvironmentValues, instead of the appearance-sensitive hex
// accessor (which resolves against UITraitCollection.current and flaps by the test
// machine's appearance — RESEARCH Pitfall 1). DarkBitIdentityTests pins every token to its
// pre-refactor hex; it passes trivially against today's static tokens and becomes
// the D-06 gate the moment Plan 02 converts them to Color.adaptive pairs.

import Testing
import Foundation
import SwiftUI
@testable import MyHome

/// Build an `EnvironmentValues` with an explicit color scheme, so dynamic-provider
/// colors resolve deterministically regardless of the host process appearance.
@MainActor
private func env(_ scheme: ColorScheme) -> EnvironmentValues {
    var values = EnvironmentValues()
    values.colorScheme = scheme
    return values
}

/// WCAG 2.x relative-luminance contrast ratio between two resolved colors.
/// File-internal so Plan 02's ContrastTests can consume it. Exact formula from
/// RESEARCH §Code Examples (sRGB gamma expansion + 0.2126/0.7152/0.0722 weights).
func contrastRatio(_ a: Color.Resolved, _ b: Color.Resolved) -> Double {
    func lum(_ c: Color.Resolved) -> Double {
        func f(_ v: Float) -> Double {
            let d = Double(v)
            return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * f(c.red) + 0.7152 * f(c.green) + 0.0722 * f(c.blue)
    }
    let l1 = lum(a)
    let l2 = lum(b)
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
}

/// D-01/D-02 + T-17-03: the AppStorage-backed appearance preference maps raw strings to the
/// SwiftUI `preferredColorScheme` argument, and any missing/malformed persisted value degrades
/// safely to `.system` (follow the device) via the optional-init fallback at the call site.
@MainActor
struct AppearanceThemeTests {

    @Test("system → nil (follow device), light → .light, dark → .dark")
    func colorSchemeMapping() {
        #expect(AppearanceTheme.system.colorScheme == nil)
        #expect(AppearanceTheme.light.colorScheme == .light)
        #expect(AppearanceTheme.dark.colorScheme == .dark)
    }

    @Test("labels are System/Light/Dark for the Settings segmented row")
    func segmentLabels() {
        #expect(AppearanceTheme.system.label == "System")
        #expect(AppearanceTheme.light.label == "Light")
        #expect(AppearanceTheme.dark.label == "Dark")
    }

    @Test("garbage persisted value falls back to .system (T-17-03)")
    func garbageValueFallsBackToSystem() {
        // D-02: a corrupted/unknown UserDefaults string must degrade to the device-following
        // default rather than crash or lock the app into an unexpected scheme.
        #expect((AppearanceTheme(rawValue: "garbage") ?? .system) == .system)
        #expect((AppearanceTheme(rawValue: String()) ?? .system) == .system)
    }

    @Test("empty-string raw value is nil (optional-init contract)")
    func emptyStringIsNil() {
        #expect(AppearanceTheme(rawValue: String()) == nil)
    }

    @Test("all cases round-trip through their rawValue")
    func rawValueRoundTrip() {
        for theme in AppearanceTheme.allCases {
            #expect(AppearanceTheme(rawValue: theme.rawValue) == theme)
        }
    }
}

@MainActor
struct DesignTokensTests {

    @Test("DesignTokens.accent resolves in dark to #FFD60A")
    func accentColorMatchesSpec() throws {
        let darkEnv = env(.dark)
        #expect(DesignTokens.accent.resolve(in: darkEnv)
                == Color(hex: "#FFD60A").resolve(in: darkEnv))
    }

    @Test("DesignTokens.shadowRaised light x=-6, dark x=7")
    func shadowRaisedSpec() throws {
        #expect(DesignTokens.shadowRaised.lightX == -6)
        #expect(DesignTokens.shadowRaised.darkX  == 7)
    }

    @Test("DesignTokens.radiusCard equals 26")
    func radiusCard() throws {
        #expect(DesignTokens.radiusCard == 26)
    }

}

// MARK: - D-06 Dark bit-identity gate (Phase 17)

@MainActor
struct DarkBitIdentityTests {

    /// Every plain (fully-opaque) color token → its pre-refactor hex, captured
    /// verbatim from DesignTokens.swift BEFORE any adaptive conversion. 31 tokens.
    nonisolated static let plain: [(String, Color, String)] = [
        ("bgCanvas",                 DesignTokens.bgCanvas,                 "#1C1C23"),
        ("surfaceRaised",            DesignTokens.surfaceRaised,            "#1F1F27"),
        ("surfaceRaisedStrong",      DesignTokens.surfaceRaisedStrong,      "#22222C"),
        ("surfaceRaisedTop",         DesignTokens.surfaceRaisedTop,         "#24242D"),
        ("surfaceRaisedBottom",      DesignTokens.surfaceRaisedBottom,      "#1B1B21"),
        ("surfaceRaisedStrongTop",   DesignTokens.surfaceRaisedStrongTop,   "#282833"),
        ("surfaceRaisedStrongBottom", DesignTokens.surfaceRaisedStrongBottom, "#1E1E26"),
        ("surfaceElevatedControl",   DesignTokens.surfaceElevatedControl,   "#262630"),
        ("fillRecessed",             DesignTokens.fillRecessed,             "#16161C"),
        ("fillRecessed2",            DesignTokens.fillRecessed2,            "#191920"),
        ("fillRecessed3",            DesignTokens.fillRecessed3,            "#15151B"),
        ("accent",                   DesignTokens.accent,                   "#FFD60A"),
        ("accentOnYellow",           DesignTokens.accentOnYellow,           "#1A1404"),
        ("positive",                 DesignTokens.positive,                 "#34E29B"),
        ("negative",                 DesignTokens.negative,                 "#FF6B6B"),
        ("orange",                   DesignTokens.orange,                   "#FFB020"),
        ("aiVioletTop",              DesignTokens.aiVioletTop,              "#C4A6FF"),
        ("aiVioletBottom",           DesignTokens.aiVioletBottom,           "#7C5CFF"),
        ("aiVioletGlow",             DesignTokens.aiVioletGlow,             "#8B5CF6"),
        ("aiVioletText",             DesignTokens.aiVioletText,             "#C4A6FF"),
        ("label",                    DesignTokens.label,                    "#ECEDF4"),
        ("catGroceries",             DesignTokens.catGroceries,             "#2DD4BF"),
        ("catDining",                DesignTokens.catDining,                "#FB923C"),
        ("catFuel",                  DesignTokens.catFuel,                  "#F472B6"),
        ("catUtilities",             DesignTokens.catUtilities,             "#7DD3FC"),
        ("catRent",                  DesignTokens.catRent,                  "#818CF8"),
        ("catAuto",                  DesignTokens.catAuto,                  "#38BDF8"),
        ("catShopping",              DesignTokens.catShopping,              "#E879F9"),
        ("catHealth",                DesignTokens.catHealth,                "#A78BFA"),
        ("catSubscriptions",         DesignTokens.catSubscriptions,         "#22D3EE"),
        ("catEntertainment",         DesignTokens.catEntertainment,         "#C084FC"),
        ("catOther",                 DesignTokens.catOther,                 "#94A3B8"),
        ("catPantryGrain",           DesignTokens.catPantryGrain,           "#FBBF24"),
        ("catPantryBrew",            DesignTokens.catPantryBrew,            "#D9A066"),
        // Plan 06 — trend-chart amber + slate-inset fill (dark = pre-refactor value verbatim).
        ("chartAmber",               DesignTokens.chartAmber,               "#FFB43C"),
        ("dishSlateInset",           DesignTokens.dishSlateInset,           "#16161C"),
    ]

    /// Alpha-carrying tokens → their legacy composite (base color + baked opacity).
    /// 7 tokens: (name, token, baseColor, alpha).
    nonisolated static let alpha: [(String, Color, Color, Double)] = [
        ("accentSoft",         DesignTokens.accentSoft,         Color(hex: "#FFD60A"), 0.16),
        ("label2",             DesignTokens.label2,             Color(hex: "#DCDFEE"), 0.56),
        ("label3",             DesignTokens.label3,             Color(hex: "#DCDFEE"), 0.32),
        ("label4",             DesignTokens.label4,             Color(hex: "#DCDFEE"), 0.16),
        ("separatorHairline",  DesignTokens.separatorHairline,  Color.white,           0.05),
        ("separatorEdge",      DesignTokens.separatorEdge,      Color.black,           0.30),
        ("glassBorder",        DesignTokens.glassBorder,        Color.white,           0.025),
        // Plan 04 — neumorphic shadow/rim/hairline tokens (dark branch = legacy white/black opacity).
        ("neuOuterHighlight",         DesignTokens.neuOuterHighlight,         Color.white, 0.05),
        ("neuOuterShade",             DesignTokens.neuOuterShade,             Color.black, 0.55),
        ("neuOuterHighlightFloat",    DesignTokens.neuOuterHighlightFloat,    Color.white, 0.055),
        ("neuOuterShadeFloat",        DesignTokens.neuOuterShadeFloat,        Color.black, 0.62),
        ("neuRimTop",                 DesignTokens.neuRimTop,                 Color.white, 0.07),
        ("neuRimBottom",              DesignTokens.neuRimBottom,              Color.black, 0.35),
        ("neuInnerShade",             DesignTokens.neuInnerShade,             Color.black, 0.55),
        ("neuInnerRise",              DesignTokens.neuInnerRise,              Color.white, 0.05),
        ("neuHairlineDark",           DesignTokens.neuHairlineDark,           Color.black, 0.45),
        ("neuHairlineLight",          DesignTokens.neuHairlineLight,          Color.white, 0.04),
        ("neuButtonHighlight",        DesignTokens.neuButtonHighlight,        Color.white, 0.04),
        ("neuButtonShade",            DesignTokens.neuButtonShade,            Color.black, 0.62),
        ("neuButtonShadePressed",     DesignTokens.neuButtonShadePressed,     Color.black, 0.25),
        ("neuButtonShadePressedSoft", DesignTokens.neuButtonShadePressedSoft, Color.black, 0.20),
        // Plan 05 — instrument-window dish chrome + EmbossedBar emboss (dark = legacy opacity).
        ("dishInnerShade",            DesignTokens.dishInnerShade,            Color.black, 0.55),
        ("dishInnerRise",             DesignTokens.dishInnerRise,             Color.white, 0.06),
        ("dishHairlineDark",          DesignTokens.dishHairlineDark,          Color.black, 0.50),
        ("dishHairlineLight",         DesignTokens.dishHairlineLight,         Color.white, 0.04),
        ("dishWellShade",             DesignTokens.dishWellShade,             Color.black, 0.35),
        ("embossTop",                 DesignTokens.embossTop,                 Color.white, 0.28),
        ("embossBottom",              DesignTokens.embossBottom,              Color.black, 0.28),
        // Plan 06 — trend-inset hairline (dark = AnalyticsTrendChart's prior black.45/white.03).
        ("dishInsetHairDark",         DesignTokens.dishInsetHairDark,         Color.black, 0.45),
        ("dishInsetHairLight",        DesignTokens.dishInsetHairLight,        Color.white, 0.03),
        // Plan 06 — IconTile glyph (dark = #16161C@0.85) + segmented-control chrome.
        ("iconTileGlyph",             DesignTokens.iconTileGlyph,             Color(hex: "#16161C"), 0.85),
        ("segRimTop",                 DesignTokens.segRimTop,                 Color.white, 0.06),
        ("segRimBottom",              DesignTokens.segRimBottom,              Color.black, 0.30),
        ("segTrackRise",              DesignTokens.segTrackRise,              Color.white, 0.03),
        // Plan 06 — AI breathing-orb core specular (dark = white@0.9 verbatim).
        ("aiVioletOrbCore",           DesignTokens.aiVioletOrbCore,           Color.white, 0.9),
    ]

    @Test("plain token resolves in dark exactly to its pre-refactor hex",
          arguments: plain)
    func darkIdentityPlain(name: String, token: Color, hex: String) {
        let darkEnv = env(.dark)
        #expect(token.resolve(in: darkEnv) == Color(hex: hex).resolve(in: darkEnv),
                "\(name) drifted in dark")
    }

    @Test("alpha token resolves in dark exactly to its legacy composite",
          arguments: alpha)
    func darkIdentityAlpha(name: String, token: Color, base: Color, opacity: Double) {
        let darkEnv = env(.dark)
        #expect(token.resolve(in: darkEnv) == base.opacity(opacity).resolve(in: darkEnv),
                "\(name) drifted in dark")
    }
}

// MARK: - Adaptive factory environment-driven resolution (Phase 17, A1/A3)

@MainActor
struct AdaptiveFactoryTests {

    @Test("Color.adaptive resolves light vs dark branch by environment (A1)")
    func resolvesByEnvironment() {
        let lightEnv = env(.light)
        let darkEnv = env(.dark)
        let pair = Color.adaptive(light: "#FFFFFF", dark: "#000000")

        #expect(pair.resolve(in: lightEnv) == Color(hex: "#FFFFFF").resolve(in: lightEnv),
                "light env must resolve the light branch")
        #expect(pair.resolve(in: darkEnv) == Color(hex: "#000000").resolve(in: darkEnv),
                "dark env must resolve the dark branch")
    }

    @Test("adaptive dark branch is component-identical to legacy Color(hex:) (A3)")
    func darkBranchMatchesLegacyParser() {
        let darkEnv = env(.dark)
        let pair = Color.adaptive(light: "#E3E6EE", dark: "#1C1C23")
        #expect(pair.resolve(in: darkEnv) == Color(hex: "#1C1C23").resolve(in: darkEnv))
    }
}

// MARK: - Contrast helper self-test (Phase 17)

@MainActor
struct ContrastHelperTests {

    @Test("white-on-black contrast ratio is 21.0")
    func whiteOnBlackIs21() {
        let lightEnv = env(.light)
        let white = Color.white.resolve(in: lightEnv)
        let black = Color.black.resolve(in: lightEnv)
        #expect(abs(contrastRatio(white, black) - 21.0) < 0.01)
    }
}

// MARK: - Light-palette WCAG floors (Phase 17 Plan 02 — D-08/09/10/12/13/15)

/// Locks the LIGHT-scheme palette contrast floors as executable regression tests. Future
/// on-device tuning (Plans 04-07) may change the light hexes, but these floors MUST stay green.
/// Tokens resolve in an explicit LIGHT `EnvironmentValues` via the file-internal contrastRatio,
/// except dish readouts (see note below).
@MainActor
struct ContrastTests {

    /// Semantic delta-text tokens that render as small text on the light canvas (D-10).
    nonisolated static let semantics: [(String, Color)] = [
        ("positive", DesignTokens.positive),
        ("negative", DesignTokens.negative),
        ("orange",   DesignTokens.orange),
    ]

    /// 11 category colors — icons/tiles/fills, WCAG non-text floor (D-09). Where a category
    /// renders SMALL TEXT on light, later plans may deepen the twin further.
    nonisolated static let categories: [(String, Color)] = [
        ("catGroceries",     DesignTokens.catGroceries),
        ("catDining",        DesignTokens.catDining),
        ("catFuel",          DesignTokens.catFuel),
        ("catUtilities",     DesignTokens.catUtilities),
        ("catRent",          DesignTokens.catRent),
        ("catAuto",          DesignTokens.catAuto),
        ("catShopping",      DesignTokens.catShopping),
        ("catHealth",        DesignTokens.catHealth),
        ("catSubscriptions", DesignTokens.catSubscriptions),
        ("catEntertainment", DesignTokens.catEntertainment),
        ("catOther",         DesignTokens.catOther),
    ]

    /// Contrast of `fg` on `bg`, both resolved in the same scheme (default light).
    private func ratio(_ fg: Color, on bg: Color, _ scheme: ColorScheme = .light) -> Double {
        let e = env(scheme)
        return contrastRatio(fg.resolve(in: e), bg.resolve(in: e))
    }

    @Test("accentText ≥ 4.5:1 on bgCanvas — small text/icon accent (D-08)")
    func accentTextFloor() {
        #expect(ratio(DesignTokens.accentText, on: DesignTokens.bgCanvas) >= 4.5)
    }

    @Test("semantic delta text ≥ 4.5:1 on bgCanvas (D-10)", arguments: semantics)
    func semanticFloors(name: String, token: Color) {
        #expect(ratio(token, on: DesignTokens.bgCanvas) >= 4.5,
                "\(name) below 4.5:1 on the light canvas")
    }

    @Test("aiVioletText ≥ 4.5:1 on bgCanvas — sparkle/text violet (D-15)")
    func aiVioletTextFloor() {
        #expect(ratio(DesignTokens.aiVioletText, on: DesignTokens.bgCanvas) >= 4.5)
    }

    @Test("label ≥ 7.0:1 on bgCanvas — primary text")
    func labelFloor() {
        #expect(ratio(DesignTokens.label, on: DesignTokens.bgCanvas) >= 7.0)
    }

    @Test("category color ≥ 3.0:1 on bgCanvas — icons/tiles/fills (D-09)",
          arguments: categories)
    func categoryFloors(name: String, token: Color) {
        #expect(ratio(token, on: DesignTokens.bgCanvas) >= 3.0,
                "\(name) below 3.0:1 on the light canvas")
    }

    // D-09: the LIGHT IconTile glyph is a white symbol on a DEEPENED category twin. Assert the
    // worst case — the lightest twin (catOther #475569) — clears the 3.0:1 non-text floor so the
    // glyph stays legible on every tile in light mode.
    @Test("iconTileGlyph (light) ≥ 3.0:1 on the lightest category twin catOther — D-09")
    func iconGlyphOnLightestTile() {
        #expect(ratio(DesignTokens.iconTileGlyph, on: DesignTokens.catOther) >= 3.0)
    }

    @Test("accentOnYellow ≥ 4.5:1 on accent (canary CTA fill) — light env (D-08)")
    func ctaTextOnCanary() {
        #expect(ratio(DesignTokens.accentOnYellow, on: DesignTokens.accent) >= 4.5)
    }

    // D-13 (revised, user sign-off): in LIGHT the chart dishes are soft-white recessed wells
    // (neumorphism), NOT dark instrument windows. The dish CONTENT is no longer force-dark — it
    // resolves its LIGHT branch and renders MATTE on the light dish. We assert the actually-
    // rendered light pairing: the readout label (deep ink) and the matte chart curve on the
    // light dish must stay legible. Dark rendering is unchanged (force-dark override removed was
    // a no-op in dark; ambient is already dark — DarkBitIdentityTests cover token dark identity).
    @Test("label readout (light) ≥ 4.5:1 on dishSlate well (light) — D-13 matte-on-light")
    func labelOnDish() {
        let r = contrastRatio(DesignTokens.label.resolve(in: env(.light)),
                              DesignTokens.dishSlate.resolve(in: env(.light)))
        #expect(r >= 4.5)
    }

    @Test("matte chart curve (light) ≥ 3:1 on dishSlate well (light) — D-12 graphical")
    func accentOnDish() {
        // chartAmber light is the matte trend-curve hue; a graphical line clears the WCAG
        // non-text 3:1 bar against the light dish (it is no longer luminous amber on charcoal).
        let r = contrastRatio(DesignTokens.chartAmber.resolve(in: env(.light)),
                              DesignTokens.dishSlate.resolve(in: env(.light)))
        #expect(r >= 3.0)
    }
}
