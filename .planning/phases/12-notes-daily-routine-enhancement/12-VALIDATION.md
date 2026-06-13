---
phase: 12
slug: notes-daily-routine-enhancement
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-13
---

# Phase 12 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (MyHomeTests target) |
| **Config file** | MyHome.xcodeproj (scheme: MyHome) |
| **Quick run command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/RoutineStreakTests` |
| **Full suite command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |
| **Estimated runtime** | ~120 seconds (full), ~20s (quick) |

---

## Sampling Rate

- **After every task commit:** Run quick test for the touched unit (streak algo / completion record / reorder).
- **After every plan wave:** Run full suite.
- **Before `/gsd-verify-work`:** Full suite must be green.
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| (planner fills) | | | | | | | | | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Test files for streak computation (NOTE-05) and completion-record idempotency
- [ ] `MyHomeTests` already exists — covers most needs

*Planner finalizes against the SchemaV9 + RoutineCompletion design.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Daily notification fires once at the set time | NOTE-03 | Local notification delivery is a runtime/OS event | Set a routine reminder ~2 min out; background app; confirm exactly one banner |
| Drag-to-reorder gesture persists | NOTE-04 | Drag gesture + @Query re-render is a live UI interaction | Reorder checklist items, dismiss, reopen — order holds |
| Routine appears on every calendar day | NOTE-01 | @Query-driven calendar rendering | Mark a note routine; scroll multiple days; confirm it shows each day with no dot-badge inflation |
| Midnight reset preserves yesterday's completion record | NOTE-05 | scenePhase .active reset is a lifecycle event | Complete a routine, advance day, confirm streak/history retained while boxes reset |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
