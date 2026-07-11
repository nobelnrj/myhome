# Phase 17: Light Mode Support - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-11
**Phase:** 17-light-mode-support-neumorphic-redesign
**Areas discussed:** Theme control & default, Light canvas character, Accent & category colors, Orb/glow & AI treatment

---

## Theme control & default

| Option | Description | Selected |
|--------|-------------|----------|
| Follow system + override | System default + Settings row (System/Light/Dark), AppStorage-backed | ✓ |
| Follow system only | Pure system-driven, no in-app control | |
| Manual toggle only | App ignores system appearance | |

**User's choice:** Follow system + override

| Option | Description | Selected |
|--------|-------------|----------|
| System | Follows phone appearance immediately after update | ✓ |
| Dark until opted in | Nothing changes until user opts in | |

**User's choice:** System default

| Option | Description | Selected |
|--------|-------------|----------|
| Segmented row | One 'Appearance' row, three pill segments, near top of Settings | ✓ |
| Sub-screen picker | Pushed screen with live preview | |
| You decide | | |

**User's choice:** Segmented row

| Option | Description | Selected |
|--------|-------------|----------|
| You decide | SwiftUI default; crossfade only if jarring; honor Reduce Motion | ✓ |
| Gentle crossfade | Deliberate ~0.3s ease | |
| Instant snap | No animation | |

**User's choice:** You decide (transition feel)

---

## Light canvas character

| Option | Description | Selected |
|--------|-------------|----------|
| Classic neumorphic gray | Cool light gray #E3E6EE family, canonical soft-UI | ✓ |
| Warm paper white | #F2EFE9 family, cozy/journal feel | |
| Cool near-white | #F4F6FA family, stock-iOS bright | |

**User's choice:** Classic neumorphic gray

| Option | Description | Selected |
|--------|-------------|----------|
| Match dark's drama | Same sculptural depth, light-tuned values | ✓ |
| Softer, airier | Gentler classic light soft-UI | |
| You decide | | |

**User's choice:** Match dark's drama — "same object, different light"

| Option | Description | Selected |
|--------|-------------|----------|
| Pixel-identical | Dark stays exactly as shipped; light purely additive | ✓ |
| Small tweaks allowed | Incidental dark fixes permitted | |

**User's choice:** Pixel-identical dark

| Option | Description | Selected |
|--------|-------------|----------|
| Tint to match canvas | Bars/chrome in light-gray canvas family | ✓ |
| Stock iOS light chrome | Default light materials | |
| You decide | | |

**User's choice:** Tint chrome to match canvas

---

## Accent & category colors

| Option | Description | Selected |
|--------|-------------|----------|
| Split by role | Fills/CTAs keep canary; accent text/icons go dark amber | ✓ |
| Handoff mix everywhere | One muted gold for all accent uses | |
| You decide | | |

**User's choice:** Split by role

| Option | Description | Selected |
|--------|-------------|----------|
| Deepen per-color | Hand-tuned darker twin per category, hue preserved | ✓ |
| Uniform darken formula | One programmatic rule for all 11 | |
| Keep as-is | Same pastels in both themes | |

**User's choice:** Deepen per-color

| Option | Description | Selected |
|--------|-------------|----------|
| Deepen to match | Deep emerald / firm crimson / amber | ✓ |
| Keep as-is | | |

**User's choice:** Deepen semantic colors

---

## Orb, glow & AI treatment

| Option | Description | Selected |
|--------|-------------|----------|
| Dark dish porthole | Dish keeps deep interior; orb + glow render as in dark | ✓ |
| Fully light-adapted orb | Light well, matte particles, no glow | |
| You decide | | |

**User's choice:** Dark dish porthole

| Option | Description | Selected |
|--------|-------------|----------|
| Orb only | Only hero orb keeps dark dish | |
| All chart dishes dark | Donut, budget ring, pill gauges too — instrument windows | ✓ |
| You decide | | |

**User's choice:** All chart dishes dark (bolder than the recommended option)

**Follow-up (user, mid-discussion):** "but the porthole treatment should adapt to the light theme"

| Option | Description | Selected |
|--------|-------------|----------|
| Harmonized deep slate | Light-tuned deep slate/gray-blue (~#3E4250), not verbatim charcoal | ✓ |
| Mid-tone recessed well | Fully light-native; glows wouldn't read | |
| You decide | | |

**User's choice:** Harmonized deep slate
**Notes:** This was an explicit user correction of the porthole concept — dishes must belong to the light palette, not read as holes into dark mode.

| Option | Description | Selected |
|--------|-------------|----------|
| Strip glow on light | Glow becomes dark-wells-only | |
| Subtle colored drop-shadow | Faint tinted shadow under colored fills | ✓ |
| You decide | | |

**User's choice:** Subtle colored drop-shadow — keep a whisper of the neon identity

| Option | Description | Selected |
|--------|-------------|----------|
| Deepen violet + keep signature | Tinted shadow edge, darker violet text, orb keeps fill | ✓ |
| Dark porthole the orb too | Small dark dish for AI orb | |
| You decide | | |

**User's choice:** Deepen violet + keep signature

---

## Claude's Discretion

- Theme-flip transition (default env change vs crossfade; honor Reduce Motion)
- All exact light hex values, shadow radii/opacities, slate dish tone — tune on device
- Token architecture for adaptivity (must keep dark bit-identical and respect the AppStorage override)

## Deferred Ideas

- App icon light/dark variants, notification styling, widgets — out of phase scope
- `test-isolation-swiftdata-multicontainer.md` todo reviewed, not folded (unrelated; keyword-only match)
