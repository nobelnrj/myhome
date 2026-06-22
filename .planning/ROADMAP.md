# Roadmap: My Home

## Overview

My Home is a single-user (v1) iOS app for a two-person Indian household, built as a Swift learning vehicle on the Swift 6.2 / SwiftUI / SwiftData stack, iOS 17+. v1.0 shipped the full MVP (expense tracking, budgets, notes/reminders, overview, Face ID). v1.1 grew it into a light household finance hub (Accounts, self-transfer detection, net-worth Asset Tracker, daily-routine notes). v1.2 is a full neumorphic (Soft UI) visual redesign of the entire app plus the design's net-new surfaces (dedicated Analytics screen, on-device AI Insight, spend donut).

## Milestones

- ✅ **v1.0 MVP** — Phases 1-7 (shipped 2026-06-03) — see [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)
- ✅ **v1.1 Accounts, Assets & Household Polish** — Phases 8-12 (shipped 2026-06-20) — see [milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md)
- 🔜 **v1.2 Neumorphic Redesign** — Phases 13-16

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-7) — SHIPPED 2026-06-03</summary>

- [x] Phase 1: Foundation & Manual Expense Spine (4/4 plans) — completed 2026-05-29
- [x] Phase 2: Categories, Tags & Budgets (5/5 plans) — completed 2026-05-30
- [x] Phase 3: Notes & Checklists (6/6 plans) — completed 2026-05-30
- [x] Phase 4: Overview & Charts (5/5 plans) — completed 2026-06-01
- [x] Phase 5: Face ID Gate & Settings (2/2 plans) — completed 2026-06-01
- [x] Phase 6: Gmail Sign-In & Client (4/4 plans) — completed 2026-06-02
- [x] Phase 7: Bank Parsers & Ingestion Pipeline (6/6 plans) — completed 2026-06-03

Full phase details archived in [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md).

</details>

<details>
<summary>✅ v1.1 Accounts, Assets & Household Polish (Phases 8-12) — SHIPPED 2026-06-20</summary>

- [x] Phase 8: Stabilization (4/4 plans) — completed 2026-06-09
- [x] Phase 9: SchemaV6 & Accounts Management (4/4 plans) — completed 2026-06-10
- [x] Phase 10: Self-Transfer Detection (4/4 plans) — completed 2026-06-10
- [x] Phase 11: Asset Tracker (4/4 plans) — completed 2026-06-12
- [x] Phase 11.1: SIP Automation & NPS NAV auto-refresh (INSERTED) (5/5 plans) — completed 2026-06-12
- [x] Phase 12: Notes & Daily Routine Enhancement (5/5 plans) — completed 2026-06-20

Full phase details archived in [milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md).

</details>

### v1.2: Neumorphic Redesign

- [ ] **Phase 13: Design System Foundation** — Tokens, NeuSurface, NeuTabBar, RollingMoneyText, accessibility infrastructure
- [ ] **Phase 14: Restyle Existing Screens + Overview Donut** — Full neumorphic restyle of every existing screen; spend donut with tap-to-filter added to Overview
- [ ] **Phase 15: Analytics Screen** — New screen pushed from Overview; AnalyticsAggregator, area chart, category bars, delta chips
- [ ] **Phase 16: AI Insight Card** — On-device FoundationModels card on Analytics screen; availability gating, streaming typewriter, numeric integrity

---

## Phase Details

### Phase 13: Design System Foundation

**Goal**: The neumorphic design system is fully built and accessible — all token constants, surface modifiers, the capsule tab bar, rolling-money readout, and motion infrastructure exist as stable, tested components that every subsequent phase can consume without revisiting.
**Depends on**: Nothing (first v1.2 phase)
**Requirements**: DS-01, DS-02, DS-03, DS-04, DS-05, DS-06
**Success Criteria** (what must be TRUE):

  1. Every color, shadow, radius, and spacing value used in v1.2 is defined in one file (`DesignTokens.swift`); no view file in the project contains a hardcoded hex string or pixel-literal shadow value.
  2. Any view can adopt the raised, pressed, or inset neumorphic surface look by applying a single `.neuSurface(.raised/pressed/inset)` modifier — no duplicated shadow code.
  3. The floating capsule tab bar replaces the native SwiftUI tab bar in `RootView`, the five existing tabs remain reachable at their current deep-link indices, and scrolled content in every tab is never occluded by the floating bar.
  4. The `RollingMoneyText` component animates hero rupee figures from old to new value in ~780ms; with Reduce Motion enabled the value snaps to the target immediately with zero intermediate frames.
  5. Running Xcode Accessibility Inspector on `NeuSurface`, `NeuTabBar`, and their previews produces zero contrast warnings; the WCAG 1.4.11 (3:1) non-text contrast requirement is satisfied by construction (canary yellow `#FFD60A` used for all active/selected states; shadow depth is never the sole affordance).
  6. `xcodebuild clean build` succeeds after all new `DesignSystem/` files are registered in `project.pbxproj` (all 4 manual pbxproj edits per file completed).**Plans**: 3 plans

