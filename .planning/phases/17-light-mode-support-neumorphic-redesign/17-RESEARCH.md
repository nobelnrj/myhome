# Phase 17: Light Mode Support (Neumorphic Redesign) - Research

**Researched:** 2026-07-11
**Domain:** SwiftUI adaptive theming (light/dark) over a hand-built neumorphic design system; iOS 17+ deployment, Xcode 26.5
**Confidence:** HIGH (core mechanism empirically verified this session; palette values are tuning targets by design)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Theme control & default
- **D-01:** **Follow system + in-app override.** Remove the hard-coded
  `.preferredColorScheme(.dark)`; replace with an AppStorage-backed setting
  (System / Light / Dark). `System` follows iOS appearance; Light/Dark pin it.
- **D-02:** **Default = System.** On first launch after the update the app
  immediately follows the phone's appearance — no opt-in gate.
- **D-03:** **Settings UI = one segmented "Appearance" row** (System / Light /
  Dark neumorphic pill segments) near the top of Settings. No sub-screen.

#### Light canvas character
- **D-04:** **Classic neumorphic cool gray.** Canvas in the `#E3E6EE` family;
  raised cards slightly lighter with the same diagonal curvature-gradient
  scheme (lit top-left → shaded bottom-right); wells darker than canvas; label
  tiers dark cool (`#23252E`-family primary + opacity tiers). Exact values are
  planner/executor's to tune on device.
- **D-05:** **Depth matches dark's drama.** Same sculptural intent — clearly
  carved wells, plump raised pillows — re-tuned for light (gray-blue dark
  shadows, bright white highlights). The two themes should read as the same
  physical object under different lighting. All inline shadow values
  (NeuSurface rims, recessed overlays, button styles, EmbossedBar,
  VerticalPillGauge, NeuCircularWell/Puck) need light twins — these are
  scattered inline today, not centralized in ShadowSpec.
- **D-06:** **Dark mode stays PIXEL-IDENTICAL.** Light mode is purely
  additive. The token refactor (static hex → adaptive) must not shift dark
  rendering at all. Verify with before/after dark screenshots per screen.
- **D-07:** **System chrome tinted to match.** Native tab bar / nav bars /
  sheets get the light-gray canvas family tones — same structural approach as
  dark today (native bar, restyled colors only; no custom bar).

#### Accent & category colors (light variants)
- **D-08:** **Accent split by role.** Fills/pills/CTA buttons keep true canary
  `#FFD60A` with dark text on them (unchanged); accent-colored TEXT and ICONS
  switch to a darker amber (`#8A6D00` family) that passes WCAG contrast on the
  light canvas. Rationale: canary on light gray is ~1.4:1 — the handoff's own
  light skin darkens it (`tokens.jsx` mixes 72% accent + `#4a3500`).
- **D-09:** **Category palette deepened per-color** for light surfaces — each
  of the 11 categories gets a hand-tuned darker/saturated light twin (teal →
  deep teal `#0F9488`-ish, dining → burnt orange, etc.). Hue identity is
  preserved: groceries is teal in both themes. Applies to icons, tiles, text,
  and any category color rendered on a light surface.
- **D-10:** **Semantic colors deepened to match** — income green → deep
  emerald, spend red → firm crimson, warning orange → amber, tuned for small
  delta text legibility on light.
- **D-11 (scope clarifier):** Inside dark chart dishes (D-12/13) chart fills
  keep the ORIGINAL luminous dark-mode palette; the deepened variants (D-09/10)
  are for elements on light surfaces. Both variants coexist.

#### Orb, glow & chart-dish treatment
- **D-12:** **All chart dishes become dark "instrument windows"** in light
  mode — the hero orb dish, donut dish, budget-ring dish, and vertical
  pill-gauge wells all keep deep interiors so particle glows, neon fills, and
  luminous chart colors render as designed. The orb itself is unchanged.
- **D-13:** **Dish interiors are harmonized deep slate, NOT verbatim
  charcoal.** User explicitly corrected this: the porthole must adapt to the
  light theme — a light-theme-tuned deep slate/gray-blue (`#3E4250` family)
  instead of near-black `#16161C`. Dark enough for glow to read, soft enough
  to belong to the light palette (no "hole punched into dark mode").
- **D-14:** **Glow on light surfaces → subtle colored drop-shadow.** Elements
  that glow while sitting directly on cards (EmbossedBar fills, accent-glowing
  numbers/icons via `neonGlow`) replace the two-layer bloom with a faint
  tinted drop-shadow — a whisper of the neon language. Calibrate so it never
  reads as a rendering smudge.
- **D-15:** **AI Insight card: deepen violet + keep signature.** Edge-glow
  becomes a subtle deep-violet tinted shadow (consistent with D-14),
  sparkles/label switch to a darker violet passing contrast, breathing orb
  keeps its violet fill with reduced bloom. Violet stays AI-only (Phase 16
  D-04 unchanged).

### Claude's Discretion
- Theme-flip transition feel (D-01): default to SwiftUI's environment change;
  add a gentle crossfade only if the flip looks jarring on device; must honor
  Reduce Motion.
- All exact light hex values, shadow radii/opacities, and the slate dish tone —
  tune via the simulator screenshot loop ([[simulator-screenshot-verify-loop]]);
  the previews in this discussion are directional, not locked values.
- Token architecture (how static hexes become adaptive — e.g.
  `Color(light:dark:)` init, UITraitCollection-based dynamic colors, or a
  theme-environment struct) — planner's call, constrained by D-06
  (dark output must be bit-identical) and the AppStorage override (D-01),
  which means the mechanism must respect the app-level override, not just the
  system trait.

### Deferred Ideas (OUT OF SCOPE)
- App icon light/dark variants, notification styling, and any widget surfaces
  — not in this phase (no widgets exist; icon untouched).

#### Reviewed Todos (not folded)
- `test-isolation-swiftdata-multicontainer.md` — matched only on generic
  keywords (score 0.4); test-infra debt unrelated to light mode. Left pending.
</user_constraints>

<phase_requirements>
## Phase Requirements

No formal requirement IDs are mapped (ROADMAP says "Requirements: TBD"). Scope is
defined entirely by CONTEXT.md decisions D-01…D-15 above. REQUIREMENTS.md still
carries the v1.2 "Dark-mode-only" language (DS-05 and the "Light-mode variant"
out-of-scope entry) — the planner should note that this phase supersedes DS-05
by user decision (roadmap promotion 2026-06-27). `[VERIFIED: .planning/REQUIREMENTS.md grep]`

