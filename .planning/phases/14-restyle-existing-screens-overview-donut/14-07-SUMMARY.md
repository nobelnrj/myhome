---
phase: 14-restyle-existing-screens-overview-donut
plan: "07"
subsystem: Expenses / Activity / Review Inbox / Transfer Inbox
tags: [restyle, neumorphic, skin-02, skin-08, skin-09, expenses, review-inbox, transfer]
dependency_graph:
  requires: ["14-02"]
  provides: [SKIN-02, SKIN-08, SKIN-09]
  affects: [ExpenseListView, ExpenseRow, ReviewInboxRow, TransferPairRow, AddExpenseView, EditExpenseView, DecimalKeypadView, AccountPickerView, CategoryPickerView]
tech_stack:
  added: []
  patterns: [DesignTokens, neuSurface, positive/negative color split, surfaceRaised, bgCanvas, surfaceElevatedControl]
key_files:
  modified:
    - MyHomeApp/Features/Expenses/ExpenseListView.swift
    - MyHomeApp/Features/Expenses/ExpenseRow.swift
    - MyHomeApp/Features/Expenses/ReviewInboxRow.swift
    - MyHomeApp/Features/Expenses/TransferPairRow.swift
    - MyHomeApp/Features/Expenses/AddExpenseView.swift
    - MyHomeApp/Features/Expenses/EditExpenseView.swift
    - MyHomeApp/Features/Expenses/DecimalKeypadView.swift
    - MyHomeApp/Features/Expenses/AccountPickerView.swift
    - MyHomeApp/Features/Expenses/CategoryPickerView.swift
decisions:
  - "Income amounts (negative) use DesignTokens.positive .semibold; spend amounts use DesignTokens.negative .semibold across all Expenses views"
  - "TransferPairRow confirm swipe tint changed from .tint(.green) to .tint(DesignTokens.positive); reject remains destructive (system red); logic unchanged (SKIN-09)"
  - "ReviewInboxRow accept swipe tint changed from .tint(.green) to .tint(DesignTokens.positive); duplicate badge uses DesignTokens.orange"
  - "Day group header uses label2 date + positive/label3 conditional total — matching UI-SPEC Screen 2 day header row contract"
  - "Delete Expense button uses DesignTokens.negative tint instead of Color(.systemRed)"
metrics:
  duration: "~20 min"
  completed: "2026-06-22"
  tasks: 2
  files: 9
---

# Phase 14 Plan 07: Activity / Expenses + Review Inbox + Transfer Inbox Restyle Summary

Neumorphic restyle of all Activity/Expenses views (SKIN-02), Gmail Review inbox rows (SKIN-08), and Transfer Inbox rows (SKIN-09): income/spend color split applied, `.tint(.green)` replaced with `DesignTokens.positive`, all stock system colors eliminated, add/edit/picker/keypad sheets migrated to `bgCanvas` + `surfaceRaised` + `surfaceElevatedControl`. CRUD, self-transfer confirm, and Gmail review flows unregressed.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Restyle ExpenseListView + rows + transfer rows (SKIN-02, SKIN-08) | cdb1c22 |
| 2 | Restyle add/edit sheets, pickers, keypad (SKIN-02) | ab11b0e |

## What Was Built

**Task 1 — ExpenseListView, ExpenseRow, ReviewInboxRow, TransferPairRow:**
- `ExpenseRow`: `.primary` → `DesignTokens.label`; `.secondary` → `DesignTokens.label2`; `Color(.systemGreen)` / `Color(.label)` → `DesignTokens.positive` / `DesignTokens.negative` (both `.semibold`)
- `ReviewInboxRow`: amount color split (`positive`/`negative` `.semibold`); Review badge `DesignTokens.accent`; Duplicate badge `DesignTokens.orange`; duplicate text `.orange` → `DesignTokens.orange`; accept swipe `.tint(.green)` → `.tint(DesignTokens.positive)`
- `TransferPairRow`: Transfer? badge `Color.purple` → `DesignTokens.accent`; route text `.secondary` → `DesignTokens.label2`; date `.tertiary` → `DesignTokens.label3`; confirm swipe `.tint(.green)` → `.tint(DesignTokens.positive)`; reject swipe unchanged (`.destructive`)
- `ExpenseListView`: toolbar `+` `.tint(.accentColor)` → `.tint(DesignTokens.accent)`; day header date `DesignTokens.label2` + total `DesignTokens.positive`/`DesignTokens.label3` conditional; OVR-06 `categoryFilter` binding and `onAppear` logic fully preserved

**Task 2 — AddExpenseView, EditExpenseView, DecimalKeypadView, AccountPickerView, CategoryPickerView:**
- Add/Edit sheets: `ScrollView` background `DesignTokens.bgCanvas`; amount section + all input rows `DesignTokens.surfaceRaised`; amount display `DesignTokens.label` / error `DesignTokens.negative` / income-negative `DesignTokens.positive`; Save button `.tint(DesignTokens.accent)`
- `DecimalKeypadView`: key cells `Color(.secondarySystemBackground)` → `DesignTokens.surfaceElevatedControl`
- `AccountPickerView` + `CategoryPickerView`: checkmark `Color.accentColor` → `DesignTokens.accent`; Clear button `Color(.systemRed)` → `DesignTokens.negative`
- `EditExpenseView`: Delete Expense button `Color(.systemRed)` → `DesignTokens.negative`; transfer toggle label `DesignTokens.label`; `applyTransferMark` static func and `isDirty` detection untouched (SKIN-09)

## Verification Results

- `grep -rnE '...' | wc -l` → **0** for both Task 1 and Task 2 acceptance checks (zero stock system colors)
- `grep -c 'DesignTokens.positive' TransferPairRow.swift` → **1** (`.tint` on confirm)
- `grep -c 'categoryFilter' ExpenseListView.swift` → **7** (OVR-06 binding preserved)
- `grep -c 'applyTransferMark' EditExpenseView.swift` → **2** (call site + static definition)
- `xcodebuild build` → **BUILD SUCCEEDED**
- `EditExpenseTransferTests` → **4/4 passed** (self-transfer confirm logic unregressed)

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

## Known Stubs

None — all token wiring is complete; no placeholder values remain.

## Threat Flags

None — only button colors/surfaces changed; confirm/dismiss bindings for both review inbox and transfer pair rows are preserved verbatim. T-14-12 and T-14-13 mitigations confirmed.

## Self-Check: PASSED

- ExpenseRow.swift: exists, contains `DesignTokens.label`
- ReviewInboxRow.swift: exists, contains `DesignTokens.accent`, `DesignTokens.positive`
- TransferPairRow.swift: exists, contains `DesignTokens.positive` (confirm tint)
- AddExpenseView.swift: exists, contains `DesignTokens.bgCanvas`, `DesignTokens.surfaceRaised`
- EditExpenseView.swift: exists, contains `applyTransferMark` (2 occurrences)
- DecimalKeypadView.swift: exists, contains `DesignTokens.surfaceElevatedControl`
- Commits cdb1c22 and ab11b0e present in git log
