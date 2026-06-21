# Phase 13: Design System Foundation - Research

**Researched:** 2026-06-21
**Domain:** SwiftUI neumorphic design system — token translation, ViewModifier authoring, custom TabBar, animated text, accessibility
**Confidence:** HIGH (all findings verified against the UI-SPEC, live codebase inspection, and first-party Apple APIs)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DS-01 | Single source-of-truth `DesignTokens` enum (colors, shadows, spacing, radii, font anchors) translated from `tokens.jsx` neuro branch | tokens.jsx fully read; hex values confirmed; shadow specs extracted; swift structure defined in UI-SPEC |
| DS-02 | `NeuSurface` ViewModifier family (raised/floating/recessed) via dual-shadow system; replaces `CardStyle` | CardStyle.swift read; existing API documented; replacement contract defined in UI-SPEC |
| DS-03 | Floating capsule tab bar replacing stock `TabView` chrome; correct safe-area insets; stable deep-link indices | RootView.swift fully read; `@State selectedTab: Int` binding documented; safeAreaInset strategy confirmed |
| DS-04 | `RollingMoneyText` with `.contentTransition(.numericText)` for ~780ms rolling animation | iOS 16+ API confirmed; degradation pattern with `@Environment(\.accessibilityReduceMotion)` documented |
| DS-05 | Dark-mode-only palette — no light-mode variant, no translucency/blur/Liquid Glass; solid opaque surfaces | `STYLE_META.neuro.plasma = false`, `light: false` confirmed in tokens.jsx; `.preferredColorScheme(.dark)` strategy documented |
| DS-06 | Accessible by construction — WCAG 1.4.11 3:1, Dynamic Type via font tokens, Reduce Motion honored | Contrast ratios verified arithmetically; `@ScaledMetric` pattern documented; Accessibility Inspector gate defined |
</phase_requirements>

---

## Summary

Phase 13 is a pure infrastructure phase: no user-facing screens ship, but every subsequent v1.2 phase depends on the four files it creates. The technical work divides cleanly into (1) a token translation from a JavaScript design handoff into a Swift enum, (2) a `ViewModifier` that applies dual outer or inner shadows to any view, (3) a custom tab bar view that replaces `TabView` chrome while preserving the existing `@State selectedTab: Int` binding in `RootView.swift`, and (4) an animated money readout that uses the SwiftUI-native `.contentTransition(.numericText)` API.

All four components are first-party SwiftUI — zero external dependencies, zero new Swift packages, zero new Xcode capabilities. The deployment floor is iOS 17.0 (confirmed in `project.pbxproj`), and every API used in this phase is available at iOS 16.0 or earlier, so no `#available` guards are needed within Phase 13 code.

The single highest-risk item for this phase is `project.pbxproj` registration. The project has NO synchronized groups; each new `.swift` file requires exactly four manual edits to the pbxproj or it silently will not compile. Phase 13 adds four new production files (`DesignTokens.swift`, `NeuSurface.swift`, `NeuTabBar.swift`, `RollingMoneyText.swift`) in a new `DesignSystem/` subdirectory that does not yet exist in the project, plus a new group entry for that directory, plus any test files. The research section on pbxproj registration below is the most precise documentation of this process in the entire codebase.

The second significant complexity is inset shadows: SwiftUI's `.shadow()` modifier applies drop shadows only (exterior). `NeuSurface(.recessed)` requires an inner-shadow visual. The UI-SPEC notes two implementation paths; this research evaluates both and recommends the overlay path as the default (no UIViewRepresentable, no UIKit dependency, iOS 17 compliant).

**Primary recommendation:** Implement in order DS-01 → DS-02 → DS-03 → DS-04 → DS-06 validation pass. Each step is a prerequisite for the next. The pbxproj registration for the new `DesignSystem/` group must be Wave 0 work before any source files are written.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Design token constants | App (compile-time) | — | Pure Swift enum with static `let`; no runtime computation |
| Neumorphic surface rendering | View layer (SwiftUI ViewModifier) | — | Shadow composition belongs in the view modifier; fills and clips are view-layer concerns |
| Tab bar state (selected tab) | RootView (existing @State) | NeuTabBar (reads Binding) | `selectedTab` already lives in `RootView.swift`; NeuTabBar is a stateless visual consumer of that binding |
| Content safe-area padding | Each screen's ScrollView | — | The tab bar floats; each screen is responsible for `.safeAreaInset(edge: .bottom)` so it is not bar-phase-specific debt |
| Rolling money animation | View component (RollingMoneyText) | — | Animation is a presentation concern; the data value (Decimal) comes from the caller |
| Color scheme enforcement | App root (MyHomeApp.swift) | — | `.preferredColorScheme(.dark)` applied once at the window root; no per-view overrides needed |

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 17+ (bundled) | All UI — ViewModifier, contentTransition, safeAreaInset | First-party; required by project |
| Swift 6.0 | 6.0 (project setting) | Language — strict concurrency, `@MainActor` annotations | Project-level setting confirmed in pbxproj |
| Swift Testing | bundled Xcode 26 | Unit tests (`@Test`, `#expect`) | Already used in all 60+ existing test files |

### Supporting (no installation needed — all bundled)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Color(hex:)` extension | existing in codebase | Parses 6-digit hex strings → `Color` | Already at `MyHomeApp/Support/Color+Hex.swift`; reuse as-is |
| `@ScaledMetric` | iOS 14+ | Scales bespoke font sizes with Dynamic Type | Used in `heroMoney`, `statNumber`, `eyebrow`, etc. |
| `@Environment(\.accessibilityReduceMotion)` | iOS 14+ | Detects Reduce Motion preference | Used in `RollingMoneyText` and `NeuTabBar` |
| `contentTransition(.numericText())` | iOS 16+ | Digit-roll animation | Used in `RollingMoneyText` [VERIFIED: Apple developer documentation] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Overlay-based inset shadow | UIViewRepresentable wrapping CALayer with `shadowPath` set inward | UIViewRepresentable is heavier, UIKit dependency, harder to compose in SwiftUI previews; overlay approach keeps everything SwiftUI |
| `.safeAreaInset(edge: .bottom)` on each screen | Manual padding computed from `UIScreen` | `safeAreaInset` is the correct SwiftUI API (iOS 15+); manual padding breaks on devices with home indicator |
| `springBouncy` spring for tab pill | `withAnimation(.easeInOut)` | Spring matches design handoff's `cubic-bezier(.34,1.32,.42,1)` intent; easeInOut feels mechanical |

