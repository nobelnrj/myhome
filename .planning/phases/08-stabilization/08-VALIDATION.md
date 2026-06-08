---
phase: 8
slug: stabilization
status: approved
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-08
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (native, no XCTest) |
| **Config file** | Standard Xcode test target; no separate config file |
| **Quick run command** | `xcodebuild test -project MyHome.xcodeproj -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/[TestSuiteName] 2>&1 | tail -20` |
| **Full suite command** | `xcodebuild test -project MyHome.xcodeproj -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30` |
| **Estimated runtime** | ~90 seconds (simulator boot + build dominate; per-suite runs are fast) |

---

## Sampling Rate

- **After every task commit:** Run the `-only-testing:` quick command for the affected suite
- **After every plan wave:** Run the full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~90 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 08-01-xx | 01 | 1 | STAB-01 | — | `remindersOnDay` skips tombstoned Note/NoteBlock; no fault crash | unit | `-only-testing:MyHomeTests/CalendarAggregationTests` | ✅ (new case) | ⬜ pending |
| 08-02-xx | 02 | 1 | STAB-02 | — | Sync completes with stale-captured Category; single `ctx.save()` after loop | unit | `-only-testing:MyHomeTests/GmailSyncControllerTests` | ✅ (new case) | ⬜ pending |
| 08-03-xx | 03 | 1 | STAB-03 | — | New custom category lands at `max(sortOrder)+1` | unit | `-only-testing:MyHomeTests/CategoryCRUDTests` | ✅ (new case) | ⬜ pending |
| 08-04-xx | 04 | 1 | STAB-04 | — | `RoutineResetService.resetIfNeeded()` does not crash or mutate models | build/smoke | `xcodebuild build` + manual scene-phase log check | ✅ (build verify; write-free scaffold needs no unit test) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] New `@Test` in `CalendarAggregationTests.swift` — STAB-01: delete Note/NoteBlock from context, verify it does not appear in `remindersOnDay` output and no crash
- [ ] New `@Test` in `GmailSyncControllerTests.swift` — STAB-02: in-memory container, insert Category, configure `SpyGmailFetch` to return a parseable message, call sync, verify expense inserted + single `ctx.save()`
- [ ] New `@Test` in `CategoryCRUDTests.swift` — STAB-03: seed categories (0–13), call `addCategory`, assert new `sortOrder == 14`
- [ ] No new test files needed — all additions go into existing suites (`CalendarAggregationTests`, `GmailSyncControllerTests`, `CategoryCRUDTests`)

*Existing infrastructure (in-memory `ModelContainer`, `SpyGmailFetch`, injected-context pattern) covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| App no longer crashes deleting a note/block with day-agenda sheet open | STAB-01 | Live UI interaction across sheet lifecycle | Open Notes calendar → open a day with reminders → delete the note/block backing a reminder → sheet stays open, row vanishes, no crash |
| Adding a custom category appends to bottom in the live app | STAB-03 | Research flagged possible stale live-store data, not a code path | In live app, add a new custom category → confirm it appears at the bottom of the list. If it appears at top, a secondary add path exists that grep missed |
| `RoutineResetService` logs "would reset" on scene `.active` | STAB-04 | Scaffold has no automated assertion this phase (no-op stub) | Foreground the app → confirm log line emitted, no model writes |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-06-08
