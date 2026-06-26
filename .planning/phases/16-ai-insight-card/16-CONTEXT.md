# Phase 16: AI Insight Card - Context

**Gathered:** 2026-06-26
**Status:** Ready for planning

<domain>
## Phase Boundary

On the Analytics screen, an **on-device Apple FoundationModels** card turns the
existing `SpendSummary` (produced by Phase 15's `AnalyticsAggregator`) into a
single natural-language spending insight — fully offline, no network call,
finance data never leaves the device.

In scope: the AI Insight card UI at the bottom of `AnalyticsView`; two-layer
availability gating (`#available(iOS 26, *)` + runtime
`SystemLanguageModel.default.availability`); a `@Generable` insight struct
(`observation` + optional `suggestion`) with guided generation; a structured
prompt that injects pre-computed `SpendSummary` facts as literal context; an
`InsightVerifier` that rejects model-invented numbers and substitutes a
templated fallback; streaming typewriter reveal with breathing-orb loading
state; Reduce-Motion handling; unit tests via a mock session covering all
availability + error branches.

Out of scope: any change to `AnalyticsAggregator` / `SpendSummary` (consumed
as-is), persisted insight history (AI-05 — discarded after session), any new
tab or navigation change, light mode.

</domain>

<decisions>
## Implementation Decisions

### Unavailable-device UI (resolves a ROADMAP↔requirement conflict)
- **D-01:** On **every** unavailability case (`deviceNotEligible`,
  `appleIntelligenceNotEnabled`, `modelNotReady`, and pre-iOS-26), the AI card
  is **omitted entirely** — no shell card, no placeholder text, no blank gap,
  no spinner. Analytics simply ends after the category bars.
- **D-02:** This **overrides the AI-02 requirement wording** ("degrades to a
  graceful 'insights available on Apple Intelligence devices' shell"). ROADMAP
  Success Criterion 2 ("omitted entirely with no error message, blank gap, or
  stuck spinner") is authoritative. **Do not build a degraded shell.** The
  availability gating logic must still be implemented and unit-tested for all
  four branches — only the *rendered output* for the unavailable branches is
  "nothing".

### Card visual style
- **D-03:** The card uses a **`.neuSurface(.raised)` neumorphic base** (same
  surface system as the rest of v1.2) — NOT the design handoff's frosted-glass
  material.
- **D-04:** A **violet edge-glow + `sparkles` icon + breathing orb** is kept as
  the **AI-only signature accent** (violet ≈ `#C4A6FF`→`#7C5CFF` per
  `analytics.jsx`). This introduces violet as a *localized AI accent only* —
  the app's primary accent stays canary `#FFD60A` everywhere else. Add the
  violet value(s) to `DesignTokens` scoped/named for AI use; do not repaint
  other surfaces. Honors [[neon-design-direction]] (canary unchanged).

### Insight tone & focus
- **D-05:** Tone = **observation + soft, data-grounded suggestion**. The
  `suggestion` field is included only when there's a clear, fact-supported
  nudge; **never nagging or budget-policing**. Mirrors the design samples
  ("Dining is up 34%… skipping one keeps you under budget").
- **D-06:** Focus angles the insight may take (all fair game; model picks the
  most salient for the range):
  - Top-category change vs prior period (default angle).
  - Overall trend / headline delta direction.
  - Notable concentration (one category dominating the range's share).
  - Calm reassurance when nothing moved much ("spending held steady") — do NOT
    invent drama on flat data.

### Regeneration trigger
- **D-07:** Generate **automatically when the card appears**, and
  **re-generate on every Week/Month/Year range switch** (matches the handoff's
  per-range typewriter feel).
- **D-08:** **Cancel any in-flight generation when the range changes** so rapid
  range taps don't stack model runs or render a stale insight against the new
  range. (Implementation detail flagged for planner — task cancellation /
  debounce on the generation `Task`.)

### Claude's Discretion
- Exactly which `SpendSummary` facts to inject and how (token-budgeted prompt
  construction per AI-03), the `InsightVerifier` matching strategy, and the
  templated-fallback sentence wording — all Claude's discretion, grounded in
  the AI-04 rule that **every** rupee/%/delta in output must match a
  Swift-precomputed `Decimal` fact. Fallback should read as a normal terse
  insight, never as an error.
- Typewriter cadence (~22–38 cps per handoff), orb animation timing.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & roadmap
- `.planning/ROADMAP.md` §"Phase 16: AI Insight Card" — Goal + 5 Success
  Criteria (authoritative; Criterion 2 overrides AI-02 shell wording per D-01/02).
- `.planning/REQUIREMENTS.md` — AI-01…AI-05 (on-device, gating, guided
  generation, numeric integrity, ephemeral + typewriter).

### Design handoff
- `design/design_handoff_myhome_neumorphic/src/analytics.jsx` §`AIInsight`
  (lines ~320–375) — visual reference for violet edge-glow, sparkles label,
  breathing orb, typewriter, and insight copy examples. **Note:** we adopt the
  ACCENT (violet/orb/sparkles) but on a neumorphic base, not the frosted glass
  (D-03/04).
- `design/design_handoff_myhome_neumorphic/src/tokens.jsx` — for violet glow
  values to port into `DesignTokens`.

### Upstream code contract (Phase 15)
- `MyHomeApp/Support/AnalyticsAggregator.swift` — `SpendSummary` struct (the
  fact source) + `summarize(...)`. Consumed unchanged.
- `.planning/phases/15-analytics-screen/15-CONTEXT.md` — established v1.2
  conventions (neuSurface, Decimal-for-money, IST bucketing, pbxproj footgun).

### Framework guidance
- Skill `everything-claude-code:foundation-models-on-device` — Apple
  FoundationModels patterns (`@Generable`, guided generation, tool calling,
  snapshot streaming, availability). Researcher should lean on this.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SpendSummary` (`MyHomeApp/Support/AnalyticsAggregator.swift`): already
  exposes `totalSpend`, `priorTotalSpend`, `delta`, `deltaFraction`,
  `categoryBreakdown` ([CategorySpendItem]), `priorCategorySpend`,
  `trendBuckets` — built in Phase 15 *explicitly* for this card ("Phase 16 can
  consume this type without modification"). This is the fact source for prompt
  injection + `InsightVerifier`.
- `.neuSurface(.raised/.floating/.recessed)` + `DesignTokens` (Phase 13) — card
  surface + (new) violet AI accent token.
- Reduce-Motion handling already established (RollingMoneyText, Phase 13/15) —
  reuse the same `@Environment(\.accessibilityReduceMotion)` pattern for the
  typewriter snap + orb suppression.

### Established Patterns
- `AnalyticsView.swift` (`MyHomeApp/Features/Analytics/`) — host screen; the AI
  card is appended at the bottom of its scroll, below `AnalyticsCategoryBars`.
- Money stays `Decimal`; `Double` only at conversion boundaries (Pitfall guard
  carried from Phase 15).
- New `.swift` files MUST be registered in `MyHome.xcodeproj/project.pbxproj`
  (4 manual edits each — no synchronized groups). See [[xcodeproj-explicit-file-refs]].

### Integration Points
- `AnalyticsView` owns the current `SpendRange`; the card observes range changes
  to trigger regenerate + cancel-in-flight (D-07/08).
- Deployment target stays `IPHONEOS_DEPLOYMENT_TARGET = 17.0`; all FoundationModels
  code sits behind `#available(iOS 26, *)` (verified: pbxproj currently 17.0).
- iOS 26 / Apple Intelligence APIs are unavailable in the Phase-15-era
  simulator/toolchain expectation — researcher should confirm the available
  SDK and how to unit-test via a mock session (Success Criterion 5).

</code_context>

<specifics>
## Specific Ideas

- Insight copy voice target (from handoff samples): terse, concrete, one short
  paragraph, e.g. *"Dining is up 34% this week — three weekend orders drove
  most of it. Skipping one keeps you under budget."* Observation first, soft
  suggestion second, no preamble.
- Two-person Indian household, single-user app — keep suggestions friendly and
  non-judgmental; rupee figures only, never invented.

</specifics>

<deferred>
## Deferred Ideas

- Persisted insight history / "past insights" timeline — explicitly out of
  scope per AI-05 (ephemeral). Backlog if ever wanted.
- A user-facing "graceful shell" advertising the feature on ineligible devices
  — rejected for this phase (D-01); could revisit if discoverability matters.
- Light mode — backlog Phase 999.1 (carried from Phase 15).

### Reviewed Todos (not folded)
None — no pending todos matched this phase.

</deferred>

---

*Phase: 16-ai-insight-card*
*Context gathered: 2026-06-26*
