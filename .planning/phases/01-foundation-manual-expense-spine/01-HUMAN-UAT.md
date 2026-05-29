---
status: partial
phase: 01-foundation-manual-expense-spine
source: [01-VERIFICATION.md]
started: 2026-05-29T11:07:13Z
updated: 2026-05-29T11:07:13Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. On-device persistence across app termination
expected: Add an expense, fully kill the app (swipe up from app switcher), cold-launch it — the expense row still appears in the list. Confirms the CR-01 explicit-save fix persists writes durably (not just via in-session autosave).
result: [pending]

### 2. en-IN lakh grouping visual rendering
expected: Enter 100000 → the amount displays as ₹1,00,000.00 (Indian lakh grouping), not ₹100,000.00 (Western grouping), both in the editor and in the list cell.
result: [pending]

### 3. ≤3-tap add flow with custom always-visible keypad
expected: From the list, tap "+" (1) → type the amount on the custom in-app decimal keypad (2) → tap "Save Expense" (3). The system keyboard never appears; the keypad is always visible. New row appears at top.
result: [pending]

### 4. Edit flow end-to-end
expected: Tap an existing row → change the amount and/or note → Save Expense → the row reflects the updated value in the list.
result: [pending]

### 5. Both delete paths remove the expense permanently
expected: (a) Swipe left on a row → Delete → row gone. (b) Open a row → "Delete Expense" → confirm the action sheet → row gone. After either, the deletion survives a cold launch.
result: [pending]

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps
