---
phase: 1
slug: foundation-manual-expense-spine
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-05-29
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (bundled, no SPM dep) + XCTest for UI tests |
| **Config file** | none — Xcode Test Plans (one unit plan, one UI plan); Wave 0 configures the test target |
| **Quick run command** | `xcodebuild test -scheme MyHome -only-testing:MyHomeTests -destination 'platform=iOS Simulator,name=iPhone 16'` (Cmd-U in Xcode) |
| **Full suite command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 16'` |
| **Estimated runtime** | ~5 seconds (unit, in-memory store) |

---

## Sampling Rate

- **After every task commit:** Run the quick unit suite (`-only-testing:MyHomeTests`)
- **After every plan wave:** Run the full suite (`xcodebuild test -scheme MyHome -destination '...'`)
- **Before `/gsd-verify-work`:** Full suite must be green + manual ≤4-tap smoke test on a real device
- **Max feedback latency:** ~5 seconds (quick unit suite on in-memory `ModelContainer`)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 1-xx | TBD | TBD | FND-03 | — | All @Model properties optional/defaulted, no `.unique` | unit (reflection) | `ExpenseModelTests/expensePropertiesAreCloudKitReady` | ❌ W0 | ⬜ pending |
| 1-xx | TBD | TBD | FND-05 | — | VersionedSchema v1 loads bundled store cleanly | integration (migration) | `MigrationTests/v1StoreMigratesCleanly` | ❌ W0 | ⬜ pending |
| 1-xx | TBD | TBD | FND-06 | — | In-memory `ModelContainer` fixture per test | unit (infra) | `ExpenseModelTests/expenseCRUD` | ❌ W0 | ⬜ pending |
| 1-xx | TBD | TBD | FND-07 | — | en-IN currency formatting produces lakh grouping (₹1,00,000.00) | unit | `ExpenseModelTests/currencyFormatting` | ❌ W0 | ⬜ pending |
| 1-xx | TBD | TBD | EXP-01 | — | Expense inserted via context appears in `@Query` | unit | `ExpenseModelTests/expenseCRUD` | ❌ W0 | ⬜ pending |
| 1-xx | TBD | TBD | EXP-02 | — | Expense fields update and persist | unit | `ExpenseModelTests/expenseUpdate` | ❌ W0 | ⬜ pending |
| 1-xx | TBD | TBD | EXP-03 | — | Expense deletes from context | unit | `ExpenseModelTests/expenseCRUD` | ❌ W0 | ⬜ pending |
| 1-xx | TBD | TBD | FND-04 | — | `PrivacyInfo.xcprivacy` exists with `NSPrivacyTracking` + required-reason keys | static check | `grep -l "NSPrivacyTracking" MyHome/Resources/PrivacyInfo.xcprivacy` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky · Task IDs finalized once PLAN.md files exist.*

---

## Wave 0 Requirements

- [ ] `MyHomeTests/ExpenseModelTests.swift` — stubs for FND-03, FND-06, FND-07, EXP-01, EXP-02, EXP-03
- [ ] `MyHomeTests/MigrationTests.swift` — stub for FND-05 (depends on a bundled v1 seed store)
- [ ] `MyHomeTests/` target configured in Xcode with Swift Testing enabled (`@Test` functions, no XCTest base class)
- [ ] `MyHomeV1Seed.store` test-bundle resource — created after the v1 schema lands (add one expense to sim, export store file, add to test resources) for the migration load test

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| ≤4-tap add flow (open → amount → save) | EXP-01 | Tap-count + custom keypad responsiveness can only be judged on-device | On a real device, add an expense in ≤3 taps from the list screen; confirm it appears in the list |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
