---
phase: 08-stabilization
verified: 2026-06-09T00:00:00Z
status: human_needed
score: 4/4 must-haves verified
overrides_applied: 1
overrides:
  - must_have: "Adding a new custom category places it at the bottom of the category list (ROADMAP SC #3 wording: max+1)"
    reason: "User explicitly reversed decision D-05 at the STAB-03 human-verify checkpoint during execution — new categories now insert at the TOP via min(sortOrder)-1. The ROADMAP SC #3 text is stale; code, test, and REQUIREMENTS.md all reflect the authorised top-insertion contract. The 08-03-SUMMARY.md 'Locked-decision reversal' section documents the AskUserQuestion interaction and user direction."
    accepted_by: "user (interactive checkpoint during 08-03 execution)"
    accepted_at: "2026-06-09T10:15:00Z"
human_verification:
  - test: "STAB-01 — open Notes calendar, open a day with at least one reminder, then delete that note or block from another tab"
    expected: "App does not crash; the row disappears live from the day-agenda sheet; if it was the day's only reminder the 'No Reminders' empty state shows and the sheet stays open"
    why_human: "The tombstone-crash path requires a live @Query result array holding a stale reference — this cannot be reproduced by re-fetching in a unit test; production behaviour on the simulator is the only reliable gate"
  - test: "STAB-04 — foreground the app (bring it to .active) and inspect the Xcode console"
    expected: "'[RoutineResetService] resetIfNeeded: startOfToday IST = ... No-op (Phase 8 scaffold).' is printed; no crash; no model writes"
    why_human: "scenePhase .active is a runtime lifecycle event; no unit test exercises the RootView onChange handler; the print line and absence of model writes cannot be confirmed from static analysis alone"
---

# Phase 8: Stabilization Verification Report

**Phase Goal:** The live app is crash-free and category ordering works correctly; the daily-routine reset service is seeded and ready for the SchemaV6 field it will consume in Phase 9.
**Verified:** 2026-06-09
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | DayAgendaView and CalendarAggregator guard all @Model property accesses against tombstoned objects (STAB-01) | VERIFIED | `CalendarView.swift` has 5 `modelContext != nil` guards (note+block in remindersOnDay, note+block in toggleCompletion, plus block in noteIsChecked via allSatisfy); `CalendarAggregator.swift` has 4 guards; both files confirm the `guard note.modelContext != nil else { continue }` idiom before any property access |
| 2 | Gmail sync uses PersistentIdentifier map + single batched save in both sync paths (STAB-02) | VERIFIED | `GmailSyncController.swift` lines 481/628 declare `[String: PersistentIdentifier]`; `ctx.model(for: catID)` re-resolves after each await at lines 533/679; `try ctx.save()` appears exactly once per path at lines 544/690, both outside the message loop; stale `[String: Category]` capture is gone |
| 3 | New custom categories insert at the TOP (min(sortOrder)-1) per user-authorised reversal of D-05 (STAB-03) | VERIFIED (override) | `ManageCategoriesView.swift:193` computes `(all.map(\.sortOrder).min() ?? 0) - 1`; `CategoryCRUDTests.newCategoryPrependsAtTop` asserts `sorted.first?.sortOrder == -1`; `SchemaV5.swift:55-60` defensive comment warns callers to use `min(existing.sortOrder)-1`; authorised deviation from ROADMAP SC #3 wording ("bottom/max+1") documented in 08-03-SUMMARY.md |
| 4 | RoutineResetService scaffold exists, is wired to RootView scenePhase .active synchronously, and contains the IST date seam with no model writes (STAB-04 scaffold) | VERIFIED | `RoutineResetService.swift` is a 27-line `@MainActor @Observable final class` with `resetIfNeeded()` computing IST `startOfDay`; no `context.save`, `.insert(`, or `.delete(` calls present; `RootView.swift:41` declares `@State private var routineResetService = RoutineResetService()` and line 111 calls `routineResetService.resetIfNeeded()` synchronously inside `if newPhase == .active { }` — no Task wrap |

