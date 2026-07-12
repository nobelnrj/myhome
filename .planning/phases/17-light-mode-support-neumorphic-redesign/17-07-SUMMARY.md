---
phase: 17-light-mode-support-neumorphic-redesign
plan: 07
subsystem: ui
tags: [phase-gate, dark-bit-identity, wcag, light-review-set, neumorphism, d-13-revised]

# Dependency graph
requires:
  - phase: 17-light-mode-support-neumorphic-redesign
    plan: 06
    provides: "All feature-file light adaptation complete going into the gate"
provides:
  - "Phase-level gate: full suite 614 pass / 0 fail on iPhone 17; 69 DarkBitIdentityTests assertions green (D-06)"
  - "Light-mode chart/dish/orb redesigned to soft-white neumorphism (D-13 revised per user sign-off)"
  - "Light review set + dark proof screenshots in baselines/"
  - "17-VALIDATION.md finalized (status: passed, wave_0_complete: true)"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Light-mode instrument charts are soft-white neumorphic surfaces (gray-blue shadow + white rim) with MATTE content — NOT dark windows with force-dark neon. Dark mode keeps the neon instrument-window aesthetic. Single adaptive token set drives both."

key-files:
  created:
    - .planning/phases/17-light-mode-support-neumorphic-redesign/baselines/light-overview-orb.png
    - .planning/phases/17-light-mode-support-neumorphic-redesign/baselines/light-analytics-trend-gauges.png
    - .planning/phases/17-light-mode-support-neumorphic-redesign/baselines/light-budgets-donut.png
  modified:
    - MyHomeApp/DesignSystem/DesignTokens.swift
    - MyHomeApp/DesignSystem/NeuSurface.swift
    - MyHomeApp/Features/Overview/SpendOverTimeChart.swift
    - MyHomeApp/Features/Shared/DonutChart.swift
    - MyHomeTests/DesignTokensTests.swift
    - .planning/phases/17-light-mode-support-neumorphic-redesign/17-VALIDATION.md

key-decisions:
  - "D-13 REVISED at end-of-phase sign-off: the user rejected the dark instrument-window treatment in light mode (referenced classic soft-white neumorphism — #ECF0F3 bg, #D1D9E6 dark shadow, #FFF light shadow, matte color accents). Light-mode charts/dishes/orb reworked to soft-white sculpted surfaces with matte content; the force-dark content override removed in light (no-op in dark). Dark mode byte-identical."
  - "An interim step (lighten the dark dish to #AAB2C4) was tried and REVERTED — the dish-contrast tests correctly proved that force-dark white/neon content and a light dish are contradictory. The real fix was recoloring content matte-on-light, not tinting the dark dish."
  - "The generative breathing orb has no direct reference analog; reinterpreted as a light sculpted disc (dark-ink readout, matte particles, soft red spend rim). Flagged as the most interpretive of the four conversions and approved by the user."

requirements-completed: [D-01, D-02, D-05, D-06, D-12, D-14, D-13-revised]
requirements-partial: []

# Metrics
duration: ~3h (gate + interrupted executor recovery + D-13 redesign via forked subagent)
completed: 2026-07-13
---

# Phase 17 Plan 07: Phase Gate + D-13 Light-Neumorphism Redesign Summary

**The phase gate passed (full suite 614/0 on iPhone 17, 69 dark bit-identity assertions green), and during the end-of-phase visual sign-off the light-mode chart/dish/orb treatment was redesigned from a dark instrument-window to soft-white neumorphism with matte content per the user's reference — with dark mode proven byte-identical throughout.**

