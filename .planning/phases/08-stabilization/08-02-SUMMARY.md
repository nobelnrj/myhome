---
phase: 08-stabilization
plan: "02"
subsystem: gmail-sync
tags: [crash-fix, persistent-identifier, swiftdata, concurrency, tdd, stab-02]
dependency_graph:
  requires: []
  provides: [STAB-02-persistent-id-resolution]
  affects: [GmailSyncController]
tech_stack:
  added: []
  patterns: [persistent-identifier-reresolution-across-await, batched-save-after-loop]
key_files:
  created:
    - MyHomeTests/GmailSyncControllerTests.swift (STAB-02 tests added to existing file)
  modified:
    - MyHomeApp/Features/Gmail/GmailSyncController.swift
    - MyHomeTests/GmailSyncControllerTests.swift
decisions:
  - "syncAccount was already in target state (PersistentIdentifier map + batched save); only legacySingleAccountSync required the refactor"
  - "ctx.model(for:) used for re-resolution (verified live-model return / nil for deleted); FetchDescriptor fallback not needed"
metrics:
  duration_minutes: 12
  completed_date: "2026-06-08"
  tasks: 3
  files: 2
---

# Phase 8 Plan 2: STAB-02 PersistentIdentifier Re-resolution in Gmail Sync — Summary

## One-liner

Both Gmail sync paths now capture category `PersistentIdentifier`s (Sendable) before the message loop, re-resolve each Category via `ctx.model(for:)` after the `getRawMessage` await suspension, and save once after the batch — eliminating the large-inbox use-after-suspension crash/stall (success criterion #2).

## What Was Built

The bug: `categoriesByName: [String: Category]` was captured once before the loop, and those `@Model` references could be invalidated across the `await fetch.getRawMessage(...)` suspension point; additionally `ctx.save()` ran inside the per-message loop (N saves for N messages).

The fix (D-04), applied to both sync paths:
1. Replace the pre-loop `[String: Category]` capture with `[String: PersistentIdentifier]` (`cat.persistentModelID`).
2. After the `await`, re-resolve via `ctx.model(for: catID) as? Category`; on any optional-binding failure, skip category assignment and continue (D-03 resilience).
3. Remove the in-loop `try ctx.save()`; insert in-loop, save once after the loop.

**`syncAccount` was already refactored to this exact pattern** (lines ~479–545) from prior work — verified, no change needed. The remaining buggy path was **`legacySingleAccountSync`** (the path the STAB-02 tests exercise, since they inject `accessToken` directly), which this plan refactored to mirror `syncAccount`.

Two STAB-02 regression tests (added in the Task 1 RED commit):
- `syncResolvesCategoryByPersistentIDAcrossAwait`: a "Dining" category + one parseable ICICI/Zomato fixture → expects exactly one Expense with a non-empty `categories` (category resolved across the await).
- `syncCompletesWhenCategoryHintMissing`: no categories present → expense still ingested (D-03).

## TDD Gate Compliance

RED was confirmed at the Task 1 commit (`test(08-02)`): with `legacySingleAccountSync` still using the stale `[String: Category]` capture, the category-resolution assertion failed. After the Task 3 refactor, both tests are GREEN and the full `GmailSyncControllerTests` suite plus the entire app suite pass.

## Commits

| Task | Type | Hash | Description |
|------|------|------|-------------|
| Task 1 | test | 4769c69 | add failing STAB-02 sync regression test (RED) |
| Task 2 | — | (prior) | syncAccount already in target state; no commit needed |
| Task 3 | fix | 49d9380 | re-resolve Category by PersistentIdentifier + single batched save in both sync paths |

## Deviations from Plan

**1. [Task 2 no-op] `syncAccount` already refactored**
- The plan scoped Task 2 to refactoring `syncAccount`, but it was already in the target state (PersistentIdentifier map + `ctx.model(for:)` + single post-loop save) from earlier work. Verified against the acceptance criteria and left unchanged. The substantive code change landed entirely in `legacySingleAccountSync` (Task 3).

**2. [OPEN QUESTION resolved] `ctx.model(for:)` used directly**
- The A2 open question asked to verify `ModelContext.model(for:)` returns the live model. The existing `syncAccount` already relies on it and the green tests confirm correct behavior (live model returned; resilient skip when absent). The `FetchDescriptor` predicate fallback was not needed.

## Success Criteria Verification

| Criterion | Status |
|-----------|--------|
| Both sync paths use `[String: PersistentIdentifier]` map + re-resolve after await | PASS — `categoryIDsByName` + `ctx.model(for:)` in both `syncAccount` and `legacySingleAccountSync` |
| Exactly one `ctx.save()` per sync path, after the loop | PASS — 2 total `try ctx.save()`, both post-loop |
| STAB-02 regression test fails pre-fix, passes post-fix | PASS — RED at 4769c69, GREEN at 49d9380 |
| Per-message resilience preserved (D-03) | PASS — `syncCompletesWhenCategoryHintMissing` green |
| Full suite green | PASS — `** TEST SUCCEEDED **` |

## Threat Surface Scan

No new network endpoints, auth paths, or schema changes. T-08-03 (large-inbox DoS via stale @Model capture) mitigated by the PersistentIdentifier re-resolution + batched save. T-08-04 (malformed message) resilience preserved — no parser changes. T-08-05 (log info disclosure) unchanged — no email body added to logs.

## Self-Check

- [x] MyHomeApp/Features/Gmail/GmailSyncController.swift — `legacySingleAccountSync` refactored (PersistentIdentifier map, post-await re-resolution, single batched save)
- [x] MyHomeTests/GmailSyncControllerTests.swift — 2 STAB-02 tests present and green
- [x] Commits 4769c69 (RED), 49d9380 (fix) exist in git log
- [x] `grep -c PersistentIdentifier` ≥ 1 (6); `[String: Category]` only in comments; 2 post-loop saves
