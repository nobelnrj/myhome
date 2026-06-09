---
status: partial
phase: 08-stabilization
source: [08-VERIFICATION.md]
started: 2026-06-09T10:30:00Z
updated: 2026-06-09T10:30:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. STAB-01 — delete note/block while day-agenda is open (no crash)
expected: With the Notes calendar / day-agenda sheet open, deleting a note or a note block (from any view) does NOT crash. The row disappears live, and the empty state shows if it was the last item. (Reproduces the tombstoned `@Model` reference path that unit tests cannot.)
result: [pending]

### 2. STAB-04 — RoutineResetService call path fires on foreground
expected: Foregrounding the app prints `[RoutineResetService] resetIfNeeded: startOfToday IST = … No-op` to the console once per `.active` transition, with no crash and no model writes.
result: [pending]

### 3. STAB-03 — new category appears at TOP (smoke confirmation)
expected: In Manage Categories, adding a brand-new custom category makes it appear at the TOP of the list (per the reversed contract). Already unit-tested (`newCategoryPrependsAtTop`); this is a visual confirmation in the running app.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
