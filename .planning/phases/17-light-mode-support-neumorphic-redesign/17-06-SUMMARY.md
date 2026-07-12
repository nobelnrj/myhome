---
phase: 17-light-mode-support-neumorphic-redesign
plan: 06
subsystem: ui
tags: [swiftui, charts, neumorphic, instrument-window, force-dark, adaptive-color, dark-bit-identity, ai-violet, icon-tile]

# Dependency graph
requires:
  - phase: 17-light-mode-support-neumorphic-redesign
    plan: 02
    provides: "all-adaptive palette + Color.adaptive factory + deepened category/violet light twins + scheme-aware neonGlow"
  - phase: 17-light-mode-support-neumorphic-redesign
    plan: 04
    provides: "neu* rim/hairline adaptive token family reused for the range-picker chrome"
  - phase: 17-light-mode-support-neumorphic-redesign
    plan: 05
    provides: "dishSlate + dish* chrome tokens + the force-dark instrument-window pattern reused for the three trend-chart insets"
provides:
  - "All three trend charts (analytics trend, spend-over-time, net-worth trend) render inside slate instrument windows in light with their luminous amber/neon palette intact (D-12 'ALL charts in deep dishes'); dark byte-identical"
  - "chartAmber token replacing 4 inline #FFB43C sites; dishSlateInset + dishInsetHair* trend-inset chrome family (dark verbatim)"
  - "LightSlateInstrumentInset modifier — the THIRD and final sanctioned @Environment(\\.colorScheme) read site — for net-new light-only chart insets (dark = no-op)"
  - "iconTileGlyph adaptive glyph (white on deepened light fills, near-black on luminous dark fills) closing the last IconTile inline hex"
  - "NeuSegmentedControl range picker on named seg*/neu* tokens; AI Insight card D-15 completed (aiVioletText label/sparkle + aiVioletOrbCore); violet stays AI-only"
