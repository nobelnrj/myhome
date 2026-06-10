---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: Accounts, Assets & Household Polish
status: executing
last_updated: "2026-06-10T14:59:16.676Z"
last_activity: 2026-06-10
progress:
  total_phases: 5
  completed_phases: 2
  total_plans: 12
  completed_plans: 9
  percent: 40
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-08)

**Core value:** Everything our household needs in one place, with the expense tracker so automated that I never have to think about logging a transaction.
**Current focus:** Phase 10 — self-transfer-detection

## Current Position

Phase: 10 (self-transfer-detection) — EXECUTING
Plan: 2 of 4
Status: Ready to execute
Last activity: 2026-06-10

Progress: [████████░░] 75%

## Performance Metrics

**Velocity:**

- Total plans completed: 17
- Average duration: — min
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 4 | - | - |
| 04 | 5 | - | - |
| 08 | 4 | - | - |
| 09 | 4 | - | - |

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

## Quick Tasks Completed

| Slug | Date | Status | Summary |
|------|------|--------|---------|
| 260603-lvt-support-syncing-from-multiple-gmail-acco | 2026-06-05 | complete ✓ | Multi-Gmail account support: SchemaV5 (Expense.sourceAccount), GmailAccountStore (per-account state + legacy forward-migration), multi-account signIn/sync/signOut, per-account Settings UI. 4 tasks, full suite green. |

## Accumulated Context

### Roadmap Evolution

- Phase 3 edited: expanded scope to Notes + Reminders hub: reminders, recurrence, notifications, calendar (goal + 5 success criteria)
- v1.1 roadmap created 2026-06-08: Phases 8-12 (Stabilization → SchemaV6+Accounts → Self-Transfer → Asset Tracker → Notes Enhancement); 32 requirements mapped; no orphans

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

### Pending Todos

None yet.

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

## Session Continuity

Last session: 2026-06-10T14:58:55.790Z
Stopped at: Phase 10 context gathered
Resume file: None

## Operator Next Steps

- Run /gsd-plan-phase 8 to plan Phase 8: Stabilization
