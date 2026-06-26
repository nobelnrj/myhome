# Phase 16: AI Insight Card - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-26
**Phase:** 16-ai-insight-card
**Areas discussed:** Unavailable-device UI, Card visual style, Insight tone & focus, Regeneration trigger

---

## Unavailable-device UI

| Option | Description | Selected |
|--------|-------------|----------|
| Omit entirely | No card/gap/message on non-AI devices; matches ROADMAP criterion 2 | ✓ |
| Graceful shell | Static "insights available on Apple Intelligence devices" card; matches AI-02 text | |
| Shell only if eligible-but-off | Omit on never-capable hardware; shell only when AI toggled off | |

**User's choice:** Omit entirely
**Notes:** Resolves the ROADMAP↔AI-02 conflict in favor of the ROADMAP success criterion. No degraded shell built; gating logic still implemented + tested for all four branches, but unavailable branches render nothing.

---

## Card visual style

| Option | Description | Selected |
|--------|-------------|----------|
| Violet glass (as designed) | Frosted glass + violet edge per analytics.jsx; breaks neumorphic+canary | |
| Neumorphic + canary | .neuSurface card with canary #FFD60A accent; fully cohesive | |
| Neumorphic base, violet accent | Neumorphic surface + violet edge-glow/sparkles/orb as AI signature | ✓ |

**User's choice:** Neumorphic base, violet accent
**Notes:** Violet introduced as a localized AI-only accent; canary stays the app's primary accent.

---

## Insight tone & focus

| Option | Description | Selected |
|--------|-------------|----------|
| Observation + soft suggestion | State pattern, then optional gentle data-grounded nudge | ✓ |
| Observation only | Neutral readout, no advice | |
| You decide per-range | Optional suggestion working as designed | |

**User's choice:** Observation + soft suggestion (never nagging)

**Focus angles (multi-select — all chosen):** Top-category change, Overall trend/delta, Notable concentration, Reassurance when flat.

**Notes:** Model picks the most salient angle per range; calm on flat data, no invented drama.

---

## Regeneration trigger

| Option | Description | Selected |
|--------|-------------|----------|
| Auto on appear + on range switch | Generates on view + re-runs each Week/Month/Year switch | ✓ |
| Auto on appear, manual refresh after | Generates once; manual tap to re-run | |
| Fully manual | Nothing runs until a "Generate" tap | |

**User's choice:** Auto on appear + on range switch
**Notes:** Planner to cancel in-flight generation on range change so rapid taps don't stack or render stale insights.

---

## Claude's Discretion

- Which `SpendSummary` facts to inject + token-budgeted prompt construction (AI-03).
- `InsightVerifier` matching strategy and the templated-fallback sentence wording (must read as a normal insight, not an error; AI-04).
- Typewriter cadence (~22–38 cps) and orb animation timing.

## Deferred Ideas

- Persisted insight history — out of scope (AI-05, ephemeral).
- User-facing shell advertising AI on ineligible devices — rejected (D-01); revisit only if discoverability matters.
- Light mode — backlog Phase 999.1.
