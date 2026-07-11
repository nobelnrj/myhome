# Phase 17: Light Mode Support - Context

**Gathered:** 2026-07-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the entire v1.2 neumorphic design system **adaptive light/dark** without
changing any feature behavior. Today the app is dark-only by decision (DS-05):
`MyHomeApp.swift:34` forces `.preferredColorScheme(.dark)` at the root and every
`DesignTokens` color is a single static dark hex.

Delivers: a theme setting (System / Light / Dark) in Settings; a complete
light-tuned token palette (canvas, surfaces, wells, labels, separators);
light-tuned neumorphic shadow/rim/inner-shadow values across all surface
components; role-split accent + deepened category/semantic colors for light;
the "instrument window" treatment for all chart dishes; adapted glow language;
and a pixel-identical dark theme throughout.

Out of scope: any new screen, feature, chart, or data change; app icon
variants; widgets; changes to dark-mode rendering.

</domain>

<decisions>
## Implementation Decisions

### Theme control & default
- **D-01:** **Follow system + in-app override.** Remove the hard-coded
  `.preferredColorScheme(.dark)`; replace with an AppStorage-backed setting
  (System / Light / Dark). `System` follows iOS appearance; Light/Dark pin it.
- **D-02:** **Default = System.** On first launch after the update the app
  immediately follows the phone's appearance — no opt-in gate.
- **D-03:** **Settings UI = one segmented "Appearance" row** (System / Light /
  Dark neumorphic pill segments) near the top of Settings. No sub-screen.

### Light canvas character
- **D-04:** **Classic neumorphic cool gray.** Canvas in the `#E3E6EE` family;
  raised cards slightly lighter with the same diagonal curvature-gradient
  scheme (lit top-left → shaded bottom-right); wells darker than canvas; label
  tiers dark cool (`#23252E`-family primary + opacity tiers). Exact values are
  planner/executor's to tune on device.
- **D-05:** **Depth matches dark's drama.** Same sculptural intent — clearly
  carved wells, plump raised pillows — re-tuned for light (gray-blue dark
  shadows, bright white highlights). The two themes should read as the same
  physical object under different lighting. All inline shadow values
  (NeuSurface rims, recessed overlays, button styles, EmbossedBar,
  VerticalPillGauge, NeuCircularWell/Puck) need light twins — these are
  scattered inline today, not centralized in ShadowSpec.
- **D-06:** **Dark mode stays PIXEL-IDENTICAL.** Light mode is purely
  additive. The token refactor (static hex → adaptive) must not shift dark
  rendering at all. Verify with before/after dark screenshots per screen.
- **D-07:** **System chrome tinted to match.** Native tab bar / nav bars /
  sheets get the light-gray canvas family tones — same structural approach as
  dark today (native bar, restyled colors only; no custom bar).

### Accent & category colors (light variants)
- **D-08:** **Accent split by role.** Fills/pills/CTA buttons keep true canary
  `#FFD60A` with dark text on them (unchanged); accent-colored TEXT and ICONS
  switch to a darker amber (`#8A6D00` family) that passes WCAG contrast on the
  light canvas. Rationale: canary on light gray is ~1.4:1 — the handoff's own
  light skin darkens it (`tokens.jsx` mixes 72% accent + `#4a3500`).
- **D-09:** **Category palette deepened per-color** for light surfaces — each
  of the 11 categories gets a hand-tuned darker/saturated light twin (teal →
  deep teal `#0F9488`-ish, dining → burnt orange, etc.). Hue identity is
  preserved: groceries is teal in both themes. Applies to icons, tiles, text,
  and any category color rendered on a light surface.
- **D-10:** **Semantic colors deepened to match** — income green → deep
  emerald, spend red → firm crimson, warning orange → amber, tuned for small
  delta text legibility on light.
- **D-11 (scope clarifier):** Inside dark chart dishes (D-12/13) chart fills
  keep the ORIGINAL luminous dark-mode palette; the deepened variants (D-09/10)
  are for elements on light surfaces. Both variants coexist.

### Orb, glow & chart-dish treatment
- **D-12:** **All chart dishes become dark "instrument windows"** in light
  mode — the hero orb dish, donut dish, budget-ring dish, and vertical
  pill-gauge wells all keep deep interiors so particle glows, neon fills, and
  luminous chart colors render as designed. The orb itself is unchanged.
- **D-13:** **Dish interiors are harmonized deep slate, NOT verbatim
  charcoal.** User explicitly corrected this: the porthole must adapt to the
  light theme — a light-theme-tuned deep slate/gray-blue (`#3E4250` family)
  instead of near-black `#16161C`. Dark enough for glow to read, soft enough
  to belong to the light palette (no "hole punched into dark mode").
- **D-14:** **Glow on light surfaces → subtle colored drop-shadow.** Elements
  that glow while sitting directly on cards (EmbossedBar fills, accent-glowing
  numbers/icons via `neonGlow`) replace the two-layer bloom with a faint
  tinted drop-shadow — a whisper of the neon language. Calibrate so it never
  reads as a rendering smudge.
- **D-15:** **AI Insight card: deepen violet + keep signature.** Edge-glow
  becomes a subtle deep-violet tinted shadow (consistent with D-14),
  sparkles/label switch to a darker violet passing contrast, breathing orb
  keeps its violet fill with reduced bloom. Violet stays AI-only (Phase 16
  D-04 unchanged).

