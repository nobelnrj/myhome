---
status: partial
phase: 09-schemav6-accounts-management
source: [09-VERIFICATION.md]
started: 2026-06-10T00:00:00Z
updated: 2026-06-10T00:00:00Z
---

## Current Test

[awaiting human testing — item 5 (live Gmail auto-attribution)]

## Tests

### 1. Live balance reactivity (ACCT-05/D-10)
expected: Open an account detail showing baseline balance, add an expense attributed to that account, and confirm the balance card updates with NO refresh affordance present.
result: pass — human-verified at 09-02 execution (09-02-SUMMARY `human_verified: true`; balance semantics confirmed against the live V5→V6 migrated store)

### 2. Archive moves account to collapsed Archived section, transactions intact (ACCT-07/D-08)
expected: Swipe-archive an account; it leaves the active list and appears in the collapsed Archived DisclosureGroup; expanding shows it with its transactions still present.
result: pass — human-verified at 09-02 execution (Accounts CRUD list with archive verified end-to-end)

### 3. Migration review badge + sheet flow (D-02)
expected: On a store with auto-created accounts the orange badge shows on the Settings Accounts row; tapping into the review sheet, renaming/retyping an account and tapping Done clears the badge.
result: pass — human-verified at 09-02 execution via real migration replay (badge + review sheet flow; an empty-sheet bug was found and fixed during that checkpoint)

### 4. Per-day routine reset across midnight (STAB-04/NOTE-02/D-11/D-12)
expected: Flag a note isDailyRoutine with checked items, advance the simulator date by one day, foreground the app, and confirm items uncheck; re-checking and same-day foreground preserves checks; a non-routine note's checks survive the day advance.
result: pass — user approved at 09-04 human-verify checkpoint (2026-06-10, this session)

### 5. Gmail sourceLabel auto-attribution (D-05)
expected: Trigger a Gmail sync; an ingested expense whose bank label matches an account is auto-attributed (visible via the account filter / detail); a non-matching one stays Unassigned.
result: pending — depends on a configured Gmail account + live network ingestion; pure resolver logic is unit-tested green (GmailAccountAttributionTests), but the end-to-end live sync path has not been observed on-device.

## Summary

total: 5
passed: 4
issues: 0
pending: 1
skipped: 0
blocked: 0

## Gaps
