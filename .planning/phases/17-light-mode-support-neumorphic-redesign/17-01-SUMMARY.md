---
phase: 17-light-mode-support-neumorphic-redesign
plan: 01
subsystem: ui
tags: [swiftui, adaptive-color, dark-mode, uicolor-dynamic-provider, swift-testing, wcag, screenshot-diff, design-tokens]

# Dependency graph
requires:
  - phase: 13-neumorphic-foundation
    provides: DesignTokens static color/shadow tokens + Color(hex:) parser
provides:
  - "Color.adaptive(light:lightAlpha:dark:darkAlpha:) dynamic-provider factory (dark branch == legacy Color(hex:) parser)"
  - "UIColor(hex:alpha:) with the same 6-digit sRGB contract as Color(hex:)"
  - "D-06 ground truth: 6 pinned-status-bar dark baselines (tabs 0-4 + Analytics) + masked PIL diff script"
  - "DarkBitIdentityTests: 38-token resolve-based dark bit-identity gate (armed for Plan 02 conversions)"
  - "contrastRatio(_:_:) WCAG helper for Plan 02 ContrastTests"
affects: [17-02, 17-03, 17-04, 17-05, 17-06, 17-07, 17-08, 17-09]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dynamic-provider adaptive color: Color(uiColor: UIColor { trait in ... }) resolves per SwiftUI environment colorScheme"
    - "Deterministic color unit tests via Color.resolve(in: EnvironmentValues) instead of appearance-sensitive hex accessor"
    - "Masked screenshot diff (PIL): mask TimelineView-animated orb dish region before comparing"

key-files:
  created:
    - .planning/phases/17-light-mode-support-neumorphic-redesign/baselines/ (6 dark PNGs)
    - .planning/phases/17-light-mode-support-neumorphic-redesign/diff_dark.py
  modified:
    - MyHomeApp/Support/Color+Hex.swift
    - MyHomeTests/DesignTokensTests.swift

key-decisions:
  - "ORB_BBOX = (120, 570, 1085, 1560) in original 1206x2622 pixels — masks the animated hero-orb dish on dark-tab0 with generous margin"
  - "UIColor(hex:) parse-failure fallback is self.init(Color.gray) — component-identical to Color(hex:)'s .gray fallback (T-17-01 mitigation)"
  - "Dark-bit-identity table split into 31 plain + 7 alpha-composite entries so alpha tokens compare against base.opacity(a) resolved in dark"

patterns-established:
  - "Adaptive color factory (dark = current hex verbatim) is the single mechanism every DesignTokens color migrates to from Plan 02"
  - "D-06 is machine-checkable: token.resolve(in: darkEnv) == Color(hex: legacy).resolve(in: darkEnv)"

requirements-completed: [D-06]

# Metrics
duration: ~20min
completed: 2026-07-12
---

# Phase 17 Plan 01: D-06 Ground Truth + Adaptive-Color Mechanism Summary

**Established the machine-checkable D-06 dark bit-identity gate (6 pinned dark baselines + masked PIL diff + a 38-token resolve-based test table) and the `Color.adaptive` dynamic-provider factory — with zero rendering-path changes.**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-07-12
- **Tasks:** 3
- **Files modified:** 2 source files + 6 baseline PNGs + 1 diff script

## Accomplishments
- Captured 6 pre-refactor dark baselines (Overview/Expenses/Budgets/Notes/Settings + Analytics) with pinned 9:41 status bar from the UNMODIFIED tree — D-06 has ground truth before any token edit.
- Added `Color.adaptive` (dynamic-provider) + `UIColor(hex:alpha:)` sharing the exact 6-digit sRGB parse as legacy `Color(hex:)`; existing `Color(hex:)`/`hexString` untouched.
- Rewrote DesignTokensTests off the appearance-sensitive hex accessor onto `Color.resolve(in:)`; added a 38-token dark-bit-identity table, adaptive-factory environment-resolution proof (A1/A3), and the WCAG `contrastRatio` helper. All green against unchanged tokens.

## Task Commits

1. **Task 1: Capture baseline dark screenshots + masked diff script** - `93a1044` (test)
2. **Task 2: Add UIColor(hex:alpha:) + Color.adaptive factory** - `3c63c0f` (feat)
3. **Task 3: Rewrite DesignTokensTests — resolve-based + dark bit-identity table** - `fc40e1d` (test)

