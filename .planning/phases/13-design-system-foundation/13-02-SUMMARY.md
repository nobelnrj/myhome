---
phase: 13-design-system-foundation
plan: "02"
subsystem: ui
tags: [swiftui, design-system, neumorphic, viewmodifier, accessibility, animation, ds-02, ds-04, ds-06]

requires:
  - phase: 13-design-system-foundation
    plan: "01"
    provides: DesignTokens.swift (all tokens) + pre-registered pbxproj entries for NeuSurface.swift and RollingMoneyText.swift

provides:
  - NeuSurface.swift — full ViewModifier with raised/floating/recessed states, dual shadow system, rim overlay, recessed gradient, isInteractive glassBorder (DS-02, DS-06)
  - RollingMoneyText.swift — full animated INR readout with color param, @ScaledMetric Dynamic Type, Reduce Motion gate, VoiceOver label (DS-04, DS-06)
  - CardStyle.swift — deprecated (renamed: neuSurface), still compiling
  - RollingMoneyTextTests.swift — 2 INR lakh-grouping assertions, both green

affects:
  - 13-03 (NeuTabBar full implementation — consumes same DesignTokens pattern)
  - 14-overview-redesign (first consumer of .neuSurface() and RollingMoneyText)
  - 15-expenses-redesign (same)
  - 16-ai-insights (same)

tech-stack:
  added: []
  patterns:
    - "NeuSurface dual-shadow ordering: light shadow FIRST, dark shadow SECOND (RESEARCH Pitfall 2) — per spec, the OuterShadowModifier applies lightColor/lightRadius/lightX/lightY then darkColor/etc"
    - "NeuSurface sub-modifiers: OuterShadowModifier + RimOverlayModifier + RecessedOverlayModifier + InteractiveBorderModifier — each private struct handles one concern"
    - "Recessed inset approximation: LinearGradient overlay (black 30% → white 2.5%, topLeading→bottomTrailing) + fillRecessed3 fill; no UIViewRepresentable needed"
    - "RollingMoneyText color contract: callers pass DesignTokens.negative for negative amounts; defaults to DesignTokens.label — no sign logic inside component"
    - "contentTransition(.numericText()) MUST be paired with .animation(_:value:) — standalone contentTransition is silent (Pitfall 6)"
    - "DS-06 Reduce Motion: .identity transition + nil animation = zero intermediate frames; same @Environment pattern used in both NeuTabBar (Plan 03) and RollingMoneyText"

key-files:
  created: []
  modified:
    - MyHomeApp/DesignSystem/NeuSurface.swift
    - MyHomeApp/DesignSystem/RollingMoneyText.swift
    - MyHomeApp/Features/Shared/CardStyle.swift
    - MyHomeTests/RollingMoneyTextTests.swift

key-decisions:
  - "NeuSurface isInteractive parameter (not automatic): interactive surfaces pass isInteractive:true to get the glassBorder DS-06 affordance; non-interactive surfaces (decorative backgrounds) omit it — caller decides"
  - "Recessed shadow as overlay gradient (not UIViewRepresentable): SwiftUI has no inset shadow; LinearGradient overlay on fillRecessed3 background is sufficient — matches RESEARCH Open Question 1 recommendation"
  - "RollingMoneyText: no font: parameter exposed (deliberate DS-06 deviation from UI-SPEC); instance @ScaledMetric anchored to .largeTitle ensures Dynamic Type scaling without a hardcoded literal in the API"
  - "RimOverlayModifier strokeBorder with LinearGradient (white 4.5% → black 30%): replicates shadowRim inner-light/inner-dark spec via a stroke gradient rather than impossible inset .shadow()"

patterns-established:
  - "Private sub-modifier pattern: each visual concern (outer shadow, rim, recessed overlay, interactive border) is its own private ViewModifier struct — keeps NeuSurface.body a readable chain"
  - "@ScaledMetric instance property (not static): confirmed again — use in RollingMoneyText follows Plan 01 documentation that static stored @ScaledMetric is a compiler error"
  - "Deprecation with @available: @available(*, deprecated, renamed: \"neuSurface\") on cardStyle() — keeps it compiling while emitting warnings at call sites"

requirements-completed: [DS-02, DS-04, DS-06]

duration: ~25min
completed: 2026-06-21
---

# Phase 13 Plan 02: NeuSurface + RollingMoneyText Summary

**NeuSurface ViewModifier (raised/floating/recessed dual-shadow system) and animated RollingMoneyText (INR lakh grouping, Reduce Motion, VoiceOver) — both token-driven, both DS-06 accessible, build and tests green**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-06-21T05:20:00Z
- **Completed:** 2026-06-21T05:55:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Replaced `NeuSurface.swift` stub with full implementation: `NeuSurfaceState` enum (raised/floating/recessed), four private sub-modifiers (`OuterShadowModifier`, `RimOverlayModifier`, `RecessedOverlayModifier`, `InteractiveBorderModifier`), `View.neuSurface()` extension with `isInteractive` parameter for DS-06 glassBorder boundary affordance, and a `#Preview` showing all three states stacked on `DesignTokens.bgCanvas`
- Replaced `RollingMoneyText.swift` stub with full implementation: `color: Color = DesignTokens.label` parameter with `.foregroundStyle(color)` (UI-SPEC Phase 14 color contract), instance `@ScaledMetric(relativeTo: .largeTitle) private var baseSize = 46` for DS-06 Dynamic Type, `accessibilityReduceMotion` gate (`.identity` + `nil` animation = zero intermediate frames), `.accessibilityLabel` with final formatted value, and an interactive `#Preview` with toggle buttons for the digit-roll demo and Reduce Motion manual test path
- Deprecated `CardStyle.cardStyle()` with `@available(*, deprecated, renamed: "neuSurface")` — still compiles; Phase 14 removes usages
- `RollingMoneyTextTests`: replaced scaffold with 2 real assertions (`inrLakhFormatting`, `inrLakhCroreFormatting`) — both green under `xcodebuild test -only-testing:MyHomeTests/RollingMoneyTextTests`

