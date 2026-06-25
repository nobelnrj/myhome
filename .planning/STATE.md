---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Neumorphic Redesign
status: executing
last_updated: "2026-06-25T15:36:08.149Z"
last_activity: 2026-06-24
progress:
  total_phases: 5
  completed_phases: 2
  total_plans: 14
  completed_plans: 13
  percent: 40
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-08)

**Core value:** Everything our household needs in one place, with the expense tracker so automated that I never have to think about logging a transaction.
**Current focus:** Phase 15 — analytics-screen

## Current Position

Phase: 15 (analytics-screen) — EXECUTING
Plan: 2 of 3
Status: Ready to execute
Last activity: 2026-06-24

## Performance Metrics

**Velocity:**

- Total plans completed: 30
- Average duration: — min
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 4 | - | - |
| 04 | 5 | - | - |
| 08 | 4 | - | - |
| 09 | 4 | - | - |
| 10 | 4 | - | - |
| 11 | 4 | - | - |
| 11.1 | 5 | - | - |

**Recent Trend:**

- Last 5 plans: —
- Trend: —

*Updated after each plan completion*
| Phase 01 P02 | 20 | 2 tasks | 9 files |
| Phase 01-foundation-manual-expense-spine P03 | 18 | 2 tasks | 7 files |
| Phase 02 P01 | 25 | 2 tasks | 11 files |
| Phase 02 P05 | 30 | 2 tasks | 5 files |
| Phase 03-notes-checklists P01 | 45 | 3 tasks | 14 files |
| Phase 03-notes-checklists P04 | 20 | 2 tasks | 7 files |
| Phase 03-notes-checklists P05 | 90 | 3 tasks + 1 fix | 8 files |
| Phase 03-notes-checklists P06 | multi-session | 3 tasks | 8 files |
| Phase 04-overview-charts P01 | 31 | 3 tasks | 4 files |
| Phase 04-overview-charts P02 | 45 | 3 tasks | 5 files |
| Phase 04-overview-charts P04 | 25 | 2 tasks | 2 files |
| Phase 05-face-id-gate-settings P01 | 45 | 2 tasks | 5 files |
| Phase 05-face-id-gate-settings P02 | 35 | 3 tasks | 5 files |
| Phase 06 P01 | 45 | 2 tasks | 13 files |
| Phase 06 P02 | 15 | 2 tasks | 5 files |
| Phase 06-gmail-sign-in-client P03 | 20 | 2 tasks | 1 files |
| Phase 06-gmail-sign-in-client P04 | 25 | 2 tasks | 7 files |
| Phase 07 P05 | 95 | 2 tasks | 12 files |
| Phase 08-stabilization P01 | 15 | 3 tasks | 3 files |
| Phase 09 P01 | 21 | 3 tasks | 9 files |
| Phase 09 P02 | — | 4 tasks | 12 files |
| Phase 09 P03 | — | 3 tasks + 1 verify | 6 files |
| Phase 10-self-transfer-detection P02 | 25 | 2 tasks | 4 files |
| Phase 10 P04 | 25 | 2 tasks | 3 files |
| Phase 11.1-sip-automation-and-nps-nav-auto-refresh P02 | 45 | 3 tasks | 3 files |
| Phase 11.1 P04 | 35 | 3 tasks | 5 files |
| Phase 11.1 P05 | 35 | 3 tasks | 6 files |
| Phase 12-notes-daily-routine-enhancement P01 | 35m | 2 tasks | 14 files |
| Phase 12-notes-daily-routine-enhancement P02 | 25 | 2 tasks | 5 files |
| Phase 12 P03 | 35 | 2 tasks | 3 files |
| Phase 13 P01 | 35 | 2 tasks | 7 files |
| Phase 13 P03 | 35 | 2 tasks + 1 fix | 3 files |
| Phase 14 P04 | 30 | 2 tasks | 8 files |
| Phase 14 P05 | 8 | 2 tasks | 3 files |
| Phase 14 P06 | 8 | 2 tasks | 14 files |

## Quick Tasks Completed