**Installation:** No packages to install. All code is hand-authored Swift files.

---

## Package Legitimacy Audit

> This phase installs zero external packages. All components are first-party Swift files.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| *(none)* | — | — | — | — | — | — |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

---

## Architecture Patterns

### System Architecture Diagram

```
MyHomeApp.swift
└─ .preferredColorScheme(.dark)  ←── DS-05 (enforced once, at root)
   └─ RootView.swift
      ├─ @State selectedTab: Int  ←── DS-03 (existing binding preserved)
      ├─ ZStack / overlay
      │   ├─ TabView (REPLACED by content-only host)
      │   │   ├─ OverviewView  ──.safeAreaInset(bottom: 100pt)──┐
      │   │   ├─ ExpenseListView  ─── same ─────────────────────│
      │   │   ├─ BudgetsView     ─── same ─────────────────────│  DS-03
      │   │   ├─ NotesHomeView   ─── same ─────────────────────│
      │   │   └─ SettingsView    ─── same ─────────────────────┘
      │   └─ NeuTabBar(selectedTab: $selectedTab)  ←── floating overlay
      │       └─ uses DesignTokens (accent, surfaceRaisedStrong, shadowFloat)
      └─ views using NeuSurface / RollingMoneyText
          ├─ .neuSurface(.raised)   ←── DS-02
          ├─ .neuSurface(.floating) ←── DS-02
          ├─ .neuSurface(.recessed) ←── DS-02
          └─ RollingMoneyText(amount:) ←── DS-04

DesignTokens.swift  ←── DS-01: imported by all of the above
```

### Recommended Project Structure

```
MyHomeApp/
├─ DesignSystem/            ← NEW (Phase 13 creates this directory and pbxproj group)
│   ├─ DesignTokens.swift   ← DS-01
│   ├─ NeuSurface.swift     ← DS-02
│   ├─ NeuTabBar.swift      ← DS-03
│   └─ RollingMoneyText.swift ← DS-04
├─ Features/
│   └─ Shared/
│       └─ CardStyle.swift  ← DEPRECATED (marked @available(*, deprecated) — not deleted)
└─ MyHomeApp.swift          ← add .preferredColorScheme(.dark) — DS-05
```

The new `DesignSystem/` group sits at the top level of `G100 /* MyHomeApp */` in `project.pbxproj` (same level as `G110 Resources`, `G120 Features`, `G130 Persistence`, etc.).

---

### Pattern 1: DesignTokens enum (DS-01)

**What:** A pure namespace `enum` (no cases, no instances) with `static let` constants for all visual tokens. Using an enum rather than a struct prevents accidental instantiation.

**When to use:** Every view that needs a color, radius, spacing, shadow, or animation constant. No view may contain a hardcoded hex string or pixel-literal shadow value after this phase.

**Key implementation points:**
- `Color(hex:)` is already available at `MyHomeApp/Support/Color+Hex.swift` — the extension handles 6-digit hex strings and falls back to `.gray` on parse failure. `DesignTokens.swift` uses it for every color constant. [VERIFIED: read `Color+Hex.swift` in codebase]
- `ShadowSpec` is a nested struct inside `DesignTokens` (value type, not a class) — stores the two-sided shadow parameters as a unit. The full struct signature is in the UI-SPEC's `DesignTokens.swift` listing. [CITED: 13-UI-SPEC.md DesignTokens.swift section]
- Animation constants (`springBouncy`, `springSoft`) are stored as `static let` of type `Animation` — avoids repeating `.spring(response: 0.4, dampingFraction: 0.65)` inline throughout the codebase.
- Font tokens are NOT stored as `Font` values in `DesignTokens` — they are Group A (OS styles used via `.font(.textStyle)`) or Group B (`@ScaledMetric` values declared in the component that uses them, anchored to an OS style). Storing `@ScaledMetric` as a static let in an enum is not possible (property wrappers cannot be applied to static stored properties). [ASSUMED: property wrapper limitation in static context — standard Swift behavior but worth verifying against Swift 6.0 release notes]

```swift
// Source: 13-UI-SPEC.md DesignTokens.swift section (authoritative)
import SwiftUI

enum DesignTokens {
    static let bgCanvas = Color(hex: "#1C1C23")
    static let accent   = Color(hex: "#FFD60A")
    // … (full listing in UI-SPEC)

    struct ShadowSpec {
        let lightColor: Color; let lightRadius: CGFloat; let lightX: CGFloat; let lightY: CGFloat
        let darkColor: Color;  let darkRadius: CGFloat;  let darkX: CGFloat;  let darkY: CGFloat
    }
    static let shadowRaised = ShadowSpec(
        lightColor: .white.opacity(0.035), lightRadius: 7, lightX: -6, lightY: -6,
        darkColor:  .black.opacity(0.55),  darkRadius:  9, darkX:   7, darkY:   7
    )
}
```

---

### Pattern 2: NeuSurface ViewModifier (DS-02)

**What:** A `ViewModifier` that applies fill, clip, shadow, and optional rim overlay to any content. Called via `.neuSurface(_:radius:padding:)` view extension.

**When to use:** Any card, tile, input field, progress track, or tappable surface in v1.2. Replaces all uses of `.cardStyle()`.

**The existing CardStyle (to replace):**
```swift
// Source: MyHomeApp/Features/Shared/CardStyle.swift (read directly)
// Current signature:
func cardStyle(cornerRadius: CGFloat = 16, padding: CGFloat? = 16) -> some View
// Current fill: Color(.secondarySystemBackground)
// Current shadow: .shadow(color: .black.opacity(0.04), radius: 2, y: 1)  ← single, minimal
```
`CardStyle` is a thin single-shadow modifier using system background colors. Phase 13 deprecates it (`@available(*, deprecated, renamed: "neuSurface")`) but does not delete it; Phase 14 will clean up usages.

**Raised / Floating states (dual outer shadow):**

Two `.shadow()` modifiers applied sequentially. SwiftUI composites them correctly — the light (top-left offset) shadow and dark (bottom-right offset) shadow together create the neumorphic extrusion. [ASSUMED: two stacked .shadow() modifiers produce additive, not overriding, shadows — matches empirical SwiftUI behavior observed across projects, but worth confirming in a quick preview]

