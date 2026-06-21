---
status: testing
phase: 13-design-system-foundation
source:
  - 13-01-SUMMARY.md
  - 13-02-SUMMARY.md
  - 13-03-SUMMARY.md
started: 2026-06-21T14:22:29Z
updated: 2026-06-21T14:22:29Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

number: 1
name: Tab switching + NavigationStack integrity
expected: |
  Tapping each of the 5 capsule tabs (Home, Activity, Budgets, Notes, Settings)
  switches content and slides the canary-yellow pill. Each tab's NavigationStack
  title and back button remain intact — no broken/missing nav chrome (Pitfall 3).
awaiting: user response

## Tests

### 0. Capsule render / float / accent (pre-confirmed)
expected: Floating capsule renders over content, clears the home indicator, active Home pill shows canary #FFD60A accent.
result: pass
reason: Confirmed in simulator via screenshot during 13-03 execution.

### 1. Tab switching + NavigationStack integrity
expected: Tapping each of the 5 tabs switches content and slides the pill; each NavigationStack title/back button intact (Pitfall 3 regression check).
result: [pending]

### 2. Deep-link to Notes tab (index 3)
expected: Triggering a note reminder (or posting kOpenNoteNotification) activates the Notes tab (index 3) and opens the note — deep-link index stability preserved (DS-03).
result: [pending]

### 3. Reduce Motion behavior
expected: With Reduce Motion ON, the active pill jumps with no slide animation and RollingMoneyText snaps to its target instantly with zero intermediate frames (DS-06).
result: [pending]

### 4. Accessibility Inspector contrast pass
expected: Running Xcode Accessibility Inspector on NeuSurface, NeuTabBar, and RollingMoneyText previews produces zero non-text contrast warnings (WCAG 1.4.11 / DS-06).
result: [pending]

### 5. NeuSurface(.recessed) inset look
expected: The NeuSurface(.recessed) overlay-gradient inset shadow looks acceptable at the spec token values — reads as a pressed/recessed well, not flat or muddy.
result: [pending]

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0

## Gaps

[none yet]