## Files Created/Modified
- `baselines/dark-tab0.png … dark-tab4.png, dark-analytics.png` - Pre-refactor dark ground truth
- `diff_dark.py` - PIL masked-pixel diff; ORB_BBOX masks the animated orb dish on tab0; exit 0 iff all screens identical
- `MyHomeApp/Support/Color+Hex.swift` - Added `UIColor(hex:alpha:)` + `Color.adaptive(...)`; legacy parser/hexString unchanged
- `MyHomeTests/DesignTokensTests.swift` - resolve-based assertions, `DarkBitIdentityTests` (31 plain + 7 alpha), `AdaptiveFactoryTests`, `ContrastHelperTests`

## Decisions Made
- **ORB_BBOX = (120, 570, 1085, 1560):** Derived by inspecting dark-tab0.png (1206x2622). The dish is horizontally centered; a generous ellipse mask covers the TimelineView-driven GlowParticleRing + rim bloom that never renders byte-stable.
- **Split dark-identity table (plain vs alpha):** Alpha tokens (accentSoft, label2-4, separators, glassBorder) compare against `base.opacity(a).resolve(in: darkEnv)` rather than a flat hex, keeping the baked-opacity semantics exact.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `@Test(arguments:)` could not reach MainActor-isolated static tables**
- **Found during:** Task 3 (test run)
- **Issue:** The Swift Testing macro expansion accesses the `plain`/`alpha` argument arrays from a nonisolated context; as `@MainActor`-isolated static properties they produced "main actor-isolated static property cannot be accessed from outside of the actor" compile errors → TEST FAILED.
- **Fix:** Marked both argument tables `nonisolated static let` (they hold only Sendable tuples of String/Color/Double, so this is safe).
- **Files modified:** MyHomeTests/DesignTokensTests.swift
- **Verification:** `-only-testing:MyHomeTests/DesignTokensTests` → ** TEST SUCCEEDED **
- **Committed in:** `fc40e1d` (Task 3 commit)

**2. [Rule 1 - Bug] Stray "hexString" token in a header comment failed the zero-usage acceptance grep**
- **Found during:** Task 3 (acceptance check `grep -c "hexString"` returned 1, expected 0)
- **Issue:** A doc comment referenced the old `hexString` accessor by name, tripping the "zero hexString-based assertions" acceptance grep.
- **Fix:** Reworded the comment to "appearance-sensitive hex accessor" without the literal token.
- **Files modified:** MyHomeTests/DesignTokensTests.swift
- **Verification:** `grep -c "hexString"` now returns 0.
- **Committed in:** `fc40e1d` (Task 3 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both were test-file mechanics; no scope creep, no rendering-path impact. D-06 invariant (no rendering source changed) preserved.

## Issues Encountered
- None beyond the two auto-fixed items above. `UIColor(red:g:b:a:)` (dark branch) resolves component-identically to `Color(red:g:b:)` — confirmed by `AdaptiveFactoryTests` A3 assertion passing, closing assumptions A1/A3 on iOS.

## Threat Flags
None — pure test/tooling scaffolding + an additive color factory. T-17-01 (malformed hex) is mitigated by the shared guard-and-`.gray` fallback contract.

## Next Phase Readiness
- D-06 gate is armed: Plan 02 can convert `DesignTokens` statics to `Color.adaptive(...)` and `DarkBitIdentityTests` will fail on any dark drift.
- Baselines + `diff_dark.py` ready for per-screen before/after dark diffing after later plans render changes.
- `contrastRatio` helper in place for Plan 02's light-palette WCAG ContrastTests.
- Note for later diffing: the diff script pairs files by name across two dirs — capture "after" screenshots with the same `dark-tab<N>.png`/`dark-analytics.png` names.

## Self-Check: PASSED
- baselines/ (6 PNGs) + diff_dark.py exist; self-diff exits 0
- Commits 93a1044, 3c63c0f, fc40e1d present
- DesignTokensTests green; hexString usage count = 0; 38 dark-identity arguments

---
*Phase: 17-light-mode-support-neumorphic-redesign*
*Completed: 2026-07-12*