| Decision cluster | Research Support |
|------------------|------------------|
| D-01/D-02/D-03 (theme setting) | Pattern 2 (AppStorage → preferredColorScheme), Settings host verified |
| D-04/D-05/D-06 (adaptive tokens + shadows, dark bit-identity) | Pattern 1 (dynamic-provider token factory — empirically verified), Pattern 4 (shadow twins), D-06 test strategy |
| D-07 (system chrome) | Finding: NO bar-appearance code exists today; native bars auto-adapt (§Architecture Patterns / chrome) |
| D-08/D-09/D-10/D-11 (role-split accent, deepened palettes) | WCAG contrast table (computed this session), token-family design |
| D-12/D-13 (instrument-window dishes) | Pattern 3 (force-dark subtree — mechanism empirically verified) + dish-chrome ordering caveat |
| D-14/D-15 (glow adaptation) | Pattern 5 (scheme-aware neonGlow) |
</phase_requirements>

## Summary

The entire phase hinges on one architectural choice: how 60+ static
`DesignTokens` colors become scheme-adaptive without touching 62 consumer files
and without shifting a single dark pixel. Research resolves this decisively:
**keep every `DesignTokens.foo` static let, but construct it via
`Color(uiColor: UIColor { trait in ... })` (dynamic provider)**. I empirically
verified this session (SwiftUI `Color.resolve(in:)` probe) that
dynamic-provider-backed Colors resolve against the SwiftUI **environment**
colorScheme — which means (a) the root `preferredColorScheme` driven by an
AppStorage setting wins over the system trait, satisfying D-01, and (b) a
subtree `.environment(\.colorScheme, .dark)` override makes everything inside
a chart dish — tokens, category colors, `neonGlow` — resolve to the dark
variants automatically, which is the cleanest possible implementation of
D-11/D-12. The dark branch of every dynamic provider uses the exact same hex
the token has today, giving a machine-checkable D-06 guarantee: a unit test can
assert `token.resolve(in: darkEnv) == Color(hex: original).resolve(in: darkEnv)`
for every token, plus before/after screenshot diffs.

Second key finding: the codebase has **zero** `UITabBarAppearance` /
`UINavigationBarAppearance` / `toolbarBackground` code — "Phase 14 restyled the
native bars" is in fact just `.tint(DesignTokens.accent)` at RootView plus the
system's own dark appearance under the forced dark scheme. So D-07 likely costs
nothing: removing the forced scheme lets native bars auto-adapt; only if
screenshots show the default light bar clashing with the `#E3E6EE` canvas does
the planner add appearance customization. Third: the real work volume is the
inline shadow audit — ~40 inline `.white.opacity()/.black.opacity()` values
across NeuSurface.swift, DonutChart.swift, AnalyticsView/TrendChart,
SpendOverTimeChart, NetWorthTrendChart, BudgetsView, plus 5 hardcoded hexes in
feature files — each needs promotion to a named adaptive token (dark twin =
current value verbatim).

**Primary recommendation:** Dynamic-provider token factory in DesignTokens.swift
(dark = current hex verbatim), AppStorage-backed `preferredColorScheme` at root,
`.environment(\.colorScheme, .dark)` on dish content, and a two-layer D-06 gate
(resolve-based unit tests + status-bar-pinned screenshot byte/pixel diff).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Theme persistence (System/Light/Dark) | App root (`MyHomeApp.swift`) via `@AppStorage` | Settings UI (writes the same key) | Single source of truth; root is where `preferredColorScheme` must be applied |
| Scheme resolution (which palette renders) | SwiftUI environment (colorScheme) | — | `preferredColorScheme` sets the window-wide environment; all tokens resolve against it |
| Adaptive color values | `DesignTokens.swift` (design-system layer) | `Color+Hex.swift` (factory helper) | Tokens stay the single source of truth; 62 consumer files untouched |
| Neumorphic surface shadows/rims | `NeuSurface.swift` (design-system layer) | Feature files with inline values (audit list below) | Inline values get promoted to named tokens, not per-view scheme reads |
| Instrument-window (force-dark) subtrees | `NeuCircularWell` / gauge components | Feature call sites (trend-chart plot insets) | The component that owns the dish owns the environment override |
| Glow language switch (bloom vs drop-shadow) | `neonGlow` modifier in DesignTokens.swift | AIInsightCard (violet variants) | One `@Environment(\.colorScheme)` read inside the modifier covers all call sites |
| System chrome (tab/nav bars, sheets, keyboard) | iOS native appearance (auto-adapts) | Optional `UITabBarAppearance` only if screenshots demand | No appearance code exists today `[VERIFIED: codebase grep]` |
| Verification (dark bit-identity, light contrast) | Unit tests (`Color.resolve(in:)`) + simulator screenshot loop | — | resolve-based tests are deterministic; screenshots catch render-level drift |

## Standard Stack

### Core

No new libraries. The phase is implemented entirely with APIs already linked by the app:

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 17 SDK (Xcode 26.5) | `preferredColorScheme`, `@AppStorage`, `.environment(\.colorScheme,...)`, `Color.resolve(in:)` (iOS 17+) | Already the app's UI framework; `resolve(in:)` is in-target (deployment floor is 17.0) `[VERIFIED: xcodebuild -version; project deployment target]` |
| UIKit | iOS 17 SDK | `UIColor(dynamicProvider:)` — the only way to build a light/dark Color pair that SwiftUI resolves per-environment | SwiftUI has no native `Color(light:dark:)` init `[CITED: jessesquires.com/blog/2023/07/11/creating-dynamic-colors-in-swiftui]` — already imported in DesignTokens.swift |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `UIColor(dynamicProvider:)`-backed static lets | Theme struct injected via `@Environment` | Changes call-site syntax across 62 files (`tokens.foo` needs an environment read per view); rejected — CONTEXT explicitly prefers preserving `DesignTokens.foo` |
| Same | Custom `ShapeStyle` with `resolve(in:)` (iOS 17) `[CITED: blog.kylelanchman.com/dynamic-colors-in-swiftui-using-shapestyle-in-ios-17]` | Definitively environment-driven, but produces a ShapeStyle, not a `Color` — breaks `Color`-typed call sites (`.shadow(color:)`, `VerticalPillGauge(color:)`, gradient arrays). Usable spot-wise, not as the token mechanism |
| Same | Asset-catalog color sets (Any/Dark) | Also dynamic-provider under the hood, but 60+ colorsets are unreviewable in PRs, values live outside DesignTokens.swift, and pbxproj churn risk; rejected |
| Same | Static computed properties reading `UITraitCollection.current` | `UITraitCollection.current` is only valid during UIKit draw callbacks — wrong/stale in SwiftUI render and in tests; rejected `[ASSUMED]` (well-known UIKit contract) |

**Installation:** none — no packages.

## Package Legitimacy Audit