**Wave 1**

- [x] 13-01-PLAN.md — Scaffold DesignSystem/ + pbxproj G_DS group; DesignTokens.swift + token tests (DS-01, DS-05)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 13-02-PLAN.md — NeuSurface (raised/floating/recessed) + RollingMoneyText; deprecate CardStyle (DS-02, DS-04, DS-06)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 13-03-PLAN.md — NeuTabBar floating capsule + RootView/MyHomeApp integration + accessibility gate (DS-03, DS-05, DS-06) *(code-complete; human-verify checkpoint outstanding as v1.2 debt)*

**UI hint**: yes

### Phase 14: Restyle Existing Screens + Overview Donut

**Goal**: Every screen in the app looks neumorphic — no stock SwiftUI system colors remain anywhere — and the Overview gains the "Where it's going" spend donut with tap-to-filter into Activity.
**Depends on**: Phase 13 (stable design tokens and `NeuSurface` modifier required before touching any screen)
**Requirements**: SKIN-01, SKIN-02, SKIN-03, SKIN-04, SKIN-05, SKIN-06, SKIN-07, SKIN-08, SKIN-09, OVR-05, OVR-06
**Success Criteria** (what must be TRUE):

  1. All nine screen groups (Overview, Activity/Expenses, Budgets, Notes/calendar/agenda, Settings, Accounts, Assets/Net-worth, Transfer Inbox, Gmail Review Inbox) render with charcoal neumorphic surfaces, canary-yellow accents, and the luminous category palette — no `Color(.secondarySystemBackground)` or other stock system color is visible anywhere.
  2. The "Where it's going" spend donut appears on the Overview screen, shows the current month's top-4 spend categories plus an "Others" roll-up, and displays the rolling total in the center using `RollingMoneyText` — confirmed-self-transfer expenses are excluded from all segment totals.
  3. Tapping any donut segment navigates to the Activity screen pre-filtered to that category.
  4. All existing flows continue working without regression: expense/account/asset/note CRUD, Gmail sync, self-transfer confirm, Face ID gate, and navigation deep-links all behave identically to v1.1.
  5. The `DonutChart` in `DonutChart.swift` has all segments fully visible inside its card container (no clipping at card edges); segment colors match the neumorphic category palette used everywhere else.
  6. Every new `.swift` file added during the restyle is registered in `project.pbxproj`; `xcodebuild clean build` succeeds with zero "cannot find type" errors.

**Plans**: 8 plans

**Wave 1** *(foundation — unblocks all restyle waves)*

- [x] 14-01-PLAN.md — CategoryStyle → DesignTokens.cat* rewrite; native tab-bar canary tint; TDD SpendDonutAggregation helper (SKIN-01, SKIN-09, OVR-05)

**Wave 2** *(blocked on 14-01; all five run in parallel — disjoint files)*

- [x] 14-02-PLAN.md — Overview restyle + NET CASH FLOW hero + SpendDonutCard (new file + pbxproj) + OVR-06 tap-to-filter wiring (SKIN-01, OVR-05, OVR-06, SKIN-09)
- [x] 14-03-PLAN.md — Budgets group restyle (summary-ring hero, category cards, StackBar) (SKIN-03, SKIN-09)
- [x] 14-04-PLAN.md — Notes / calendar / agenda / reminder / routine restyle (SKIN-04, SKIN-09)
- [x] 14-05-PLAN.md — Settings + UnlockView + MigrationReviewSheet restyle (icon-tile color map) (SKIN-05, SKIN-08, SKIN-09)
- [ ] 14-06-PLAN.md — Accounts + Assets / Net-worth restyle (floating detail heros, donut segment recolor) (SKIN-06, SKIN-07, SKIN-09)

**Wave 3** *(blocked on 14-02 — shares ExpenseListView.swift)*

- [ ] 14-07-PLAN.md — Activity / Expenses + Gmail Review + Transfer Inbox rows restyle (SKIN-02, SKIN-08, SKIN-09)

**Wave 4** *(blocked on all restyle plans — deletion must come last)*

- [ ] 14-08-PLAN.md — Delete CardStyle.swift + NeuTabBar.swift (pbxproj removals); full clean-build + test gate; end-of-phase human-verify (SKIN-09)

**UI hint**: yes

### Phase 15: Analytics Screen

