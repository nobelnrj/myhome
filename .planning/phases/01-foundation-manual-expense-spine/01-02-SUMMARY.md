---
phase: 01-foundation-manual-expense-spine
plan: 02
subsystem: swiftdata-schema
tags: [swiftdata, schema, migration, cloudkit-readiness, en-IN, formatting, tdd]
dependency_graph:
  requires:
    - xcode-project (01-01)
  provides:
    - expense-model (SchemaV1.Expense @Model, CloudKit-ready)
    - versioned-schema (SchemaV1 + AppMigrationPlan)
    - container-factory (ModelContainer.appContainer())
    - currency-formatter (Decimal.formattedINR() en-IN lakh grouping)
    - date-helpers (Date.formattedForExpenseList / formattedForDatePickerRow)
  affects:
    - 01-03 (UI screens depend on Expense @Model and container factory)
    - 01-04 (MigrationTests seed store uses AppMigrationPlan)
tech_stack:
  added:
    - SwiftData VersionedSchema (SchemaV1: VersionedSchema)
    - SwiftData SchemaMigrationPlan (AppMigrationPlan: SchemaMigrationPlan)
    - Foundation FormatStyle .currency(code:).locale() for en-IN formatting
  patterns:
    - "@Model inside VersionedSchema enum (prevents namespace collision on v2)"
    - "typealias Expense = SchemaV1.Expense (views/tests use bare Expense)"
    - "App Group store URL with Application Support fallback"
    - "Static container factory with .modelContainer modifier in @main App"
    - "In-memory ModelContainer per test (FND-06, Pitfall 16)"
key_files:
  created:
    - MyHomeApp/Persistence/Schema/SchemaV1.swift
    - MyHomeApp/Persistence/Schema/MigrationPlan.swift
    - MyHomeApp/Persistence/Models/Expense.swift
    - MyHomeApp/Persistence/ModelContainer+App.swift
    - MyHomeApp/Support/Decimal+INR.swift
    - MyHomeApp/Support/Date+Display.swift
  modified:
    - MyHomeApp/MyHomeApp.swift (wired .modelContainer)
    - MyHomeTests/ExpenseModelTests.swift (stubs → real assertions)
    - MyHome.xcodeproj/project.pbxproj (wired all new files)
decisions:
  - "Expense @Model nested inside SchemaV1 enum to prevent namespace collision when SchemaV2 arrives"
  - "typealias Expense = SchemaV1.Expense in Expense.swift — views/tests use bare Expense; flip to SchemaV2 in one line when Phase 2 arrives"
  - "App Group URL with Application Support fallback: free Apple Developer account may not provision the entitlement; store path is documented for migration when paid account activates"
  - "cloudKitDatabase: .none in ModelConfiguration v1 — flip to .private('iCloud.com.reojacob.myhome') post-paid-upgrade (one-line change)"
  - "FormatStyle .currency(code:'INR').locale(Locale(identifier:'en_IN')) — not NumberFormatter, not hand-rolled ₹ (Pitfall 17, RESEARCH Pattern 5)"
metrics:
  duration: 20 min
  completed_date: "2026-05-29"
  tasks_completed: 2
  tasks_total: 2
  files_created: 6
  files_modified: 3
---

# Phase 01 Plan 02: SwiftData Schema & Formatting Helpers Summary

CloudKit-ready Expense @Model inside VersionedSchema v1, SchemaMigrationPlan scaffolding, App Group ModelContainer factory, and en-IN lakh-grouping currency + UTC date display helpers — 4 plan-01 red stubs now green.

## What Was Built

**Task 1 — Expense @Model + VersionedSchema v1 + ModelContainer factory** (commit a668bd3)

Created the durable data spine:

- `SchemaV1.swift`: `enum SchemaV1: VersionedSchema` with `versionIdentifier = Schema.Version(1, 0, 0)`. Nested `@Model final class Expense` carrying all D-05 fields: `id: UUID = UUID()`, `amount: Decimal = Decimal(0)`, `currencyCode: String = "INR"`, `date: Date = Date()`, `note: String? = nil`, `createdAt: Date = Date()`, `updatedAt: Date = Date()`. All 8 CloudKit-readiness rules applied: optional/defaulted fields, no `@Attribute(.unique)`, `Decimal` money, UUID PK, UTC timestamp dates, `currencyCode` present, relationships reserved for Phase 2.

- `MigrationPlan.swift`: `enum AppMigrationPlan: SchemaMigrationPlan` with `schemas = [SchemaV1.self]` and `stages = []`. Empty stages = single version, forward-compatible from day one (D-08). Phase 2 appends `SchemaV2.self` and a migration stage.

- `Expense.swift`: `typealias Expense = SchemaV1.Expense` — views and tests use bare `Expense`. When Phase 2 restructures the model, this typealias is the only change needed.

- `ModelContainer+App.swift`: `appContainer()` factory resolving `group.com.reojacob.myhome` App Group URL; Application Support fallback with `// TODO` comment if entitlement unavailable on free account. `cloudKitDatabase: .none` — flip to `.private("iCloud.com.reojacob.myhome")` post paid-account upgrade.

