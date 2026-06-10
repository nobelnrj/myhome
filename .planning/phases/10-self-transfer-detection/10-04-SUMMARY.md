---
phase: 10-self-transfer-detection
plan: "04"
subsystem: expenses/transfer-mark
tags: [transfer, edit-view, cascade-unlink, xfer-05]
dependency_graph:
  requires: [10-01, 10-02]
  provides: [manual-mark-unmark-toggle, cascade-unlink-on-unmark]
  affects: [EditExpenseView, spend-exclusion-via-plan-02-filter]
tech_stack:
  added: []
  patterns: [local-state-mirror-isdirty, static-helper-for-testability, cascade-unlink]
key_files:
  created:
    - MyHomeTests/EditExpenseTransferTests.swift
  modified:
    - MyHomeApp/Features/Expenses/EditExpenseView.swift
decisions:
  - "applyTransferMark extracted as static func on EditExpenseView for unit-test access without SwiftUI"
  - "nil used (not false) on unmark so scorer can re-evaluate (D-14)"
  - "cascade-unlink fetches all expenses and finds partner by transferPairID (T-10-12)"
  - "Toggle styled identically to Account row: .toggleStyle(.switch) + .padding + .frame(minHeight: 44) + RoundedRectangle background"
metrics:
  duration: 25
  completed: "2026-06-10"
  tasks: 2
  files: 3
---

# Phase 10 Plan 04: isTransfer Toggle + Cascade-Unlink Summary

Manual mark/unmark self-transfer toggle in EditExpenseView with cascade-unlink on unmark and 4 passing unit tests.

## What Was Built

Added a "Mark as Transfer" toggle to the expense edit view (XFER-05, D-14). The toggle uses the existing `@State` local-mirror + `isDirty` pattern:

- `@State private var isMarkedTransfer: Bool` seeded in `initializeFields()` from `expense.isTransfer == true`
- `isDirty` checks `isMarkedTransfer != (expense.isTransfer == true)`
- `saveExpense()` calls `EditExpenseView.applyTransferMark(_:expense:context:)` before the explicit `context.save()`

The static `applyTransferMark` helper contains the mutation logic:
- **Mark (`true`):** sets `isTransfer = true`, preserves `transferPairID` as-is (solo flag allowed — D-14)
- **Unmark (`false`) when `isTransfer == true`:** fetches all expenses, finds partner by `transferPairID`, resets both legs to `isTransfer = nil` + `transferPairID = nil` (T-10-12 cascade); if no pair, resets self only
- **`nil` chosen over `false`** so the scorer can re-evaluate the expense (D-14)

The solo transfer is excluded from spend via Plan 02's existing `isTransfer != true` filter (D-15).

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | isTransfer toggle + cascade-unlink (TDD RED) | 1c931f5 | MyHomeTests/EditExpenseTransferTests.swift, MyHome.xcodeproj/project.pbxproj |
| 1 | isTransfer toggle + cascade-unlink (TDD GREEN) | 289a538 | MyHomeApp/Features/Expenses/EditExpenseView.swift |
| 2 | Human verify mark/unmark on simulator | — | (checkpoint — awaiting user) |

## Test Results

All 4 tests in `EditExpenseTransferTests` pass:
- `manualMarkSetsSoloTransfer` — mark sets isTransfer=true, transferPairID stays nil
- `manualUnmarkResetsTransfer` — unmark solo resets isTransfer to nil, transferPairID stays nil
- `unmarkCascadeUnlinksCounterpart` — unmark linked pair resets both legs
- `markDoesNotClearTransferPairID` — mark on already-paired expense preserves transferPairID

Full suite: TEST EXECUTE SUCCEEDED.

## Acceptance Criteria Verification

- `grep -c 'isMarkedTransfer' EditExpenseView.swift` → **5** (≥4 required: @State, initializeFields, isDirty, saveExpense delegate, toggle binding)
- `grep -c 'transferPairID = nil' EditExpenseView.swift` → **3** (≥2 required: partner reset, self reset)

## Deviations from Plan

### Auto-added

**1. [Rule 2 - Missing test] markDoesNotClearTransferPairID test added**
- **Found during:** Task 1 implementation
- **Issue:** Plan specified 3 behavior tests; a 4th case (mark preserving existing transferPairID for already-paired expenses) was implicit in D-14 "leave transferPairID as-is" but not listed
- **Fix:** Added `markDoesNotClearTransferPairID` test to document and verify the behavior explicitly
- **Files modified:** MyHomeTests/EditExpenseTransferTests.swift

## TDD Gate Compliance

- RED gate commit: `1c931f5` (test(10-04)) — build fails with "has no member 'applyTransferMark'"
- GREEN gate commit: `289a538` (feat(10-04)) — all 4 tests pass, full suite green

## Known Stubs

None — the toggle is fully wired to the model's `isTransfer` field via `applyTransferMark`.

## Threat Flags

None — all surfaces (cascade-unlink, solo mark, unmark reset) were in the plan's threat model (T-10-12, T-10-13, T-10-14).

## Self-Check: PASSED

- MyHomeApp/Features/Expenses/EditExpenseView.swift: exists and modified
- MyHomeTests/EditExpenseTransferTests.swift: exists and created
- Commits 1c931f5 and 289a538: verified in git log
