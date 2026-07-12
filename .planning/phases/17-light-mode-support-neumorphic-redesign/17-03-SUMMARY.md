---
phase: 17-light-mode-support-neumorphic-redesign
plan: 03
subsystem: ui
tags: [swiftui, appstorage, colorscheme, appearance-theme, neumorphic, segmented-control, tab-bar, dark-bit-identity]

# Dependency graph
requires:
  - phase: 17-light-mode-support-neumorphic-redesign
    plan: 01
    provides: "Color.adaptive factory + DarkBitIdentityTests + 6 dark baselines + diff_dark.py"
  - phase: 17-light-mode-support-neumorphic-redesign
    plan: 02
    provides: "All-adaptive DesignTokens palette incl. accentText role-split token; scheme-aware neonGlow"
provides:
  - "AppearanceTheme enum (system/light/dark → ColorScheme?) with Settings labels (D-01)"
  - "@AppStorage(\"appearanceTheme\")-driven root preferredColorScheme; missing/garbage key → .system (D-02, T-17-03)"
  - "Neumorphic Appearance segmented row in Settings bound to the same key — live re-theme (D-03)"
  - "Native chrome verified auto-adapting in light (D-07, A4 default path); selected-tab tint = accentText (D-08 chrome slice)"
affects: [17-04, 17-05, 17-06, 17-07, 17-08, 17-09]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "First @AppStorage in the codebase: plain UserDefaults.standard (no App Group — theme is app-only), shared key string between app root and Settings row"
    - "Custom neumorphic segmented pill: recessed fillRecessed3 track (EmbossedBar recipe) + raised surfaceRaisedStrong active segment (NeuSecondaryButtonStyle recipe) sliding via matchedGeometryEffect + springBouncy"

key-files:
  created: []
  modified:
    - MyHomeApp/DesignSystem/DesignTokens.swift
    - MyHomeApp/MyHomeApp.swift
    - MyHomeApp/Features/Settings/SettingsView.swift
    - MyHomeApp/RootView.swift
    - MyHomeTests/DesignTokensTests.swift

key-decisions:
  - "A4 outcome: native tab bar / nav bars / sheets auto-adapt in light with no UITabBarAppearance/UINavigationBarAppearance fallback — default path held; light bar material sits fine on the #E3E6EE canvas"
  - "D-06 render gate re-based same-day: Plan 01 baselines embed seeded row TIMES (store was wiped by an uninstall), so the authoritative render diff is base-commit binary vs new binary over the SAME persisted store — 5/6 screens byte-identical, tab4 differs only by the intended new Appearance section"
  - "AppearanceSegmentedRow lives INSIDE SettingsView.swift (no new file — avoids the 4-edit pbxproj tax)"

requirements-completed: [D-01, D-02, D-03, D-07]
requirements-partial: [D-08 (chrome slice only — app-wide accent call-site audit is Plans 17-08/17-09)]

# Metrics
duration: ~55min (incl. usage-limit interruption + base-commit rebuild for the render gate)
completed: 2026-07-12
---

# Phase 17 Plan 03: AppStorage Theme Plumbing + Appearance Row + Chrome Adaptation Summary

**Light mode is now user-reachable: the forced-dark root pin is replaced by an AppStorage-backed System/Light/Dark setting (default System) with a neumorphic Appearance segmented row in Settings, native chrome auto-adapts in light with the selected-tab tint moved to accentText — and dark rendering is proven byte-identical (unit gate + same-store render diff).**

## Performance
- **Duration:** ~55 min (including a provider usage-limit interruption and a base-commit rebuild to re-base the D-06 render gate)
- **Completed:** 2026-07-12
- **Tasks:** 3
- **Files modified:** 5 (no new files — pbxproj untouched)