- `MyHomeApp.swift`: wired `.modelContainer(container)` via static factory (RESEARCH Pattern 3).

- `ExpenseModelTests.swift`: replaced 4 `#expect(Bool(false))` stubs with real assertions:
  - `expenseCRUD`: insert/fetch/delete against in-memory container
  - `expenseUpdate`: mutate amount + note + updatedAt, re-fetch, assert
  - `expensePropertiesAreCloudKitReady`: Mirror reflection over all properties + uniquenessConstraints == empty
  - `currencyFormatting`: formattedINR() lakh grouping "1,00,000" + "₹" prefix

**Task 2 — en-IN currency formatting + UTC date display helpers** (commit 752d73a)

- `Decimal+INR.swift`: `func formattedINR() -> String` using `self.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN")))` — FormatStyle, not NumberFormatter, not hand-rolled ₹ (RESEARCH Pattern 5, Pitfall 17). Produces lakh grouping ₹1,00,000.00 (FND-07).

- `Date+Display.swift`: `formattedForExpenseList()` (.medium date / .short time, user locale/timezone) and `formattedForDatePickerRow()` ("Today, h:mm a" or medium+short) — UTC storage / local display (D-02).

## Verification Evidence

```
xcodebuild test -scheme MyHome -only-testing:MyHomeTests/ExpenseModelTests -destination 'platform=iOS Simulator,name=iPhone 17'
→ TEST SUCCEEDED
  ExpenseModelTests/expenseCRUD() PASSED
  ExpenseModelTests/expenseUpdate() PASSED
  ExpenseModelTests/currencyFormatting() PASSED
  ExpenseModelTests/expensePropertiesAreCloudKitReady() PASSED

xcodebuild test -scheme MyHome -only-testing:MyHomeTests/MigrationTests -destination 'platform=iOS Simulator,name=iPhone 17'
→ TEST FAILED (v1StoreMigratesCleanly FAILED — correct, seed store not yet created; plan 04)

grep -rn "@Attribute(.unique)" MyHomeApp/ → only comment lines, zero actual usage ✓
grep -rn ": Double" MyHomeApp/Persistence/ → zero results ✓
grep -rn "VersionedSchema" MyHomeApp/ → SchemaV1.swift + MigrationPlan.swift ✓
grep -rn "SchemaMigrationPlan" MyHomeApp/ → MigrationPlan.swift ✓
grep -rn "group.com.reojacob.myhome" → ModelContainer+App.swift ✓
grep -rn "migrationPlan" → ModelContainer+App.swift ✓
grep -rn "en_IN" MyHomeApp/ → Decimal+INR.swift ✓
grep -rn "modelContainer" MyHomeApp/ → MyHomeApp.swift ✓
grep -rn "String(format:" MyHomeApp/Support/Decimal+INR.swift → only in comment ✓
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Tests missing Foundation import**

- **Found during:** Task 1 test run
- **Issue:** `ExpenseModelTests.swift` used `Decimal`, `Date`, and `FetchDescriptor` without importing `Foundation` — compile errors "cannot find 'Decimal' in scope".
- **Fix:** Added `import Foundation` to `ExpenseModelTests.swift`.
- **Files modified:** `MyHomeTests/ExpenseModelTests.swift`
- **Commit:** a668bd3 (included in Task 1 commit)

## TDD Gate Compliance

RED gate: Tests were written using `Expense` and `formattedINR()` before those types existed, causing compile failure (legitimate RED state — tests failed to compile, not just runtime). Proceeding to GREEN was correct after verifying the tests failed.

GREEN gate: All 4 tests pass after implementation (commit a668bd3 + 752d73a).

REFACTOR: No cleanup required — code is already minimal and idiomatic.

## Threat Surface Scan

No new threat surface beyond the plan's declared threat model:
- T-01-05 (VersionedSchema migration path): mitigated — `AppMigrationPlan` scaffolded from day one.
- T-01-04 (store at App Group URL): store URL set to App Group container; Application Support fallback inherits iOS Data Protection (Complete class by default). No downgrade.
- T-01-03 (amount input validation): accepted for this plan — documented for plan 03 keypad input boundary.
- Zero third-party packages — T-01-SC not applicable.

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| `v1StoreMigratesCleanly` | `MyHomeTests/MigrationTests.swift` | Requires seed store created in plan 04 — correctly remains RED |
| `RootView` placeholder | `MyHomeApp/RootView.swift` | ExpenseListView arrives in plan 03 |

## Self-Check: PASSED

Files exist:
- MyHomeApp/Persistence/Schema/SchemaV1.swift ✓
- MyHomeApp/Persistence/Schema/MigrationPlan.swift ✓
- MyHomeApp/Persistence/Models/Expense.swift ✓
- MyHomeApp/Persistence/ModelContainer+App.swift ✓
- MyHomeApp/Support/Decimal+INR.swift ✓
- MyHomeApp/Support/Date+Display.swift ✓

Commits exist:
- a668bd3 feat(01-02): Expense @Model + VersionedSchema v1 + ModelContainer factory ✓
- 752d73a feat(01-02): en-IN currency formatting + UTC date display helpers ✓
