---
phase: 02
slug: categories-tags-budgets
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-29
---

# Phase 02 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `02-RESEARCH.md` § Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (bundled in Swift 6.2 toolchain, Xcode 26.5) |
| **Config file** | Xcode Test Plan (no external config file) |
| **Test target** | MyHomeTests |
| **Quick run command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing MyHomeTests 2>&1 \| tail -20` |
| **Full suite command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 \| tail -30` |
| **Estimated runtime** | ~60–120 seconds (simulator boot dominated) |

**Existing infrastructure:** `ExpenseModelTests.swift` + `MigrationTests.swift` + `MyHomeV1Seed.store` bundled resource. In-memory `ModelConfiguration(isStoredInMemoryOnly: true)` everywhere except `MigrationTests` (uses the bundled v1 store).

---

## Sampling Rate

- **After every task commit:** Run the relevant `-only-testing` unit subset (quick).
- **After every plan wave:** Run the full suite command.
- **Before `/gsd-verify-work`:** Full suite must be green.
- **Max feedback latency:** ~120 seconds (simulator-bound).

---

## Per-Task Verification Map

> Task IDs are provisional until plans are finalized; the planner must keep each Wave-0 test stub tied to the requirement below. Filled from `02-RESEARCH.md` req→test map.

| Requirement | Behavior | Test Type | Automated Command | File Exists |
|-------------|----------|-----------|-------------------|-------------|
| EXP-04 | 14 predefined categories seeded on empty store | unit | `xcodebuild test -only-testing MyHomeTests/CategorySeedTests` | ❌ W0 |
| EXP-04 | Seeding idempotent (no dupes on relaunch) | unit | `… CategorySeedTests/seedIsIdempotent` | ❌ W0 |
| EXP-05 | Category add / rename / delete | unit | `… CategoryCRUDTests` | ❌ W0 |
| EXP-05 | Delete nullifies `expense.categories` link | unit | `… CategoryCRUDTests/deleteNullifiesExpenseLink` | ❌ W0 |
| EXP-06 | Expense category assign + clear | unit | `… ExpenseCategoryTests` | ❌ W0 |
| EXP-07 | `monthlyBudget` Decimal store/retrieve | unit | `… BudgetModelTests` | ❌ W0 |
| EXP-08 | Budget fraction / remaining / threshold computed | unit | `… BudgetCalculatorTests` | ❌ W0 |
| EXP-08 | Color thresholds: <80% normal, 80–99% warning, ≥100% over | unit | `… BudgetCalculatorTests/colorThresholds` | ❌ W0 |
| EXP-09 | Month-scoped aggregation groups by category | unit | `… BudgetCalculatorTests/monthlyAggregation` | ❌ W0 |
| EXP-09 | Uncategorized bucket excluded from budget math | unit | `… BudgetCalculatorTests/uncategorizedBucket` | ❌ W0 |
| Migration | V1 store opens cleanly under SchemaV2 + AppMigrationPlan | integration | `… MigrationTests` | ✅ (update to SchemaV2) |
| Migration | V1 expense readable post-V2 (amount/note/date intact) | integration | `… MigrationTests/v1StoreMigratesCleanly` | ✅ (update) |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `MyHomeTests/CategorySeedTests.swift` — EXP-04 (seeding, idempotency)
- [ ] `MyHomeTests/CategoryCRUDTests.swift` — EXP-05 (add/rename/delete, nullify cascade)
- [ ] `MyHomeTests/ExpenseCategoryTests.swift` — EXP-06 (attach/clear category)
- [ ] `MyHomeTests/BudgetModelTests.swift` — EXP-07 (`monthlyBudget` storage)
- [ ] `MyHomeTests/BudgetCalculatorTests.swift` — EXP-08 + EXP-09 (aggregation, thresholds, uncategorized) — pure-function tests, no ModelContainer
- [ ] Update `MyHomeTests/MigrationTests.swift` — point schema ref at SchemaV2; `MyHomeV1Seed.store` fixture stays valid

All in-memory tests use `ModelConfiguration(isStoredInMemoryOnly: true)` (Pitfall 16).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Progress-bar color shift renders at 80%/100% in UI | EXP-08 | Visual rendering / color tokens | Add expenses to push a category to 79%, 85%, 105%; observe bar color (normal→warning→over) and that text (₹-remaining/%) co-signals |
| Tab shell + month-paging navigation feel | EXP-09 / D2-10 | Interaction/navigation | Switch tabs, page months prev/next, tap category card → filtered list for that month |
| Category picker stays off the ≤3-tap fast path | D2-12 / EXP-01 | Subjective flow timing | Add an expense leaving category empty; confirm no added taps vs Phase 1 |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