## Accomplishments
- **Task 1 — theme plumbing (D-01/D-02):** Added `AppearanceTheme: String, CaseIterable` (system/light/dark → `ColorScheme?`, plus `label`) to DesignTokens.swift. MyHomeApp.swift now reads `@AppStorage("appearanceTheme")` (plain `UserDefaults.standard`, no App Group) and maps it via `AppearanceTheme(rawValue:) ?? .system` — the forced `.preferredColorScheme(.dark)` is gone; a missing or garbage persisted value resolves to System with zero migration (T-17-03 mitigation, unit-tested). Added `AppearanceThemeTests` (5 tests: mapping, labels, garbage fallback, empty-string nil, raw round-trip).
- **Task 2 — Appearance row (D-03):** New `Section("Appearance")` above Security hosting a private `AppearanceSegmentedRow` — a custom neumorphic 3-segment pill (NOT `Picker(.segmented)`): recessed `fillRecessed3` track with top shade band + hairline (EmbossedBar recipe), raised `surfaceRaisedStrong` gradient active segment with rim stroke (NeuSecondaryButtonStyle recipe), sliding via `matchedGeometryEffect` + `springBouncy`, `Haptics.selection()` on change, Reduce Motion honored. Bound to the same `"appearanceTheme"` key as the root, so a flip re-themes live. No crossfade added (Plan 07 evaluates the transition on device).
- **Task 3 — chrome (D-07) + tab tint (D-08 slice):** RootView's `.tint(DesignTokens.accent)` → `.tint(DesignTokens.accentText)` — dark amber selected-tab iconography on the light bar, canary in dark (accentText's dark branch == #FFD60A, so dark cannot shift). Light-appearance screenshots of all 5 tabs confirm native tab bar/nav bars render the system light material with no black bars or forced-dark remnant.