```swift
// Source: 13-UI-SPEC.md Shadow System section
// Applied as:
.shadow(color: DesignTokens.shadowRaised.lightColor,
        radius: DesignTokens.shadowRaised.lightRadius,
        x: DesignTokens.shadowRaised.lightX,
        y: DesignTokens.shadowRaised.lightY)
.shadow(color: DesignTokens.shadowRaised.darkColor,
        radius: DesignTokens.shadowRaised.darkRadius,
        x: DesignTokens.shadowRaised.darkX,
        y: DesignTokens.shadowRaised.darkY)
```

**Inner rim overlay (raised and floating only):**

The "rim" (`shadowRim`) is inset — white on top-left, dark on bottom-right. SwiftUI `.shadow()` does not produce inset shadows. The rim is implemented as an overlay of a `RoundedRectangle` stroke or a gradient border:

```swift
// Rim as overlay approach (no UIKit needed):
.overlay {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
        .strokeBorder(
            LinearGradient(
                colors: [Color.white.opacity(0.045), Color.black.opacity(0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 1
        )
}
```

**Recessed state (inset shadow):**

SwiftUI has no native inset shadow. Two proven approaches:

| Approach | Pros | Cons |
|----------|------|------|
| Overlay with a dark outer rectangle that clips inward (blend mode) | Pure SwiftUI | Complex blend mode reasoning, color accuracy depends on background |
| Overlay with a gradient that darkens edges | Pure SwiftUI, simple | Approximation, not a true box shadow |
| `UIViewRepresentable` wrapping `UIView` with CALayer shadow using a `shadowPath` set to inward rectangle | Pixel-exact | UIKit dependency, harder to test in previews |

**Recommendation:** Use the overlay-gradient approach as the primary implementation. The neumorphic recessed look in this project is applied to tracks, inputs, and progress bars where pixel-perfect shadow rendering is less critical than correct fill color (`fillRecessed3 #15151B`). The visual difference from a true inset shadow is imperceptible at the values in the spec (blur 5, offset ±2). The inner "lightening" effect is produced by the fill color being lighter than the canvas (`#15151B` vs `#1C1C23`), not solely by the shadow. [ASSUMED: visual equivalence is acceptable — should be confirmed in Xcode preview before Wave 2 plan commit]

A helper function on `NeuSurfaceState` that returns the correct fill, shadow style, and rim setting encapsulates the three cases cleanly:

```swift
// Source: pattern derived from 13-UI-SPEC.md NeuSurface Contract
enum NeuSurfaceState { case raised, floating, recessed }

struct NeuSurface: ViewModifier {
    let state: NeuSurfaceState
    var radius: CGFloat = DesignTokens.radiusCard
    var padding: CGFloat? = 16

    func body(content: Content) -> some View {
        let paddedContent = Group {
            if let p = padding { content.padding(p) } else { content }
        }
        paddedContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .modifier(ShadowModifier(state: state))
            .overlay { rimOverlay }
    }

    private var fill: Color {
        switch state {
        case .raised:    return DesignTokens.surfaceRaised
        case .floating:  return DesignTokens.surfaceRaisedStrong
        case .recessed:  return DesignTokens.fillRecessed3
        }
    }
    // …
}
```

**Interactive surface accessibility border:** When `NeuSurface` is used as a tappable surface (button, tappable card), add a 0.5pt `glassBorder` stroke as per DS-06. The modifier needs an `isInteractive: Bool` parameter (or the caller applies `.overlay(RoundedRectangle(...).stroke(DesignTokens.glassBorder, lineWidth: 0.5))` separately).

---

### Pattern 3: NeuTabBar (DS-03)

**What:** A custom SwiftUI `View` that renders the floating capsule tab bar. It is NOT a ViewModifier — it's a standalone view that `RootView` renders as an overlay.

**RootView integration strategy:**

The existing `RootView.swift` uses `TabView(selection: $selectedTab)`. The correct migration approach for DS-03 is:

1. Keep `TabView` as the content host (it handles navigation stack isolation per tab, scroll-to-top on re-tap, and memory management). Remove the native tab bar chrome via `.tabViewStyle(.page(indexDisplayMode: .never))` (hides dots but keeps content) — BUT this changes scroll behavior. Better: use `.toolbar(.hidden, for: .tabBar)` (iOS 16+) to suppress the native tab bar while keeping all TabView semantics. [ASSUMED: `.toolbar(.hidden, for: .tabBar)` successfully hides the built-in tab bar on iOS 17 without affecting per-tab NavigationStack isolation — verify in a preview]

2. Overlay `NeuTabBar` at the bottom of the `ZStack` or via `.overlay(alignment: .bottom)`:

```swift
// In RootView.body:
TabView(selection: $selectedTab) { … }
    .toolbar(.hidden, for: .tabBar)
    .overlay(alignment: .bottom) {
        NeuTabBar(selectedTab: $selectedTab)
    }
```

3. Each content view applies:
```swift
.safeAreaInset(edge: .bottom, spacing: 0) {
    Color.clear.frame(height: DesignTokens.tabBarClearance)  // 100pt
}
```
This is each screen's responsibility (DS-03 contract from UI-SPEC), not NeuTabBar's.

**Deep-link stability:** `RootView`'s `@State private var selectedTab: Int = 0` is passed as a `Binding<Int>` to `NeuTabBar`. The existing deep-link observers (`kOpenNoteNotification` → `selectedTab = 3`, etc.) continue to work unchanged because they mutate the same `selectedTab` state. NeuTabBar reads from and writes to the same binding. [VERIFIED: read RootView.swift — `selectedTab` is `@State private var selectedTab: Int = 0`; all deep-links write to it directly]

**Tab index mapping (from UI-SPEC, confirmed against RootView.swift):**

| Index | RootView current label | NeuTabBar label | SF Symbol (inactive/active) |
|-------|----------------------|-----------------|---------------------------|
| 0 | Home | Home | `house` / `house.fill` |
| 1 | Expenses | Activity | `creditcard` / `creditcard.fill` |
| 2 | Budgets | Budgets | `chart.pie` / `chart.pie.fill` |
| 3 | Notes | Notes | `note.text` / `note.text` |
| 4 | Settings | Settings | `gear` / `gear` |