**Score:** 4/4 truths verified (1 via authorised override)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `MyHomeApp/Features/Notes/CalendarView.swift` | Tombstone-guarded remindersOnDay | VERIFIED | 5 `modelContext != nil` guards present; remindersOnDay note+block loops guarded; toggleCompletion guarded |
| `MyHomeApp/Support/CalendarAggregator.swift` | Tombstone-guarded aggregation | VERIFIED | 4 `modelContext != nil` guards; events(from:) note+block guarded; noteIsChecked allSatisfy guarded |
| `MyHomeTests/CalendarAggregationTests.swift` | STAB-01 regression tests | VERIFIED | `tombstonedNoteIsFilteredFromAggregation` and `tombstonedBlockIsFilteredFromAggregation` present, both tagged "STAB-01" |
| `MyHomeApp/Features/Gmail/GmailSyncController.swift` | PersistentIdentifier map + batched save in both sync paths | VERIFIED | `categoryIDsByName: [String: PersistentIdentifier]` in syncAccount (line 481) and legacySingleAccountSync (line 628); `ctx.model(for:)` re-resolution after await in both; single post-loop save in both |
| `MyHomeTests/GmailSyncControllerTests.swift` | STAB-02 regression test | VERIFIED | `syncResolvesCategoryByPersistentIDAcrossAwait` (line 396) and `syncCompletesWhenCategoryHintMissing` (line 432) present, both tagged "STAB-02" |
| `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` | min(sortOrder)-1 insertion (STAB-03 reversal) | VERIFIED | Line 193: `(all.map(\.sortOrder).min() ?? 0) - 1` |
| `MyHomeTests/CategoryCRUDTests.swift` | STAB-03 regression test (top-insertion) | VERIFIED | `newCategoryPrependsAtTop` asserts `sorted.first?.sortOrder == -1` |
| `MyHomeApp/Persistence/Schema/SchemaV5.swift` | Defensive comment on Category.init sortOrder | VERIFIED | Lines 55-60: 5-line comment warns callers to pass `min(existing.sortOrder)-1`; `sortOrder: Int = 0` default unchanged |
| `MyHomeApp/Features/Notes/RoutineResetService.swift` | @MainActor @Observable scaffold with IST seam | VERIFIED | File exists (27 lines); `@MainActor`, `@Observable`, `final class RoutineResetService`, `func resetIfNeeded()`; `Asia/Kolkata` timezone; `startOfDay(for: Date())`; no model writes |
| `MyHomeApp/RootView.swift` | @State ownership + onChange wiring | VERIFIED | `@State private var routineResetService = RoutineResetService()` at line 41; `routineResetService.resetIfNeeded()` at line 111 inside `if newPhase == .active { }` |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `CalendarView.remindersOnDay` note loop | `AgendaReminderItem` construction | `guard note.modelContext != nil else { continue }` | WIRED | Guard present as first statement in note iteration; block guard also present |
| `CalendarAggregator.events(from:)` | note/block property access | `guard note.modelContext != nil else { continue }` | WIRED | Guards present at lines 72 and 85 in CalendarAggregator.swift |
| `GmailSyncController.syncAccount` message loop | `ctx.model(for: catID) as? Category` | post-await PersistentIdentifier re-resolution | WIRED | Lines 528-534: `model(for: catID)` called after `await fetch.getRawMessage` |
| `GmailSyncController.legacySingleAccountSync` message loop | `ctx.model(for: catID) as? Category` | post-await PersistentIdentifier re-resolution | WIRED | Lines 674-680: same pattern mirrored |
| `GmailSyncController` both sync paths | `ctx.save()` | single batched save after loop | WIRED | `try ctx.save()` at lines 544 and 690, both inside post-loop `if let ctx = modelContext { }` blocks |
| `RootView.onChange(of: scenePhase)` | `routineResetService.resetIfNeeded()` | synchronous call on `.active` (no Task wrap) | WIRED | Line 110-111: `if newPhase == .active { routineResetService.resetIfNeeded() }` — direct synchronous call confirmed |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| CalendarAggregator has >= 2 tombstone guards (non-comment lines) | `grep -v '^[[:space:]]*//' CalendarAggregator.swift \| grep -c "modelContext != nil"` | 4 | PASS |
| CalendarView has >= 2 tombstone guards | `grep -v '^[[:space:]]*//' CalendarView.swift \| grep -c "modelContext != nil"` | 5 | PASS |
| GmailSyncController has PersistentIdentifier | `grep -c "PersistentIdentifier" GmailSyncController.swift` | 6 | PASS |
| GmailSyncController has no in-loop save (save count == 2, both post-loop) | `grep -c "ctx\.save\|context\.save\|modelContext\.save" GmailSyncController.swift` | 2 | PASS |
| ManageCategoriesView uses min-1 | `grep "map(\\\.sortOrder).min()" ManageCategoriesView.swift` | found line 193 | PASS |
| RoutineResetService has no model writes | `grep -c "context\.save\|ctx\.save\|\.insert(\|\.delete(" RoutineResetService.swift` | 0 | PASS |
| RootView wires synchronous call with .active gate | `grep -n "newPhase == .active" RootView.swift` | lines 110, 115 | PASS |
| STAB-01 regression test count | `grep -c "STAB-01" CalendarAggregationTests.swift` | 8 (>= 2) | PASS |
| STAB-02 regression test count | `grep -c "STAB-02" GmailSyncControllerTests.swift` | 6 (>= 1) | PASS |
| STAB-03 regression test (top) | `grep -c "newCategoryPrependsAtTop" CategoryCRUDTests.swift` | 1 | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| STAB-01 | 08-01-PLAN.md | Tombstone-guard Notes calendar / day-agenda against deleted @Model refs | SATISFIED | Both crash surfaces guarded; regression tests present and passing |
| STAB-02 | 08-02-PLAN.md | PersistentIdentifier re-resolution + single batched save in both Gmail sync paths | SATISFIED | Both sync paths refactored; STAB-02 regression tests present |
| STAB-03 | 08-03-PLAN.md | New category insertion order (top, per user direction) locked in | SATISFIED (authorised deviation) | min-1 logic in production; test asserts sortOrder == -1 at first position |
| STAB-04 | 08-04-PLAN.md | RoutineResetService scaffold wired; full per-day reset deferred to Phase 9 (NOTE-02) | SATISFIED (scaffold scope) | Service exists, wired, no model writes; ROADMAP and REQUIREMENTS.md both assign full STAB-04 observable behavior to Phase 9 |

