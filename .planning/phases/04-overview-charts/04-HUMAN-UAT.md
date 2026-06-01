---
status: partial
phase: 04-overview-charts
source: [04-VERIFICATION.md]
started: 2026-06-01
updated: 2026-06-01
---

## Current Test

[awaiting human testing of item 2]

## Tests

### 1. Full Overview manual smoke
expected: App launches on Home (tag 0, leftmost); tab order Home → Expenses → Budgets → Notes; five cards render top→bottom (This Month bar, Top Categories, Pinned Note, Spend by Category bars, Spend Over Time line); toolbar `+` presents Add Expense and Overview updates after save; Week/Month/Year picker recomputes the line and stays visible; empty states render with no blank/broken charts; a Notes reminder notification deep-links to the Notes tab (tag 3) and opens the note.
result: passed (human-approved 2026-06-01, all 7 steps — see 04-05-SUMMARY.md)

### 2. CR-01 Year-view regression check (post-fix)
expected: After the CR-01 fix (SpendOverTimeChart now fed by a year-scoped `@Query`), the Spend Over Time chart's **Year** view shows real multi-month data across the calendar year — NOT 11 empty buckets — and a Week view straddling a month boundary still includes prior-month days. This validates the fix made after the original smoke approval.
result: pending

## Summary

total: 2
passed: 1
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps
