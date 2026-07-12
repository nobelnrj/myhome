---
phase: 17-light-mode-support-neumorphic-redesign
plan: 04
subsystem: ui
tags: [swiftui, neumorphic, shadow-tokens, adaptive-color, design-system, dark-bit-identity, light-depth]

# Dependency graph
requires:
  - phase: 17-light-mode-support-neumorphic-redesign
    plan: 02
    provides: "All-adaptive DesignTokens palette + Color.adaptive(light:lightAlpha:dark:darkAlpha:) factory; accentText role-split token"
  - phase: 17-light-mode-support-neumorphic-redesign
    plan: 03
    provides: "Live AppStorage theme switch — light mode reachable on device for depth tuning"
provides:
  - "Named neumorphic shadow/rim/hairline adaptive tokens (neuOuterHighlight/Shade[Float], neuRimTop/Bottom, neuInnerShade/Rise, neuHairlineDark/Light) — dark branch = prior white/black opacity verbatim (D-06)"
  - "NeuSurface surfaces, both button styles, and the circular puck rewired to named tokens with light-tuned gray-blue shadows + bright white highlights (D-05)"
  - "NeuSecondaryButtonStyle label → accentText — closes the D-08 site (NeuSurface.swift:288) that Plan 09's Gate A delegated here"
  - "Paired light+dark #Preview gallery for the neumorphic design-system views"
affects: [17-05, 17-06, 17-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Neumorphic depth is now token-driven: shadow/rim/hairline colors resolve through DesignTokens.neu* adaptive tokens instead of inline .white.opacity/.black.opacity, so light gets tuned gray-blue shade + bright white highlight while dark stays byte-identical"
    - "Shadow GEOMETRY (radii, offsets, blur, lineWidth) held constant across schemes — only colors adapt (D-05 pass-1 rule)"

key-files:
  created: []
  modified:
    - MyHomeApp/DesignSystem/DesignTokens.swift
    - MyHomeApp/DesignSystem/NeuSurface.swift
    - MyHomeApp/DesignSystem/RollingMoneyText.swift
    - MyHomeApp/Features/Overview/SpendBudgetCard.swift
    - MyHomeTests/DesignTokensTests.swift

key-decisions:
  - "Shadow/rim/hairline colors promoted to named neu* adaptive tokens; light values tuned on-device (gray-blue #8E97AD/#9BA3B8 shades, bright white highlights) until the light theme reads as the same sculptural object under different lighting (D-05)"
  - "Button-face GLAZE gradients (e.g. NeuPrimaryButtonStyle top-glaze [.white.opacity, .clear]) left inline — these are gloss highlights on the CTA face, not shadow/rim/hairline colors, and read as intentional gloss in both schemes"
  - "EmbossedBar / VerticalPillGauge inner-chrome inline opacity left untouched — bars and gauges are Plan 05's instrument-window scope, not this plan's raised/recessed/button/puck vocabulary"

requirements-completed: [D-05, D-06, D-08 (NeuSurface:288 delegated site)]
requirements-partial: []

# Metrics
duration: ~70min (incl. two provider usage-limit interruptions; verification + SUMMARY completed by orchestrator from committed state)
completed: 2026-07-12
---

# Phase 17 Plan 04: Neumorphic Component Light Twins Summary

**The core neumorphic vocabulary — raised surfaces, both CTA button styles, and the circular puck — now carries light-tuned depth (gray-blue shadows + bright white highlights) driven by named adaptive tokens whose dark branches are byte-identical to the prior inline white/black opacity, so light mode reads as the same physical object under different lighting while dark rendering is proven pixel-identical.**

## Performance
- **Duration:** ~70 min (including two provider usage-limit interruptions; implementation committed by the executor, final verification + this SUMMARY completed by the orchestrator from the verified worktree state)
- **Completed:** 2026-07-12
- **Tasks:** 3 (all implementation commits present)
- **Files modified:** 5 (no new files — pbxproj untouched)

## Accomplishments
- **Task 1 — token promotion (D-06):** Every inline `white`/`black` opacity used as a shadow, rim, or hairline color in NeuSurface.swift (outer shadows, rim overlays, recessed inner shades, interactive-border hairlines) plus RollingMoneyText and SpendBudgetCard was promoted to a named `Color.adaptive` token: `neuOuterHighlight`/`neuOuterShade` (+`Float` variants for floating surfaces), `neuRimTop`/`neuRimBottom`, `neuInnerShade`/`neuInnerRise`, `neuHairlineDark`/`neuHairlineLight`. Each token's **dark branch is the current white/black opacity verbatim**, so dark rendering cannot shift.
- **Task 2 — light depth tuning (D-05):** Light branches tuned on the simulator with the live theme switch (from Plan 03) — gray-blue shade colors (`#8E97AD`/`#9BA3B8`/`#99A1B5`) at calibrated alpha for recessed depth, bright white (`#FFFFFF` at 0.80–0.90) for raised highlights — until raised cards, recessed wells, both button styles, and the circular puck read with the same sculptural drama as dark. Shadow geometry (radii/offsets/blur/lineWidth) is unchanged in both schemes. Committed on-device evidence: `light-tuning-tab0-cta.png`, `light-tuning-tab1.png`, `light-tuning-tab2-cta.png`, `light-tuning-tab4.png`.
- **Task 3 — delegated D-08 site + paired previews:** `NeuSecondaryButtonStyle` label `foregroundStyle` moved from `accent` to `accentText` (NeuSurface.swift:288) — the one accent site Plan 09's Gate A explicitly excluded and delegated here, closing the app-wide D-08 audit. Added a paired light+dark `#Preview` gallery so the neumorphic recipes are inspectable in both schemes.

## Verification Evidence
- **Post-merge gate (orchestrator, iPhone 17):** `xcodebuild test -scheme MyHome` → **`** TEST SUCCEEDED **`**, 0 failures; 52 `DarkBitIdentityTests` assertions passed — the byte-exact D-06 authority confirms dark rendering is unchanged after the token promotion.
- **Acceptance greps (on the merged tree):** the D-08 delegated site `NeuSurface.swift:288` = `.foregroundStyle(DesignTokens.accentText)`; the two remaining `DesignTokens.accent` references in NeuSurface are `.shadow(color:)` halo fills (fill-role canary, correctly retained); `DesignTokens.neu*` tokens resolve the surface/button/puck shadow-rim recipes; 2 `#Preview` blocks present.
- **Shadow-geometry invariant:** the token promotion is color-only — radii, offsets, blur, and lineWidth are byte-unchanged in both schemes (D-05 pass-1 rule).

## Task Commits
1. **Task 1: promote surface/button/puck shadow colors to adaptive neu* tokens** — `27ef127` (feat)
2. **Task 2: light-mode depth tuned on device — screenshot evidence (D-05)** — `14de00e` (docs/evidence)
3. **Task 3: pair light/dark previews for neumorphic design-system views** — `a8d762b` (test)

## Files Created/Modified
- `MyHomeApp/DesignSystem/DesignTokens.swift` — added the `neu*` adaptive shadow/rim/hairline token family (dark = prior opacity verbatim)
- `MyHomeApp/DesignSystem/NeuSurface.swift` — surfaces, both button styles, circular puck rewired to named tokens; NeuSecondaryButtonStyle label → accentText (D-08:288); paired light/dark previews
- `MyHomeApp/DesignSystem/RollingMoneyText.swift` — inline shadow/rim opacity → neu* tokens
- `MyHomeApp/Features/Overview/SpendBudgetCard.swift` — inline shadow/rim opacity → neu* tokens
- `MyHomeTests/DesignTokensTests.swift` — extended dark bit-identity coverage for the new neu* tokens

## Scoping Decisions (documented — not gaps)
- **Button-face glaze gradients left inline:** e.g. `NeuPrimaryButtonStyle`'s top-glaze `LinearGradient(colors: [.white.opacity(...), .clear])`. The plan's must-have promotes *shadow, rim, and hairline* colors — a face glaze is a gloss highlight on the CTA fill, not one of those roles, and reads as intentional gloss in both schemes. Its enclosing shadows/rims WERE promoted.
- **EmbossedBar / VerticalPillGauge inner chrome left inline:** these bar/gauge internals are Plan 05's instrument-window scope ("dishes/gauges/bars are Plan 05" per this plan's objective), not the raised/recessed/button/puck vocabulary this plan owns. `NeuCircularWell` inner strokes fall in the same gauge-chrome family and are addressed with the instrument-window treatment in Plan 05.
- Net effect: no shadow/rim/hairline color that this plan owns remains inline; the residual `.white/.black.opacity` sites are all glaze-gloss or Plan-05 gauge chrome. Dark rendering is unaffected by any of them (byte-identity gate green).