affects: [17-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Existing-inset chart (AnalyticsTrendChart): swap fill/hairline to dish*Inset tokens whose DARK branch is the pre-refactor value verbatim + force-dark the Chart content inside a ZStack sibling of the chrome (no dark drift)"
    - "Net-new-inset charts (SpendOverTime, NetWorth): the slate window is gated LIGHT-ONLY via a single @Environment(\\.colorScheme) modifier so dark gains zero net-new pixels (D-06); the chart content is force-dark unconditionally so its palette glows in the light window and is a no-op in dark"
    - "Token-level scheme adaptation preferred over new @Environment reads for the AI orb core (white specular in dark → bright violet in light)"

key-files:
  created: []
  modified:
    - MyHomeApp/DesignSystem/DesignTokens.swift
    - MyHomeApp/Features/Analytics/AnalyticsTrendChart.swift
    - MyHomeApp/Features/Overview/SpendOverTimeChart.swift
    - MyHomeApp/Features/Assets/NetWorthTrendChart.swift
    - MyHomeApp/Features/Shared/IconTile.swift
    - MyHomeApp/Features/Analytics/AnalyticsView.swift
    - MyHomeApp/Features/Settings/EditAccountView.swift
    - MyHomeApp/Features/Analytics/AIInsightCard.swift
    - MyHomeTests/DesignTokensTests.swift

key-decisions:
  - "RESEARCH Open Question 1 resolved YES: all three trend charts get instrument-window treatment (user's 'ALL charts in deep dishes' intent, D-12)."
  - "AnalyticsTrendChart's inset hairline is black.45/white.03 today — NOT the black.50/white.04 of the Plan-05 dish hairline. Blindly swapping to dishHairline* would have shifted dark. Added dedicated dishInsetHairDark/Light (dark = black.45/white.03 verbatim) instead of the plan's literal 'inset hairline → dish* tokens' (Rule 1 fix)."
  - "SpendOverTime + NetWorth insets are NET-NEW: rendering them in dark would add pixels D-06 forbids. Gated the whole inset (background + hairline + padding) to light via LightSlateInstrumentInset so dark is byte-identical by construction; the chart content force-dark is a no-op in dark."
  - "NeuSegmentedControl inline opacities (white.06/black.30/black.45/white.03) don't all match existing neu* dark alphas — reused neuHairlineDark for the two black.45 legs (exact) and added segRimTop/segRimBottom/segTrackRise for the rest (dark verbatim) rather than accepting a sub-tolerance dark drift by force-fitting neuRimTop(0.07)/neuRimBottom(0.35)."
  - "aiVioletOrbCore named with the aiViolet prefix so the AI-only scope grep still resolves to exactly two files."

requirements-completed: [D-09, D-11, D-12, D-13, D-15]

# Metrics
duration: ~55min
completed: 2026-07-12
---

# Phase 17 Plan 06: Feature-File Light Audit — Trend Charts, IconTile, Range Picker, AI Card Summary

**All three trend charts (analytics, spend-over-time, net-worth) now render inside deep-slate instrument windows in light mode with their luminous amber/neon curves intact — resolving RESEARCH Open Question 1 as YES (the user's "ALL charts in deep dishes" intent) — while the AnalyticsTrendChart swap keeps dark byte-identical and the two net-new insets are gated light-only so dark gains zero pixels; the IconTile glyph, the Analytics range picker, and the AI Insight card's D-15 violet all complete their light adaptation, closing every hardcoded feature-level color path.**

## Performance
- **Duration:** ~55 min
- **Completed:** 2026-07-12
- **Tasks:** 3
- **Files modified:** 8 source/test + 5 evidence PNGs (no new source files — pbxproj untouched)

## Accomplishments

- **Task 1 — trend charts → slate instrument windows (D-12):** Promoted `#FFB43C` to `DesignTokens.chartAmber` and swapped all 4 inline sites (SpendOverTimeChart, AnalyticsTrendChart). `AnalyticsTrendChart` (which already had a recessed inset in both schemes) now fills the inset with `dishSlateInset` (dark `#16161C` verbatim) and strokes it with `dishInsetHairDark`/`dishInsetHairLight` (dark `black.45`/`white.03` verbatim), with the `chart` forced `.dark` inside a **ZStack sibling** of the chrome so amber curve + gridlines + glow stay luminous on slate — dark byte-identical. `SpendOverTimeChart` and `NetWorthTrendChart` gained a **NET-NEW slate inset rendered in LIGHT ONLY** via the new `LightSlateInstrumentInset` modifier (the third sanctioned `@Environment(\.colorScheme)` read site) plus an unconditional force-dark on their chart content; in dark both charts render exactly as before (chart on the raised card / inline in NetWorthCard, no inset).
- **Task 2 — IconTile + range picker + account palette audit (D-09):** `IconTile` glyph promoted to `DesignTokens.iconTileGlyph` (dark `#16161C`@0.85 verbatim; light flips to white@0.92 for contrast on the deepened category twins — verified white-on-catOther ≥ 3.0:1 by a new ContrastTest and on-device across all tiles). `NeuSegmentedControl` rims/shade moved onto `segRimTop`/`segRimBottom`/`segTrackRise` + reused `neuHairlineDark` (dark opacities verbatim; no geometry change). `EditAccountView` color-picker audited in light: the vivid iOS swatch fills read fine on the light Form; the only weak point was the plain-white selection checkmark on the lighter swatches (Yellow/Mint/Cyan/Teal), fixed with a dark contrast halo — **presentation chrome only, the stored `colorHex` user data is untouched**.
- **Task 3 — AI Insight card D-15 violet:** Header sparkle + "AI INSIGHT" label moved from `aiVioletTop` to `aiVioletText` (light `#5B21B6` 7.19:1; dark `#C4A6FF` verbatim). The breathing-orb radial core white specular promoted to `aiVioletOrbCore` (dark `white`@0.9 verbatim; light bright-violet `#7C3AED` so the orb reads as a violet sphere on the light card) — token-level, **no new scheme-read site**. Edge glow + orb ring stay on the scheme-aware `neonGlow`/adaptive tokens (D-14 tinted drop-shadow in light). Violet remains AI-only (scope grep = 2 files).

## Final New Token Values (light / dark)
| Token | Light | Dark (verbatim) | Role |
|---|---|---|---|
| chartAmber | #FFB43C | #FFB43C | trend line/area/glow (renders inside force-dark) |
| dishSlateInset | #3E4250 | #16161C | AnalyticsTrendChart inset fill |
| dishInsetHairDark | #23262F @0.55 | #000000 @0.45 | trend-inset hairline dark end |
| dishInsetHairLight | #565B6C @0.45 | #FFFFFF @0.03 | trend-inset hairline light end |
| iconTileGlyph | #FFFFFF @0.92 | #16161C @0.85 | IconTile glyph |
| segRimTop | #FFFFFF @0.90 | #FFFFFF @0.06 | range-picker thumb rim top |
| segRimBottom | #9BA3B8 @0.55 | #000000 @0.30 | range-picker thumb rim bottom |
| segTrackRise | #FFFFFF @0.70 | #FFFFFF @0.03 | range-picker track hairline rise |
| aiVioletText | #5B21B6 | #C4A6FF | AI label/sparkle text |
| aiVioletOrbCore | #7C3AED | #FFFFFF @0.9 | AI breathing-orb core |

## Verification Evidence
- **D-06 unit gate (authoritative):** `DarkBitIdentityTests` + `ContrastTests` → `** TEST SUCCEEDED **`, 0 failures. All 10 new tokens resolve in dark exactly to their pre-refactor hex/opacity composite; `aiVioletText` (a Plan-02 token) also added to the gate.
- **Acceptance greps:** `#FFB43C` in `MyHomeApp/Features` = **0**; non-comment `Color(hex:` in `IconTile.swift` = **0**; `aiViolet` scope = **2 files** (DesignTokens.swift + AIInsightCard.swift).
- **Light render (on-device iPhone 17):** `17-06-light-analytics-trendchart.png` (amber→red curve in slate window + neumorphic Week/Month/Year picker), `17-06-light-spend-overtime.png` (amber curve in slate window), `17-06-light-networth-trend.png` (green area+line in slate window beside the donut dish), `17-06-light-icontiles.png` (white glyphs legible on all deepened category fills).
- **Dark sanity:** `17-06-dark-overtime-sanity.png` shows the SpendOverTime chart with **no net-new inset** (chart on the raised card exactly as before) — proves the light-only gating keeps dark byte-identical (D-06 / threat T-17-07 mitigated).

## Open-Question-1 Resolution (plan output requirement)
RESEARCH Open Question 1 ("do all charts get the dish treatment, or only some?") is resolved **YES — all three trend charts get instrument windows**, per CONTEXT §specifics ("ALL charts in deep dishes", D-12). Implemented for analytics-trend, spend-over-time, and net-worth-trend.

## Account-Palette Audit Outcome (plan output requirement)
The `EditAccountView` picker palette (`availableColors`: iOS system colors #007AFF…#00C7BE) was audited in light mode. The **swatch fills read fine** on the light Form background (vivid solid colors are legible on any surface). The one legibility gap was the **selection checkmark** — plain white, which sits poorly on the lightest swatches (Yellow #FFCC00, Mint #00C7BE, Cyan #32ADE6, Teal #5AC8FA). Fixed with a `black@0.35` contrast halo on the checkmark (presentation chrome only). **No stored `account.colorHex` value was altered** (PATTERNS user-data rule).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] AnalyticsTrendChart inset hairline would have drifted dark under the plan's literal "→ dish* tokens" instruction**
- **Found during:** Task 1
- **Issue:** The plan said to move the AnalyticsTrendChart inset hairline to "the dish* tokens (Plan 05)". Those tokens are dark `black.50`/`white.04`, but the chart's current hairline is `black.45`/`white.03` — a direct swap would shift dark by ~1 alpha step and violate D-06.
- **Fix:** Added dedicated `dishInsetHairDark`/`dishInsetHairLight` tokens whose dark branch is the chart's prior `black.45`/`white.03` verbatim (light branch harmonized with the slate dish family). Covered by DarkBitIdentityTests.
- **Files modified:** DesignTokens.swift, AnalyticsTrendChart.swift, DesignTokensTests.swift
- **Commit:** b76abb1

**2. [Rule 1 - Bug] Range-picker "→ neu* tokens" swap did not have exact dark-alpha matches**
- **Found during:** Task 2
- **Issue:** The plan said swap the NeuSegmentedControl rims/shadows to the Plan-04 neu* tokens. The control's inline alphas (white.06 / black.30 / white.03) do not match any neu* dark branch (neuRimTop=0.07, neuRimBottom=0.35, neuHairlineLight=0.04); reusing them would silently drift dark (sub-screenshot-tolerance but not byte-identical).
- **Fix:** Reused `neuHairlineDark` only for the two exact `black.45` legs (thumb shadow + track top); added `segRimTop`/`segRimBottom`/`segTrackRise` (dark verbatim) for the mismatched values. Dark stays byte-identical.
- **Files modified:** DesignTokens.swift, AnalyticsView.swift, DesignTokensTests.swift
- **Commit:** bc34553

**3. [Rule 2 - Missing legibility] Account-picker selection checkmark illegible on light swatches**
- **Found during:** Task 2 (audit)
- **Issue:** The white selection checkmark has ~1.4:1 contrast on the Yellow/Mint swatches.
- **Fix:** Added a `black@0.35` contrast halo (shadow) to the checkmark — presentation chrome only, no stored-data change.
- **Files modified:** EditAccountView.swift
- **Commit:** bc34553

## Authentication Gates
None.

## Known Stubs
None. All new tokens/modifiers are wired into live recipes.

## Threat Flags
None. Matches the plan's threat register: **T-17-07** (net-new light-only chart insets leaking into dark) is mitigated by structurally gating the two net-new insets to `colorScheme == .light` — verified by the dark sanity screenshot (no inset in dark) + the D-06 unit gate. No new inputs, storage, network, or trust boundaries; account `colorHex` remains read-only user data.

## Notes for Plan 07 (phase verification)
- Every hardcoded feature-level color now has a light-aware path; only phase-level verification remains.
- The three trend charts are the only new force-dark instrument windows in the feature layer; the `@Environment(\.colorScheme)` read-site budget is now fully consumed (NeonGlowModifier + NeuCircularWell dish content + LightSlateInstrumentInset = 3).
- Dark before/after screenshot diffs must be same-store / masked (orb + gauge animations); the authoritative D-06 gate is DarkBitIdentityTests (now covering 10 additional tokens).

## Task Commits
1. **Task 1: trend charts → slate instrument windows (D-12)** — `b76abb1` (feat)
2. **Task 2: IconTile glyph + range picker + account palette audit (D-09)** — `bc34553` (feat)
3. **Task 3: AI Insight card D-15 violet; violet stays AI-only** — `fe15621` (feat)
4. **On-device light/dark evidence** — `7650937` (docs/evidence)

## Self-Check: PASSED
- All 9 modified source/test files present; 5 evidence PNGs present in the phase dir; this SUMMARY present
- Commits b76abb1, bc34553, fe15621, 7650937 present on the worktree branch
- D-06 unit gate green (0 drift on 10 new/added tokens); light + dark render evidence captured
- Acceptance greps: #FFB43C in Features = 0; IconTile Color(hex:) = 0; aiViolet scope = 2 files

---
*Phase: 17-light-mode-support-neumorphic-redesign*
*Completed: 2026-07-12*