**Goal**: A dedicated Analytics screen — accessible via push from Overview — gives users a clear view of their spending trend, category breakdown, and period-over-period delta for any of three time ranges (week, month, year), with all data backed by a single testable aggregator whose output also feeds the AI card.
**Depends on**: Phase 13 (DesignTokens and NeuSurface for screen styling); Phase 14 not strictly required but completing restyle first keeps the design direction confirmed before committing Analytics layout
**Requirements**: ANL-01, ANL-02, ANL-03, ANL-04, ANL-05, ANL-06, ANL-07
**Success Criteria** (what must be TRUE):

  1. From the Overview screen, a single tap opens the Analytics screen via a navigation push (slide-in); the Analytics screen is not a new tab and does not change the existing tab-bar layout.
  2. Switching between Week, Month, and Year range tabs updates the spend headline, delta chip, area chart, and category bars simultaneously with no stale data visible.
  3. The spending-trend area chart buckets expenses into IST-correct day (week range), week (month range), or month (year range) slots; the "Year" tab shows only months up to and including the current month with no future zero-bars.
  4. The by-category horizontal bar breakdown shows all categories for the selected range, sorted descending by spend amount, with the correct neumorphic category palette.
  5. Each period-over-period delta chip uses the inverted color convention: green when total spend decreased vs the prior period, coral when it increased; tapping a delta chip reveals the underlying category or period detail that drove the change.
  6. `AnalyticsAggregatorTests.testMidnightISTBucketBoundary` passes: expenses timestamped 18:29Z and 18:31Z on the same UTC date are assigned to different IST day buckets.
  7. `xcodebuild clean build` succeeds after all new `Features/Analytics/` and `Support/` files are registered in `project.pbxproj`.

**Plans**: TBD
**UI hint**: yes

### Phase 16: AI Insight Card

**Goal**: On devices with Apple Intelligence enabled, the Analytics screen surfaces a natural-language spending insight generated entirely on-device; on every other device the card is silently absent with zero error noise, and no rupee figure ever appears in the insight that was not pre-computed in Swift.
**Depends on**: Phase 15 (AnalyticsView and SpendSummary from AnalyticsAggregator must exist before InsightService can be wired)
**Requirements**: AI-01, AI-02, AI-03, AI-04, AI-05
**Success Criteria** (what must be TRUE):

  1. On an iOS 26 device with Apple Intelligence enabled (A17 Pro+), the AI Insight card appears at the bottom of the Analytics screen and produces a coherent natural-language observation about the current range's spending patterns — all on-device with no network call.
  2. On any device where AI is unavailable (pre-iOS 26, `deviceNotEligible`, `appleIntelligenceNotEnabled`, or `modelNotReady`), the Analytics screen renders fully with charts and category bars; the AI card section is omitted entirely with no error message, blank gap, or stuck spinner visible to the user.
  3. Insight text reveals character-by-character via a streaming typewriter animation; with Reduce Motion enabled the full text appears instantly; the breathing orb loading state is shown while the model generates and is absent when Reduce Motion is on.
  4. Every rupee amount, percentage, and delta figure appearing in the generated insight text matches a value that was pre-computed by `AnalyticsAggregator` and injected as literal context — `InsightVerifier` catches any model-invented number and substitutes the templated fallback before display.
  5. All four availability branches (`available`, `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`) and both generation error cases (`guardrailViolation`, `exceededContextWindowSize`) are exercised by unit tests using a mock session; `grep IPHONEOS_DEPLOYMENT_TARGET MyHome.xcodeproj/project.pbxproj` returns `17.0`; and `xcodebuild clean build` succeeds.

**Plans**: TBD
**UI hint**: yes

---

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-7 | v1.0 | 32/32 | Complete | 2026-06-03 |
| 8. Stabilization | v1.1 | 4/4 | Complete | 2026-06-09 |
| 9. SchemaV6 & Accounts Management | v1.1 | 4/4 | Complete | 2026-06-10 |
| 10. Self-Transfer Detection | v1.1 | 4/4 | Complete | 2026-06-10 |
| 11. Asset Tracker | v1.1 | 4/4 | Complete | 2026-06-12 |
| 11.1 SIP Automation & NPS NAV (INSERTED) | v1.1 | 5/5 | Complete | 2026-06-12 |
| 12. Notes & Daily Routine Enhancement | v1.1 | 5/5 | Complete | 2026-06-20 |
| 13. Design System Foundation | v1.2 | 2/3 | In Progress|  |
| 14. Restyle Existing Screens + Overview Donut | v1.2 | 5/8 | In Progress|  |
| 15. Analytics Screen | v1.2 | 0/? | Not started | - |
| 16. AI Insight Card | v1.2 | 0/? | Not started | - |
