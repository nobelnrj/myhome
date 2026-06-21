---
phase: 13-design-system-foundation
plan: "03"
subsystem: ui
tags: [swiftui, design-system, neumorphic, tab-bar, matchedgeometryeffect, accessibility, dark-mode, ds-03, ds-05, ds-06]

requires:
  - phase: 13-design-system-foundation
    plan: "01"
    provides: DesignTokens.swift (accent, accentSoft, surfaceRaisedStrong, shadowFloat, radiusTabBar, tabBarHeight, tabBarBottomOffset, tabItemWidth, springBouncy, glassBorder) + pre-registered pbxproj entry for NeuTabBar.swift
  - phase: 13-design-system-foundation
    plan: "02"
    provides: NeuSurface dual-shadow + Reduce Motion @Environment pattern reused by NeuTabBar

provides:
  - NeuTabBar.swift — floating capsule tab bar reading/writing Binding<Int> selectedTab; 5-tab tuple at indices 0–4; matchedGeometryEffect sliding pill; safe-area-aware bottom offset; VoiceOver labels/hints (DS-03, DS-05, DS-06)
  - RootView.swift — native tab chrome hidden per-tab (.toolbar(.hidden, for: .tabBar)) + NeuTabBar overlaid at bottom; deep-link indices preserved (DS-03)
  - MyHomeApp.swift — single root .preferredColorScheme(.dark) forcing dark-mode-only (DS-05)

affects:
  - 14-overview-redesign (hosts NeuTabBar; screens must apply 100pt bottom clearance so content clears the floating capsule)
  - 15-analytics (same)
  - 16-ai-insights (same)

tech-stack:
  added: []
  patterns:
    - "Sliding active pill: RoundedRectangle + matchedGeometryEffect(id: \"activePill\", in: pillNamespace), animated with reduceMotion ? nil : DesignTokens.springBouncy (DS-06 Reduce Motion gate — jumps instantly, zero intermediate frames)"
    - "Native-chrome replacement: keep TabView(selection:) + all .tabItem/.tag intact (TabView needs them to track tabs), suppress visual chrome with .toolbar(.hidden, for: .tabBar) per tab, overlay NeuTabBar — binding-driven so kOpenNoteNotification deep-link (selectedTab=3) still works untouched"
    - "Safe-area-aware float: GeometryReader + .padding(.bottom, max(tabBarBottomOffset, geometry.safeAreaInsets.bottom + 8)) clears the home indicator (RESEARCH Pitfall 5 — not a bare literal)"
    - "Dual outer shadow ordering: shadowFloat light shadow FIRST, dark shadow SECOND (RESEARCH Pitfall 2), matching NeuSurface convention"
    - "DS-05 dark-mode-only: ONE .preferredColorScheme(.dark) at the app root in MyHomeApp, never per-view (RESEARCH Pattern 5)"

key-files:
  created:
    - MyHomeApp/DesignSystem/NeuTabBar.swift
  modified:
    - MyHomeApp/RootView.swift
    - MyHomeApp/MyHomeApp.swift

key-decisions:
  - "Per-tab .toolbar(.hidden, for: .tabBar) (not a single app-level call): the native bar otherwise renders doubled beneath NeuTabBar — applied to all five tab content roots (fix commit 58f5f27)"
  - "Capsule clipped with RoundedRectangle(cornerRadius: radiusTabBar) (not Capsule()): radiusTabBar (34pt) on the 62pt-tall bar matches the UI-SPEC continuous-corner spec exactly while keeping the rim/shadow geometry token-driven"
  - "GeometryReader-wrapped body constrained to a fixed height (tabBarHeight + tabBarBottomOffset + 34) so the overlay does not expand to fill and push content"

patterns-established:
  - "Binding-driven custom tab bar overlaying a chrome-hidden TabView — the reusable v1.2 navigation shell every Phase 14+ screen inherits"
  - "Active-pill matchedGeometryEffect + Reduce Motion gate — the standard DS-06 motion pattern across the design system (shared with RollingMoneyText)"

