# Requirements — Milestone v1.2: Neumorphic Redesign

**Milestone goal:** A full neumorphic (Soft UI) visual redesign of the entire app, plus the design handoff's net-new surfaces — a dedicated Analytics screen, a "where it's going" spend donut on Overview, and an on-device AI Insight card — making My Home look and feel like a polished, cohesive personal-finance product rather than a stock SwiftUI app.

**Constraints carried from v1.0/v1.1:** local-only (no CloudKit/sharing — remains the v2.0 trigger gated on the $99/yr upgrade), zero recurring cost, no paid third-party services/SDKs, no analytics/telemetry, free public data only with manual override always available, CloudKit-ready SwiftData schema (additive, no `.unique`, optional/defaulted).

**v1.2-specific ground rules (from research, see `.planning/research/SUMMARY.md`):**
- **Zero new dependencies** — every capability ships on first-party Apple frameworks already available with Xcode 26.
- **iOS 17 deployment floor stays.** FoundationModels (iOS 26) is adopted behind `#available(iOS 26, *)` + runtime `SystemLanguageModel.default.availability` gating; it lights up only on eligible devices and is invisibly absent elsewhere. No other code is affected.
- **No SwiftData schema change** — SchemaV9 is sufficient; v1.2 is presentation + service concerns only.
- **Dark-mode-only** design; no light-mode variant; no translucency/blur/Liquid Glass.
- Dev device confirmed **A17 Pro+** → AI Insight is testable end-to-end on-device.

---

## v1.2 Requirements

### Design System Foundation (DS)

<!-- Pure UI, zero data dependencies. Ships FIRST — every other v1.2 surface depends on stable tokens. -->

- [ ] **DS-01**: A single source-of-truth `DesignTokens` defines the neumorphic palette (charcoal surfaces, canary-yellow accent), dual light/dark shadow specs, 26px corner radius, and spacing scale — translated from `design/design_handoff_myhome_neumorphic/src/tokens.jsx`.
- [ ] **DS-02**: A reusable `NeuSurface` view-modifier family renders raised / recessed / floating states via the dual-shadow system, so any view adopts the look with one modifier (replaces the thin `CardStyle`).
- [ ] **DS-03**: A floating capsule tab bar replaces the stock `TabView` chrome, with correct safe-area insets so scrolled content is never occluded and existing deep-link tab indices remain stable.
- [ ] **DS-04**: A rolling/animated money readout component (`.contentTransition(.numericText)`) for headline figures (balances, totals).
- [ ] **DS-05**: Dark-mode-only palette — no light-mode variant, no translucency/blur/Liquid Glass; solid opaque surfaces with the dual-shadow system only.
- [ ] **DS-06**: The design system is accessible by construction — meets WCAG 1.4.11 (3:1) non-text contrast for interactive surface boundaries (never relying on the 3.5%-white shadow as the only affordance), scales with Dynamic Type via font tokens (no hardcoded pixel sizes), and honors Reduce Motion (rolling-money and typewriter animations degrade to instant).

### Restyle Existing Screens (SKIN)

<!-- Mechanical application of DS tokens across every screen; highest regression surface (~118 files). -->

- [ ] **SKIN-01**: Overview restyled to the neumorphic look.
- [ ] **SKIN-02**: Activity / Expenses (list + add/edit) restyled.
- [ ] **SKIN-03**: Budgets restyled.
- [ ] **SKIN-04**: Notes, calendar, and day-agenda restyled.
- [ ] **SKIN-05**: Settings restyled.
- [ ] **SKIN-06**: Accounts restyled.
- [ ] **SKIN-07**: Assets / Net-worth (incl. existing `DonutChart`) restyled to the neumorphic palette.
- [ ] **SKIN-08**: Transfer Inbox and Gmail / ingestion Review Inbox restyled.
- [ ] **SKIN-09**: No regression — existing flows (expense/account/asset/note CRUD, Gmail sync, self-transfer confirm, Face ID gate, navigation/deep-links) continue to work after restyle, and every new `.swift` file is registered in `project.pbxproj` so the target builds clean.

### Overview Spend Donut (OVR)

<!-- Continues OVR numbering from v1.0 (OVR-01..04). Wired to existing SwiftData expense queries. -->

- [ ] **OVR-05**: A "where it's going" spend donut on Overview shows current-month spend by category via Swift Charts `SectorMark` — center total, top-4 categories + "Others" roll-up legend, and a grow-in animation; reuses the existing expense query with the confirmed-self-transfer exclusion.
- [ ] **OVR-06**: Tapping a donut segment opens Activity filtered to that category (tap-to-filter).

### Analytics Screen (ANL)

<!-- New screen, pushed from Overview. Shared AnalyticsAggregator feeds charts AND the AI card. -->