| Slug | Date | Status | Summary |
|------|------|--------|---------|
| 260603-lvt-support-syncing-from-multiple-gmail-acco | 2026-06-05 | complete ✓ | Multi-Gmail account support: SchemaV5 (Expense.sourceAccount), GmailAccountStore (per-account state + legacy forward-migration), multi-account signIn/sync/signOut, per-account Settings UI. 4 tasks, full suite green. |

## Accumulated Context

### Roadmap Evolution

- Phase 3 edited: expanded scope to Notes + Reminders hub: reminders, recurrence, notifications, calendar (goal + 5 success criteria)
- v1.1 roadmap created 2026-06-08: Phases 8-12 (Stabilization → SchemaV6+Accounts → Self-Transfer → Asset Tracker → Notes Enhancement); 32 requirements mapped; no orphans
- Phase 11.1 inserted after Phase 11: SIP Automation and NPS NAV auto-refresh (URGENT)

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: Manual expense entry ships before Gmail ingestion (load-bearing sequencing — validates schema/UI/budget loop before staking the project on the riskiest sub-system)
- [Roadmap]: Foundation lock-ins (bundle/CloudKit/App-Group IDs, privacy manifest, CloudKit-ready schema) folded into Phase 1 because they are one-way doors
- [Roadmap]: Gmail ingestion split — OAuth/client proven in isolation (Phase 6) before parsers + pipeline + background tasks (Phase 7)
- [Roadmap v1.1]: Stabilization gates all schema work — crash vectors must be fixed before any schema migration begins
- [Roadmap v1.1]: SchemaV6 (Account + Asset models + transfer + routine fields) bundled into Phase 9 with Accounts Management — one migration stage, not two
- [Roadmap v1.1]: STAB-04 (daily routine reset) assigned to Phase 9 because its observable behavior requires the NoteBlock.lastCheckedDate schema field; Phase 8 ships the RoutineResetService skeleton only
- [Roadmap v1.1]: NOTE-02 (lastCheckedDate field) placed in Phase 9 (schema phase) to avoid an intermediate migration stage; observable per-day reset behavior is a Phase 9 success criterion
- [Roadmap v1.1]: ACCT-05 assigned to Phase 9 (baseline ± transactions); transfer balance-move semantics completed in Phase 10 (self-transfer confirm wires the balance-move)
- [Roadmap v1.1]: Phase 11 (Asset Tracker) and Phase 12 (Notes Enhancement) are independent after Phase 9; serial order chosen (11 before 12) so spend accuracy is confirmed before net-worth figures are presented
- [Phase 9 research flag]: V5→V6 didMigrate closure is first non-nil didMigrate in this codebase — verify error-handling (throwing closure: rollback vs. partial state) against FB13812722 workaround in MigrationPlan.swift before writing the migration stage
- [Phase ?]: Expense @Model nested in SchemaV1 enum; typealias Expense = SchemaV1.Expense for clean view imports
- [Phase ?]: FormatStyle .currency(code:INR).locale(en_IN) for lakh grouping — not NumberFormatter, not hand-rolled
- [Phase ?]: App Group store URL with Application Support fallback for free-account provisioning
- [Phase ?]: EditExpenseView uses local @State mirror of expense fields for isDirty detection; Cancel dismisses without mutating model
- [Phase ?]: RootView reduced to single-line pass-through to ExpenseListView; ExpenseListView owns its own NavigationStack
- [Phase ?]: Seed store generated via macOS SwiftData script (xcrun -sdk macosx swift) — deterministic, reproducible, no simulator required
- [Phase ?]: Required companion to container flip
- [Phase ?]: AppMigrationPlan chains to V3 now
- [Phase ?]: 03-06: categoryIdentifier must be stamped in NotificationScheduler.makeRequest — iOS drops actions if absent
- [Phase ?]: 03-06: Deep-link via kOpenNoteNotification + RootView @State tab-selection Binding — no environment key needed
- [Phase ?]: 03-06: Calendar day-agenda binds live to Note/NoteBlock @Model via AgendaReminderItem — never snapshot for completion-state UI
- [Phase ?]: BiometricAuthPort protocol-port seam (mirrors NotificationCenterPort) makes every LAError path unit-testable without a device
- [Phase ?]: LockController @MainActor for Swift 6 strict concurrency when scenePhase onChange mutates @Observable state
- [Phase ?]: canEvaluate called before evaluate in authenticate() — passcodeNotSet only detectable from canEvaluatePolicy path (D5-05)
- [Phase ?]: shouldRefresh in sync() uses (accessToken==nil || (expiry!=nil && needsProactiveRefresh))
- [Phase ?]: STAB-01 tombstone guard: modelContext != nil applied to all Note/NoteBlock iteration sites in CalendarView and CalendarAggregator
- [Phase ?]: applyTransferMark extracted as static func on EditExpenseView for testability without SwiftUI
- [Phase ?]: nil chosen over false on unmark so scorer can re-evaluate (D-14)
- [Phase ?]: Avoids init-time predicate complexity with asset.id capture
- [Phase ?]: Enables direct unit testing without a view instance
- [Phase ?]: OQ-1 RESOLVED: UUID direct equality in #Predicate compiles and works — no .uuidString fallback needed
- [Phase ?]: All 11 model typealiases flipped atomically to SchemaV9 (STAB-08)
- [Phase ?]: v8ToV9 uses nil-closure .custom stage — purely additive (RoutineCompletion new empty table)
- [Phase 13→14, 2026-06-21]: DS-03 floating capsule tab bar REVERTED to native iOS tab bar per user (commit 92e3e61). NeuTabBar.swift now orphaned/unused (delete during Phase 14). Phase 14 restyles the NATIVE bar's colors only — do NOT rebuild a custom tab bar. Reference design's yellow-active-pill bar is explicitly out of scope.
- [Phase 14 SKIN DECISION, 2026-06-21]: Design handoff ships 6 interchangeable skins (Liquid Glass / Glassmorphism / Neomorphism / Minimalism / Bento / Spatial). User's reference screenshots = the DEFAULT 'liquid' (Liquid Glass) skin; Phase 13 DesignTokens.swift translated the 'neuro' (Neomorphism) branch — hence the mismatch. After a side-by-side comparison (design/skin-comparison.html), user CHOSE **Neomorphism** (keep what Phase 13 built) over matching the glass reference. So: NO rework of DesignTokens/NeuSurface; Phase 14 applies the existing neuro tokens + canary-yellow accent + colored category palette + "Where it's going" donut + net-cash-flow card across all 67 feature view files. Do NOT pursue Liquid Glass / translucent material.
- [Phase 14 verified state, 2026-06-21]: Phase 13 components (DesignTokens/NeuSurface/RollingMoneyText/NeuTabBar) exist + pushed to main + compile, but are applied to 0 real screens (only CardStyle.swift deprecation shim references them). All 67 feature views still use system colors (secondarySystemBackground, .accentColor blue). Phase 14 is the wiring/restyle pass. CardStyle is marked "removed in Phase 14".