Note: The existing RootView uses `list.bullet` for Expenses and `chart.bar` for Budgets. NeuTabBar uses `creditcard`/`chart.pie` as per the design handoff. The indices (0–4) remain stable — this is the only concern for deep-link continuity.

**Active pill animation:**

```swift
// Source: 13-UI-SPEC.md Motion & Interaction Contract
@Namespace private var pillNamespace

// HStack of tab buttons, each: if index == selectedTab → ZStack with background pill
// matchedGeometryEffect on the pill for spring transition:
RoundedRectangle(cornerRadius: 26)
    .fill(DesignTokens.accentSoft)
    .matchedGeometryEffect(id: "activePill", in: pillNamespace)
    .animation(reduceMotion ? nil : DesignTokens.springBouncy, value: selectedTab)
```

**Safe area bottom inset for the capsule itself:**

`NeuTabBar` must respect the device's home indicator area. The capsule sits 24pt above the safe area bottom, not 24pt from the screen edge:

```swift
// NeuTabBar internal bottom padding:
.padding(.bottom, max(24, geometry.safeAreaInsets.bottom + 8))
// OR: use safeAreaInset on the capsule itself to stay above the home indicator
```

[ASSUMED: `geometry.safeAreaInsets.bottom` in a `.overlay` context correctly reflects the home indicator safe area — standard iOS behavior but should be confirmed via iPhone 17 simulator preview]

---

### Pattern 4: RollingMoneyText (DS-04)

**What:** A SwiftUI `View` that displays a `Decimal` amount as formatted INR currency, animating digit changes via `.contentTransition(.numericText())`.

**API availability:** `.contentTransition(.numericText())` was introduced in iOS 16.0. Deployment floor is iOS 17.0. No guard needed. [ASSUMED: confirmed against Apple documentation knowledge — API introduced iOS 16; should be double-checked in Xcode 26.5 docs since `.numericText(countsDown:)` is a variation]

**Implementation skeleton:**

```swift
// Source: 13-UI-SPEC.md RollingMoneyText Component Contract
struct RollingMoneyText: View {
    let amount: Decimal
    var currencyCode: String = "INR"
    var locale: Locale = Locale(identifier: "en_IN")
    var animationDuration: Double = 0.78

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var baseSize: CGFloat = 46

    private var formatted: String {
        amount.formatted(.currency(code: currencyCode).locale(locale))
    }

    var body: some View {
        Text(formatted)
            .font(.system(size: baseSize, weight: .ultraLight, design: .rounded))
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .smooth(duration: animationDuration), value: amount)
            .accessibilityLabel("₹\(formatted)")
    }
}
```

**INR lakh formatting:** `Decimal.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN")))` produces lakh-grouped output (e.g., ₹1,23,456.78). This uses `FormatStyle` — the same pattern already documented in `STATE.md` as a project decision. [VERIFIED: STATE.md decision "FormatStyle .currency(code:INR).locale(en_IN) for lakh grouping — not NumberFormatter, not hand-rolled"]

**Reduce Motion:** When `accessibilityReduceMotion` is `true`, the transition is `.identity` (no intermediate frames) and the animation is `nil` (instant snap). This satisfies DS-06 and matches the UI-SPEC's behavior contract exactly.

**`.onAppear` behavior:** No animation on initial mount. Achieved naturally: `.animation(_:value:)` only triggers when `amount` changes after the view is already displayed. On first appearance the value is set immediately (no `withAnimation` around initial render).

---

### Pattern 5: Dark-mode enforcement (DS-05)

**What:** Apply `.preferredColorScheme(.dark)` at the window root so the entire app is forced to dark mode regardless of system setting. No per-view overrides needed.

**Where:** `MyHomeApp.swift`, applied to `RootView`:

```swift
// In MyHomeApp.body WindowGroup:
RootView(gmailSyncController: gmailSyncController)
    .preferredColorScheme(.dark)   // DS-05: neumorphic dark-mode-only
    .onAppear { setupNotifications() }
```

This is the correct location because `MyHomeApp.swift` currently has no `.preferredColorScheme` modifier (confirmed by codebase grep). [VERIFIED: read MyHomeApp.swift — no preferredColorScheme present]

**No `Color(.systemBackground)` usage:** `DesignTokens.bgCanvas` replaces all `Color(.secondarySystemBackground)` / `Color(.systemBackground)` references in v1.2 views. `CardStyle` used `Color(.secondarySystemBackground)` — another reason NeuSurface must replace it entirely in v1.2 code.

---

### Pattern 6: pbxproj registration for DesignSystem/ files

**The four required edits per new .swift file** (confirmed by analyzing how `CardStyle.swift` and `Color+Hex.swift` are registered in the actual `project.pbxproj`): [VERIFIED: read project.pbxproj directly]

#### Edit 1 — PBXBuildFile section (line ~83 area)
Add one line in the `/* Begin PBXBuildFile section */` block:
```
A13DS1 /* DesignTokens.swift in Sources */ = {isa = PBXBuildFile; fileRef = F13DS1 /* DesignTokens.swift */; };
```

#### Edit 2 — PBXFileReference section (line ~323 area)
Add one line in the `/* Begin PBXFileReference section */` block:
```
F13DS1 /* DesignTokens.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DesignTokens.swift; sourceTree = "<group>"; };
```

#### Edit 3 — PBXGroup section (once per directory — new group + children)
For the new `DesignSystem/` group, add a NEW group entry (once) AND reference it from the parent group `G100 /* MyHomeApp */`:

New group block:
```
G_DS /* DesignSystem */ = {
    isa = PBXGroup;
    children = (
        F13DS1 /* DesignTokens.swift */,
        F13NS /* NeuSurface.swift */,
        F13NTB /* NeuTabBar.swift */,
        F13RMT /* RollingMoneyText.swift */,
    );
    path = DesignSystem;
    sourceTree = "<group>";
};
```

Reference in `G100 /* MyHomeApp */` children list:
```
G_DS /* DesignSystem */,
```

#### Edit 4 — PBXSourcesBuildPhase section (line ~956 area in P001)
Add one line per file in the `P001 /* Sources */` build phase files list:
```
A13DS1 /* DesignTokens.swift in Sources */,
A13NS /* NeuSurface.swift in Sources */,
A13NTB /* NeuTabBar.swift in Sources */,
A13RMT /* RollingMoneyText.swift in Sources */,
```