This phase installs **no external packages** (all work is in-repo Swift against
Apple SDKs already linked). No slopcheck run required.

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
                         ┌──────────────────────────────────────────┐
 iOS system appearance ─►│ MyHomeApp.swift (root)                   │
                         │  @AppStorage("appearanceTheme")          │
 Settings "Appearance"──►│  = system | light | dark                 │
 segmented row (D-03)    │  .preferredColorScheme(mapped value)     │
                         └──────────────┬───────────────────────────┘
                                        │ sets window-wide environment colorScheme
                                        ▼
              ┌──────────────────────────────────────────────────────┐
              │ SwiftUI Environment (colorScheme = .light / .dark)   │
              └──────┬──────────────────────┬────────────────────────┘
                     │ resolves             │ resolves
                     ▼                      ▼
      ┌──────────────────────────┐   ┌─────────────────────────────┐
      │ DesignTokens statics     │   │ Native chrome (tab bar, nav │
      │ (dynamic-provider pairs: │   │ bars, sheets, keyboard) —   │
      │  dark = current hex,     │   │ auto-adapts; optional bar-  │
      │  light = new twin)       │   │ appearance tint (D-07)      │
      └──────┬───────────────────┘   └─────────────────────────────┘
             │ consumed unchanged by 62 files
             ▼
   ┌────────────────────────────────────────────────────────────┐
   │ Feature views (Overview, Budgets, Analytics, Notes, …)     │
   │                                                            │
   │  ┌───────────────────────────────────────────────┐         │
   │  │ Chart dishes (NeuCircularWell, pill wells,    │         │
   │  │ trend plot insets):                           │         │
   │  │  • dish CHROME = adaptive slate token (D-13)  │         │
   │  │  • dish CONTENT wrapped in                    │         │
   │  │    .environment(\.colorScheme, .dark) →       │         │
   │  │    tokens + neonGlow inside resolve DARK      │         │
   │  │    (luminous palette, full bloom) (D-11/12)   │         │
   │  └───────────────────────────────────────────────┘         │
   └────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

No new files required — everything extends existing files (avoids the 4-edit
pbxproj tax `[VERIFIED: memory xcodeproj-explicit-file-refs]`):

```
MyHomeApp/
├── Support/Color+Hex.swift          # add UIColor(hex:alpha:) + Color.adaptive(light:dark:) factory
├── DesignSystem/DesignTokens.swift  # tokens become adaptive pairs; new named shadow/rim tokens;
│                                    #   AppearanceTheme enum; scheme-aware neonGlow
├── DesignSystem/NeuSurface.swift    # inline shadow values → named tokens; dish env override
├── MyHomeApp.swift                  # @AppStorage theme + preferredColorScheme(mapped)
└── Features/Settings/SettingsView.swift  # Appearance segmented row (D-03)
MyHomeTests/DesignTokensTests.swift  # D-06 resolve-based bit-identity tests + contrast tests
```

### Pattern 1: Dynamic-provider token factory (the core mechanism)

**What:** Replace each `static let foo = Color(hex: "#…")` with the same static
let built from a light/dark pair, where the **dark branch is the current hex
verbatim**.

**When to use:** Every DesignTokens color, every promoted inline shadow value.

**Empirical verification (this session):** A dynamic-provider-backed Color
resolved via `Color.resolve(in:)` returns the **light variant when
`EnvironmentValues.colorScheme == .light` and the dark variant when `.dark`** —
proven with a compiled SwiftUI probe (macOS analog `NSColor(name:dynamicProvider:)`;
same SwiftUI resolution machinery). `[VERIFIED: compiled probe, scratchpad/probe.swift — printed light #E6E6E6 / dark #1A1A1A from one Color]`
Consequences:
- Root `preferredColorScheme` (which sets the environment window-wide
  `[CITED: nilcoalescing.com/blog/ReadingAndSettingColorSchemeInSwiftUI]`) drives token
  resolution → the AppStorage override wins over the system trait (D-01). ✔
- A subtree `.environment(\.colorScheme, .dark)` flips every token inside it to
  the dark variant (Pattern 3 / D-11-12). ✔
