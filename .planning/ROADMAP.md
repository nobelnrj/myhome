# Roadmap: My Home

## Overview

My Home is a single-user (v1) iOS app for a two-person Indian household, built as a Swift learning vehicle on the Swift 6.2 / SwiftUI / SwiftData stack, iOS 17+. v1.0 shipped the full MVP (expense tracking, budgets, notes/reminders, overview, Face ID). v1.1 grew it into a light household finance hub (Accounts, self-transfer detection, net-worth Asset Tracker, daily-routine notes). v1.2 delivered a full neumorphic (Soft UI) redesign plus a dedicated Analytics screen, on-device AI Insight, and spend donut. v1.3 added free private P2P sync, a synced Kitchen, and Overview filtering. v1.3.1 is a fast interim UX-polish pass — a custom floating nav bar, an Overview declutter, and tap-to-edit expenses everywhere — local-only, no schema change, no new dependencies.

## Milestones

- ✅ **v1.0 MVP** — Phases 1-7 (shipped 2026-06-03) — see [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)
- ✅ **v1.1 Accounts, Assets & Household Polish** — Phases 8-12 (shipped 2026-06-20) — see [milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md)
- ✅ **v1.2 Neumorphic Redesign** — Phases 13-17 (shipped 2026-07-13) — see [milestones/v1.2-ROADMAP.md](milestones/v1.2-ROADMAP.md)
- ✅ **v1.3 Private Sync & Kitchen** — Phases 18-22 (shipped 2026-07-22) — see [milestones/v1.3-ROADMAP.md](milestones/v1.3-ROADMAP.md)
- ✅ **v1.3.1 UX Polish** — Phases 23-24 (shipped 2026-07-23)

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

<details>
<summary>✅ v1.2 Neumorphic Redesign (Phases 13-17) — SHIPPED 2026-07-13</summary>

- [x] Phase 13: Design System Foundation (3/3 plans) — completed 2026-06-22
- [x] Phase 14: Restyle Existing Screens + Overview Donut (8/8 plans) — completed 2026-06-22
- [x] Phase 15: Analytics Screen (3/3 plans) — completed 2026-06-25
- [x] Phase 16: AI Insight Card (5/5 plans) — completed 2026-06-27
- [x] Phase 17: Light Mode Support (9/9 plans) — completed 2026-07-12

Full phase details archived in [milestones/v1.2-ROADMAP.md](milestones/v1.2-ROADMAP.md).

</details>

<details>
<summary>✅ v1.3 Private Sync & Kitchen (Phases 18-22) — SHIPPED 2026-07-22</summary>

- [x] Phase 18: Sync Foundation — Schema, Merge Engine & AirDrop (5/5 plans) — completed 2026-07-17
- [x] Phase 19: Auto-Sync & Sync UX — Multipeer + Bootstrap (5/5 plans) — completed 2026-07-20
- [x] Phase 20: Kitchen Inventory & Shopping List (5/5 plans) — completed 2026-07-21
- [x] Phase 21: Overview Filtering (3/3 plans) — completed 2026-07-22
- [x] Phase 22: Pantry Icon Intelligence (4/4 plans) — completed 2026-07-22

Full phase details archived in [milestones/v1.3-ROADMAP.md](milestones/v1.3-ROADMAP.md).

</details>

### ✅ v1.3.1 UX Polish (Shipped 2026-07-23)

**Milestone Goal:** A fast interim polish pass — de-crowd the Overview (remove duplicated spend charts), make every expense editable wherever it appears, and give the app a more premium feel with a floating nav bar. Local-only, no schema change, no new dependencies (SchemaV11 unchanged).

- [x] **Phase 23: Overview Declutter & Tap-to-Edit Everywhere** — consolidated Overview spend into one donut; every expense row (incl. budget drill-downs) opens the edit sheet (PR #46; contentShape tap-fix PR #46)
- [x] **Phase 24: Floating Nav Bar** — shipped as the **native iOS 26 floating TabView** (`.tabBarMinimizeBehavior(.never)`); custom-container approach abandoned. Scroll-edge band hidden so the bar floats transparently (PR #47 + polish PR #48)

## Phase Details

### Phase 23: Overview Declutter & Tap-to-Edit Everywhere
**Goal**: The Overview presents spend-by-category exactly once (no duplicated donut / by-category / overlapping budget), and every expense row shown anywhere in the app opens the existing edit sheet on tap.
**Depends on**: Phase 22 (v1.3 complete)
**Requirements**: OVF-04, EDIT-01
**Success Criteria** (what must be TRUE):
  1. The Overview shows a single spend-by-category presentation — the previously duplicated "Where it's going" donut, "By category" section, and overlapping budget content are consolidated into one, less-crowded view.
  2. Tapping a category in the consolidated Overview spend view still filters into the Activity list (tap-to-filter-into-Activity preserved).
  3. The v1.3 account × date-range filter (OVF-01..03) still applies to the consolidated Overview spend view, with one-tap clear intact.
  4. Tapping any expense row in a Budget-screen filtered list opens the existing expense edit sheet.
  5. Tapping any expense row in Analytics / category drill-downs opens the same existing edit sheet, and saved edits are reflected wherever that expense appears.
**Plans**: TBD
**UI hint**: yes

### Phase 24: Floating Nav Bar
**Shipped note (2026-07-23):** After a custom-container attempt regressed on-device (bad positioning, no bottom clearance, full-screen filter sheet), pivoted to the **native iOS 26 floating TabView** (`.tabBarMinimizeBehavior(.never)`); `FloatingNavBar.swift` deleted. Follow-up PR #48 hid the bottom scroll-edge "Liquid Glass" band so the bar floats transparently over content (no background band).

**Original goal**: The five tab destinations are presented in a custom floating, neumorphic nav bar detached from the screen edge instead of the native tab bar — a genuine custom bar over a plain TabView selection — without breaking navigation or leaving main undeployable.
**Depends on**: Phase 23
**Requirements**: NAV-01
**Success Criteria** (what must be TRUE):
  1. All five destinations are reachable from a custom floating bar that sits detached from the screen edge; the native tab bar is no longer visible.
  2. Selecting any of the five destinations from the floating bar switches to it with correct active-selection state.
  3. Existing `-startTab N` debug indices still launch the app on the correct destination.
  4. The floating bar renders correctly in both light and dark themes and does not regress existing navigation or deep-links (e.g. the note deep-link into Notes).
**Plans**: TBD
**UI hint**: yes

## Progress

**Execution Order:** Phases execute in numeric order: 23 → 24

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1-7 | v1.0 | 32/32 | Complete | 2026-06-03 |
| 8-12 | v1.1 | 26/26 | Complete | 2026-06-20 |
| 13-17 | v1.2 | 28/28 | Complete | 2026-07-13 |
| 18-22 | v1.3 | 22/22 | Complete | 2026-07-22 |
| 23. Overview Declutter & Tap-to-Edit Everywhere | v1.3.1 | 1/1 | Complete (PR #46) | 2026-07-23 |
| 24. Floating Nav Bar (native iOS 26) | v1.3.1 | 1/1 | Complete (PR #47, #48) | 2026-07-23 |

## Backlog

Post-v1.3.1 items live in the GitHub tracker (nobelnrj/myhome, Project "My Home"):

- **v1.4 Finance & AI Depth** — security debt first (#31 Face ID review fixes, #43 paired-device sync allowlist), then bill reminders (#27), recurring detection (#28), exports (#29), smarter AI (#30), Expenses scope pill (#44)
- **Untriaged debt** — test-infra crash (#24), doc/Nyquist gaps (#25), v1.0 deferred verification (#26)