## Performance
- **Duration:** ~3 h including gate execution, recovery of an interrupted executor, and the D-13 redesign (delegated to a forked subagent to keep orchestrator context clean at the user's request)
- **Completed:** 2026-07-13
- **Model note:** Fable 5 session/quota limit was reached mid-phase; the gate and redesign completed on Opus 4.8.

## Gate Results (D-06 authoritative)
- **Full suite:** `xcodebuild test -scheme MyHome` on iPhone 17 → **`** TEST SUCCEEDED **`, 614 pass / 0 fail.**
- **Dark bit-identity:** 69 `DarkBitIdentityTests` assertions green — dark rendering byte-identical to the pre-phase baselines. Every `dark:`/`darkAlpha:` token branch is verbatim.
- **Light review set:** captured in `baselines/` (Overview orb, Analytics trend+gauges, Budgets donut); dark proof in `baselines/dark-final-analytics.png` shows the original neon instrument window unchanged.

## D-13 Revision (end-of-phase sign-off)
The phase originally shipped light-mode charts as **dark instrument windows with force-dark neon content** (D-11/D-12/D-13). During visual sign-off the user rejected that in light mode and supplied a classic soft-white **neumorphism** reference (single off-white surface sculpted by a gray shadow + white highlight; charts as light raised/recessed surfaces with matte color accents).

**What changed (light branches only; dark untouched):**
- Trend charts (Analytics, Spend-over-time, Net-worth) → soft-white recessed wells, matte curve, faint ink gridlines (added adaptive `chartGridline`; `chartAmber` gained a matte light branch).
- Category pill gauges → soft-white wells with matte color fills.
- Budget donut / rings (`NeuCircularWell`) → soft-white recessed well + raised center puck + matte gradient ring (closest to the reference "Statistic" donut).
- Overview breathing orb → light sculpted disc (dark-ink readout, matte particles, soft red spend rim) — the most interpretive conversion, user-approved.
- `dishSlate`/`dish*` light branches flipped from dark-slate to soft-white recessed neumorphism (gray-blue `#9BA3B8` shadow + white rim); `.environment(\.colorScheme,.dark)` force-dark override removed at all five call sites (a no-op in dark).
- Dish-contrast tests `labelOnDish`/`accentOnDish` rewritten from the force-dark contract to the new matte-on-light contract (readout ≥4.5:1, matte curve ≥3:1).

**Dead-end recorded:** an interim attempt to merely *lighten* the dark dish (to `#AAB2C4`) was reverted — the two dish-contrast tests correctly failed, proving force-dark white/neon content and a light dish are contradictory. The correct fix was recoloring content matte-on-light.

## Task Commits (D-13 redesign)
- `032d6b9` feat(17): light-mode chart dishes → soft-white neumorphism (D-13 revised)
- `8d2fc16` test(17): dish contrast tests → matte-on-light contract (D-13 revised)
- (`9e47325` lighten-dish attempt → reverted by `acf1b22`)

## Deviations from Plan
- **Plan 07 was authored as a verification-only gate** (run suite, dark sweep, light review set, finalize VALIDATION.md). In practice the end-of-phase sign-off surfaced a design-direction change (D-13), so this plan also carried the light-neumorphism redesign. That is the intended purpose of the `human_verify_mode: end-of-phase` gate — catch look-and-feel issues before closeout — so the redesign is recorded as an in-gate revision rather than a separate phase.
- **Definitive dark screenshot double-sweep vs Plan-01 baselines was not run as scripted** — the Plan-01 baseline PNGs embed seeded row times and legitimately-changed dark screens (the Appearance section), so a byte diff false-fails. The authoritative D-06 gate (`DarkBitIdentityTests`, 69 assertions) is green and is the byte-exact authority; a dark analytics screenshot confirms the neon instrument window is visually unchanged.

## Authentication Gates
None.

## Known Stubs
None. Net-worth trend chart was not screenshot-reachable via launch args (simctl can't tap "See holdings") but uses the identical verified `NeuCircularWell` + light-inset code path as the other charts.

## Threat Flags
None new. Theme preference remains a non-sensitive UserDefaults string.

## Self-Check: PASSED
- Merged light-neumorphism branch to main (fast-forward); full suite re-run on main: 614 pass / 0 fail
- 69 DarkBitIdentityTests assertions green — D-06 intact; every dark token branch verbatim
- Light review set + dark proof committed to baselines/
- 17-VALIDATION.md finalized (status: passed, wave_0_complete: true)

---
*Phase: 17-light-mode-support-neumorphic-redesign*
*Completed: 2026-07-13 (gate + D-13 light-neumorphism redesign; dark mode byte-identical)*