## Task Commits

1. **Task 1: NeuSurface full implementation + CardStyle deprecation** - `d4f454b` (feat)
2. **Task 2: RollingMoneyText full animation + INR lakh tests** - `3f1e569` (feat)

**Plan metadata:** _(docs commit follows)_

## Files Modified

- `MyHomeApp/DesignSystem/NeuSurface.swift` — full ViewModifier: dual outer shadow, rim overlay, recessed gradient, isInteractive glassBorder, Preview
- `MyHomeApp/DesignSystem/RollingMoneyText.swift` — full animated component: color param, @ScaledMetric, Reduce Motion gate, accessibilityLabel, Preview
- `MyHomeApp/Features/Shared/CardStyle.swift` — added @available(*, deprecated, renamed: "neuSurface") to cardStyle() extension
- `MyHomeTests/RollingMoneyTextTests.swift` — 2 @Test INR lakh-grouping assertions (both green)

## Decisions Made

- `isInteractive` is an explicit parameter (not auto-detected from context): callers who wrap tappable content opt in to the glassBorder stroke; decorative surfaces don't pay for an unneeded overlay
- Recessed shadow implemented as LinearGradient overlay on `fillRecessed3` fill (no UIViewRepresentable): the darker fill color plus the black-to-white gradient provides sufficient depth cue; avoids complexity confirmed in RESEARCH Open Question 1
- `RollingMoneyText` exposes no `font:` parameter: the instance `@ScaledMetric` approach is the only DS-06-compliant way to anchor to 46pt while scaling with Dynamic Type — a `font: Font` parameter would force callers to hardcode sizes

## Deviations from Plan

### Auto-fixed Issues

None.

### Deliberate Deviations (DS-06 compliance)

**1. [DS-06 compliance] RollingMoneyText: @ScaledMetric instance property instead of font: parameter**
- **Found during:** Task 2 implementation analysis
- **Issue:** UI-SPEC declares `font: Font = .system(size: 46, …)` as an API parameter. Exposing a fixed 46pt Font default passes a hardcoded pixel literal through the public API, making DS-06 Dynamic Type compliance the caller's responsibility (and likely to be violated).
- **Fix:** Instance `@ScaledMetric(relativeTo: .largeTitle) private var baseSize: CGFloat = 46` in the component; `.font(.system(size: baseSize, weight: .ultraLight, design: .rounded))` in the body. Size scales automatically with the user's preferred text size.
- **Code comment:** Added citing DS-06 as the plan instructed.
- **Plan reference:** Plan explicitly says "DELIBERATE DEVIATION FROM UI-SPEC — do NOT expose the UI-SPEC's font: parameter"

---

**Total deviations:** 1 deliberate DS-06 compliance deviation (documented in plan instructions, not an unexpected fix)

## Known Stubs

None — NeuSurface and RollingMoneyText are fully implemented. NeuTabBar.swift remains a stub (Plan 03).

## Verification Results

- `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` — BUILD SUCCEEDED
- `xcodebuild test -only-testing:MyHomeTests/RollingMoneyTextTests` — TEST SUCCEEDED (2/2 assertions green)
- `grep -rE "systemBackground" MyHomeApp/DesignSystem/` — 0 matches (DS-05 compliant)
- `grep -c "glassBorder" MyHomeApp/DesignSystem/NeuSurface.swift` — 7 (interactive boundary affordance present, DS-06)
- `grep -c "accessibilityReduceMotion" MyHomeApp/DesignSystem/RollingMoneyText.swift` — 2 (DS-06 Reduce Motion gate present)
- Manual: `baseSize` in `RollingMoneyText.body` is `@ScaledMetric` instance property (not literal) — confirmed in source

## Threat Surface Scan

No new security-relevant surface introduced. Both components are stateless presentation-layer views that render caller-supplied values. No network, persistence, auth, or trust-boundary crossing. No threat flags.

## Self-Check: PASSED

- [x] `MyHomeApp/DesignSystem/NeuSurface.swift` exists and contains `NeuSurface: ViewModifier`
- [x] `MyHomeApp/DesignSystem/RollingMoneyText.swift` exists and contains `struct RollingMoneyText: View`
- [x] `MyHomeApp/Features/Shared/CardStyle.swift` contains `deprecated, renamed: "neuSurface"`
- [x] `MyHomeTests/RollingMoneyTextTests.swift` contains `inrLakhFormatting` @Test
- [x] Commit `d4f454b` exists (Task 1)
- [x] Commit `3f1e569` exists (Task 2)

---
*Phase: 13-design-system-foundation*
*Completed: 2026-06-21*
