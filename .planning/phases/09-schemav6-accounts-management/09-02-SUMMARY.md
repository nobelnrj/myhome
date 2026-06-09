---
phase: 09-schemav6-accounts-management
plan: 02
subsystem: features/settings/accounts
tags: [swiftui, swiftdata, accounts, crud, migration-review, tdd]
dependency_graph:
  requires: [SchemaV6, Account model, v5ToV6 migration]
  provides: [AccountsListView, EditAccountView, AccountDetailView, MigrationReviewSheet, AccountBalance helper]
  affects: [09-03 expense attribution, SettingsView]
tech_stack:
  added: [AccountBalance.swift, Color+Hex.swift, AccountsListView.swift, EditAccountView.swift, AccountDetailView.swift, MigrationReviewSheet.swift]
  patterns: [computed live balance (never stored), lookup-before-insert uniqueness, archive via collapsed DisclosureGroup, self-healing stale UserDefaults flag]
key_files:
  created:
    - MyHomeApp/Features/Settings/AccountsListView.swift
    - MyHomeApp/Features/Settings/EditAccountView.swift
    - MyHomeApp/Features/Settings/AccountDetailView.swift
    - MyHomeApp/Features/Settings/MigrationReviewSheet.swift
    - MyHomeApp/Support/AccountBalance.swift
    - MyHomeApp/Support/Color+Hex.swift
    - MyHomeTests/AccountBalanceTests.swift
    - MyHomeTests/AccountTypeInferenceTests.swift
    - MyHomeTests/AccountCRUDTests.swift
  modified:
    - MyHomeApp/Features/Settings/SettingsView.swift
    - MyHomeApp/Persistence/Schema/MigrationPlan.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "Live balance computed via AccountBalance.compute (never stored); reactive through @Query (ACCT-05, D-10)"
  - "Balance = baseline + sum(attributed expenses dated on/after as-of date); returns 0 when baseline/as-of nil (intended — manual opening balance per D-10/ACCT-04)"
  - "Account type inferred during migration via inferAccountType (CC/credit/card → credit_card; else savings, D-03)"
  - "Migration-review badge/banner gated on accountReviewPending AND existence of auto-created accounts; stale flag self-heals (fix after human verification)"
  - "Uniqueness via case-insensitive lookup-before-insert (no CloudKit unique constraint, rule 2)"
  - "Archived accounts hidden from active list, shown in collapsed DisclosureGroup (D-08)"
metrics:
  completed_date: "2026-06-10"
  tasks_completed: 4
  files_changed: 12
  human_verified: true
---

# Phase 9 Plan 02: Accounts Management Surface Summary

Full Accounts management under Settings (D-06): CRUD list with archive/delete, create/edit form with type inference and opening-balance + as-of picker, per-account detail with live computed balance, and the first-launch migration-review sheet for auto-created accounts. Human-verified end-to-end by replaying the real V5→V6 migration.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 (RED) | Failing account tests | ec46758 | AccountBalanceTests.swift, AccountTypeInferenceTests.swift, AccountCRUDTests.swift, project.pbxproj |
| 2 (GREEN) | AccountBalance helper + AccountsListView CRUD + Edit/Detail/Review views | 801c1df | AccountBalance.swift, Color+Hex.swift, MigrationPlan.swift, AccountsListView.swift, EditAccountView.swift, AccountDetailView.swift, MigrationReviewSheet.swift, project.pbxproj |
| 3 | SettingsView Accounts row + review badge | f406351 | SettingsView.swift |
| 4 | Human verification (migration-review flow + balance semantics) | — (verification) | — |

## Deviations from Plan

### Fix applied during human verification

**1. [Bug] Migration-review badge showed with nothing to review (stale flag)**
- **Found during:** Task 4 human verification — user saw the orange review badge in Settings, but tapping through opened an empty review sheet.
- **Root cause:** The badge (SettingsView) and banner (AccountsListView) gated purely on the `accountReviewPending` UserDefaults flag. A stale flag (set during Plan 01 dev/test runs, then the store reset while UserDefaults persisted) produced a badge with no matching auto-created accounts behind it. The migration logic itself was correct (only sets the flag when `didCreateAny`).
- **Fix:** Gate both the badge and banner on `accountReviewPending && hasAutoCreatedAccounts` (accounts with non-nil `sourceLabel`). SettingsView gained a `@Query` for accounts; AccountsListView self-heals the stale flag in `.onAppear` when no auto-created accounts exist.
- **Files modified:** AccountsListView.swift, SettingsView.swift
- **Commit:** 35af212

## Verification

### Automated
- `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` — **TEST SUCCEEDED** (full suite, including new AccountBalanceTests / AccountTypeInferenceTests / AccountCRUDTests), no compile errors.

### Human (real migration replay)
Built the last-V5 commit (c7e5e33) in a throwaway worktree, populated its store via Gmail sync, then launched the current V6 build over the same App Group store to trigger the real `v5ToV6` migration. Verified against the live store:
- **4 accounts auto-created** from distinct `sourceLabel`s (ICICI CC ••5005, HDFC ••2758, ICICI CC ••8006, HDFC ••1329) with type correctly inferred (CC → credit_card, others → savings).
- **205/205 labeled expenses backfilled** with `accountID` — none left unattributed.
- `accountReviewPending = true` → badge shows with **real** accounts behind it (post-fix).
- Migration-review sheet lists all 4; rename/retype/delete work; **badge clears** after Done in both the list and Settings.
- Manual account create/edit works; live balance is reactive via `@Query`.

### Balance semantics (confirmed intended, not a bug)
Auto-created accounts have no manual opening balance, so `AccountBalance.compute` returns 0 (baseline/as-of nil → 0, per D-10/ACCT-04). The app tracks expenses, not income, so a balance is undefined without a manual baseline. After the user sets an opening balance, the live balance reacts to expenses **dated on/after the chosen as-of date** (which defaults to today) — confirmed with the user.

## Threat Surface Scan

No new unplanned threat surface. T-09-05 (abs(balanceBaseline) < 1e9 guard), T-09-06 (account name via plain `Text()`, never `AttributedString(markdown:)`), and T-09-08 (case-insensitive lookup-before-insert) implemented per plan.

## Known Stubs

None. AccountDetailView, EditAccountView, AccountsListView, and MigrationReviewSheet are all fully wired to SwiftData.

## Self-Check: PASSED

Created files exist:
- MyHomeApp/Features/Settings/AccountsListView.swift: FOUND
- MyHomeApp/Features/Settings/EditAccountView.swift: FOUND
- MyHomeApp/Features/Settings/AccountDetailView.swift: FOUND
- MyHomeApp/Features/Settings/MigrationReviewSheet.swift: FOUND
- MyHomeApp/Support/AccountBalance.swift: FOUND

Commits exist:
- ec46758: FOUND (test(09-02) RED)
- 801c1df: FOUND (feat(09-02) AccountBalance + AccountsListView GREEN)
- f406351: FOUND (feat(09-02) SettingsView Accounts row + badge)
- 35af212: FOUND (fix(09-02) gate review badge on actual auto-created accounts)