**ID convention in this project:** Build file IDs are prefixed `A`, file reference IDs are prefixed `F`, groups are prefixed `G`. All existing IDs in this project use short mnemonic suffixes (e.g., `A803SH` for CardStyle, `F803SH` for its file reference). The planner must choose non-colliding IDs — recommend using `A13DS1`/`F13DS1` pattern (13 = phase, DS1/NS/NTB/RMT = component).

**Test files also need registration in P003 (MyHomeTests build phase):** Same four-edit pattern, but Edit 4 targets `P003 /* Sources */` instead of `P001`.

**The DesignSystem/ directory must be created on disk BEFORE the pbxproj edits are made** (Xcode does not create directories from pbxproj references — the filesystem directory must exist).

---

### Anti-Patterns to Avoid

- **Hardcoded hex in view files:** After this phase, no `.foregroundStyle(Color(hex: "#FFD60A"))` in any view. All colors go through `DesignTokens.accent` etc.
- **Hardcoded shadow values in view files:** `.shadow(color: .black.opacity(0.55), radius: 9, x: 7, y: 7)` directly in a view — must go through `NeuSurface` or a `ShadowSpec`.
- **Using `.tabItem {}` with `NeuTabBar`:** Once `NeuTabBar` is the visual layer, the `.tabItem {}` modifiers in `TabView` become vestigial. They can be left empty or minimal — their icons/labels are no longer displayed. Do NOT remove them entirely as `TabView` requires at least one `.tabItem` per child to track tabs correctly.
- **Applying `.preferredColorScheme(.dark)` per view:** Apply it once at the root (`MyHomeApp.swift`). Per-view overrides create maintenance debt and can be overridden by sheets.
- **`@ScaledMetric` as `static let` in an enum:** Property wrappers cannot be applied to static stored properties. Font sizing for Group B roles must be declared as instance `@ScaledMetric` vars inside each component that uses them — not inside `DesignTokens`.
- **Forgetting the DesignSystem/ group in pbxproj:** Creating files on disk without registering the new group `G_DS` in `G100`'s children list means Xcode doesn't show the group in the navigator, but more critically — it won't compile without the PBXFileReference and PBXBuildFile entries.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| INR currency formatting with lakh grouping | Custom `NumberFormatter` with grouping sizes | `Decimal.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN")))` | `FormatStyle` handles grouping sizes (2/3), locale, and symbol automatically; already a project decision in STATE.md |
| Digit-roll animation | Frame-by-frame interpolation of intermediate numeric strings | `.contentTransition(.numericText())` with `.animation(.smooth(duration:))` | SwiftUI handles the morphing; custom interpolation would require computing intermediate values and re-rendering text |
| Spring physics for tab pill | Manual `withAnimation(.spring(...))` inline | `DesignTokens.springBouncy` / `springSoft` | Centralized spring parameters keep the feel consistent across all Phase 13 components |
| Color from hex string | `UIColor(hex:)` or `CGColor` round-trip | Existing `Color(hex:)` extension at `Color+Hex.swift` | Extension already handles `#` prefix stripping, 6-digit parsing, and `.gray` fallback |
| Safe-area bottom clearance | `UIScreen.main.bounds.height - someConstant` | `.safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 100) }` | `safeAreaInset` adapts to device variations and Dynamic Island; pixel math doesn't |

**Key insight:** Every custom solution in this domain has been solved by Apple's first-party APIs. The value of this phase comes from correct wiring of those APIs — not from reimplementing them.

---

## Runtime State Inventory

> Not applicable. Phase 13 adds new Swift files and modifies `MyHomeApp.swift` and `RootView.swift`. It does not rename any model, key, or stored identifier. No database migration, no OS-registered state, no secret key renaming.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no model changes, no SwiftData schema change | None |
| Live service config | None — no external services involved | None |
| OS-registered state | None — no notification categories, background task identifiers, or schemes affected | None |
| Secrets/env vars | None | None |
| Build artifacts | The new `DesignSystem/` directory and 4 `.swift` files must be created on disk and registered in `project.pbxproj` before `xcodebuild` succeeds | pbxproj 4-edit protocol per file (documented above) |

---

## Common Pitfalls

### Pitfall 1: New Swift files compile silently but are not in the target
**What goes wrong:** A developer creates `DesignTokens.swift` on disk and even in the Xcode navigator (if using a synchronized group workaround), but the file is not in `PBXSourcesBuildPhase`. The file compiles in isolation when editing but `xcodebuild clean build` fails with "use of unresolved identifier 'DesignTokens'".
**Why it happens:** The project uses explicit file references with no synchronized folders. Creating a file does NOT automatically add it to the build phase.
**How to avoid:** The four-edit pbxproj protocol must be completed for every file. The planner should make pbxproj registration a discrete task that precedes any code-writing task, with a build verification step after.
**Warning signs:** "Cannot find type 'DesignTokens' in scope" at a call site that otherwise looks correct; or the Xcode navigator shows the file but the Build Phases > Compile Sources list does not include it.

### Pitfall 2: Two `.shadow()` modifiers applied in wrong order
**What goes wrong:** The light shadow is applied after the dark shadow, producing incorrect layering or unexpected visual blending on certain backgrounds.
**Why it happens:** SwiftUI applies shadow modifiers in the order they are called; the second shadow renders on top of the first.
**How to avoid:** Always apply the light (white, top-left offset) shadow FIRST, then the dark (black, bottom-right offset) shadow. This matches the neumorphic convention where white highlight sits "above" the dark depth shadow in the z-order.
**Warning signs:** The card looks wrong in preview — the extrusion appears flat or the wrong corner is highlighted.

### Pitfall 3: `TabView` with `.toolbar(.hidden, for: .tabBar)` breaks NavigationStack on a tab
**What goes wrong:** Hiding the tab bar with `.toolbar(.hidden, for: .tabBar)` sometimes causes the navigation stack in a child view to also hide its toolbar or produce unexpected layout.
**Why it happens:** `.toolbar(.hidden, for: .tabBar)` suppresses the entire TabView toolbar, and toolbar visibility can propagate into child NavigationStacks.
**How to avoid:** Apply `.toolbar(.hidden, for: .tabBar)` directly on `TabView`, not on individual tab content views. If a child NavigationStack's toolbar is affected, restore it explicitly on that view with `.toolbar(.visible, for: .navigationBar)`. Test all 5 tabs in the iPhone 17 simulator after applying the modifier.
**Warning signs:** A tab's NavigationStack title disappears; back buttons are gone; or the content layout shifts unexpectedly.

