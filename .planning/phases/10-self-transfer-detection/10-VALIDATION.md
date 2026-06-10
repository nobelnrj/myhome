---
phase: 10
slug: self-transfer-detection
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-10
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`import Testing`, `@Test`/`#expect`) |
| **Config file** | none — MyHome.xcodeproj scheme `MyHome`, target `MyHomeTests` |
| **Quick run command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/TransferDetectionScorerTests` |
| **Full suite command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |
| **Estimated runtime** | ~90 seconds (full suite, simulator boot included) |

---

## Sampling Rate

- **After every task commit:** Run the targeted `-only-testing:` quick command for the unit under test
- **After every plan wave:** Run the full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~90 seconds

---

## Per-Task Verification Map

> Populated by the planner. Each row maps a plan task to its automated proof. The
> highest-risk behaviors below MUST each have at least one unit-test row.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 1 | XFER-01 | — | Scorer surfaces a pair only when all 5 AND-rules hold; no false positives | unit | `xcodebuild test ... -only-testing:MyHomeTests/TransferDetectionScorerTests` | ❌ W0 | ⬜ pending |

---

## Highest-Risk Behaviors (Nyquist focus — derived from RESEARCH §Validation Architecture)

| Risk | Failure Mode | Proof Surface |
|------|--------------|---------------|
| **False-positive matching** | A non-transfer debit/credit pair surfaces | Unit tests over `TransferDetectionScorer` covering each AND-rule independently (amount, sign, two distinct accounts, ≤3-day IST window, `isTransfer == nil`) |
| **Double-counted balance** | Confirmed pair moves net worth instead of leaving it unchanged | Unit test on `AccountBalance.compute` asserting total net worth unchanged across a confirmed linked pair; debit account ↓, credit account ↑ |
| **Predicate fragility (STAB-08)** | `isTransfer == nil` candidates missed by a `Bool?` `#Predicate` | Scorer fetch-then-filter in Swift; test asserts nil candidates are evaluated under the versioned SchemaV6 container |
| **Re-surfacing confirmed/rejected pairs** | A `true`/`false` leg re-appears in the inbox | Unit test: re-running the scorer over a corpus with non-nil legs yields zero new candidates |
| **Solo transfer balance leak** | A solo marked transfer (no counterpart) moves balance | Unit test: solo `isTransfer == true`, `transferPairID == nil` excluded from spend but does NOT alter account balances |
| **Tie-break nondeterminism** | One debit matching multiple credits pairs unpredictably | Unit test: closest-in-time wins; `id.uuidString` lexicographic tiebreak; remaining candidates stay `nil` |

---

## Wave 0 Requirements

- [ ] `MyHomeTests/TransferDetectionScorerTests.swift` — scorer AND-rule + tie-break stubs for XFER-01
- [ ] `MyHomeTests/TransferBalanceMoveTests.swift` — `AccountBalance.compute` net-worth-unchanged stubs for XFER-04 / ACCT-05
- [ ] `MyHomeTests/TransferExclusionTests.swift` — spend/budget/chart exclusion stubs for XFER-04

*Existing Swift Testing infrastructure covers the framework; only new test files are needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Review Inbox transfer-pair row confirm/reject UX | XFER-02 | SwiftUI interaction; verified on simulator | Run app, trigger scan, confirm a pair in Review Inbox, verify both legs marked + linked |
| Transfers filter section in ExpenseListView | XFER-03 | SwiftUI presentation | Confirm a pair, verify it disappears from default list and appears only under Transfers filter |
| Manual mark/unmark on expense detail | XFER-05 | SwiftUI interaction | Mark an expense as transfer on detail view, verify excluded from spend; unmark resets |

*The detection/exclusion/balance math underneath each of these has automated unit coverage above.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
