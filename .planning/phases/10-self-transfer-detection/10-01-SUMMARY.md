---
phase: 10-self-transfer-detection
plan: "01"
subsystem: transfer-detection
tags: [swift, swiftdata, transfer, scorer, scan-service, account-balance, tdd, bugfix]

requires:
  - phase: 09 (Accounts)
    provides: Expense.accountID, Account.balanceBaseline/balanceAsOfDate, AccountBalance.compute
  - phase: 10-self-transfer-detection
    provides: isTransfer Bool? + transferPairID UUID? fields on Expense (SchemaV6)

provides:
  - TransferDetectionScorer — pure value-type 5-signal pairing helper (XFER-01, D-01..D-05)
  - TransferScanService — @MainActor coordinator writing pending pairs via no-new-schema encoding (transferPairID != nil && isTransfer == nil, D-07)
  - AccountBalance.compute SIGN FIX — spends (positive) now reduce a savings balance (baseline − net); was inverted (baseline + net)
  - Confirmed transfer legs included in per-account balance with correct direction (D-16); net worth invariant under a transfer pair
  - Full unit/integration test surface for scorer, scan service, and balance behavior

affects:
  - 10-self-transfer-detection/10-03 (consumes scorer + scan service; balance-move now safe to wire on corrected formula)
  - any feature reading AccountBalance.compute (AccountDetailView, AccountsListView net worth)

tech-stack:
  added: []
  patterns:
    - "Value-type scorer: operates on [Expense], returns CandidatePair UUID scalars only — no @Model held across boundaries (STAB-02)"
    - "No-new-schema pending encoding: transferPairID != nil && isTransfer == nil = pending pair (D-07)"
    - "Deterministic pairing: sort debits by date then id.uuidString; tie-break credits by closest time then UUID"
    - "AccountBalance: spends stored POSITIVE app-wide → balance = baseline − net(attributed, post-asOf)"

key-files:
  created:
    - MyHomeApp/Features/Gmail/TransferDetectionScorer.swift
    - MyHomeApp/Features/Gmail/TransferScanService.swift
    - MyHomeTests/TransferDetectionScorerTests.swift
    - MyHomeTests/TransferScanServiceTests.swift
    - MyHomeTests/AccountBalanceTransferTests.swift
  modified:
    - MyHomeApp/Support/AccountBalance.swift
    - MyHomeTests/AccountBalanceTests.swift
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "RESEARCH-A3 / Critical Finding 4 RESOLVED via human-verify gate: a real positive-baseline savings spend INCREASED the displayed balance → confirmed sign inversion in AccountBalance.compute."
  - "Root cause: spends are stored POSITIVE (AddExpenseView default; BudgetCalculator 'negative = refund'); compute used baseline + net, must be baseline − net."
  - "Phase 9 AccountBalanceTests had masked the bug by feeding NEGATIVE amounts for spends — corrected to the real convention and added savingsSpendDecreasesRefundIncreases regression."
  - "Scorer labels amount > 0 = debit/outflow leg, amount < 0 = credit/inflow leg; under corrected formula the outflow leg lowers the source account and the inflow leg raises the destination — net worth unchanged (D-16)."

requirements: [XFER-01, XFER-04]

tasks:
  - "Task 1: TransferDetectionScorer 5-signal helper + 12 tests — DONE (commit 94df8ec)"
  - "Task 2: TransferScanService pending-pair coordinator + 6 tests — DONE (commit 5d8b702)"
  - "Task 3: AccountBalance transfer-move tests — DONE (commit f49fce0)"
  - "Task 4: human-verify AccountBalance sign vs real savings account — RESOLVED: sign bug found and fixed (commit 458bab2)"

self_check: PASSED
---

## Plan 10-01 — Transfer Detection Engine + AccountBalance sign correction

### What was built
A deterministic, pure-value-type transfer detection engine and the service that persists
detected pairs, plus a correctness fix to the account balance formula surfaced by the
plan's blocking human-verify gate.

- **TransferDetectionScorer** (`enum`, no SwiftData): `findCandidatePairs(from:calendar:)`
  applies the five AND-rules (exact Decimal amount, opposite direction, two distinct
  assigned accounts, ≤3 IST-day window) with deterministic ordering and a closest-time/UUID
  tie-break. 12 unit tests cover every rule plus determinism and claim-once semantics.
- **TransferScanService** (`@MainActor`): fetches `isTransfer == nil` candidates, runs the
  scorer, and writes pending pairs using the no-new-schema encoding
  (`transferPairID != nil && isTransfer == nil`). Idempotent; skips confirmed/rejected legs;
  sets a first-run flag. 6 integration tests.
- **AccountBalance sign fix**: the human-verify gate (Task 4) caught a real inversion —
  `compute` was `baseline + net`, but spends are stored positive app-wide, so it must be
  `baseline − net`. Fixed, with Phase 9 tests corrected (they had hidden the bug with
  negative spend amounts) and a regression test added.

### Execution note (session recovery)
The first executor agent hit the provider session limit mid-run after writing all five
files but before committing or writing this SUMMARY. On resume, the orchestrator verified
the working-tree code built and passed (21 tests green), committed Tasks 1–3 atomically,
presented the Task 4 human-verify checkpoint, and — on the user's "balance went UP" finding —
diagnosed and fixed the sign bug within the phase per user direction.

### Verification
- `xcodebuild build-for-testing` clean on iPhone 17 (Xcode 26.5, scheme MyHome).
- Suites green: TransferDetectionScorerTests, TransferScanServiceTests,
  AccountBalanceTransferTests, AccountBalanceTests (incl. new regression),
  BudgetCalculatorTests, SpendOverTimeAggregatorTests.
- In-app: a +500 spend on a 10,000 savings baseline now yields 9,500 (was 10,500).

### Follow-ups for Plan 10-03
The corrected `baseline − net` formula makes the D-16 balance-move safe to wire: a confirmed
pair's outflow leg lowers the source account and the inflow leg raises the destination, with
net worth unchanged.
