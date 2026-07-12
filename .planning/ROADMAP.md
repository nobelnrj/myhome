# Roadmap: My Home

## Overview

My Home is a single-user (v1) iOS app for a two-person Indian household, built as a Swift learning vehicle on the Swift 6.2 / SwiftUI / SwiftData stack, iOS 17+. v1.0 shipped the full MVP (expense tracking, budgets, notes/reminders, overview, Face ID). v1.1 grew it into a light household finance hub (Accounts, self-transfer detection, net-worth Asset Tracker, daily-routine notes). v1.2 is a full neumorphic (Soft UI) visual redesign of the entire app plus the design's net-new surfaces (dedicated Analytics screen, on-device AI Insight, spend donut).

## Milestones

- â **v1.0 MVP** â Phases 1-7 (shipped 2026-06-03) â see [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)
- â **v1.1 Accounts, Assets & Household Polish** â Phases 8-12 (shipped 2026-06-20) â see [milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md)
- ð **v1.2 Neumorphic Redesign** â Phases 13-17

## Phases

<details>
<summary>â v1.0 MVP (Phases 1-7) â SHIPPED 2026-06-03</summary>

- [x] Phase 1: Foundation & Manual Expense Spine (4/4 plans) â completed 2026-05-29
- [x] Phase 2: Categories, Tags & Budgets (5/5 plans) â completed 2026-05-30
- [x] Phase 3: Notes & Checklists (6/6 plans) â completed 2026-05-30
- [x] Phase 4: Overview & Charts (5/5 plans) â completed 2026-06-01
- [x] Phase 5: Face ID Gate & Settings (2/2 plans) â completed 2026-06-01
- [x] Phase 6: Gmail Sign-In & Client (4/4 plans) â completed 2026-06-02
- [x] Phase 7: Bank Parsers & Ingestion Pipeline (6/6 plans) â completed 2026-06-03

Full phase details archived in [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md).

</details>

<details>
<summary>â v1.1 Accounts, Assets & Household Polish (Phases 8-12) â SHIPPED 2026-06-20</summary>

- [x] Phase 8: Stabilization (4/4 plans) â completed 2026-06-09
- [x] Phase 9: SchemaV6 & Accounts Management (4/4 plans) â completed 2026-06-10
- [x] Phase 10: Self-Transfer Detection (4/4 plans) â completed 2026-06-10
- [x] Phase 11: Asset Tracker (4/4 plans) â completed 2026-06-12
- [x] Phase 11.1: SIP Automation & NPS NAV auto-refresh (INSERTED) (5/5 plans) â completed 2026-06-12
- [x] Phase 12: Notes & Daily Routine Enhancement (5/5 plans) â completed 2026-06-20

Full phase details archived in [milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md).

</details>

### v1.2: Neumorphic Redesign

- [x] **Phase 13: Design System Foundation** â Tokens, NeuSurface, NeuTabBar, RollingMoneyText, accessibility infrastructure
- [x] **Phase 14: Restyle Existing Screens + Overview Donut** â Full neumorphic restyle of every existing screen; spend donut with tap-to-filter added to Overview (completed 2026-06-22)
- [x] **Phase 15: Analytics Screen** â New screen pushed from Overview; AnalyticsAggregator, area chart, category bars, delta chips (completed 2026-06-25)
- [x] **Phase 16: AI Insight Card** â On-device FoundationModels card on Analytics screen; availability gating, streaming typewriter, numeric integrity (completed 2026-06-27)
- [x] **Phase 17: Light Mode Support** — Light-tuned palette, reworked neumorphic shadow directions/opacities, and non-glow treatment for the particle orb + activity rings (promoted from backlog 2026-06-27) (completed 2026-07-12)

---

## Phase Details

### Phase 13: Design System Foundation

