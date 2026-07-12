---
phase: 17-light-mode-support-neumorphic-redesign
plan: 05
subsystem: ui
tags: [swiftui, neumorphic, instrument-window, force-dark, dish-chrome, adaptive-color, dark-bit-identity, neon-glow]

# Dependency graph
requires:
  - phase: 17-light-mode-support-neumorphic-redesign
    plan: 02
    provides: "dishSlate token + all-adaptive palette + scheme-aware neonGlow"
  - phase: 17-light-mode-support-neumorphic-redesign
    plan: 04
    provides: "neu* shadow/rim/hairline adaptive token family reused for EmbossedBar chrome"
provides:
  - "NeuCircularWell + VerticalPillGauge as instrument windows: dishSlate chrome + force-dark content() / fill subtree so luminous chart palette + full neonGlow bloom render inside the slate dish in both themes (D-11/D-12/D-13)"
  - "dish* chrome token family (dishInnerShade/dishInnerRise/dishHairlineDark/dishHairlineLight/dishWellShade) — dark = pre-refactor black/white opacity verbatim"
  - "EmbossedBar light glow language (D-14): stays fillRecessed3 light well, neu*-family shade/hairline, embossTop/embossBottom fill emboss pair; NOT a dish"
affects: [17-06, 17-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Instrument-window pattern: dish CHROME uses adaptive slate tokens (light) resolving verbatim charcoal (dark); dish CONTENT gets .environment(\\.colorScheme, .dark) so it renders the luminous dark palette + full bloom in BOTH themes"
    - "Force-dark override placed on content()/fill subtrees ONLY, never the chrome ZStack (Pitfall 4 / D-13 'no hole into dark mode')"
    - "EmbossedBar is explicitly NOT a dish: light-tuned recessed well + deepened caller fills + scheme-aware neonGlow drop-shadow (D-14)"

key-files:
  created: []
  modified:
    - MyHomeApp/DesignSystem/NeuSurface.swift
    - MyHomeApp/DesignSystem/DesignTokens.swift
    - MyHomeTests/DesignTokensTests.swift

key-decisions:
  - "DonutChart.swift left UNCHANGED: it contains zero dish-chrome layers — every opacity in it (contact shadow, orb radial body, particle vignette, sphere shading, glow rim) is orb CONTENT living inside the force-dark subtree, and all are scheme-invariant black/white opacities. The dish chrome is 100% in NeuCircularWell. Modifying them to dish* tokens would wrongly alter the orb."
  - "VerticalPillGauge well hairline dark end (black .55) reuses dishInnerShade (also black .55 in dark) rather than adding a 6th near-duplicate token; the gauge well top shade band (black .35) gets its own dishWellShade"
  - "EmbossedBar chrome reuses the Plan-04 neu* family (neuRimBottom for the black-.35 shade band, neuInnerShade + neuHairlineLight for the black-.55/white-.04 hairline) — the only NEW EmbossedBar tokens are embossTop/embossBottom for the fill emboss"
  - "Slate #3E4250 + dish* directional light values from Tasks 1/2 accepted as-is after the on-device tuning pass — dishes harmonize with the light palette, glow reads clearly, and none read as a hole into dark mode; no token-value tuning was required"

requirements-completed: [D-05, D-11, D-12, D-13, D-14]

# Metrics
duration: ~40min
completed: 2026-07-12
---

# Phase 17 Plan 05: Instrument-Window Dish/Gauge/Bar Treatment Summary

**Every chart dish (hero-orb, donut, net-worth donut, budget-ring, and vertical pill-gauge wells) is now a deep-slate instrument window in light and byte-identical charcoal in dark, with the chart CONTENT forced into the dark environment so the original luminous palette + full neonGlow bloom render inside the dish in both themes — while EmbossedBar speaks the D-14 light glow language (light well + deepened fills + drop-shadow), NOT a dish.**

## Performance
- **Duration:** ~40 min
- **Completed:** 2026-07-12
- **Tasks:** 3
- **Files modified:** 3 (no new files — pbxproj untouched)

## Accomplishments
- **Task 1 — NeuCircularWell instrument window:** dish `Circle` fill `fillRecessed3` → `dishSlate`; the three inner-depth layers (dark arc, light rim, hairline) → new `dishInnerShade`/`dishInnerRise`/`dishHairlineDark`/`dishHairlineLight` adaptive tokens (dark = the prior `.black/.white.opacity` verbatim). `content()` — and only content(), never the chrome ZStack — wrapped in `.environment(\.colorScheme, .dark)` with a D-11/D-12/D-13 + Pitfall-4 doc comment. All four NeuCircularWell dishes (orb `SpendBudgetCard:95`, donut `SpendDonutCard:46`, net-worth donut `NetWorthCard:53`, budget ring `BudgetsView:278`) inherit the treatment.
- **Task 2 — VerticalPillGauge wells + EmbossedBar:** pill-gauge well fill → `dishSlate`, shade band → `dishWellShade`, hairline → `dishInnerShade`/`dishHairlineLight`; the fill-pill subtree (`if fraction > 0`) forced `.dark` so the caller's adaptive category `color` resolves luminous and the `.shadow(color:radius:8)` glow renders at full strength inside the well (D-11) — well chrome stays outside. EmbossedBar track stays `fillRecessed3` (NOT a dish, D-14); its shade/hairline reuse the Plan-04 `neuRimBottom`/`neuInnerShade`/`neuHairlineLight`; fill emboss → new `embossTop`/`embossBottom`. Exactly **2** `.environment(\.colorScheme, .dark)` sites in NeuSurface.swift.
- **Task 3 — on-device tuning pass:** built + installed on iPhone 17, captured light-mode screenshots of the orb+donut dish (tab 0), budget-ring dish (tab 2), and Analytics pill-gauge wells. All render as deep-slate instrument windows with luminous glowing content (teal/sky-blue gauge fills glow at full strength; yellow→green budget ring blooms). Confirmed the slate harmonizes with the light palette and does NOT read as a hole into dark mode. `#3E4250` + dish* directional starts judged final — no token-value change needed. Dark sanity capture confirms the budget-ring dish is the original charcoal well with luminous ring.

## DonutChart Layer Classification (chrome vs content) — required by plan output
The plan anticipated dish-chrome gradients inside `DonutChart.swift` (`~:405-488`). On inspection **every one of those layers is orb CONTENT, not dish chrome** — the dish chrome is entirely in `NeuCircularWell` (NeuSurface.swift). Per-layer:

| Layer (DonutChart.swift) | Role | Disposition |
|---|---|---|
| Aura bloom `rimAccent.opacity` (:396) | content (glow) | leave — inside force-dark subtree, adaptive rimAccent resolves luminous |
| Contact shadow ellipse `black .45` (:405) | content (orb resting cue) | leave — scheme-invariant black; resolves same in dark subtree |
| Dark radial body `black .45/.30/.0` (:426-428) | content (orb 3D shading) | leave — scheme-invariant |
| Particle fills `col.opacity` (:455/459) | content (data) | leave — adaptive income/expense colors resolve luminous in force-dark |
| Centre vignette `black .88/.62/.0` (:466-468) | content (orb core) | leave — scheme-invariant |
| Sphere highlight/limb `white .07`, `black .0/.32` (:481-488) | content (orb convexity) | leave — scheme-invariant |
| Blur glow rim + bright rim (:496/499) | content (glow) | leave — adaptive rimAccent/rimBright resolve luminous |

Net: **`DonutChart.swift` needed no edits** — the force-dark override on `NeuCircularWell.content()` makes all of the above render exactly as designed in both themes. Similarly `BudgetsView.swift:340` ring track `Color.black.opacity(0.18)` is orb-subtree content and scheme-invariant, so it was left unchanged (Task 1.3, as the plan directed).

## Final Dish Token Values (light / dark)
| Token | Light | Dark (verbatim) |
|---|---|---|
| dishSlate (Plan 02) | #3E4250 | #15151B |
| dishInnerShade | #23262F @0.60 | #000000 @0.55 |
| dishInnerRise | #565B6C @0.50 | #FFFFFF @0.06 |
| dishHairlineDark | #23262F @0.55 | #000000 @0.50 |
| dishHairlineLight | #565B6C @0.45 | #FFFFFF @0.04 |
| dishWellShade | #23262F @0.42 | #000000 @0.35 |
| embossTop | #FFFFFF @0.45 | #FFFFFF @0.28 |
| embossBottom | #8E97AD @0.30 | #000000 @0.28 |

## Verification Evidence
- **D-06 unit gate (authoritative):** `DarkBitIdentityTests` + `DesignTokensTests` + `ContrastTests` → `** TEST SUCCEEDED **`, 0 failures. All 7 new tokens resolve in dark exactly to their pre-refactor black/white opacity composite.
- **Env-override source assertion:** `grep -c 'colorScheme, .dark' NeuSurface.swift` = **2** (NeuCircularWell content + VerticalPillGauge fill) — neither on a chrome ZStack.
- **Chrome-token assertions:** `DesignTokens.dishSlate` used twice in NeuSurface (well + gauge); EmbossedBar track still `Capsule().fill(DesignTokens.fillRecessed3)`.
- **Light render:** three phase-dir PNGs — orb/donut dish, budget-ring dish, pill-gauge wells — all slate instrument windows with luminous content.
- **Dark render:** sanity capture (budget ring) shows the original charcoal dish + luminous ring, visually unchanged; byte-identity proven by the unit gate.

## Task Commits
1. **Task 1: NeuCircularWell instrument window — slate chrome + force-dark content** — `e3a7b60` (feat)
2. **Task 2: pill-gauge instrument wells + EmbossedBar light glow language** — `ec1390e` (feat)
3. **Task 3: on-device light-mode dish/gauge tuning evidence** — `f916b21` (docs/evidence)

## Files Created/Modified
- `MyHomeApp/DesignSystem/NeuSurface.swift` — NeuCircularWell (slate chrome + force-dark content), VerticalPillGauge (slate well + force-dark fill), EmbossedBar (neu*-family chrome + embossTop/Bottom fill)
- `MyHomeApp/DesignSystem/DesignTokens.swift` — added dish* chrome family + embossTop/embossBottom (dark = legacy opacity verbatim)
- `MyHomeTests/DesignTokensTests.swift` — extended DarkBitIdentityTests with the 7 new tokens

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Plan's DonutChart/BudgetsView premise corrected — files left unchanged**
- **Found during:** Task 1
- **Issue:** The plan lists `DonutChart.swift` (and `BudgetsView.swift`) in `files_modified` with an artifact "Dish gradients harmonized to slate in light". Inspection shows neither file contains dish-chrome layers — DonutChart's opacities are all orb CONTENT (contact shadow, radial body, particles, vignette, sphere shading, glow) and BudgetsView:340 is the ring track (content); the dish chrome is entirely in `NeuCircularWell`. All are scheme-invariant black/white opacities living inside the force-dark subtree.
- **Fix:** Left both files unchanged (editing content layers to dish* tokens would wrongly alter the orb/ring). The instrument-window goal is fully achieved by the `NeuCircularWell.content()` force-dark override. Per-layer classification documented above (plan Task 1.2/1.3 output requirement).
- **Files modified:** none
- **Committed in:** n/a (documented classification)

### Scoping notes
- `AnalyticsTrendChart` recessed inset (mentioned in the Pattern Map) is out of this plan's task scope and was not touched; it already renders as a light recessed inset with luminous curve.

## Authentication Gates
None.

## Known Stubs
None. All new tokens are wired into live recipes.

## Threat Flags
None — matches the plan's threat register (T-17-06: force-dark override confined to content()/fill subtrees, verified by the 2-site grep + light screenshots showing slate — not charcoal — chrome). No new inputs, storage, network, or trust boundaries.

## Self-Check: PASSED
- NeuSurface.swift, DesignTokens.swift, DesignTokensTests.swift, 3 light-dishes PNGs, and this SUMMARY all present
- Commits e3a7b60, ec1390e, f916b21 present
- Env-override count = 2; dishSlate used twice; EmbossedBar track = fillRecessed3
- D-06 unit gate green (0 drift on 7 new tokens); light + dark render evidence captured

---
*Phase: 17-light-mode-support-neumorphic-redesign*
*Completed: 2026-07-12*
