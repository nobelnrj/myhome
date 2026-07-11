# Phase 17: Light Mode Support (Neumorphic Redesign) - Pattern Map

**Mapped:** 2026-07-11
**Files analyzed:** 11 modified (0 new — all work extends existing files to avoid the 4-edit pbxproj tax)
**Analogs found:** 11 / 11 (this is a refactor phase — most files ARE their own analog; sibling patterns supply the light twins and net-new mechanisms)

> **Nature of this phase:** No new source files (RESEARCH §Recommended Project Structure — extend, don't create). Every "analog" is either (a) the current version of the file being made adaptive, whose dark branch must be preserved verbatim (D-06), or (b) an existing in-repo pattern the net-new code should copy (AppStorage-less settings, ShadowSpec dual-shadow shape, Swift Testing `@Suite` style). The planner should treat each pattern block as "here is the exact current code you are converting, and here is the shape to copy."

## File Classification

| Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------|------|-----------|----------------|---------------|
| `MyHomeApp/Support/Color+Hex.swift` | utility (factory) | transform | itself + Jesse-Squires dynamic-provider recipe (RESEARCH Pattern 1) | self / role-match |
| `MyHomeApp/DesignSystem/DesignTokens.swift` | config (design tokens) | transform | itself (static hex → adaptive pair, dark = verbatim) | self (D-06 verbatim) |
| `MyHomeApp/DesignSystem/NeuSurface.swift` | component (surface DS) | transform | itself (~inline shadow values → named tokens) | self |
| `MyHomeApp/MyHomeApp.swift` | provider (app root) | event-driven | itself line 34 + RootView `@State`/`ProcessInfo` persisted-flag pattern | self / role-match |
| `MyHomeApp/Features/Settings/SettingsView.swift` | component (screen) | request-response | itself (`Section` + `.listRowBackground` rows) + `NotesHomeView` segmented header | self / role-match |
| `MyHomeApp/RootView.swift` | provider (tab host) | event-driven | itself line 102 `.tint(DesignTokens.accent)` | self |
| `MyHomeApp/Features/Shared/IconTile.swift` | component (glyph tile) | transform | itself line 35 hardcoded `#16161C` glyph | self |
| `MyHomeApp/Features/Analytics/AIInsightCard.swift` | component (card) | request-response | itself (`aiViolet*` tokens + `neonGlow` at :150) | self (D-15) |
| chart-dish call sites (`NeuCircularWell`, `VerticalPillGauge`, trend insets) | component (chart) | transform | `NeuCircularWell` in NeuSurface.swift:465 | exact |
| `MyHomeApp/DesignSystem/DesignTokens.swift` `neonGlow` | utility (modifier) | transform | current `neonGlow` free func :139 + `EntranceModifier` ViewModifier shape :150 | role-match |
| `MyHomeTests/DesignTokensTests.swift` | test | request-response | itself + `LockSettingsTests`/other `@Suite` files | self / role-match |

## Pattern Assignments

### `MyHomeApp/Support/Color+Hex.swift` (utility, transform)

**Analog:** itself — the existing `Color(hex:)` is the exact sRGB math the dark branch of every adaptive pair MUST reuse (D-06 bit-identity, RESEARCH Pitfall 2).

**Existing hex parser to preserve exactly** (lines 8-20):
```swift
init(hex: String) {
    let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "#", with: "")
    guard cleaned.count == 6,
          let value = UInt64(cleaned, radix: 16) else {
        self = .gray
        return
    }
    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    self = Color(red: r, green: g, blue: b)
}
```

**Extend here (net-new — RESEARCH Pattern 1 example):** add a `UIColor(hex:alpha:)` that parses with this SAME 6-digit sRGB math, plus a `Color.adaptive(light:lightAlpha:dark:darkAlpha:)` factory backed by `UIColor { trait in ... }`. Keep the dark branch component-identical to `Color(red:g:b:)` — the D-06 resolve test enforces this. Do NOT change the existing `init(hex:)` or `hexString` (still used by `Account.colorHex` user data).

**Warning (RESEARCH Pitfall 1):** `hexString` resolves against `UITraitCollection.current` (light in a test process). `DesignTokensTests.accentColorMatchesSpec` uses it — that test must migrate to `resolve(in:)` (see test section).

---

### `MyHomeApp/DesignSystem/DesignTokens.swift` (config, transform)

**Analog:** itself — every `static let foo = Color(hex: "#…")` becomes `Color.adaptive(light:dark:)` with **dark = current hex verbatim**. Call sites in 62 files stay untouched.

**Current static token block to convert** (lines 12-67) — dark branch = these exact values:
```swift
static let bgCanvas               = Color(hex: "#1C1C23")
static let surfaceRaised          = Color(hex: "#1F1F27")
static let surfaceRaisedStrong    = Color(hex: "#22222C")
static let surfaceRaisedTop          = Color(hex: "#24242D")
static let surfaceRaisedBottom       = Color(hex: "#1B1B21")
static let surfaceRaisedStrongTop    = Color(hex: "#282833")
static let surfaceRaisedStrongBottom = Color(hex: "#1E1E26")
static let surfaceElevatedControl = Color(hex: "#262630")
static let fillRecessed           = Color(hex: "#16161C")
static let fillRecessed2          = Color(hex: "#191920")
static let fillRecessed3          = Color(hex: "#15151B")
static let accent        = Color(hex: "#FFD60A")
static let accentSoft    = Color(hex: "#FFD60A").opacity(0.16)
static let positive      = Color(hex: "#34E29B")
static let negative      = Color(hex: "#FF6B6B")
static let orange        = Color(hex: "#FFB020")
// label tiers use baked opacity — port alpha into the adaptive pair (per-scheme alpha)
static let label  = Color(hex: "#ECEDF4")
static let label2 = Color(hex: "#DCDFEE").opacity(0.56)
static let label3 = Color(hex: "#DCDFEE").opacity(0.32)
static let label4 = Color(hex: "#DCDFEE").opacity(0.16)
static let separatorHairline = Color.white.opacity(0.05)   // white/black opacity → adaptive too
static let separatorEdge     = Color.black.opacity(0.30)
static let glassBorder       = Color.white.opacity(0.025)
// 11-category palette (D-09 deepened light twins):
static let catGroceries = Color(hex: "#2DD4BF")  // light twin ~#0F9488 (text ~#0B6E66)
// … catDining #FB923C, catFuel #F472B6, catUtilities #7DD3FC, catRent #818CF8,
//    catAuto #38BDF8, catShopping #E879F9, catHealth #A78BFA,
//    catSubscriptions #22D3EE, catEntertainment #C084FC, catOther #94A3B8
```

**Adaptive-pair pattern to apply** (RESEARCH Pattern 1 — baked-alpha form for label tiers):
```swift
static let bgCanvas = Color.adaptive(light: "#E3E6EE", dark: "#1C1C23")
static let label2 = Color.adaptive(light: "#23252E", lightAlpha: 0.62,
                                   dark: "#DCDFEE",  darkAlpha: 0.56)
```

**Role-split accent (D-08 — RESEARCH Pitfall 6):** keep `accent` as fill-canary in BOTH schemes; add a NEW `accentText` adaptive pair (dark amber `#755C00`-family in light → 5.12:1, canary in dark). Audit `.tint(...)` and `NeuSecondaryButtonStyle`/RootView call sites into fill vs text/icon roles.

**AI violet (D-15):** add deepened light twins for `aiVioletTop/Bottom/Glow` (lines 40-42); text/sparkle twin ~`#5B21B6` (7.19:1). Violet stays AI-only.

**ShadowSpec is already a dual light/dark struct** (lines 101-125) — but its "light/dark" mean top-left-highlight vs bottom-right-depth, NOT color-scheme. Do NOT overload it; promote the inline `.white.opacity()/.black.opacity()` COLORS inside each spec to adaptive tokens, keep radii/offsets scheme-invariant (RESEARCH Pattern 4 "keep geometry frozen"):
```swift
static let shadowRaised = ShadowSpec(
    lightColor: .white.opacity(0.05),  lightRadius: 7,  lightX: -6, lightY: -6,
    darkColor:  .black.opacity(0.55),  darkRadius:  9,  darkX:   7, darkY:   7
)
```

---

### `MyHomeApp/DesignSystem/DesignTokens.swift` → `neonGlow` (utility, transform)

**Analog:** current `neonGlow` free function (lines 139-143) for the exact dark bloom to preserve; `EntranceModifier` (lines 150-169) for the `ViewModifier` + `@Environment` shape to copy.

**Current dark bloom to keep verbatim as the `.dark` branch** (D-06):
```swift
func neonGlow(_ color: Color, radius: CGFloat = 8, intensity: Double = 1) -> some View {
    self
        .shadow(color: color.opacity(0.55 * intensity), radius: radius * 0.55)
        .shadow(color: color.opacity(0.32 * intensity), radius: radius * 1.5)
}
```

**Convert to a `ViewModifier` reading the environment** — copy the `@Environment` + `func body(content:)` shape from `EntranceModifier` (already in this file, lines 150-169). Light branch = single faint tinted drop-shadow (D-14, values tuned on device). Call sites (`AIInsightCard:150`, `BudgetProgressView:50`, `BudgetsView:263`, `OverviewView:354`) stay unchanged — keep the `.neonGlow(_:radius:intensity:)` extension signature.

---

### `MyHomeApp/DesignSystem/NeuSurface.swift` (component, transform)

**Analog:** itself — the largest inline-shadow surface. Every `.white.opacity(x)/.black.opacity(y)` becomes a named adaptive token (dark = current alpha verbatim). Geometry (radius/offset/blur/lineWidth) stays scheme-invariant.

**Inline values to promote (RESEARCH Pattern 4 audit — all in this file):**
- RimOverlayModifier rim gradient (lines 133-138): `white .07 → black .35`
- RecessedOverlayModifier (lines 165-181): dark arc `black .55` / light rim `white .05` / hairline `black .45→white .04`
- NeuPrimaryButtonStyle (lines 234-271): CTA hexes `#231B00`/`#E8C918`/`#D9B000`/`#FFE04A`/`#F2C500`, top rim `white .45/.15`, shadows `white .04`/`black .62/.25`, accent halo `accent .22/.10`
- NeuSecondaryButtonStyle (lines 285-323): rim `white .07/black .35` (flips when pressed), shadows `white .04`/`black .62/.20`, accent halo
- EmbossedBar (lines 347-379): track `black .35`, hairline `black .55→white .04`, fill emboss `white .28 / black .28`
- VerticalPillGauge (lines 418-452): well `black .35`, hairline `black .55→white .04`, fill sheen `white .35`, glow `color .45`
- NeuCircularWell (lines 477-500): dish fill `fillRecessed3`, dark arc `black .55`, light rim `white .06`, hairline `black .50→white .04`
- NeuCircularPuck (lines 519-533): shadows `white .05`/`black .55`, rim `white .07→black .35`

**Dish force-dark override to ADD (RESEARCH Pattern 3 — D-11/12/13).** The dish CHROME uses adaptive slate tokens (light `#3E4250`-family / dark `#15151B` verbatim); only `content()` gets the env override. Apply to the `NeuCircularWell` body (lines 472-507):
```swift
ZStack {
    // dish chrome: fill/arcs use ADAPTIVE tokens (slate in light, verbatim dark)
    ZStack { /* Circle().fill(DesignTokens.fillRecessed3) … arcs … */ }
        .drawingGroup()
    content()
        .environment(\.colorScheme, .dark)   // D-11: luminous palette + full bloom inside dish
}
```
**Critical ordering (RESEARCH Pitfall 4):** override goes on `content()` ONLY — wrapping the whole ZStack forces the chrome to `#15151B` charcoal = the "hole into dark mode" D-13 forbids.

**Update the preview** (lines 555-595) — it pins `.preferredColorScheme(.dark)`; add a Light variant (RESEARCH Pitfall 8; same for `RollingMoneyText.swift:74`, `SpendBudgetCard.swift:268/284`).

---

### `MyHomeApp/MyHomeApp.swift` (provider, event-driven)

**Analog:** itself, line 34 — the single forced-scheme modifier to replace. For the persisted-value read there is no existing `@AppStorage` in the repo (net-new); the nearest in-repo persistence idiom is `UserDefaults.standard.bool(forKey:)` (SettingsView:26,188) and the `ProcessInfo`-driven `@State` default in RootView:34-40.

**Line to replace** (D-01):
```swift
RootView(gmailSyncController: gmailSyncController)
    .preferredColorScheme(.dark)   // DS-05 — REPLACE with AppStorage-mapped value
```

**Pattern to apply (RESEARCH Pattern 2):** add an `AppearanceTheme: String` enum (`system/light/dark` → `ColorScheme?`, nil = system) in DesignTokens.swift; add `@AppStorage("appearanceTheme")` here; `.preferredColorScheme((AppearanceTheme(rawValue: raw) ?? .system).colorScheme)`. Plain `UserDefaults.standard` — no App Group needed (no widget/extension reads it). Missing key → `.system` satisfies D-02 with zero migration.

---

### `MyHomeApp/Features/Settings/SettingsView.swift` (component, request-response)

**Analog for row hosting:** this file's own `Section("…") { … }.listRowBackground(DesignTokens.surfaceRaised)` idiom (lines 49-66, 240-244) — add a new `Section("Appearance")` near the top (above Security).

**Analog for the segmented control:** `NotesHomeView.swift:85-90` shows the existing native segmented pattern —
```swift
Picker("View", selection: $selectedSegment) { … }
    .pickerStyle(.segmented)
```
BUT D-03 wants a CUSTOM neumorphic 3-segment pill (recessed track + raised active segment), NOT `.pickerStyle(.segmented)`. Copy the recessed-track + raised-pill language from `NeuSurface.swift`: recessed track = `VerticalPillGauge`/`EmbossedBar` well recipe (Capsule + `fillRecessed3` + top shade + hairline, lines 418-436); active segment = `NeuSecondaryButtonStyle` raised gradient pill (lines 292-313). Bind to the same `@AppStorage("appearanceTheme")` key so the root updates live.

**Row-label helper to reuse** (lines 373-379): `IconTile` + `label2` text. `.tint(DesignTokens.accent)` at :64 is a control tint (text-role → candidate for `accentText`).

---

### `MyHomeApp/RootView.swift` (provider, event-driven)

**Analog:** itself, line 102.
```swift
.tint(DesignTokens.accent)   // D-02: canary yellow selected-tab tint (#FFD60A)
```
Selected-tab icon/label is accent iconography on a (light) bar → switch to the role-split `accentText` token (dark amber in light, canary in dark) — one-line change, `.tint` accepts the adaptive Color (RESEARCH D-07 note 2). No `UITabBarAppearance` code exists anywhere; native bars auto-adapt once the forced scheme is removed (add appearance customization only if screenshots clash with `#E3E6EE`).

---

### `MyHomeApp/Features/Shared/IconTile.swift` (component, transform)

**Analog:** itself, line 35.
```swift
.foregroundStyle(Color(hex: "#16161C").opacity(0.85))
```
Glyph is a near-black on a category fill. On deepened light category fills a dark glyph likely still works (verify per-tile; deepest twins may need a white glyph — RESEARCH assumption A5). Promote to an adaptive glyph token rather than an inline hex.

---

### `MyHomeApp/Features/Analytics/AIInsightCard.swift` (component, request-response) — D-15

**Analog:** itself. Uses `aiVioletTop` text (:93,:97), edge gradient `aiVioletTop→aiVioletBottom` (:134), `neonGlow(aiVioletGlow, radius: 8)` (:150), stroke `aiVioletGlow.opacity(0.5)` (:164), sparkle gradient `white .9 → aiVioletGlow` (:172). No call-site changes: the deepened-violet behavior comes from making `aiViolet*` adaptive + the scheme-aware `neonGlow`. Add a deepened `aiVioletText` pair for the text/sparkle (`#5B21B6`, 7.19:1) that passes contrast on light.

---

### `MyHomeTests/DesignTokensTests.swift` (test, request-response) — extend, no new file

**Analog for structure:** this file's `@MainActor struct DesignTokensTests` + `@Test("…")` funcs (Swift Testing). `@Suite` siblings: `LockSettingsTests`, `NPSNavServiceTests`, etc.

**Existing test that BREAKS under dynamic colors** (RESEARCH Pitfall 1) — must migrate off `hexString`:
```swift
@Test("DesignTokens.accent equals #FFD60A")
func accentColorMatchesSpec() throws {
    #expect(DesignTokens.accent.hexString.uppercased() == "#FFD60A")  // resolves vs UITraitCollection.current (light in tests) → flaps
}
```

**Add (Wave 0 — RESEARCH Code Examples):**
1. `DarkBitIdentityTests` — for every token, `token.resolve(in: darkEnv) == Color(hex: legacyHex).resolve(in: darkEnv)` (the D-06 gate; capture the legacy hex table from the current DesignTokens values above BEFORE editing).
2. `AppearanceTheme` mapping test — raw↔`ColorScheme?`; missing/garbage key → `.system`.
3. `ContrastTests` — WCAG relative-luminance ≥ 4.5 (text) / 3.0 (icon) for locked light pairs.

Quick run: `xcodebuild test -scheme MyHome -destination "id=2F09365E-5099-490E-9484-B8788C53C816" -only-testing:MyHomeTests/DesignTokensTests -quiet`

---

## Shared Patterns

### Adaptive color factory (the core mechanism)
**Source:** RESEARCH Pattern 1 → land in `Support/Color+Hex.swift`
**Apply to:** every DesignTokens color + every promoted inline shadow/rim color
```swift
static func adaptive(light: String, lightAlpha: CGFloat = 1,
                     dark: String,  darkAlpha: CGFloat = 1) -> Color {
    Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(hex: dark,  alpha: darkAlpha)
            : UIColor(hex: light, alpha: lightAlpha)
    })
}
```
**Rule:** dark branch = current value verbatim (D-06). Geometry never adapts in pass 1.

### Dark bit-identity (D-06 guarantee)
**Source:** the current DesignTokens hex values (captured above) + `Color.resolve(in:)` (iOS 17)
**Apply to:** every token — enforced by `DarkBitIdentityTests` + before/after masked screenshot diff.

### Force-dark dish subtree (instrument window)
**Source:** `NeuSurface.swift:465` `NeuCircularWell` + RESEARCH Pattern 3
**Apply to:** `NeuCircularWell` (call sites BudgetsView:278, NetWorthCard:53, SpendDonutCard:46, SpendBudgetCard:95), `VerticalPillGauge`, recessed trend-plot insets (`AnalyticsTrendChart:56-61`).
```swift
content().environment(\.colorScheme, .dark)   // on CONTENT only, never the chrome
```

### Scheme-aware glow language
**Source:** `neonGlow` :139 (dark verbatim) + `EntranceModifier` :150 (ViewModifier+`@Environment` shape)
**Apply to:** all `.neonGlow(...)` call sites (unchanged signatures) + `EmbossedBar` fills (D-14).

### AppStorage-backed root scheme
**Source:** RESEARCH Pattern 2 (net-new; nearest idiom = `UserDefaults.standard.bool(forKey:)` in SettingsView:26/188)
**Apply to:** `MyHomeApp.swift` root + `SettingsView` Appearance row (same `@AppStorage("appearanceTheme")` key drives both).

## No Analog Found (net-new mechanisms — use RESEARCH patterns)

| Concern | Why no in-repo analog | Source to use |
|---------|-----------------------|---------------|
| `@AppStorage` usage | Zero `@AppStorage` in the codebase today (grep) | RESEARCH Pattern 2 |
| `@Environment(\.colorScheme)` reads | Zero scheme reads exist today (grep) — only 3 new legit sites: `NeonGlowModifier`, dish content override, optionally NeuSurface | RESEARCH Anti-Patterns |
| `Color.resolve(in:)` unit tests | No resolve-based color tests exist | RESEARCH Code Examples |
| Custom neumorphic segmented pill | Only native `.pickerStyle(.segmented)` exists (NotesHomeView:90) | Compose from NeuSurface recessed-track + raised-pill recipes |

## Metadata

**Analog search scope:** `MyHomeApp/DesignSystem`, `MyHomeApp/Support`, `MyHomeApp/Features/{Settings,Analytics,Shared,Notes}`, `MyHomeApp` root, `MyHomeTests`
**Files scanned:** DesignTokens.swift, NeuSurface.swift, MyHomeApp.swift, RootView.swift, Color+Hex.swift, SettingsView.swift, DesignTokensTests.swift, NotesHomeView.swift (grep), IconTile.swift (grep), AIInsightCard.swift (grep)
**Pattern extraction date:** 2026-07-11
</content>
</invoke>