**Goal**: The neumorphic design system is fully built and accessible â all token constants, surface modifiers, the capsule tab bar, rolling-money readout, and motion infrastructure exist as stable, tested components that every subsequent phase can consume without revisiting.
**Depends on**: Nothing (first v1.2 phase)
**Requirements**: DS-01, DS-02, DS-03, DS-04, DS-05, DS-06
**Success Criteria** (what must be TRUE):

  1. Every color, shadow, radius, and spacing value used in v1.2 is defined in one file (`DesignTokens.swift`); no view file in the project contains a hardcoded hex string or pixel-literal shadow value.
  2. Any view can adopt the raised, pressed, or inset neumorphic surface look by applying a single `.neuSurface(.raised/pressed/inset)` modifier â no duplicated shadow code.
  3. The floating capsule tab bar replaces the native SwiftUI tab bar in `RootView`, the five existing tabs remain reachable at their current deep-link indices, and scrolled content in every tab is never occluded by the floating bar.
  4. The `RollingMoneyText` component animates hero rupee figures from old to new value in ~780ms; with Reduce Motion enabled the value snaps to the target immediately with zero intermediate frames.
  5. Running Xcode Accessibility Inspector on `NeuSurface`, `NeuTabBar`, and their previews produces zero contrast warnings; the WCAG 1.4.11 (3:1) non-text contrast requirement is satisfied by construction (canary yellow `#FFD60A` used for all active/selected states; shadow depth is never the sole affordance).
  6. `xcodebuild clean build` succeeds after all new `DesignSystem/` files are registered in `project.pbxproj` (all 4 manual pbxproj edits per file completed).**Plans**: 3 plans

**Wave 1**

- [x] 13-01-PLAN.md â Scaffold DesignSystem/ + pbxproj G_DS group; DesignTokens.swift + token tests (DS-01, DS-05)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 13-02-PLAN.md â NeuSurface (raised/floating/recessed) + RollingMoneyText; deprecate CardStyle (DS-02, DS-04, DS-06)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 13-03-PLAN.md â NeuTabBar floating capsule + RootView/MyHomeApp integration + accessibility gate (DS-03, DS-05, DS-06) *(code-complete; human-verify checkpoint outstanding as v1.2 debt)*

**UI hint**: yes

### Phase 14: Restyle Existing Screens + Overview Donut

**Goal**: Every screen in the app looks neumorphic â no stock SwiftUI system colors remain anywhere â and the Overview gains the "Where it's going" spend donut with tap-to-filter into Activity.
**Depends on**: Phase 13 (stable design tokens and `NeuSurface` modifier required before touching any screen)
**Requirements**: SKIN-01, SKIN-02, SKIN-03, SKIN-04, SKIN-05, SKIN-06, SKIN-07, SKIN-08, SKIN-09, OVR-05, OVR-06
**Success Criteria** (what must be TRUE):

  1. All nine screen groups (Overview, Activity/Expenses, Budgets, Notes/calendar/agenda, Settings, Accounts, Assets/Net-worth, Transfer Inbox, Gmail Review Inbox) render with charcoal neumorphic surfaces, canary-yellow accents, and the luminous category palette â no `Color(.secondarySystemBackground)` or other stock system color is visible anywhere.
  2. The "Where it's going" spend donut appears on the Overview screen, shows the current month's top-4 spend categories plus an "Others" roll-up, and displays the rolling total in the center using `RollingMoneyText` â confirmed-self-transfer expenses are excluded from all segment totals.
  3. Tapping any donut segment navigates to the Activity screen pre-filtered to that category.
  4. All existing flows continue working without regression: expense/account/asset/note CRUD, Gmail sync, self-transfer confirm, Face ID gate, and navigation deep-links all behave identically to v1.1.
  5. The `DonutChart` in `DonutChart.swift` has all segments fully visible inside its card container (no clipping at card edges); segment colors match the neumorphic category palette used everywhere else.
  6. Every new `.swift` file added during the restyle is registered in `project.pbxproj`; `xcodebuild clean build` succeeds with zero "cannot find type" errors.

**Plans**: 8 plans

**Wave 1** *(foundation â unblocks all restyle waves)*

- [x] 14-01-PLAN.md â CategoryStyle â DesignTokens.cat* rewrite; native tab-bar canary tint; TDD SpendDonutAggregation helper (SKIN-01, SKIN-09, OVR-05)

**Wave 2** *(blocked on 14-01; all five run in parallel â disjoint files)*