requirements-completed: [DS-03, DS-05, DS-06]

duration: ~35min
completed: 2026-06-21
---

# Phase 13 Plan 03: NeuTabBar + RootView Integration + Dark Mode Summary

**Floating capsule NeuTabBar (DS-03) with a matchedGeometryEffect sliding accent pill replaces the native tab chrome in RootView; the app is forced dark-mode-only (DS-05) via one root modifier; all five deep-link indices preserved. Code complete and build green — the blocking human-verify checkpoint (Accessibility Inspector + interactive tab/deep-link/Reduce Motion pass) remains outstanding as tracked debt.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-06-21
- **Tasks:** 2 auto (complete) + 1 human-verify checkpoint (outstanding)
- **Files:** 1 created, 2 modified

## Accomplishments

- Implemented `NeuTabBar.swift` (121 lines): `struct NeuTabBar` with `@Binding var selectedTab: Int`, `@Environment(\.accessibilityReduceMotion)`, `@Namespace pillNamespace`; the five-tab tuple at exact indices (0 Home, 1 Activity, 2 Budgets, 3 Notes, 4 Settings) with `.fill` SF Symbol variants when active; sliding pill via `matchedGeometryEffect(id: "activePill")` gated by `reduceMotion ? nil : DesignTokens.springBouncy`; `surfaceRaisedStrong` fill, `glassBorder` rim, dual `shadowFloat` outer shadow (light-first), safe-area-aware bottom offset; `accessibilityLabel`/`accessibilityHint("Tab N of 5")`; a `#Preview` over `bgCanvas` for the Accessibility Inspector target. Reads only `DesignTokens` — zero hardcoded `systemBackground`.
- Wired `RootView.swift`: kept `TabView(selection: $selectedTab)` and all `.tabItem`/`.tag()` intact, hid the native chrome with `.toolbar(.hidden, for: .tabBar)` on each tab, and overlaid `NeuTabBar(selectedTab: $selectedTab)` at the bottom. The `kOpenNoteNotification` observer (`selectedTab = 3`) is untouched — deep-link continuity preserved because NeuTabBar reads/writes the same binding.
- Forced dark mode in `MyHomeApp.swift`: single `.preferredColorScheme(.dark)` on `RootView` at the app root (DS-05, applied once).

## Task Commits

1. **Task 1: NeuTabBar full floating capsule + sliding pill** - `49d512b` (feat)
2. **Task 2: wire NeuTabBar into RootView + force dark mode** - `1c00f21` (feat)
3. **Follow-up fix: hide native tab bar per-tab so NeuTabBar isn't doubled** - `58f5f27` (fix)

**Plan metadata:** _(docs commit follows)_

## Files

- `MyHomeApp/DesignSystem/NeuTabBar.swift` (created) — floating capsule tab bar, sliding pill, safe-area-aware, VoiceOver, Preview
- `MyHomeApp/RootView.swift` (modified) — native chrome hidden per tab + NeuTabBar overlay; deep-link binding preserved
- `MyHomeApp/MyHomeApp.swift` (modified) — single root `.preferredColorScheme(.dark)`

## Deviations from Plan

### Auto-fixed Issues

**1. Native tab bar rendered doubled beneath NeuTabBar**
- **Found during:** post-integration simulator run
- **Issue:** A single app-level chrome suppression left the native bar visible under the custom capsule on tab content roots.
- **Fix:** Applied `.toolbar(.hidden, for: .tabBar)` to each of the five tab content roots (commit `58f5f27`).

### Deliberate Deviations

None.

## Known Stubs

None — NeuTabBar is fully implemented. Phase 13 design system (DesignTokens, NeuSurface, RollingMoneyText, NeuTabBar) is code-complete.

## Verification Results