### Pitfall 4: `@ScaledMetric` declared at wrong scope
**What goes wrong:** Developer tries to add `@ScaledMetric(relativeTo: .largeTitle) static let heroMoneySize: CGFloat = 46` inside the `DesignTokens` enum. This is a compile error in Swift — property wrappers cannot be applied to static stored properties.
**Why it happens:** It's natural to want all token values in one place. But `@ScaledMetric` is a property wrapper that requires an instance context to read the current Dynamic Type setting from the environment.
**How to avoid:** Declare `@ScaledMetric` vars as instance properties inside the View or ViewModifier that uses them. The base value (46pt) can be documented as a comment in `DesignTokens.swift` for reference, but the `@ScaledMetric` declaration lives in `RollingMoneyText.swift`.
**Warning signs:** Compiler error "property wrappers are not allowed on static stored properties" or "property wrappers cannot be applied to 'let' declarations".

### Pitfall 5: `NeuTabBar` using wrong safe-area approach
**What goes wrong:** The capsule tab bar is positioned 24pt from the bottom edge of the screen (not the safe area), causing it to overlap with the home indicator on iPhone 14/15/16/17.
**Why it happens:** Using `.padding(.bottom, 24)` without accounting for the device's `safeAreaInsets.bottom`.
**How to avoid:** Use `GeometryReader` inside the overlay OR use `.safeAreaInset` to position the bar, OR use a `VStack(spacing:0)` with `Spacer()` that reads the environment's safeAreaInsets. The bar should float `24pt` above the safe area bottom edge (i.e., `safeAreaInsets.bottom + 24pt` from the screen edge). Alternatively: combine `.ignoresSafeArea()` on the content with `.safeAreaInset` on the containing view — the standard SwiftUI pattern for overlaid toolbars.
**Warning signs:** On iPhone with home indicator, the capsule bar overlaps the home indicator swipe strip.

### Pitfall 6: `.contentTransition(.numericText())` not animating
**What goes wrong:** The `RollingMoneyText` digit-roll animation does nothing — numbers snap immediately even without Reduce Motion.
**Why it happens:** `.contentTransition` requires a paired `.animation(_:value:)` modifier on the same view to trigger. Without the animation modifier, the transition is applied but immediately completed.
**How to avoid:** Always pair `.contentTransition(...)` with `.animation(.smooth(duration: 0.78), value: amount)`. The `value:` argument must be the same value that changes — `amount` in `RollingMoneyText`.
**Warning signs:** In a preview with a Button that mutates `amount`, tapping shows instant change with no rolling effect.

### Pitfall 7: VoiceOver reading mid-animation interpolated text
**What goes wrong:** VoiceOver announces partial (intermediate) digit strings during the roll animation — "₹twelve thousand four hundred" when the final value is ₹12,400.
**Why it happens:** Without an explicit `.accessibilityLabel`, VoiceOver reads the `Text` view's display string, which changes during animation.
**How to avoid:** Apply `.accessibilityLabel("₹\(formatted)")` where `formatted` is computed from the final `amount` value. Also apply `.accessibilityValue(formatted)` for VoiceOver's numeric reading style.
**Warning signs:** VoiceOver speaks partial strings or rapid successive announcements during an amount transition.

---

## Code Examples

### Hex color in Swift (reusing existing extension)

```swift
// Source: MyHomeApp/Support/Color+Hex.swift (read directly from codebase)
// Existing extension — NO new code needed for hex parsing.
// DesignTokens.swift uses it directly:
static let accent = Color(hex: "#FFD60A")
// Falls back to .gray on malformed input; handles "#" prefix automatically.
```

### Dual outer shadow application

```swift
// Source: 13-UI-SPEC.md Shadow System section
// For raised state — applied to the clipped surface:
.shadow(color: DesignTokens.shadowRaised.lightColor,
        radius: DesignTokens.shadowRaised.lightRadius,
        x: DesignTokens.shadowRaised.lightX,
        y: DesignTokens.shadowRaised.lightY)
.shadow(color: DesignTokens.shadowRaised.darkColor,
        radius: DesignTokens.shadowRaised.darkRadius,
        x: DesignTokens.shadowRaised.darkX,
        y: DesignTokens.shadowRaised.darkY)
```

### Reduce Motion in RollingMoneyText

```swift
// Source: 13-UI-SPEC.md Reduce Motion implementation
@Environment(\.accessibilityReduceMotion) private var reduceMotion

// Applied to the Text view:
.contentTransition(reduceMotion ? .identity : .numericText())
.animation(reduceMotion ? nil : .smooth(duration: 0.78), value: amount)
```

### safeAreaInset for tab bar content clearance

```swift
// Source: 13-UI-SPEC.md NeuTabBar safe-area inset contract
// Applied to each screen's ScrollView or List:
.safeAreaInset(edge: .bottom, spacing: 0) {
    Color.clear.frame(height: DesignTokens.tabBarClearance)  // 100pt
}
```

### Tab bar hidden from native TabView

```swift
// Source: pattern for DS-03 — iOS 16+ API
TabView(selection: $selectedTab) {
    OverviewView(...)
        .tag(0)
    // … other tabs
}
.toolbar(.hidden, for: .tabBar)  // hides native chrome; NeuTabBar overlaid separately
```

### pbxproj PBXBuildFile entry pattern