- [x] 14-02-PLAN.md â Overview restyle + NET CASH FLOW hero + SpendDonutCard (new file + pbxproj) + OVR-06 tap-to-filter wiring (SKIN-01, OVR-05, OVR-06, SKIN-09)
- [x] 14-03-PLAN.md â Budgets group restyle (summary-ring hero, category cards, StackBar) (SKIN-03, SKIN-09)
- [x] 14-04-PLAN.md â Notes / calendar / agenda / reminder / routine restyle (SKIN-04, SKIN-09)
- [x] 14-05-PLAN.md â Settings + UnlockView + MigrationReviewSheet restyle (icon-tile color map) (SKIN-05, SKIN-08, SKIN-09)
- [x] 14-06-PLAN.md â Accounts + Assets / Net-worth restyle (floating detail heros, donut segment recolor) (SKIN-06, SKIN-07, SKIN-09)

**Wave 3** *(blocked on 14-02 â shares ExpenseListView.swift)*

- [x] 14-07-PLAN.md â Activity / Expenses + Gmail Review + Transfer Inbox rows restyle (SKIN-02, SKIN-08, SKIN-09)

**Wave 4** *(blocked on all restyle plans â deletion must come last)*

- [x] 14-08-PLAN.md â Delete CardStyle.swift + NeuTabBar.swift (pbxproj removals); full clean-build + test gate; end-of-phase human-verify (SKIN-09)

**UI hint**: yes

### Phase 15: Analytics Screen

**Goal**: A dedicated Analytics screen â accessible via push from Overview â gives users a clear view of their spending trend, category breakdown, and period-over-period delta for any of three time ranges (week, month, year), with all data backed by a single testable aggregator whose output also feeds the AI card.
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

**Plans**: 3 plans

- [x] 15-01-PLAN.md â AnalyticsAggregator + SpendSummary + IST-boundary tests (ANL-03, ANL-07)
- [x] 15-02-PLAN.md â Analytics screen shell, push nav, AreaMark trend + category bars (ANL-01, ANL-02, ANL-03, ANL-04)
- [x] 15-03-PLAN.md â Inverted-color delta chips + drill-down sheet + full clean-build gate + human-verify (ANL-05, ANL-06, ANL-07)

**UI hint**: yes

### Phase 16: AI Insight Card

**Goal**: On devices with Apple Intelligence enabled, the Analytics screen surfaces a natural-language spending insight generated entirely on-device; on every other device the card is silently absent with zero error noise, and no rupee figure ever appears in the insight that was not pre-computed in Swift.
**Depends on**: Phase 15 (AnalyticsView and SpendSummary from AnalyticsAggregator must exist before InsightService can be wired)
**Requirements**: AI-01, AI-02, AI-03, AI-04, AI-05
**Success Criteria** (what must be TRUE):

  1. On an iOS 26 device with Apple Intelligence enabled (A17 Pro+), the AI Insight card appears at the bottom of the Analytics screen and produces a coherent natural-language observation about the current range's spending patterns â all on-device with no network call.
  2. On any device where AI is unavailable (pre-iOS 26, `deviceNotEligible`, `appleIntelligenceNotEnabled`, or `modelNotReady`), the Analytics screen renders fully with charts and category bars; the AI card section is omitted entirely with no error message, blank gap, or stuck spinner visible to the user.
  3. Insight text reveals character-by-character via a streaming typewriter animation; with Reduce Motion enabled the full text appears instantly; the breathing orb loading state is shown while the model generates and is absent when Reduce Motion is on.
  4. Every rupee amount, percentage, and delta figure appearing in the generated insight text matches a value that was pre-computed by `AnalyticsAggregator` and injected as literal context â `InsightVerifier` catches any model-invented number and substitutes the templated fallback before display.
  5. All four availability branches (`available`, `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`) and both generation error cases (`guardrailViolation`, `exceededContextWindowSize`) are exercised by unit tests using a mock session; `grep IPHONEOS_DEPLOYMENT_TARGET MyHome.xcodeproj/project.pbxproj` returns `17.0`; and `xcodebuild clean build` succeeds.

**Plans**: 5 plans

**Wave 1** (foundation — unblocks all)

- [x] 16-01-PLAN.md — Contracts + scaffolds: SpendInsight @Generable, InsightGenerating seam, isInsightAvailable + verifier/prompt stubs, violet DesignTokens, pbxproj registration of all 5 files, RED test scaffolds (AI-02, AI-03, AI-04, AI-05)