**REQUIREMENTS.md traceability note:** The traceability table in REQUIREMENTS.md shows STAB-02 and STAB-03 as "Pending" and STAB-04 as "Phase 9 / Pending". The STAB-02 and STAB-03 statuses are stale — code and tests confirm both are implemented. The STAB-04 Phase 9 assignment is correct and intentional per the ROADMAP note (observable reset behavior requires SchemaV6 / Phase 9). These stale table entries are a documentation gap, not a code gap.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `RoutineResetService.swift` | 25 | `print(...)` scaffold log | INFO | Intentional Phase 8 scaffold; must be replaced or gated with a debug flag before Phase 9 ships — flagged as advisory only per 08-REVIEW.md IN-02 |
| `GmailSyncController.swift` | 211-215 | Double-negation guard `!defaults.bool(...) == false` | WARNING | Confusing but functionally correct (WR-01 in 08-REVIEW.md); not introduced by Phase 8 — pre-existing code; no action required for Phase 8 sign-off |
| `GmailSyncController.swift` | 549/693 | Auth error classified by `localizedDescription` string match | WARNING | Locale-fragile (WR-03 in 08-REVIEW.md); pre-existing pattern not introduced by this phase |

**Debt markers:** No unreferenced TBD/FIXME/XXX markers found in phase-modified files.

**CR-01 note (08-REVIEW.md):** The code review raised a BLOCKER finding about sortOrder collision under add/delete churn (two categories could share the same integer, producing undefined tie-break order). The review's designation as "BLOCKER" is advisory from a code-quality standpoint. As a verification gate, this is a robustness concern for future churn paths — not a failure of the phase goal ("category ordering works correctly" means the primary insertion path is correct and test-locked). The STAB-03 regression test covers the pristine seed path only. CR-01 should be tracked as follow-up work (a tie-break sort descriptor or renumber-on-insert) in a later phase; it does not block Phase 8 sign-off.

---

### Human Verification Required

#### 1. STAB-01 Tombstone-crash smoke test

**Test:** Build and run the app on iPhone 17 simulator (Xcode 26.5). Open Notes tab → tap the calendar icon → tap any day that has a reminder → from a second tab (e.g. Notes list) delete the note or block whose reminder is showing. Switch back to the day-agenda sheet.
**Expected:** App does not crash; the reminder row disappears live from the sheet; if it was the day's last reminder the "No Reminders" / `ContentUnavailableView` empty state shows and the sheet stays open.
**Why human:** The crash path requires a live `@Query` result array holding a stale `@Model` reference across a tombstone event. The unit test harness re-fetches after deletion and never holds a stale reference, so it cannot reproduce the production crash condition. Only a running app with the live SwiftData stack can confirm the guard works.

#### 2. STAB-04 RoutineResetService call path

**Test:** With the app running, background it then foreground it (or cold-launch) and inspect the Xcode debug console.
**Expected:** The console shows `[RoutineResetService] resetIfNeeded: startOfToday IST = <date>. No-op (Phase 8 scaffold).` — exactly once per foreground event. No crash. No model write activity in the console.
**Why human:** `scenePhase .active` is a UIApplication lifecycle event; no unit test exercises the `RootView.onChange(of:)` handler end-to-end. The `print` statement and absence of side effects can only be observed in a running simulator session.

---

### Gaps Summary

No gaps found. All four must-haves are verified by codebase evidence. The STAB-03 plan/code divergence (bottom → top insertion) is an authorised deviation with a complete audit trail (08-03-SUMMARY.md "Locked-decision reversal", commit c2b0e94). Two human verification items remain for runtime confidence on the primary crash-fix and the scaffold call path. Phase 8 is ready to proceed to Phase 9 upon human verification.

---

_Verified: 2026-06-09_
_Verifier: Claude (gsd-verifier)_