### Pending Todos

- [Phase 13]: Blocking human-verify checkpoint (13-03 Task 3) outstanding — interactive 5-tab tap + NavigationStack regression check, kOpenNoteNotification deep-link to Notes (index 3), Reduce Motion pill-jump, Accessibility Inspector zero-contrast pass on NeuSurface/NeuTabBar/RollingMoneyText previews, NeuSurface(.recessed) look check. Resume via `/gsd-verify-work 13`. (Capsule render/float/accent already confirmed in simulator.)

### Blockers/Concerns

Carried from v1.1 research/SUMMARY.md, to resolve at the relevant phase:

- [Phase 9]: SchemaV6 didMigrate closure error handling — first non-nil didMigrate in this codebase; verify behavior of a throwing closure (rollback vs. partial store) against FB13812722 workaround in MigrationPlan.swift before writing the stage
- [Phase 10]: Self-transfer 3-day window — well-reasoned for Indian settlement (NEFT/IMPS/UPI) but not yet validated against household's actual transaction history; spot-check historical expenses during Phase 10 planning
- [Phase 11]: Yahoo Finance rate-limit and ToS risk — 2-person household is well within community-reported ~360 req/hr cap; implementation must fall back to manual immediately on any non-200 or decode error; do not retry or chase alternative endpoints
- [Phase 11]: npsnav.in availability — single-maintainer hobby project; app must degrade gracefully to last-known NAV on any failure; manual override is the primary NPS entry path

Carried from v1.0 (pre-existing, still outstanding):