## Deviations from Plan

### Auto-fixed Issues
**1. [Rule 3 — Blocking] Render-diff false failure from tab-switch + animated orb**
- **Found during:** Task 2/3 dark render re-verification.
- **Issue:** A `-startTab 1` relaunch didn't switch tabs, so the "dark-tab1" capture actually showed tab 0 (Overview) with the live TimelineView-animated hero orb — non-deterministic frame-to-frame, producing a diff that looked like drift but was pure orb animation.
- **Fix:** pass `-startTab` and its value as separate argv items; capture same-store before/after within one run; the animated orb on tab 0 is masked by `ORB_BBOX` in `diff_dark.py` (TOLERANCE=16). The authoritative D-06 gate is `DarkBitIdentityTests` regardless, and it is green.

## Authentication Gates
None.

## Issues Encountered
- **Two provider usage-limit interruptions** (Fable 5 session limit, then Fable 5 quota) hit this executor mid-verification, after all three implementation commits (27ef127, 14de00e, a8d762b) were already on the worktree branch with a clean tree. The orchestrator (now on Opus 4.8) verified the committed state, ran the full post-merge test gate (D-06 authority green), confirmed the D-08:288 fix and token promotion via source greps, and completed this SUMMARY from that verified state rather than re-running the cut-off narration. No implementation rework was needed.

## Known Stubs
None. All promoted tokens are wired into the live recipes; no placeholder values.

## Threat Flags
None. Color-token refactor only — no new network, file, schema, or trust-boundary surface.

## Next Phase Readiness
- The raised/recessed/button/puck neumorphic vocabulary now has light twins; Plan 05 can build the instrument-window (dish/gauge/bar) treatment on top of these tokens.
- The `neu*` token family is the reuse point for Plan 05's gauge chrome — extend it rather than re-introducing inline opacity.
- D-08 app-wide accent audit is fully closed (Plans 08, 09, and this plan's :288 site).
- Render-gate reminder still applies: dark before/after diffs must be same-store or re-based; the Plan-01 baseline PNGs embed seed times.

## Self-Check: PASSED
- All 5 modified files present on main; no new files (pbxproj untouched)
- Commits 27ef127, 14de00e, a8d762b merged to main (fast-forward)
- Post-merge full suite: ** TEST SUCCEEDED **, 52 DarkBitIdentity assertions passed, 0 failures
- D-08 delegated site NeuSurface.swift:288 = accentText confirmed

---
*Phase: 17-light-mode-support-neumorphic-redesign*
*Completed: 2026-07-12 (implementation by executor; verification + summary by orchestrator after Fable-5 limit)*
