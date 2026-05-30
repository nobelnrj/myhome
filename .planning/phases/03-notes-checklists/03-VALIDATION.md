---
phase: 3
slug: notes-checklists
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-30
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from the `## Validation Architecture` section of `03-RESEARCH.md`.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (Xcode 26.5 toolchain), `import Testing` |
| **Config file** | none — `MyHomeTests` target already exists (Phase 1/2) |
| **Quick run command** | `xcodebuild test -project MyHome.xcodeproj -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/NoteModelTests -only-testing:MyHomeTests/NotificationSchedulerTests` |
| **Full suite command** | `xcodebuild test -project MyHome.xcodeproj -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |
| **Estimated runtime** | ~90 seconds (full simulator build + test) |

> Simulator: **iPhone 17** (per MEMORY — not iPhone 16), Xcode 26.5, scheme/module `MyHome`. In-memory `ModelContainer(isStoredInMemoryOnly: true)` per L1 test; bundled `.store` fixture for L2 migration tests.

---

## Sampling Rate

- **After every task commit:** Run the quick `-only-testing:` command for the touched suite (L1).
- **After every plan wave:** Run the full suite command (L1 + L2) — must be green.
- **Before `/gsd-verify-work`:** Full suite green AND the Manual UAT Checklist completed/recorded.
- **Max feedback latency:** ~90 seconds (full suite).

---

## Per-Task Verification Map

| Req / SC | Plan | Wave | Observable signal (proof) | Test Type | Automated Command / Manual step | File Exists | Status |
|----------|------|------|---------------------------|-----------|----------------------------------|-------------|--------|
| NOT-01 | TBD | — | Note with title + blocks persists & refetches with title intact | unit (L1) | `-only-testing:MyHomeTests/NoteModelTests/noteWithTitlePersists` | ❌ W0 | ⬜ pending |
| NOT-02 | TBD | — | Interleaved text + checkbox blocks persist preserving `order` | unit (L1) | `NoteModelTests/blockListPreservesOrder` | ❌ W0 | ⬜ pending |
| NOT-03 | TBD | — | Ordering = Daily Routine → Pinned → Other(recent-first) | unit+manual (L1+L3) | `NoteListOrderingTests/sectionOrdering`; UAT confirm section order | ❌ W0 | ⬜ pending |
| NOT-04 | TBD | — | Toggling `isPinned` moves note to Pinned section | unit+manual (L1+L3) | `NoteListOrderingTests/pinMovesToPinnedSection`; UAT tap pin | ❌ W0 | ⬜ pending |
| NOT-05 | TBD | — | Debounced auto-save ~500ms; no save button; reopen shows edits | unit+manual (L1+L3) | `AutoSaveTests/debounceCommitsAfterQuiet`; UAT edit→kill→reopen | ❌ W0 | ⬜ pending |
| NOT-06 | TBD | — | Search predicate matches title + block text; non-matches excluded | unit+manual (L1+L3) | `NoteSearchTests/matchesTitleAndBlockText`; UAT type query | ❌ W0 | ⬜ pending |
| SC-R1 (reminders) | TBD | — | Reminder fields persist on Note AND NoteBlock; all-day vs timed honored; lead-time adds requests | unit (L1) | `NotificationSchedulerTests/buildRequestsLeadAlerts`, `ReminderModelTests/reminderOnNoteAndBlock` | ❌ W0 | ⬜ pending |
| SC-R2 (recurrence) | TBD | — | Daily/Weekly(weekdays)/Monthly/Yearly triggers correct; "after N" stops; end-on-date stops | unit (L1) | `NotificationSchedulerTests/weeklyMultiWeekday`, `RecurrenceTests/afterNStops`, `RecurrenceTests/endOnDateStops` | ❌ W0 | ⬜ pending |
| SC-R3 (notifications) | TBD | — | Scheduler emits correct requests/identifiers (L1); permission prompt on first reminder, banner fires, Complete/Snooze, deep-link (L3) | unit+manual (L1+L3) | `NotificationSchedulerTests/*`; **UAT mandatory** (see checklist) | ❌ W0 | ⬜ pending |
| SC-R4 (calendar) | TBD | — | Per-day count aggregation + tapped-day agenda + completion math correct | unit+manual (L1+L3) | `CalendarAggregationTests/perDayCountsAndProgress`; UAT calendar grid+tap | ❌ W0 | ⬜ pending |
| SC-R5 (Daily Routine + auto-pin) | TBD | — | Daily-recurring notes in Daily Routine; yearly reminder shows pre-checked pin toggle | unit+manual (L1+L3) | `NoteListOrderingTests/dailyRoutineFilter`; UAT toggle | ❌ W0 | ⬜ pending |
| Migration | TBD | — | V2→V3 store opens under `AppMigrationPlan`; Expense rows survive | migration (L2) | `MigrationTests/v2StoreMigratesToV3` | ❌ W0 | ⬜ pending |
| 64-cap (D3-15) | TBD | — | `pendingCount()` ≤ 64 under multi-weekday-weekly + after-N load | unit (L1) | `NotificationSchedulerTests/pendingCountUnderCap` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky · ❌ W0 = test file created in Wave 0*
*Plan/Wave columns are filled in by the planner once PLAN.md files exist.*

---

## Wave 0 Requirements

- [ ] `MyHomeTests/NoteModelTests.swift` — NOT-01, NOT-02 (persistence + order)
- [ ] `MyHomeTests/NoteListOrderingTests.swift` — NOT-03, NOT-04, SC-R5 (sectioning/sort/Daily Routine)
- [ ] `MyHomeTests/NoteSearchTests.swift` — NOT-06 (search predicate)
- [ ] `MyHomeTests/AutoSaveTests.swift` — NOT-05 (debounce unit)
- [ ] `MyHomeTests/NotificationSchedulerTests.swift` — SC-R1, SC-R3(a,d), 64-cap; requires `NotificationCenterPort` + `SpyCenter` seam
- [ ] `MyHomeTests/RecurrenceTests.swift` — SC-R2 ("after N", end-on-date, weekly weekdays)
- [ ] `MyHomeTests/CalendarAggregationTests.swift` — SC-R4(a,b) (per-day counts + completion math)
- [ ] `MyHomeTests/MigrationTests.swift` — extend with `v2StoreMigratesToV3`; add bundled `MyHomeV2Seed.store` to `MyHomeTests` Copy-Bundle-Resources (mirror `MyHomeV1Seed.store`)
- [ ] Shared test helper: `SpyCenter` conforming to `NotificationCenterPort` + reminder fixture builders

*Framework install: none — Swift Testing + `MyHomeTests` already exist.*

---

## Manual-Only Verifications

> Run on iPhone 17 simulator; record pass/fail in VERIFICATION.md. CI cannot assert these headlessly.

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| First-reminder permission prompt | SC-R3(b) | OS-owned system prompt | Set first reminder → confirm prompt appears in-context (not on launch); deny → confirm Settings hint |
| Notification delivery (banner fires) | SC-R3(c) | Real notification center delivery | Set a 1–2 min timed reminder → confirm banner fires at time |
| Complete action | SC-R3(d) | Notification action UI | Tap Complete → target row checks (D3-04) + future advance alerts cancelled |
| Snooze action | SC-R3(e) | Notification action UI | Tap Snooze → re-fires ~1h later |
| Deep-link | SC-R3(f) | Routing on tap of delivered notification | Tap banner → opens correct note/row |
| Calendar grid + tap | SC-R4(c) | Visual + interaction | Open Calendar segment → confirm per-day counts/dots → tap day → confirm agenda + x/y progress |
| Auto-save + no save button | NOT-05 | Visual + lifecycle | Edit → wait ~1s → force-quit → reopen → edits persisted; confirm no save button anywhere |
| Accessibility | (all UI) | VoiceOver/Dynamic Type | VoiceOver labels on checkbox/pin/reminder controls; Dynamic Type scales text |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [ ] Manual UAT Checklist recorded before `/gsd-verify-work`
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