- [Phase 6]: Gmail OAuth library choice (raw ASWebAuthenticationSession vs GoogleSignIn SDK) — RESOLVED (shipped Phase 6); retained for reference
- [Phase 7]: Collect 50+ real anonymized bank emails per target bank BEFORE building parsers; confirm final 2 banks (likely HDFC + ICICI); confidence threshold (0.85) needs real-data calibration after first week
- [Phase 7]: BGAppRefreshTask must be verified on-device unplugged-overnight; simulator triggering is not representative

## Deferred Items

Items acknowledged and carried forward (v2 — gated on $99/yr Apple Developer upgrade or real v1 usage):

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Sync | CloudKit private DB + shared zone with wife's Apple ID, TestFlight | Deferred to v2 | Roadmap |
| Apple surfaces | Widgets, App Intents/Siri, watchOS app | Deferred to v2 | Roadmap |
| Expense v1.x | Per-merchant category memory, more bank parsers, today's tile, vs-prior-month | Deferred to v2 | Roadmap |
| Notes/Notifications | Share-sheet receive, Spotlight, budget/inbox notifications, haptics | Deferred to v2 | Roadmap |
| Asset Tracker v1.x | Stock quote auto-fetch (Yahoo Finance) — deferred until manual flow proven | Deferred to v1.2+ | REQUIREMENTS.md |
| Asset Tracker v1.x | NPS NAV auto-fetch (npsnav.in) — single-maintainer source risk; manual entry suffices for v1.1 | Deferred to v1.2+ | REQUIREMENTS.md |
| Asset Tracker v1.x | CAS / broker import, XIRR | Deferred to v2 | REQUIREMENTS.md |
| Notes v1.x | RoutineCompletion-driven analytics beyond simple streaks (heatmaps, insights) | Deferred to v1.2+ | REQUIREMENTS.md |

### Acknowledged at v1.0 Milestone Close (2026-06-03)

Open human-verification artifacts deferred at milestone close — code is implemented; these are manual on-device verification/UAT passes that remain outstanding:

| Category | Item | Status |
|----------|------|--------|
| uat_gap | 04-HUMAN-UAT.md | partial (1 pending scenario) |
| uat_gap | 06-UAT.md | core-complete-1-deferred-issue |
| verification_gap | 02-VERIFICATION.md | human_needed |
| verification_gap | 04-VERIFICATION.md | human_needed |

### Acknowledged at v1.1 Milestone Close (2026-06-20)

Open artifacts deferred at v1.1 close — code is implemented; the verification items are outstanding manual on-device passes carried into v1.2 as tracked debt:

| Category | Item | Status |
|----------|------|--------|
| uat_gap | 09-HUMAN-UAT.md | partial (1 pending scenario) |
| verification_gap | 08-VERIFICATION.md | human_needed |
| verification_gap | 09-VERIFICATION.md | human_needed |
| quick_task | 260603-lvt-support-syncing-from-multiple-gmail-acco | missing/stale |
| todo | test-isolation-swiftdata-multicontainer.md | pending (test-infra debt) |

## Session Continuity

Last session: 2026-06-24T17:32:49.357Z
Stopped at: Phase 12 UI-SPEC approved
Resume file: None

## Operator Next Steps

- Phase 14 RESUME POINT (2026-06-21): 14-CONTEXT.md committed (skin=Neomorphism, native tab bar, donut). 14-UI-SPEC.md drafted by ui-researcher. UI-checker returned BLOCKED but ONLY on a Dimension-4 typography technicality (named scale has 5 sizes / 5 weights vs the checker's max 4/2) — these are the LOCKED Phase-13 DesignTokens type roles, not sprawl. FIX = doc reframe only (split the type table into ≤4 primary roles + the rest as "contextual overrides" e.g. heroMoney 46/ultraLight, statNumber 21/light; no DesignTokens change). UI-SPEC typography section is at 14-UI-SPEC.md lines ~61-79. After reframe, re-run ui-checker, then /gsd-plan-phase 14.
- Note: NeuTabBar.swift is orphaned (delete in Phase 14, needs pbxproj edits). CardStyle.swift deprecated, 14 call-sites migrate to .neuSurface in Phase 14.