- [ ] **ANL-01**: A dedicated Analytics screen is reachable by push from Overview (slide-in), not as a tab.
- [ ] **ANL-02**: Time-range tabs (week / month / year) scope all analytics content; no custom date-range picker.
- [ ] **ANL-03**: A spending-trend area chart (`AreaMark`) over the selected range, with IST-correct date bucketing that reuses the existing `SpendOverTimeAggregator` (no re-implementation).
- [ ] **ANL-04**: A by-category bar breakdown (`BarMark`) for the selected range.
- [ ] **ANL-05**: Period-over-period delta chips using the inverted color convention — green = spent less than the prior period (good), coral = spent more (bad).
- [ ] **ANL-06**: Tapping a delta chip drills into the underlying category/period breakdown.
- [ ] **ANL-07**: All analytics aggregation is computed by a single pure/testable `AnalyticsAggregator` that produces a `SpendSummary` value type reused by the AI Insight card; an IST-midnight-boundary bucketing test is a required exit criterion.

### On-Device AI Insight (AI)

<!-- FoundationModels, iOS 26, gated behind availability. Finance-AI safety is non-negotiable. -->

- [ ] **AI-01**: An AI Insight card on the Analytics screen produces a natural-language spending insight from on-device Apple FoundationModels (iOS 26 / Apple Intelligence) — fully on-device and offline; finance data never leaves the device.
- [ ] **AI-02**: Two-layer availability gating — `#available(iOS 26, *)` plus runtime `SystemLanguageModel.default.availability` — with all unavailability cases handled (`deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`); on ineligible devices the card degrades to a graceful "insights available on Apple Intelligence devices" shell with no error noise, and no non-gated code is affected.
- [ ] **AI-03**: The insight uses guided generation — a `@Generable` struct (`observation` + optional `suggestion`) with a structured prompt kept under the model's token budget — and handles `guardrailViolation` and `exceededContextWindowSize`.
- [ ] **AI-04**: Numeric integrity — all rupee amounts, percentages, and deltas are pre-computed in Swift (`Decimal`) and injected as literal context; the model never computes figures, and its output is verified against the injected facts before display (no invented numbers).
- [ ] **AI-05**: Insights are generated on demand and discarded after the session (no persisted insight history), revealed with a streaming typewriter animation that honors Reduce Motion.

---

## Out of Scope (explicit exclusions)

- **CloudKit / multi-device sharing** — remains the v2.0 trigger, gated on the $99/yr Apple Developer upgrade. Schema stays CloudKit-ready but no sync work in v1.2.
- **Light-mode variant** — the neumorphic skin is dark-mode-only by design; a light variant breaks the dual-shadow language.
- **Cloud LLM fallback for AI Insight** — finance data must not leave the device; the on-device gate is by design, not a limitation to work around.
- **Persisted AI insight history** — saved generated text becomes misleading as underlying data changes; generate on demand, discard after session.
- **Custom analytics date-range picker** — the three fixed ranges cover all household use cases for two specific users.
- **SwiftData schema changes** — SchemaV9 is sufficient; introducing a V10 for a presentation milestone is unnecessary risk.
- **Translucency / blur / Liquid Glass material** — incompatible with the opaque neumorphic surfaces.

## Future Requirements (deferred, not this milestone)

- AI insight surfaced on Overview (in addition to Analytics) — deferred; v1.2 ships the card on Analytics only to keep one gated surface.
- Richer AI interactions (follow-up questions, multi-month trend narratives) — out of scope for an on-device 3B model's first integration.

## Traceability

| REQ-ID | Phase | Status |
|--------|-------|--------|
| DS-01 | Phase 13 | Pending |
| DS-02 | Phase 13 | Pending |
| DS-03 | Phase 13 | Pending |
| DS-04 | Phase 13 | Pending |
| DS-05 | Phase 13 | Pending |
| DS-06 | Phase 13 | Pending |
| SKIN-01 | Phase 14 | Pending |
| SKIN-02 | Phase 14 | Pending |
| SKIN-03 | Phase 14 | Pending |
| SKIN-04 | Phase 14 | Pending |
| SKIN-05 | Phase 14 | Pending |
| SKIN-06 | Phase 14 | Pending |
| SKIN-07 | Phase 14 | Pending |
| SKIN-08 | Phase 14 | Pending |
| SKIN-09 | Phase 14 | Pending |
| OVR-05 | Phase 14 | Pending |
| OVR-06 | Phase 14 | Pending |
| ANL-01 | Phase 15 | Pending |
| ANL-02 | Phase 15 | Pending |
| ANL-03 | Phase 15 | Pending |
| ANL-04 | Phase 15 | Pending |
| ANL-05 | Phase 15 | Pending |
| ANL-06 | Phase 15 | Pending |
| ANL-07 | Phase 15 | Pending |
| AI-01 | Phase 16 | Pending |
| AI-02 | Phase 16 | Pending |
| AI-03 | Phase 16 | Pending |
| AI-04 | Phase 16 | Pending |
| AI-05 | Phase 16 | Pending |
