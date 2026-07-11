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

    @Test("DesignTokens.tabBarClearance equals 100")
    func tabBarClearance() throws {
        #expect(DesignTokens.tabBarClearance == 100)
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