### Claude's Discretion
- Theme-flip transition feel (D-01): default to SwiftUI's environment change;
  add a gentle crossfade only if the flip looks jarring on device; must honor
  Reduce Motion.
- All exact light hex values, shadow radii/opacities, and the slate dish tone —
  tune via the simulator screenshot loop ([[simulator-screenshot-verify-loop]]);
  the previews in this discussion are directional, not locked values.
- Token architecture (how static hexes become adaptive — e.g.
  `Color(light:dark:)` init, UITraitCollection-based dynamic colors, or a
  theme-environment struct) — planner's call, constrained by D-06
  (dark output must be bit-identical) and the AppStorage override (D-01),
  which means the mechanism must respect the app-level override, not just the
  system trait.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design system (the code being made adaptive)
- `MyHomeApp/DesignSystem/DesignTokens.swift` — all color/shadow/spacing
  tokens; single dark hex per color today; `neonGlow`, entrance, Haptics.
- `MyHomeApp/DesignSystem/NeuSurface.swift` — surface modifier + button
  styles + EmbossedBar + VerticalPillGauge + NeuCircularWell/Puck; contains
  many INLINE white/black shadow values that need light twins (D-05).
- `MyHomeApp/MyHomeApp.swift` — line 34: DS-05 `.preferredColorScheme(.dark)`
  root modifier to be replaced by the theme setting (D-01).

### Design handoff
- `design/design_handoff_myhome_neumorphic/src/tokens.jsx` — skin metadata
  (lines ~55-60: `neuro` is `light: false` — NO light-neuro reference exists;
  light values must be derived) and the light-accent mix recipe (lines ~69-74)
  that motivated D-08.

### Prior phase contracts (carried decisions)
- `.planning/phases/14-restyle-existing-screens-overview-donut/14-CONTEXT.md`
  — skin=Neomorphism locked, native tab bar, no glass; DS-05 origin.
- `.planning/phases/16-ai-insight-card/16-CONTEXT.md` — violet is AI-only
  (D-04 there); AI card structure for D-15 here.
- `.planning/ROADMAP.md` §"Phase 17: Light Mode Support" — goal + why it's a
  phase, not a toggle.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DesignTokens` is consumed by **62 files** — making its statics adaptive
  retrofits most of the app in one move.
- `NeuSurface`/`EmbossedBar`/`VerticalPillGauge`/`NeuCircularWell`/`NeuCircularPuck`
  centralize surface rendering — but hold inline `.white.opacity()`/
  `.black.opacity()` shadow/rim values that bypass tokens and must be made
  theme-aware individually.
- Settings screen already restyled neumorphic (Phase 14) — host for the
  Appearance segmented row (D-03).

### Established Patterns
- **Zero `colorScheme` environment reads exist today** — nothing in the app
  is scheme-aware; every adaptive behavior is net-new.
- Hard-coded `Color(hex:)` OUTSIDE DesignTokens in: `NeuSurface.swift` (CTA
  gradients), `Features/Settings/Account*.swift` + `MergeAccountView.swift`,
  `Features/Shared/IconTile.swift`, `Features/Overview/SpendOverTimeChart.swift`,
  `Features/Analytics/AnalyticsTrendChart.swift` — each needs audit for light.
- Previews pin `.preferredColorScheme(.dark)` in several files (NeuSurface,
  RollingMoneyText, SpendBudgetCard) — update to show both themes.
- New `.swift` files need the 4 manual pbxproj edits
  ([[xcodeproj-explicit-file-refs]]) — prefer extending existing files where
  sensible.
- Self-verify UI via build→install→launch `-seedSampleData`→screenshot loop;
  debug hooks `-openAnalytics`/`-scrollTo`/`-startTab N` available.

### Integration Points
- `MyHomeApp.swift` root: theme setting replaces the fixed `.dark` modifier;
  an AppStorage-backed value must drive `preferredColorScheme(nil/.light/.dark)`.
- Face ID lock overlay, launch experience, and sheets inherit whatever the
  root scheme resolves to — verify they follow the theme (no separate work
  expected, but check).
- Charts (donut, trend, pill gauges, orb) sit inside wells → D-12/13 slate
  dishes; their internal colors stay dark-palette (D-11).

</code_context>

<specifics>
## Specific Ideas

- "Same object under different lighting" — the user wants light mode to carry
  the SAME sculptural neumorphic drama as the just-shipped dark v2, not a
  flatter/softer parallel theme.
- The instrument-window language: user chose to keep ALL charts in deep dishes
  (bolder than the recommended orb-only option) but explicitly corrected the
  tone — dishes must harmonize with the light palette (deep slate, D-13), not
  read as holes into dark mode.
- User chose tinted drop-shadows over fully stripping glow on light — keep a
  whisper of the neon identity everywhere.
- WHOOP remains the data-viz quality bar; hero numerals stay solid
  `.semibold` (no thin fonts) in both themes.

</specifics>

<deferred>
## Deferred Ideas

- App icon light/dark variants, notification styling, and any widget surfaces
  — not in this phase (no widgets exist; icon untouched).

### Reviewed Todos (not folded)
- `test-isolation-swiftdata-multicontainer.md` — matched only on generic
  keywords (score 0.4); test-infra debt unrelated to light mode. Left pending.

</deferred>

---

*Phase: 17-light-mode-support-neumorphic-redesign*
*Context gathered: 2026-07-11*