- `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,id=iPhone 17'` — **BUILD SUCCEEDED**
- App installed + launched on iPhone 17 (iOS 26.5) simulator — floating capsule renders, clears the home indicator, Home pill shows canary `#FFD60A` accent (visual confirmation captured; screenshot delivered to user)
- `grep "NeuTabBar(selectedTab:" RootView.swift` — present; `.toolbar(.hidden, for: .tabBar)` on all 5 tabs
- `grep "preferredColorScheme(.dark)" MyHomeApp.swift` — exactly 1 (DS-05)
- `grep "matchedGeometryEffect(id: \"activePill\"" NeuTabBar.swift` — present; `accessibilityHint`/`accessibilityLabel` present (DS-06 VoiceOver)
- `grep -rE "systemBackground" MyHomeApp/DesignSystem/` — 0 matches (DS-05 compliant)
- `xcodebuild test` full suite: design-system + most suites green. 7 `SpendOverTimeAggregatorTests` reported failures under parallel full-suite run **pass in isolation** (re-ran `-only-testing:MyHomeTests/SpendOverTimeAggregatorTests` → 9/9 TEST SUCCEEDED). This is the pre-existing SwiftData multi-container test-isolation flakiness already tracked as `test-isolation-swiftdata-multicontainer.md`, not a Phase 13 regression (SpendOverTimeAggregator is Phase 10 code, untouched here).

## Outstanding — Blocking Human-Verify Checkpoint (Task 3)

Per the plan's `human_verify_mode: end-of-phase`, Task 3 is a blocking checkpoint requiring an interactive manual pass. **Partially satisfied** (simulator launch + capsule render/float/accent confirmed via screenshot), **remaining items outstanding** because programmatic tap-driving was unavailable this session (no Accessibility permission / no tap tooling) and the user opted to defer the manual pass:

- [ ] Tap each of the 5 tabs; confirm content switches and each NavigationStack title/back button is intact (Pitfall 3 regression check)
- [ ] Deep-link: trigger a note reminder (or post kOpenNoteNotification) → Notes tab (index 3) activates and note opens (DS-03 index stability)
- [ ] Reduce Motion ON → pill jumps with no slide; RollingMoneyText snaps instantly (DS-06)
- [ ] Accessibility Inspector on NeuSurface / NeuTabBar / RollingMoneyText previews → zero non-text contrast warnings (WCAG 1.4.11 / DS-06)
- [ ] Confirm `NeuSurface(.recessed)` overlay-gradient inset shadow acceptable at spec values

Recorded as v1.2 verification debt (mirrors the v1.0/v1.1 deferred-human-UAT pattern). Resume via `/gsd-verify-work 13`.

## Threat Surface Scan

No new security-relevant surface. NeuTabBar mutates an in-process `Binding<Int>`; RootView/MyHomeApp edits are pure presentation wiring. No network, persistence, auth, or trust-boundary crossing. Matches plan STRIDE register (T-13-03: accept, n/a). Zero new dependencies.

## Self-Check: PASSED (code) / DEFERRED (human-verify checkpoint)

- [x] `MyHomeApp/DesignSystem/NeuTabBar.swift` exists and contains `struct NeuTabBar` (121 lines ≥ 50)
- [x] `RootView.swift` contains `NeuTabBar(selectedTab: $selectedTab)` + `.toolbar(.hidden, for: .tabBar)`
- [x] `MyHomeApp.swift` contains exactly one `.preferredColorScheme(.dark)`
- [x] Commit `49d512b` (Task 1), `1c00f21` (Task 2), `58f5f27` (fix) exist
- [x] `xcodebuild build` succeeds; app launches and renders NeuTabBar
- [ ] Human-verify checkpoint (interactive tab/deep-link/Reduce Motion + Accessibility Inspector) — outstanding, tracked as v1.2 debt

---
*Phase: 13-design-system-foundation*
*Completed (code): 2026-06-21*