**Wave 2** *(blocked on 16-01; parallel — disjoint files)*

- [x] 16-02-PLAN.md — InsightVerifier numeric integrity + templated fallback; TDD (AI-04)
- [x] 16-03-PLAN.md — isInsightAvailable (4 branches) + token-budgeted InsightPromptBuilder + InsightService.generate + error routing; TDD (AI-02, AI-03)

**Wave 3** *(blocked on 16-02 + 16-03)*

- [x] 16-04-PLAN.md — AIInsightCard view (availability switch, violet glow/orb, streaming typewriter, ReduceMotion, verifier) + AnalyticsView integration + full-suite gate (AI-01, AI-02, AI-05)

**Wave 4** *(blocked on 16-04)*

- [x] 16-05-PLAN.md — On-device human-verify: live insight, typewriter, silent absence (AI-01, AI-05)

**UI hint**: yes

### Phase 17: Light Mode Support

**Goal**: Add a light-mode theme to the v1.2 neumorphic redesign. Today the app is dark-only by decision (DS-05): `MyHomeApp.swift` forces `.preferredColorScheme(.dark)` at the root, and every `DesignTokens` color is a single static dark hex with no adaptive `Color(light:dark:)` variants.
**Depends on**: Phase 13 (DesignTokens + NeuSurface), Phase 16 (AI Insight orb/glow treatment) — the entire v1.2 dark design system must exist before it can be made adaptive.
**Requirements**: none formally mapped — scope locked by 17-CONTEXT.md decisions D-01…D-15 (supersedes DS-05 dark-only by user decision, promoted from backlog 2026-06-27)
**Plans**: 9 plans
Plans:
**Wave 1**

- [x] 17-01-PLAN.md — Wave 1: dark baselines + Color.adaptive factory + D-06 bit-identity test harness

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 17-02-PLAN.md — Wave 2: all DesignTokens → adaptive pairs + accentText/aiVioletText/dishSlate + scheme-aware neonGlow + WCAG floors

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 17-03-PLAN.md — Wave 3: AppStorage theme (System/Light/Dark) + Settings Appearance row + chrome + accent role-split audit

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 17-08-PLAN.md — Wave 4: accent role-split audit — RollingMoneyText + Settings + Expenses areas (foregroundStyle(accent) → accentText, dark identity)

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 17-09-PLAN.md — Wave 5: accent role-split audit — Notes/Budgets + Overview/Assets/Analytics areas + app-wide accent gate

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 17-04-PLAN.md — Wave 6: NeuSurface surface/button/puck light shadow twins + on-device depth tuning + paired previews

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 17-05-PLAN.md — Wave 7: instrument windows (orb/donut/ring dishes, pill-gauge wells) + EmbossedBar light glow language

**Wave 8** *(blocked on Wave 7 completion)*

- [x] 17-06-PLAN.md — Wave 8: trend charts in slate windows + IconTile/range-picker/account audit + AI card violet (D-15)

**Wave 9** *(blocked on Wave 8 completion)*

- [x] 17-07-PLAN.md — Wave 9: final D-06 double dark sweep + light integration smoke + end-of-phase human sign-off

**Cross-cutting constraints:**

- Dark rendering remains pixel-identical to Plan 01 baselines
- Every accent call site in these areas has a recorded role classification — no site is silently skipped

Why it's a phase, not a toggle:

- Needs a full light-tuned palette (canvas, surfaces, fills, label tiers).
- Neumorphic shadows must be reworked — soft inner/outer shadow directions and opacities are calibrated for a dark canvas.
- The WHOOP-style particle orb + activity rings need a non-glow / adjusted treatment; the bloom only reads against darkness.

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
| 13. Design System Foundation | v1.2 | 3/3 | Complete | 2026-06-22 |
| 14. Restyle Existing Screens + Overview Donut | v1.2 | 8/8 | Complete   | 2026-06-22 |
| 15. Analytics Screen | v1.2 | 3/3 | Complete    | 2026-06-25 |
| 16. AI Insight Card | v1.2 | 5/5 | Complete    | 2026-06-27 |
| 17. Light Mode Support | v1.2 | 9/9 | Complete    | 2026-07-12 |
