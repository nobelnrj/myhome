---
phase: 10-self-transfer-detection
plan: "03"
subsystem: transfer-detection-ui
tags: [swift, swiftui, swiftdata, transfer, inbox, filter, settings, gmail-hook]

requires:
  - phase: 10-self-transfer-detection/10-01
    provides: TransferScanService.scan(), TransferDetectionScorer, pending-pair encoding (transferPairID != nil && isTransfer == nil)

provides:
  - TransferPairRow — two-leg inbox row with confirm/reject swipe actions (XFER-02, D-13)
  - Possible Transfers section in ExpenseListView Review Inbox (D-11)
  - TransferFilter enum — .normal hides confirmed transfers; .transfers reveals only them (D-12)
  - Tab badge counts pending transfer pairs alongside review items (XFER-03)
  - GmailSyncController post-sync scan hook: transferScanService?.scan() after final save (D-08)
  - RootView injection: TransferScanService @State wired to GmailSyncController and SettingsView
  - SettingsView "Scan for Transfers" row with first-run badge hint

affects:
  - 10-self-transfer-detection/10-04 (human-verify: confirm/reject UX + Transfers filter end-to-end)
  - any consumer of ExpenseListView filteredExpenses (now excludes isTransfer == true in .normal mode)

tech-stack:
  added: []
  patterns:
    - "TransferPairRow mirrors ReviewInboxRow: swipeActions trailing allowsFullSwipe:false, destructive + tint(.green), mutate-both-legs-then-single-save (CR-01)"
    - "Pending @Query uses transferPairID != nil && amount > 0 — NOT #Predicate on Bool? (STAB-08 / A2)"
    - "Defensive ForEach: credit leg resolved in-memory from expenses array; row skipped if either leg != isTransfer == nil"
    - "TransferFilter: third filter step after existing category + account steps in filteredExpenses"
    - "TransferScanService injected via @State in RootView, same pattern as RoutineResetService"

key-files:
  created:
    - MyHomeApp/Features/Expenses/TransferPairRow.swift
  modified:
    - MyHomeApp/Features/Expenses/ExpenseListView.swift
    - MyHomeApp/Features/Gmail/GmailSyncController.swift
    - MyHomeApp/App/RootView.swift (path: MyHomeApp/RootView.swift)
    - MyHomeApp/Features/Settings/SettingsView.swift
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "TransferPairRow confirmPair() keeps transferPairID intact post-confirm — required for D-16 balance-move wiring (outflow leg lowers source account, inflow leg raises destination)."
  - "rejectPair() clears transferPairID on both legs so the scorer can re-evaluate in a future scan if the user changes their mind."
  - "Possible Transfers section added to ExpenseListView (same view as Needs Review) per D-11 — no new screen."
  - "Scan for Transfers placed in Data section of SettingsView alongside Accounts, as contextually the closest home."
  - "First-run badge on Scan row uses UserDefaults key 'transferScanFirstRunDone' set by TransferScanService.scan() — no new keys."

requirements: [XFER-02, XFER-03, XFER-01]

tasks:
  - "Task 1: TransferPairRow + pending section in ExpenseListView — DONE (commit 9242458)"
  - "Task 2: TransferFilter + badge wiring — DONE (commit 9242458, same file as Task 1)"
  - "Task 3: Post-sync hook + RootView injection + Settings scan action — DONE (commit 69c0207)"
  - "Task 4: Human-verify checkpoint — PENDING (awaiting user verification)"

self_check: PASSED
---

## Plan 10-03 — Transfer Detection UI: Confirm/Reject Inbox + Transfers Filter + Sync Hook

### What was built

The user-facing confirm gate for self-transfer detection. Detected pending pairs now surface in
the existing Review Inbox as a "Possible Transfers" section with two-leg rows. The user swipes
to confirm or reject each pair. Confirmed transfers are excluded from the default spend list and
visible only under a new Transfers filter. The review tab badge counts pending pairs. The scorer
runs after every Gmail sync and on demand from Settings.

**TransferPairRow** (`struct TransferPairRow: View`):
- Two-leg layout: debit amount headline + "Transfer?" purple capsule, debit-account → arrow → credit-account, date.
- `confirmPair()`: sets `isTransfer = true` on both legs, stamps `updatedAt`, keeps `transferPairID` cross-set for D-16 balance-move, single `try context.save()`.
- `rejectPair()`: sets `isTransfer = false` on both legs, clears `transferPairID` on both, stamps `updatedAt`, single `try context.save()`.
- CR-01 compliant: both legs mutated before every save (atomic commit or rollback).
- Swipe actions mirror ReviewInboxRow: trailing, allowsFullSwipe: false, destructive reject + green confirm.

**ExpenseListView** changes:
- `pendingDebitLegs` `@Query` with `#Predicate` on `transferPairID != nil && amount > 0` (STAB-08-safe — no `Bool?` in predicate).
- `Possible Transfers` Section: defensively filters in-memory (checks both legs still have `isTransfer == nil` before rendering a `TransferPairRow`).
- `TransferFilter` enum (`.normal` / `.transfers`); `@State private var transferFilter`.
- `filteredExpenses` step 3: `.normal` returns `isTransfer != true`; `.transfers` returns `isTransfer == true`.
- Filter menu extended with Transfers Picker (dollarsign.circle / arrow.left.arrow.right icons).
- Filled filter icon also fills when `transferFilter != .normal`.
- `reviewBadgeCount` now `reviewItems.count + pendingDebitLegs.count` in both `onChange` callbacks and `onAppear`.

**GmailSyncController**:
- `var transferScanService: TransferScanService? = nil` property.
- `transferScanService?.scan()` called after the final `ctx.save()` and before `return true` in `syncAccount` (D-08 comment, synchronous @MainActor call — no STAB-02 risk).

**RootView**:
- `@State private var transferScanService = TransferScanService()`.
- `onAppear`: `transferScanService.modelContext = modelContext`; `gmailSyncController.transferScanService = transferScanService`.
- `transferScanService` passed to `SettingsView`.

**SettingsView**:
- `let transferScanService: TransferScanService` parameter.
- "Scan for Transfers" row in Data section: calls `transferScanService.scan()`; shows orange badge when `transferScanFirstRunDone == false`.

### Verification

- `xcodebuild build` clean on iPhone 17 (Xcode 26.5, scheme MyHome) — Tasks 1–3.
- Task 4 human-verify: awaiting user interaction on simulator.

### Known Stubs

None — all functionality is wired end-to-end. The confirm/reject actions write real SwiftData mutations; the filter reads real `isTransfer` state; the scan hook invokes the real `TransferScanService.scan()`.

## Self-Check: PASSED

- TransferPairRow.swift: FOUND
- ExpenseListView.swift (TransferFilter, pendingDebitLegs, Possible Transfers section): FOUND
- GmailSyncController.swift (transferScanService property + scan hook): FOUND
- RootView.swift (transferScanService wiring): FOUND
- SettingsView.swift (Scan for Transfers row): FOUND
- Commits: 9242458 (Task 1+2), 69c0207 (Task 3): FOUND