- iOS-simulator smoke check of the same behavior should still be an early
  execution step (the probe used AppKit's color type). `[ASSUMED: iOS parity — near-certain, verify in Wave 1]`

**Example:**

```swift
// Support/Color+Hex.swift — extend, don't create a new file
extension UIColor {
    /// 6-digit hex + alpha, same parsing contract as Color(hex:).
    convenience init(hex: String, alpha: CGFloat = 1) { /* same parser, sRGB */ }
}

extension Color {
    /// Adaptive pair. DARK branch must be the token's current hex verbatim (D-06).
    static func adaptive(light: String, lightAlpha: CGFloat = 1,
                         dark: String,  darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: dark,  alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

// DesignTokens.swift — call sites in 62 files unchanged
static let bgCanvas = Color.adaptive(light: "#E3E6EE", dark: "#1C1C23")
// Opacity tiers: bake alpha into the pair (per-scheme opacity becomes possible)
static let label2 = Color.adaptive(light: "#23252E", lightAlpha: 0.62,
                                   dark: "#DCDFEE",  darkAlpha: 0.56)
```

**D-06 note on bit-identity:** current `Color(hex:)` produces
`Color(red:g:b:)`; `UIColor(red:green:blue:alpha:)` uses the same extended-sRGB
components, so dark-resolved output is component-identical. Lock this with the
resolve-based unit test (below) rather than trusting the reasoning. `[ASSUMED → test-enforced]`

### Pattern 2: AppStorage-backed root scheme (D-01/D-02)

```swift
// DesignTokens.swift (or MyHomeApp.swift) — no new file
enum AppearanceTheme: String, CaseIterable {
    case system, light, dark
    var colorScheme: ColorScheme? {   // nil = follow system
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

// MyHomeApp.swift — replaces line 34's .preferredColorScheme(.dark)
@AppStorage("appearanceTheme") private var appearanceThemeRaw = AppearanceTheme.system.rawValue

RootView(gmailSyncController: gmailSyncController)
    .preferredColorScheme((AppearanceTheme(rawValue: appearanceThemeRaw) ?? .system).colorScheme)
```

- `nil` = system-following; passing a value pins it — the documented contract
  `[CITED: developer.apple.com/documentation/swiftui/view/preferredcolorscheme(_:)]`.
- Store in `UserDefaults.standard` (plain `@AppStorage`): no widget/extension
  reads the theme, so the App Group suite (used by LockController) is
  unnecessary. `[VERIFIED: no extensions/widgets in project]`
- Default `.system` satisfies D-02 with zero migration (missing key → system).
- Settings row (D-03): a custom neumorphic 3-segment pill in SettingsView bound
  to the same `@AppStorage` key — `@AppStorage` in both places observes the same
  default's key, so the root updates live when the row changes.

### Pattern 3: Force-dark dish subtree (D-11/D-12/D-13)

**What:** The dish component keeps its chrome on adaptive tokens (slate in
light), and wraps only its **content** in `.environment(\.colorScheme, .dark)`
so every adaptive token, category color, and `neonGlow` inside resolves to the
original luminous dark values.

```swift
// NeuCircularWell.swift body (conceptual)
ZStack {
    dishChrome            // fills/inner shadows use ADAPTIVE tokens:
                          //   dark: #15151B (verbatim today) / light: #3E4250-family slate (D-13)
        .drawingGroup()
    content()
        .environment(\.colorScheme, .dark)   // D-11: luminous palette + full neonGlow bloom
}
```

- `.environment(\.colorScheme, .dark)` scopes downward only (does not leak up)
  `[CITED: nilcoalescing.com/blog/ReadingAndSettingColorSchemeInSwiftUI]`; verified to drive
  dynamic-provider Color resolution `[VERIFIED: compiled probe]`.
- Apply the same treatment to: `NeuCircularWell` (hero orb 300, donut 236,
  net-worth 236, budget ring 136 — all call sites found
  `[VERIFIED: grep — BudgetsView:278, NetWorthCard:53, SpendDonutCard:46, SpendBudgetCard:95]`),
  `VerticalPillGauge`, and the trend-chart recessed plot insets
  (`AnalyticsTrendChart` uses a `fillRecessed` plot inset `[VERIFIED: AnalyticsTrendChart.swift:56-61]`).
- **Ordering matters:** the override goes on `content()` only — putting it on
  the whole ZStack would force the dish chrome itself to dark (`#15151B`
  charcoal), which is exactly the "hole punched into dark mode" D-13 forbids.
- **Boundary decision for the planner:** D-12 enumerates orb/donut/budget-ring
  dishes + pill-gauge wells. Trend charts (`SpendOverTimeChart` renders on a
  `.raised` card `[VERIFIED: SpendOverTimeChart.swift:122]`; `AnalyticsTrendChart`
  and `NetWorthTrendChart` sit in/on recessed insets) are not explicitly
  enumerated — but the user's intent was "ALL charts in deep dishes"
  (CONTEXT §specifics). Recommend: treat every recessed plot inset as an
  instrument window; `SpendOverTimeChart` needs a recessed inset added or its
  luminous amber `#FFB43C` line/glow swapped to a deepened twin. Flag as an
  explicit plan decision, tune on device.
- **EmbossedBar tracks are NOT dishes** — D-14 names "EmbossedBar fills" as
  glow-on-light-surface elements, so its track becomes a light-tuned recessed
  well and its fill uses deepened colors + tinted drop-shadow.

### Pattern 4: Inline shadow values → named adaptive tokens (D-05)

**What:** Every inline `.white.opacity(x)` / `.black.opacity(y)` in the
neumorphic recipes becomes a named DesignTokens adaptive color whose dark
branch is white/black at the exact current alpha (bit-identical), and whose
light branch is the gray-blue-shadow / bright-white-highlight twin.

**Keep geometry frozen:** radii, offsets, blur, and lineWidths stay
scheme-invariant in the first pass — only colors adapt. This keeps dark
rendering structurally untouchable and avoids `@Environment` reads inside
NeuSurface (any env read is a new re-render dependency). If on-device tuning
proves light needs different radii, add a scheme read then — the dark branch
must return today's exact values.

**Complete inline-color audit** `[VERIFIED: grep this session]`:

| File | What | Light treatment |
|------|------|-----------------|
| `DesignSystem/NeuSurface.swift` | RimOverlay (w.07/b.35), RecessedOverlay (b.55/w.05/hairline b.45–w.04), both ButtonStyles (rims w.45/.15, shadows w.04/b.62/b.25/b.20), EmbossedBar track (b.35/b.55/w.04) + fill emboss (w.28/b.28), VerticalPillGauge well (b.35/b.55/w.04) + fill sheen (w.35), NeuCircularWell (b.55/w.06/hairline b.50–w.04), NeuCircularPuck (w.05/b.55/rim w.07–b.35), CTA hexes `#231B00/#E8C918/#D9B000/#FFE04A/#F2C500` | Named tokens; light twins tuned on device. CTA yellows likely unchanged (canary fills keep identity per D-08); CTA outer black shadow needs a light twin |
| `Features/Shared/DonutChart.swift` (incl. GlowParticleRing) | Dish gradients b.45/.30/.88/.62/.32, w.07 (lines 405–488) | Inside instrument windows — harmonize with slate chrome (D-13), NOT forced by env override (chrome layer) |
| `Features/Analytics/AnalyticsView.swift` | Range-picker pill rims/shadows (w.06/b.30/b.45/b.45–w.03) | Standard light twins (on-surface control) |
| `Features/Analytics/AnalyticsTrendChart.swift` | Plot-inset hairline (b.45/w.03), point shadow (b.5), gridlines w.045, luminous `#FFB43C` line + glow | Instrument-window candidate (see Pattern 3 boundary decision) |
| `Features/Overview/SpendOverTimeChart.swift` | Gridlines w.045 ×2, `#FFB43C` gradient + glow | Same boundary decision |
| `Features/Assets/NetWorthTrendChart.swift` | Gridlines w.045 ×2 | Same |
| `Features/Budgets/BudgetsView.swift` | Ring track b.18 | Inside budget-ring dish (instrument window) |
| `Features/Analytics/AIInsightCard.swift` | Sparkle gradient w.90 + violet glow | D-15 treatment |
| `Features/Shared/IconTile.swift` | Glyph `#16161C`.opacity(0.85) on category fill | On deepened light category fills, a dark glyph still works — verify; possibly needs white glyph on the deepest twins `[ASSUMED]` |
| `Features/Settings/Account*.swift`, `MergeAccountView.swift` | `Color(hex: account.colorHex ?? "#636366")` — user data, not tokens | Account colors are user-chosen; audit the picker palette for light legibility, don't adapt stored data |

### Pattern 5: Scheme-aware neonGlow (D-14)

```swift
// DesignTokens.swift — neonGlow becomes a ViewModifier so it can read the environment
private struct NeonGlowModifier: ViewModifier {
    let color: Color; let radius: CGFloat; let intensity: Double
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        if scheme == .dark {
            // EXACT current two-layer bloom — dark path unchanged (D-06)
            content
                .shadow(color: color.opacity(0.55 * intensity), radius: radius * 0.55)
                .shadow(color: color.opacity(0.32 * intensity), radius: radius * 1.5)
        } else {
            // D-14: single faint tinted drop-shadow (values tuned on device)
            content.shadow(color: color.opacity(0.28 * intensity), radius: radius * 0.7, y: 2)
        }
    }
}
```

- Inside force-dark dishes the env reads `.dark` → full bloom is preserved
  automatically (synergy with Pattern 3).
- Call sites `[VERIFIED: grep]`: BudgetProgressView:50, BudgetsView:263,
  OverviewView:354, AIInsightCard:150 — no call-site changes needed.
- AIInsightCard (D-15) additionally needs a deepened violet text/sparkle token
  (`aiVioletText` adaptive pair) — see contrast table.

### System chrome (D-07) — likely zero-code

`[VERIFIED: grep]` There is **no** `UITabBarAppearance` / `UINavigationBarAppearance` /
`toolbarBackground` / `toolbarColorScheme` code anywhere. Today's "restyled
native bar" = the system dark bar + `.tint(DesignTokens.accent)`
(RootView:102). Therefore:
1. Removing the forced dark scheme lets bars/sheets/keyboard auto-adapt to the
   resolved scheme — the "same structural approach" D-07 asks for.
2. `.tint(DesignTokens.accent)` at RootView drives tab selection color. Per
   D-08 the selected-tab ICON/label is accent-colored **iconography on a light
   bar** → should use the role-split `accentText` token (dark amber in light,
   canary in dark) — one-line change, and `.tint` accepts the adaptive Color.
3. Only if screenshots show the default light bar material clashing with
   `#E3E6EE` should the planner add `UITabBarAppearance`/`UINavigationBarAppearance`
   with dynamic `UIColor`s (set once in an init — they accept dynamic providers).
4. Note: building with the iOS 26 SDK, native bars on the iOS 26 simulator
   render the system's current bar material in both schemes — this is already
   shipped behavior in dark; light inherits the same treatment. `[ASSUMED]`

### Anti-Patterns to Avoid

- **`@Environment(\.colorScheme)` reads scattered through feature views:** the
  codebase has zero today `[VERIFIED: grep]`; keep it that way. Only three
  legitimate read sites: `NeonGlowModifier`, (optionally) NeuSurface if light
  geometry must diverge, and nothing else. Everything else adapts via tokens.
- **Per-scheme `if` at call sites** (`scheme == .dark ? tokenA : tokenB`) —
  defeats the token system and risks dark drift.
- **`UITraitCollection.current` in static computed properties** — stale outside
  UIKit draw callbacks; the dynamic provider closure receives the correct trait.
- **Two parallel token enums** (`DesignTokensLight`) — doubles the audit
  surface and forces call-site switching; rejected by the 62-file constraint.
- **Forcing `.environment(\.colorScheme, .dark)` on whole cards** to "save
  work" — creates the charcoal-hole effect D-13 explicitly forbids.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Light/dark color pairs | Custom theme-environment plumbing / notification-driven repaint | `UIColor(dynamicProvider:)` bridged to `Color` | OS-native trait resolution; SwiftUI resolves it per-environment (verified); animates correctly on scheme flips |
| Theme override | Manual `overrideUserInterfaceStyle` window walking | `.preferredColorScheme()` at root | Documented SwiftUI contract; nil = system; propagates through the presentation `[CITED: Apple docs]` |
| Per-scheme color assertions in tests | Screenshot-only verification | `Color.resolve(in: EnvironmentValues)` (iOS 17) | Deterministic, fast, runs in the existing Swift Testing suite `[CITED: blog.kylelanchman.com — iOS 17 resolve API]` |
| Contrast checking | Eyeballing | WCAG relative-luminance formula in a unit test (20 lines) | Ratios computed this session (table below) become executable regression tests |
| Scheme flip in simulator | Reinstalling / device Settings spelunking | `xcrun simctl ui <device> appearance light\|dark` | Verified available in this Xcode 26.5 toolchain `[VERIFIED: simctl help]` |
| Deterministic screenshots | Accepting clock/battery noise in diffs | `xcrun simctl status_bar <device> override --time 9:41 …` | Verified available `[VERIFIED: simctl help]` |

**Key insight:** every hand-rolled theming layer eventually fights the OS trait
system (sheets, keyboard, UIKit-hosted views). The dynamic-provider approach
delegates all of that to UIKit/SwiftUI and reduces this phase to "author the
light values."

## Common Pitfalls

### Pitfall 1: `hexString` / token tests break silently under dynamic colors
**What goes wrong:** `DesignTokensTests.accentColorMatchesSpec` does
`UIColor(token).getRed(...)` which resolves a dynamic color against
`UITraitCollection.current` — in a test process that's typically **light**, so
tests would start asserting against light variants (or flap).
`[VERIFIED: MyHomeTests/DesignTokensTests.swift:14 uses hexString]`
**How to avoid:** rewrite token tests to resolve explicitly:
`UIColor(token).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))`
or SwiftUI `token.resolve(in: darkEnv)`. Make this the D-06 unit gate (test
every token's dark resolution equals its pre-refactor hex).
**Warning signs:** DesignTokensTests failing/passing depending on machine appearance.

### Pitfall 2: Dark drift from "harmless" refactor differences (D-06 killer)
**What goes wrong:** replacing `Color(hex:).opacity(0.56)` with a baked-alpha
dynamic color, or swapping `Color(red:g:b:)` for `UIColor(red:g:b:a:)`, can
shift resolved components if color spaces differ (sRGB vs extended sRGB vs P3).
**How to avoid:** (1) the adaptive factory's dark branch must parse with the
same 6-digit sRGB math as `Color(hex:)`; (2) unit test: for EVERY token,
`newToken.resolve(in: darkEnv) == legacyColor.resolve(in: darkEnv)` exact
component equality; (3) screenshot byte-diff with pinned status bar.
**Warning signs:** resolve test exact-equality failures at the 3rd decimal.

### Pitfall 3: Animated regions make "pixel-identical" screenshot diffs impossible
**What goes wrong:** the hero orb (`GlowParticleRing` is TimelineView-driven),
`entrance()` cascades, and `contentTransition(.numericText())` counters mean
two screenshots of Overview are never byte-identical even with zero code change.
**How to avoid:** pin `status_bar override --time`; screenshot after a settle
delay (entrance caps at ~0.36s + spring); diff with PIL (installed
`[VERIFIED: PIL 11.3.0]`; ImageMagick absent) and **mask the orb dish region**
(fixed 300pt circle position) or compare orb-free screens byte-exact and the
Overview screen with a masked diff + eyeball pass. Alternatively capture with
Reduce Motion? — does not stop TimelineView; masking is the reliable route.
**Warning signs:** diffs failing only in the dish circle.

### Pitfall 4: Force-dark dish override applied at the wrong layer
**What goes wrong:** wrapping the whole `NeuCircularWell` (chrome included) in
`.environment(\.colorScheme, .dark)` renders the dish interior `#15151B`
charcoal in light mode — precisely the D-13-forbidden "hole into dark mode."
Conversely, forgetting the override on content leaves donut segments rendered
in deepened light category colors on a slate dish (muddy, violates D-11).
**How to avoid:** override on `content()` only; dish chrome fills/inner shadows
use the adaptive slate tokens. Add a light-mode preview of each dish component.
**Warning signs:** dishes look near-black in light screenshots; chart fills look
dull inside dishes.

### Pitfall 5: `drawingGroup()` + theme flips
**What goes wrong:** `NeuCircularWell` rasterizes its chrome via
`.drawingGroup()` `[VERIFIED: NeuSurface.swift:502]`. Rasterized layers
re-evaluate when the environment changes, but live theme flips (Settings
segmented row while the app is visible) should be verified for stale rasters /
un-animated jumps — and Metal rasterization can slightly alter blur compositing
vs the non-rasterized path (already true in dark, so no D-06 risk; only a
light-tuning consideration).
**How to avoid:** flip the theme live via the Settings row during on-device
verification (not only via simctl appearance + relaunch).
**Warning signs:** dish chrome not updating until scroll/relaunch after a flip.

### Pitfall 6: The accent role split (D-08) is a call-site audit, not a token swap
**What goes wrong:** `DesignTokens.accent` is used for BOTH fills (keep canary
in light) and text/icons (must become dark amber in light) — e.g.
`.tint(DesignTokens.accent)` renders button TEXT in accent across ~15 files
`[VERIFIED: grep .tint listing]`, while `Capsule().fill` and `accentSoft`
washes are fills. A blind adaptive `accent` breaks one role or the other.
**How to avoid:** introduce `accentText` (adaptive: dark amber / canary) and
keep `accent` as fill-canary in both schemes (still adaptive-capable but same
value); audit each `accent` call site into fill vs text/icon. `NeuSecondaryButtonStyle`
(accent text on raised pill) and RootView `.tint` are text-role.
`accentSoft` (0.16 wash) likely needs a light twin (~0.22 per handoff recipe
`[CITED: design/design_handoff_myhome_neumorphic/src/tokens.jsx lines ~69-74]`).
**Warning signs:** illegible canary text on light cards; brown CTA buttons.

### Pitfall 7: Sheets/covers and the root override
**What goes wrong:** `preferredColorScheme` set INSIDE a sheet affects only that
presentation `[CITED: nilcoalescing.com]`. The inverse direction — root-set scheme
propagating INTO sheets — works in the shipped app (all sheets render dark
today with the root-only modifier `[VERIFIED: shipped v1.2 behavior]`), but
verify one sheet (EditExpenseView) and one fullScreenCover/alert in pinned-Light
+ system-dark during Wave-1 smoke, since this combination is net-new.
**Warning signs:** a sheet rendering the opposite scheme from the host screen.

### Pitfall 8: Previews pin `.dark` and will hide light regressions
**What goes wrong:** NeuSurface.swift:594, RollingMoneyText.swift:74,
SpendBudgetCard.swift:268+284 pin dark previews `[VERIFIED: grep]` — light-mode
work would be invisible in previews.
**How to avoid:** add light variants (or paired `#Preview("Light")`) for the
design-system previews as part of the token work.

## Code Examples

### D-06 bit-identity unit test (the automated dark gate)

```swift
// MyHomeTests/DesignTokensTests.swift — Swift Testing, iOS 17 resolve API
import Testing
import SwiftUI
@testable import MyHome

@MainActor
struct DarkBitIdentityTests {
    // Legacy hex values captured BEFORE the refactor (source of truth for D-06)
    static let legacy: [(String, Color, String)] = [
        ("bgCanvas", DesignTokens.bgCanvas, "#1C1C23"),
        ("accent",   DesignTokens.accent,   "#FFD60A"),
        // … every color token
    ]

    @Test("every token resolves in dark exactly to its pre-refactor value",
          arguments: legacy)
    func darkIdentity(name: String, token: Color, hex: String) {
        var env = EnvironmentValues(); env.colorScheme = .dark
        let resolved = token.resolve(in: env)
        let expected = Color(hex: hex).resolve(in: env)
        #expect(resolved == expected, "\(name) drifted in dark")
    }
}
```
`[VERIFIED: resolve(in:) drives dynamic-provider resolution — compiled probe this session]`

### WCAG contrast regression test (light palette)

```swift
func contrastRatio(_ a: Color.Resolved, _ b: Color.Resolved) -> Double {
    func lum(_ c: Color.Resolved) -> Double {
        func f(_ v: Float) -> Double { let d = Double(v)
            return d <= 0.03928 ? d/12.92 : pow((d+0.055)/1.055, 2.4) }
        return 0.2126*f(c.red) + 0.7152*f(c.green) + 0.0722*f(c.blue)
    }
    let (l1, l2) = (lum(a), lum(b)); return (max(l1,l2)+0.05)/(min(l1,l2)+0.05)
}
// #expect(contrastRatio(accentText.resolve(in: lightEnv), bgCanvas.resolve(in: lightEnv)) >= 4.5)
```

### Simulator verification loop (D-06 + light tuning)

```bash
UDID="2F09365E-5099-490E-9484-B8788C53C816"   # iPhone 17 [VERIFIED: booted]
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100
xcrun simctl ui "$UDID" appearance dark        # or: light   [VERIFIED: simctl help]

xcodebuild -scheme MyHome -destination "id=$UDID" build   # scheme MyHome [VERIFIED: xcodebuild -list]
xcrun simctl install "$UDID" <path>/MyHome.app
xcrun simctl launch "$UDID" com.reojacob.myhome -seedSampleData -startTab 0
sleep 3   # let entrance cascade settle
xcrun simctl io "$UDID" screenshot dark-overview-after.png

# Pixel diff with masked orb region (PIL installed; ImageMagick is NOT)
python3 - <<'EOF'
from PIL import Image, ImageChops, ImageDraw
a, b = Image.open("dark-overview-before.png"), Image.open("dark-overview-after.png")
for im in (a, b):
    d = ImageDraw.Draw(im); d.ellipse(ORB_BBOX, fill=(0,0,0))  # mask animated dish
diff = ImageChops.difference(a.convert("RGB"), b.convert("RGB"))
print("identical outside mask:", diff.getbbox() is None)
EOF
```

### Settings appearance row (D-03 sketch)

```swift
// SettingsView.swift — new top Section, above Security (host verified: neumorphic List)
@AppStorage("appearanceTheme") private var appearanceThemeRaw = AppearanceTheme.system.rawValue

Section("Appearance") {
    // Custom neumorphic 3-segment pill (recessed track + raised active segment),
    // NOT a system Picker(.segmented) — matches the v2 pill-control language.
    AppearanceSegmentedRow(selection: $appearanceThemeRaw)
}
.listRowBackground(DesignTokens.surfaceRaised)
```

## WCAG Contrast Table (computed this session)

`[VERIFIED: WCAG 2.x relative-luminance formula, computed via script]` — these
justify the locked decisions and set the tuning floor. Thresholds: 4.5:1 normal
text, 3:1 large text & non-text UI (WCAG 1.4.3 / 1.4.11).

| Pair | Ratio | Verdict |
|------|-------|---------|
| `#FFD60A` canary text on `#E3E6EE` canvas | 1.13:1 | Fails — confirms D-08's rationale |
| `#8A6D00` amber text on `#E3E6EE` canvas | 3.94:1 | Passes 3:1 (large/icons); **fails 4.5:1 small text** — tune family darker: `#806400` = 4.50, `#755C00` = 5.12 |
| `#23252E` primary label on `#E3E6EE` | 12.23:1 | Passes AAA |
| `#0F9488` deep teal on `#E3E6EE` | 3.00:1 | Icons/graphics OK; small category TEXT needs ~`#0B6E66` (4.89) |
| `#2DD4BF` original teal on light canvas | 1.49:1 | Fails — confirms D-09 |
| `#34E29B` original green on light canvas | 1.35:1 | Fails — confirms D-10; `#047857` emerald = 4.39, `#065F46` = 6.15 |
| `#FF6B6B` original red on light canvas | 2.22:1 | Fails; `#DC2626` = 3.87, `#B91C1C` = 5.18 |
| `#FFB020` original orange on light canvas | 1.46:1 | Fails; `#B45309` = 4.02 |
| `#1A1404` on `#FFD60A` (CTA text, unchanged) | 12.98:1 | Passes — D-08 fill rule safe |
| `#ECEDF4` label on `#3E4250` slate dish | 8.57:1 | Dish readouts stay legible on slate |
| `#FFD60A` canary on `#3E4250` slate dish | 7.08:1 | Canary works inside dishes |
| `#2DD4BF` / `#34E29B` luminous fills on slate | 5.37 / 5.95:1 | D-13 slate is dark enough for the luminous palette |
| `#7C5CFF` original AI violet on light canvas | 3.48:1 | Icon-OK, text-fail; `#5B21B6` = 7.19 for D-15 text |

**Planner guidance:** where a deepened color is used for **small text** (delta
labels, category amounts), target ≥4.5:1; where only icons/tiles/chart fills,
≥3:1 suffices. Encode the final locked pairs as unit tests.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `colorScheme(_:)` modifier | `preferredColorScheme(_:)` | iOS 14 (old one deprecated) | Use preferred; nil = system-following |
| Trait-only dynamic colors (UIKit windows) | SwiftUI `Color.resolve(in: EnvironmentValues)` + `Color.Resolved` | iOS 17 | Enables deterministic unit-testing of adaptive tokens — the D-06 gate |
| Screenshot-only theme verification | resolve-based tests + masked pixel diffs | — | Two-layer gate; unit layer catches drift before a build |

**Deprecated/outdated:** nothing relevant removed in iOS 17–26 SDKs for these APIs. `[ASSUMED]`

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | iOS `UIColor(dynamicProvider:)`-backed Color behaves like the macOS `NSColor(name:dynamicProvider:)` probe (environment-driven resolution) | Pattern 1 | Core mechanism fails → fall back to custom ShapeStyle/theme-env; verify in Wave-1 simulator smoke (5 min) |
| A2 | Root `preferredColorScheme` propagates into sheets/covers on the iOS 26 simulator runtime (shipped dark app suggests yes) | Pitfall 7 | Sheets render wrong scheme when pinned ≠ system; fix = re-apply modifier on sheet roots |
| A3 | `UIColor(red:g:b:a:)` and `Color(red:g:b:)` resolve to identical components (extended sRGB) | Pitfall 2 | Dark drift — caught deterministically by the D-06 resolve tests |
| A4 | Native light bar material harmonizes with `#E3E6EE` canvas without appearance code | Chrome (D-07) | Add `UITabBarAppearance`/`UINavigationBarAppearance` with dynamic colors — bounded extra task |
| A5 | IconTile's dark glyph (`#16161C` @ 0.85) stays legible on deepened light category fills | Pattern 4 audit | Per-tile glyph color twin needed — small |
| A6 | Keyboard appearance and Face ID/system overlays follow the window's resolved scheme with no extra work | Pitfall 7 | Cosmetic; scoped fixes |
| A7 | `drawingGroup()` chrome re-renders on live theme flip | Pitfall 5 | Remove/condition drawingGroup or force id() on scheme — verify live-flip in Wave-1 |

## Open Questions (RESOLVED)

1. **Do the three trend charts get instrument-window treatment?** (D-12
   enumerates dishes; CONTEXT §specifics says "ALL charts in deep dishes.")
   - **RESOLVED (YES)** — 17-06-PLAN.md Task 1 "PLANNER DECISION" block: all
     three trend charts get instrument-window (slate + force-dark) treatment;
     SpendOverTimeChart's `#FFB43C` line swaps to a deepened twin.
   - What we know: AnalyticsTrendChart already has a recessed plot inset;
     SpendOverTimeChart renders directly on a raised card; NetWorthTrendChart
     sits inside the NetWorthCard near its donut dish.
   - Recommendation: treat recessed plot insets as instrument windows (slate +
     force-dark content); for SpendOverTimeChart either add a matching inset or
     swap its `#FFB43C` luminous line to a deepened twin. Planner decides; tune
     on device (within Claude's discretion — no user re-ask needed).
2. **Exact light values for ~25 shadow/rim twins** — by decision these are
   device-tuned (Claude's discretion). Plan should structure tuning as an
   explicit screenshot-loop task per component group, not bake guesses into
   many tasks.
   - **RESOLVED (device-tuning scope, not a blocking question)** — structured
     as explicit screenshot-loop tuning tasks in 17-04-PLAN.md Task 2 and
     17-05-PLAN.md; no fixed values baked into the plan.
3. **Theme-flip transition** — default to the environment change; only add a
   crossfade if jarring (discretion). No research blocker.
   - **RESOLVED (default, no crossfade)** — 17-03-PLAN.md Task 2 ships the plain
     environment-driven flip; a crossfade is added only if device review finds
     it jarring.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode + iOS SDK | build/test | ✓ | Xcode 26.5 (17F42) `[VERIFIED]` | — |
| iPhone 17 simulator | screenshot loop | ✓ (booted, UDID 2F09365E…) `[VERIFIED]` | currently appearance=light | — |
| `simctl ui … appearance` | scheme flipping | ✓ `[VERIFIED: help output]` | — | device Settings |
| `simctl status_bar override` | deterministic screenshots | ✓ `[VERIFIED: help output]` | — | crop status bar in diff |
| Python 3 + Pillow | pixel diffs | ✓ PIL 11.3.0 `[VERIFIED]` | — | byte-compare via `cmp` for static screens |
| ImageMagick | (alternative differ) | ✗ | — | Pillow (above) — no install needed |

**Missing dependencies with no fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`import Testing`, 76 test files) `[VERIFIED: grep]` |
| Config file | none (Xcode test target `MyHomeTests`) |
| Quick run command | `xcodebuild test -scheme MyHome -destination "id=2F09365E-5099-490E-9484-B8788C53C816" -only-testing:MyHomeTests/DesignTokensTests -quiet` |
| Full suite command | `xcodebuild test -scheme MyHome -destination "id=2F09365E-5099-490E-9484-B8788C53C816" -quiet` |

### Phase Requirements → Test Map

(No formal REQ IDs — mapped to CONTEXT decisions.)

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| D-06 | Every token resolves in dark to its pre-refactor hex (bit-identity) | unit | quick run above (`DarkBitIdentityTests`) | ❌ Wave 0 — extend `MyHomeTests/DesignTokensTests.swift` |
| D-01/D-02 | `AppearanceTheme` raw↔`ColorScheme?` mapping; missing key → system | unit | `-only-testing:MyHomeTests/DesignTokensTests` (co-located) | ❌ Wave 0 |
| D-08/09/10/15 | Locked light pairs meet WCAG floors (4.5 text / 3.0 non-text) | unit | same target (`ContrastTests`) | ❌ Wave 0 |
| D-04/05/13/14 | Light look: canvas, depth, slate dishes, drop-shadow glow | manual-only (visual tuning is the deliverable) | screenshot loop + human eyeball | — |
| D-06 (render level) | Per-screen dark screenshots byte/masked-pixel identical before vs after | scripted-manual | simctl loop + PIL diff (Code Examples) | ❌ Wave 0 — capture BEFORE screenshots prior to any token change |
| D-03/D-07 | Settings row live-flips theme; bars/sheets/keyboard follow | manual smoke | launch args `-startTab 4`, flip, screenshot | — |

### Sampling Rate
- **Per task commit:** `DesignTokensTests` quick run (~seconds once simulator is warm)
- **Per wave merge:** full `MyHomeTests` suite
- **Phase gate:** full suite green + dark-identity screenshot diff across all 5 tabs + light screenshot review before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] Capture BASELINE dark screenshots of all 5 tabs (+ one sheet, Analytics via `-openAnalytics`) on current `main` with pinned status bar — **must happen before the first token edit**, or D-06 has no ground truth
- [ ] Extend `MyHomeTests/DesignTokensTests.swift` with dark-bit-identity (legacy hex table), theme-mapping, and contrast tests (extend existing file — avoids pbxproj edits)
- [ ] 5-minute Wave-1 simulator smoke proving A1/A2 (adaptive token + env-override dish + sheet inheritance) before the bulk token conversion

## Security Domain

`security_enforcement: true`, ASVS level 1. This phase is a pure client-side
theming change: no new inputs, network, storage of sensitive data, auth, or
crypto surface.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Face ID gate untouched (verify overlay follows theme — cosmetic only) |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | minimal | `AppearanceTheme(rawValue:)` with `?? .system` fallback — malformed/absent UserDefaults value degrades safely to system |
| V6 Cryptography | no | — |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Unvalidated UserDefaults value crashing theme resolution | DoS (trivial) | Optional enum init + `.system` fallback (Pattern 2) |
| Privacy blur under app switcher regressing with scheme change | Information disclosure | Existing `.blur` on scenePhase is scheme-independent `[VERIFIED: RootView]`; include in manual smoke |

## Sources

### Primary (HIGH confidence)
- Compiled SwiftUI probe (this session, scratchpad/probe.swift) — dynamic-provider Color resolves per `EnvironmentValues.colorScheme`
- Codebase greps/reads (this session) — DesignTokens.swift, NeuSurface.swift, MyHomeApp.swift:34, RootView.swift:102, DonutChart.swift, trend charts, SettingsView, DesignTokensTests.swift, tokens.jsx STYLE_META (`neuro: light:false`) + light-accent mix recipe
- Toolchain verification — Xcode 26.5, iPhone 17 sim booted (UDID 2F09365E…), `simctl ui appearance`, `simctl status_bar`, PIL 11.3.0, ImageMagick absent
- WCAG ratios — computed from the 2.x relative-luminance formula (script in session)
- [Apple: colorScheme environment value](https://developer.apple.com/documentation/swiftui/environmentvalues/colorscheme)

### Secondary (MEDIUM confidence)
- [Nil Coalescing: Reading and setting color scheme in SwiftUI](https://nilcoalescing.com/blog/ReadingAndSettingColorSchemeInSwiftUI/) — preferredColorScheme presentation-boundary semantics; `.environment(\.colorScheme,...)` scopes downward
- [Jesse Squires: Creating dynamic colors in SwiftUI](https://www.jessesquires.com/blog/2023/07/11/creating-dynamic-colors-in-swiftui/) — SwiftUI lacks a dynamic-provider init; UIColor bridge is the standard workaround
- [Kyle Lanchman: Dynamic Colors in SwiftUI using ShapeStyle in iOS 17](https://blog.kylelanchman.com/dynamic-colors-in-swiftui-using-shapestyle-in-ios-17/) — `resolve(in:)`-based alternative

### Tertiary (LOW confidence)
- [Swift by Sundell: Defining dynamic colors in Swift](https://www.swiftbysundell.com/articles/defining-dynamic-colors-in-swift/), [Anton Gubarenko: Dynamic Color Init](https://antongubarenko.substack.com/p/dynamic-color-init) — background reading, consistent with the above

## Metadata

**Confidence breakdown:**
- Token mechanism: HIGH — empirically verified this session (probe) + iOS smoke planned as A1
- Codebase audit (inline colors, chrome absence, call sites): HIGH — direct greps/reads this session
- Light palette values / shadow twins: intentionally directional (locked as device-tuned per CONTEXT discretion)
- Chrome auto-adaptation (D-07): MEDIUM — A4 assumption with cheap fallback
- Pitfalls: HIGH for 1–4, 6, 8 (grounded in verified code); MEDIUM for 5, 7

**Research date:** 2026-07-11
**Valid until:** 2026-08-11 (stable Apple APIs; codebase facts valid until Phase 17 execution begins)