## A4 Chrome Outcome (required by plan)
**Auto-adapt OK — no appearance-code fallback added.** With the forced scheme removed, the native tab bar, nav bars, and status bar all render the system light material correctly on the `#E3E6EE` canvas (verified via light screenshots of tabs 0–4: dark status-bar text, dark large-titles, light bar material, dark-amber selected-tab icon at ~(101,78,0) ≈ accentText #755C00 under anti-aliasing). No `UITabBarAppearance`/`UINavigationBarAppearance` objects were needed. Light-mode NEUMORPHIC quality (surfaces, dish interiors) was not judged here — tuned in Plans 04–07.

## Verification Evidence
- **Unit gates:** All DesignTokens suites green — `AppearanceThemeTests`, `DesignTokensTests`, `DarkBitIdentityTests` (the byte-exact D-06 authority), `AdaptiveFactoryTests`, `ContrastHelperTests`, `ContrastTests` → ** TEST SUCCEEDED **, 0 failures.
- **Acceptance greps:** `preferredColorScheme(.dark)` in MyHomeApp.swift = 0; `AppStorage("appearanceTheme")` in MyHomeApp.swift = 1; `Section("Appearance")` = 1 and placed before `Section("Security")` (source lines 52 vs 60); `pickerStyle(.segmented)` in SettingsView = 0; `.tint(DesignTokens.accentText)` in RootView = 1 with zero `.tint(DesignTokens.accent)` remaining.
- **preferredColorScheme audit:** only the AppStorage-mapped root modifier remains outside `#Preview` blocks — the 4 remaining `.preferredColorScheme(.dark)` hits (NeuSurface:594, RollingMoneyText:74, SpendBudgetCard:268/284) are all inside `#Preview` blocks (verified), which the plan assigns to Plan 04's cleanup.
- **D-06 render gate (same-day, same-store):** base-commit (0e05abd) binary vs new binary over the SAME persisted seeded store, 6 dark screens, pinned 9:41 status bar → `diff_dark.py`: **PASS** dark-tab0 (orb masked), dark-tab1, dark-tab2, dark-tab3, dark-analytics; dark-tab4 differs only from y=864 down = the intended new Appearance section shifting the Settings list (D-03's visible change, present in dark by design).
- **vs Plan 01 baselines:** date-independent screens dark-tab0 + dark-tab3 also PASS directly against the original baselines (exit 0).

## Task Commits
1. **Task 1: AppStorage-driven root scheme + AppearanceTheme enum** — `e6ef164` (feat)
2. **Task 2: Neumorphic Appearance segmented row in Settings (D-03)** — `3cfffa4` (feat)
3. **Task 3: Selected-tab tint accent → accentText (D-07/D-08 chrome slice)** — `699239b` (feat)

## Files Created/Modified
- `MyHomeApp/DesignSystem/DesignTokens.swift` — added `AppearanceTheme` enum (D-01/D-02 doc comments)
- `MyHomeApp/MyHomeApp.swift` — `@AppStorage("appearanceTheme")` + mapped `preferredColorScheme`; forced-dark DS-05 pin removed
- `MyHomeApp/Features/Settings/SettingsView.swift` — `Section("Appearance")` + private `AppearanceSegmentedRow` (same file, no pbxproj edits)
- `MyHomeApp/RootView.swift` — `.tint(DesignTokens.accentText)` with D-07/D-08 comment
- `MyHomeTests/DesignTokensTests.swift` — `AppearanceThemeTests` suite

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Plan 01 baselines unusable for the data-driven screens after a store wipe**
- **Found during:** Task 3 (dark render gate)
- **Issue:** The plan's acceptance ("diff_dark.py vs Plan 01 baselines exits 0, all 6 screens") implicitly depends on the simulator's original seeded store: seeded expense rows display their seed TIME (e.g. "2:50 AM"), and the seeder is idempotent — prior runs re-used the store seeded at baseline capture. This executor uninstalled the app during Task 2 verification, wiping the App Group store; the re-seed at a new time made dark-tab1/tab2/analytics content genuinely differ (row times/labels), a full-screen environmental diff with zero token drift. Additionally, dark-tab4 can never match the Plan 01 baseline again because this plan intentionally adds the Appearance row.
- **Fix:** Re-based the render gate same-day/same-store: exported the base commit (`git archive 0e05abd` to scratch), built the pre-plan binary, installed it fresh (one seed), captured 6 dark screens, then installed the new binary OVER it (store persists, seeder skips) and captured again. Result: 5/6 byte-identical (tol=16), tab4 differs only by the intended new section. Date-independent tab0/tab3 also pass directly against the original Plan 01 baselines.
- **Files modified:** none (verification procedure)
- **Committed in:** n/a (process; documented here)

**2. [Capture note] Plan-02 status-bar procedure confirmed**
- The first capture batch added `--cellularMode active` to the status-bar override, producing a top-right icon diff on otherwise-identical screens. Correct procedure (matches Plan 02's note): `status_bar clear`, then override ONLY time/wifi/battery.

### Not a deviation
- Dark-tab4 failing the render diff is the plan working as designed: D-03 adds a visible row to Settings in BOTH schemes. The plan's "every screen pixel-identical with theme pinned to Dark" truth is satisfied for all pre-existing content; the byte-exact D-06 authority (DarkBitIdentityTests, 38 tokens) is green.

## Authentication Gates
None.

## Issues Encountered
- A provider usage-limit interruption occurred mid-Task-3; execution resumed from the orchestrator's verified state (commits e6ef164, 3cfffa4 present; RootView.swift edit uncommitted) with no rework.
- Stale-binary false negative during light verification: the first light screenshots were taken before reinstalling the tint-swapped build (gear sampled canary). Reinstalling the fresh binary fixed it (gear ≈ accentText). No code change.

## Known Stubs
None. The Appearance row is fully wired to the root scheme via the shared AppStorage key; no placeholder data or dead controls.

## Threat Flags
None beyond the plan's register. T-17-03 (garbage `appearanceTheme` UserDefaults value) is mitigated by the `?? .system` fallback and unit-tested. No new network/file/schema surface; the only new trust-boundary read is the UserDefaults string already modeled in the plan's threat register.

## Next Phase Readiness
- Light mode is user-reachable end-to-end: System default → device appearance; Settings row flips live.
- Plans 04–07 can now tune light surfaces on device with the theme switch in place; Plan 07 evaluates the theme-flip transition (no crossfade added here).
- Plans 17-08/17-09 own the app-wide accent→accentText call-site audit; SettingsView's `.tint(DesignTokens.accent)` (Face ID toggle) and `.foregroundStyle(DesignTokens.accent)` were deliberately left untouched per plan.
- Render-gate note for later plans: dark before/after diffs must be same-store (do not uninstall between captures) or freshly re-based from the current commit — the Plan 01 baseline PNGs embed seed times that no longer reproduce.

## Self-Check: PASSED
- All 5 modified files exist; no new files (pbxproj untouched)
- Commits e6ef164, 3cfffa4, 699239b present on the worktree branch
- Acceptance greps re-verified; full token test suites TEST SUCCEEDED
- Same-store dark render diff: 5/6 PASS + tab4 intended-change only

---
*Phase: 17-light-mode-support-neumorphic-redesign*
*Completed: 2026-07-12*