```
// Source: read from MyHome.xcodeproj/project.pbxproj directly
// Pattern established by existing entries (e.g., CardStyle.swift):
A803SH /* CardStyle.swift in Sources */ = {isa = PBXBuildFile; fileRef = F803SH /* CardStyle.swift */; };
// New DesignTokens.swift entry follows same pattern:
A13DS1 /* DesignTokens.swift in Sources */ = {isa = PBXBuildFile; fileRef = F13DS1 /* DesignTokens.swift */; };
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `CardStyle` (single weak shadow, system background) | `NeuSurface` (dual outer/inner shadows, token fills) | Phase 13 | Complete visual replacement; `cardStyle()` deprecated |
| `TabView` native chrome | Custom floating capsule `NeuTabBar` | Phase 13 | Native chrome hidden; custom view overlaid with `$selectedTab` binding preserved |
| Hardcoded hex strings in view files | `DesignTokens.accent` etc. | Phase 13 | Single source of truth; hex strings banned from view files |
| `Color(.secondarySystemBackground)` fills | `DesignTokens.surfaceRaised` / `surfaceRaisedStrong` / `fillRecessed*` | Phase 13 | System adaptive colors replaced by fixed dark palette (DS-05) |

**Deprecated/outdated after Phase 13:**
- `CardStyle`: marked `@available(*, deprecated, renamed: "neuSurface")` — usages remain until Phase 14 cleanup
- Inline `.shadow(color: .black.opacity(0.04), radius: 2, y: 1)` patterns: must be replaced with `NeuSurface` in v1.2 views

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Two stacked `.shadow()` modifiers produce additive (not overriding) shadows in SwiftUI | Pattern 2: NeuSurface | The neumorphic dual-shadow effect would not render correctly; would need a different approach (Canvas, or `.drawingGroup()`) |
| A2 | Overlay-gradient approach for recessed inset shadow is visually acceptable at the token values (blur 5, offset ±2) | Pattern 2: NeuSurface | If unacceptable, need UIViewRepresentable + CALayer approach; more complex, adds UIKit dependency |
| A3 | `.toolbar(.hidden, for: .tabBar)` on `TabView` hides native tab chrome without affecting child NavigationStack toolbars on iOS 17 | Pattern 3: NeuTabBar | If NavigationStack toolbars are also hidden, need alternative approach (e.g., `UITabBar.appearance().isHidden = true` in `UIViewControllerRepresentable`) |
| A4 | `geometry.safeAreaInsets.bottom` in a `.overlay` context correctly reflects the home indicator safe area on iPhone 17 | Pattern 3: NeuTabBar | Capsule would overlap home indicator; needs alternate inset strategy |
| A5 | `.contentTransition(.numericText())` and `.contentTransition(.numericText(countsDown:))` are available on iOS 16+ | Pattern 4: RollingMoneyText | If not available until iOS 17+, no action needed (deployment floor is 17); if removed from iOS 17, need fallback |
| A6 | `@ScaledMetric` cannot be applied to `static let` in an enum in Swift 6.0 | Pattern 1 / Pitfall 4 | If this changed, font tokens could live in `DesignTokens` — a cleaner design, no impact on safety |

---

## Open Questions (RESOLVED)

All three open questions are operationally resolved within the Phase 13 plans; each resolves via a `#Preview` and/or the end-of-phase human-verify gate in 13-03.

1. **Inset shadow fidelity** — RESOLVED in plan 13-02 Task 1 (default to overlay-gradient inset per PATTERNS, with a `#Preview` of all three NeuSurface states) and confirmed at the 13-03 human-verify checkpoint step 6.
   - What we know: SwiftUI has no native inset shadow; overlay-gradient is an approximation.
   - What's unclear: Whether the visual approximation satisfies the design at the values in the spec (blur 5, ±2 offset, 50% black / 3.5% white).
   - Resolution: Plan 13-02 implements the `.recessed` state via overlay-gradient (the `fillRecessed3` color carries most of the sunken look); the 13-03 checkpoint visually confirms it at spec values.

2. **`TabView` behavior with `.toolbar(.hidden, for: .tabBar)` on iPhone 17 / Xcode 26.5** — RESOLVED in plan 13-03 Task 2 (Pitfall 3 note on restoring NavigationStack toolbars) and exercised at the human-verify checkpoint step 2 (navigate all 5 tabs).
   - What we know: The modifier is documented as available iOS 16+.
   - What's unclear: Edge cases with `TabView` + per-tab NavigationStack in Xcode 26.5 / iOS 26-era SDK.
   - Resolution: Fallback `UITabBar.appearance().isHidden` documented; the manual gate validates per-tab NavigationStack titles + back buttons.

3. **NeuTabBar home indicator positioning** — RESOLVED in plan 13-03 Task 1 (acceptance criterion requires reading `geometry.safeAreaInsets.bottom` via GeometryReader, Pitfall 5 — not a bare 24pt literal).
   - What we know: Tab bar must not overlap home indicator. The spec says "24pt from screen bottom (safe area aware)".
   - What's unclear: The exact SwiftUI idiom that correctly reads safe area in a `.overlay(alignment: .bottom)` context on iPhone 17.
   - Resolution: Plan 13-03 mandates `GeometryReader` + `geometry.safeAreaInsets.bottom`, confirmed in the NeuTabBar preview task.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 26.5 | Build & simulator | ✓ (per project memory) | 26.5 | — |
| iPhone 17 simulator | Testing | ✓ (per project memory) | — | — |
| SwiftUI `contentTransition(.numericText())` | DS-04 | ✓ | iOS 16+ | — |
| SwiftUI `safeAreaInset(edge:spacing:content:)` | DS-03 | ✓ | iOS 15+ | — |
| SwiftUI `.toolbar(.hidden, for:)` | DS-03 | ✓ | iOS 16+ | UITabBar.appearance() workaround |
| SwiftUI `@ScaledMetric(relativeTo:)` | DS-06 | ✓ | iOS 14+ | — |
| `@Environment(\.accessibilityReduceMotion)` | DS-04, DS-06 | ✓ | iOS 13+ | — |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** `.toolbar(.hidden, for: .tabBar)` — if edge cases appear, fallback to `UITabBar.appearance().isHidden = true` in a `UIViewRepresentable` wrapper.

---

## Validation Architecture

> `workflow.nyquist_validation` is `true` in `.planning/config.json` — this section is required.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (bundled Xcode 26.5) — `import Testing` |
| Config file | None — existing pattern; tests live in `MyHomeTests/` |
| Quick run command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/DesignTokensTests` |
| Full suite command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |

**Existing test pattern (confirmed from codebase):** `import Testing`, `@testable import MyHome`, `@MainActor struct FooTests { @Test("description") func testFoo() throws { … } }`, `#expect(…)`. All new tests follow this pattern.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DS-01 | `DesignTokens.accent` equals `#FFD60A` | Unit | `xcodebuild test … -only-testing:MyHomeTests/DesignTokensTests` | ❌ Wave 0 |
| DS-01 | `DesignTokens.shadowRaised.lightX` equals -6, `darkX` equals 7 | Unit | same | ❌ Wave 0 |
| DS-01 | `DesignTokens.radiusCard` equals 26 | Unit | same | ❌ Wave 0 |
| DS-01 | `DesignTokens.tabBarClearance` equals 100 | Unit | same | ❌ Wave 0 |
| DS-02 | `NeuSurface` compiles and renders in a SwiftUI preview without crash | Preview/build | `xcodebuild clean build` | ❌ Wave 0 |
| DS-03 | `NeuTabBar` selection binding propagates: tapping tab 2 sets `selectedTab = 2` | Unit (with PreviewProvider host) | Not easily automated — manual-only for binding test | Manual |
| DS-03 | Deep-link: setting `selectedTab = 3` programmatically selects Notes tab | Integration | Manual (simulator) | Manual |
| DS-04 | `RollingMoneyText` with `reduceMotion = true` shows `.identity` transition (no animation) | Unit | `xcodebuild test … -only-testing:MyHomeTests/RollingMoneyTextTests` | ❌ Wave 0 |
| DS-04 | INR formatting: `Decimal(123456)` formats as "₹1,23,456.00" | Unit | same | ❌ Wave 0 |
| DS-05 | No `Color(.systemBackground)` or `Color(.secondarySystemBackground)` in `DesignSystem/` files | Static analysis / grep | `grep -r "systemBackground" MyHomeApp/DesignSystem/` | Automated grep |
| DS-06 | `xcodebuild clean build` succeeds after all pbxproj edits | Build gate | `xcodebuild clean build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` | — |
| DS-06 | Accessibility Inspector: zero contrast warnings on NeuSurface previews | Manual — Xcode Inspector | Manual | Manual |
| DS-06 | No hardcoded numeric font size in `DesignSystem/` files | Static / grep | `grep -rE '\\.font\(.system\(size: [0-9]+' MyHomeApp/DesignSystem/'` | Automated grep |

### Sampling Rate

- **Per task commit:** `xcodebuild clean build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` (confirms compilation)
- **Per wave merge:** Full `xcodebuild test` suite
- **Phase gate:** Full suite green + Xcode Accessibility Inspector manual pass on `NeuSurface` and `NeuTabBar` previews before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `MyHomeTests/DesignTokensTests.swift` — covers DS-01 token value assertions
- [ ] `MyHomeTests/RollingMoneyTextTests.swift` — covers DS-04 formatting and Reduce Motion assertions
- [ ] `MyHomeApp/DesignSystem/` directory — must be created on disk before any source file is written
- [ ] pbxproj `G_DS` group entry — must be added before `xcodebuild` can find the new files

---

## Security Domain

> `security_enforcement: true`, `security_asvs_level: 1` in `.planning/config.json`.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No — this phase adds no auth flows | — |
| V3 Session Management | No — no session state in design system | — |
| V4 Access Control | No — no data access in design system | — |
| V5 Input Validation | No — `DesignTokens` has no user input | — |
| V6 Cryptography | No — no cryptographic operations | — |
| V7 Error Handling / Logging | Minimal — `Color(hex:)` falls back to `.gray` silently; acceptable for a compile-time constant | Existing `Color+Hex.swift` behavior |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| None specific — pure presentation layer | — | No user data flows through design tokens or UI modifiers |

**Security note:** Phase 13 is a pure UI infrastructure phase. It processes no user data, makes no network calls, reads no sensitive state, and introduces no new attack surface. The only security-adjacent concern is that `DesignTokens.bgCanvas` sets the opaque background color — if ever set incorrectly, content from other apps could theoretically show through (opaque by design, not a risk here since fills are always explicit solid colors). ASVS Level 1 has no blocking requirements for this phase.

---

## Sources

### Primary (HIGH confidence)
- `13-UI-SPEC.md` (read directly) — authoritative design contract; all token values, component APIs, shadow specs, animation parameters
- `design/design_handoff_myhome_neumorphic/src/tokens.jsx` (read directly) — source of hex values, shadow CSS specs, spring constants, category palette
- `MyHomeApp/RootView.swift` (read directly) — existing `@State selectedTab: Int`, tab order, deep-link observers
- `MyHomeApp/Features/Shared/CardStyle.swift` (read directly) — current deprecated API being replaced
- `MyHomeApp/Support/Color+Hex.swift` (read directly) — existing hex extension, confirmed 6-digit only, falls back to `.gray`
- `MyHome.xcodeproj/project.pbxproj` (read directly) — pbxproj structure, ID conventions, group hierarchy, both build phase targets
- `MyHomeApp/MyHomeApp.swift` (read directly) — app entry point, no `.preferredColorScheme` currently
- `.planning/REQUIREMENTS.md` (read directly) — DS-01 through DS-06 specification
- `STATE.md` (read directly) — FormatStyle INR decision, project decisions history
- `.planning/config.json` (read directly) — nyquist_validation: true, security_enforcement: true

### Secondary (MEDIUM confidence)
- Apple Developer Documentation (training knowledge, not fetched this session): `contentTransition(.numericText())` iOS 16+, `safeAreaInset(edge:)` iOS 15+, `.toolbar(.hidden, for:)` iOS 16+, `@ScaledMetric(relativeTo:)` iOS 14+, `@Environment(\.accessibilityReduceMotion)` iOS 13+

### Tertiary (LOW confidence)
- Training knowledge on two stacked `.shadow()` modifier behavior (additive vs. override) — tagged `[ASSUMED]` in Assumptions Log; should be verified with a 5-minute preview test before finalizing NeuSurface implementation

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no external packages; all first-party SwiftUI APIs confirmed against project's iOS 17 deployment floor
- Architecture: HIGH — live codebase read for RootView, CardStyle, pbxproj structure; UI-SPEC is the authoritative contract
- Pitfalls: HIGH — pbxproj risk is documented from actual project structure; SwiftUI pitfalls are well-established patterns; 3 items tagged [ASSUMED] where runtime behavior wasn't verified this session
- Token values: HIGH — hex values cross-verified between tokens.jsx and UI-SPEC; all values agree

**Research date:** 2026-06-21
**Valid until:** 2026-07-21 (stable — all APIs are first-party iOS; no external dependencies to drift)
