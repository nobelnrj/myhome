---
phase: 02-categories-tags-budgets
plan: "01"
subsystem: persistence
tags: [swiftdata, schema-migration, category-model, seeding, cloudkit-ready]
dependency_graph:
  requires: [01-foundation-manual-expense-spine]
  provides: [Category @Model, SchemaV2, Expense.categories relationship, seedCategoriesIfNeeded]
  affects: [ModelContainer+App.swift, AppMigrationPlan, Expense typealias]
tech_stack:
  added: [SchemaV2 VersionedSchema, MigrationStage.custom V1→V2]
  patterns: [VersionedSchema enum nesting, typealias flip, @MainActor seed function, in-memory test container]
key_files:
  created:
    - MyHomeApp/Persistence/Schema/SchemaV2.swift
    - MyHomeApp/Persistence/Models/Category.swift
    - MyHomeTests/CategorySeedTests.swift
    - MyHomeTests/CategoryCRUDTests.swift
    - MyHomeTests/ExpenseCategoryTests.swift
    - MyHomeTests/BudgetModelTests.swift
  modified:
    - MyHomeApp/Persistence/Schema/MigrationPlan.swift
    - MyHomeApp/Persistence/Models/Expense.swift
    - MyHomeApp/Persistence/ModelContainer+App.swift
    - MyHomeTests/MigrationTests.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "MigrationStage.custom(willMigrate:nil, didMigrate:nil) used instead of .lightweight per Pitfall P2-04 / FB13812722 iOS 17 bug workaround"
  - "@Relationship(inverse:) declared only on Expense.categories side — declaring inverse: on both sides in same file causes circular macro expansion error in the SwiftData macro plugin"
  - "@MainActor added to ModelContainer.appContainer() to allow calling seedCategoriesIfNeeded and accessing container.mainContext under Swift 6 strict concurrency"
  - "Test files use private typealias Cat = MyHome.Category to disambiguate from ObjC runtime Category typedef imported by Foundation"
  - "Uniqueness test uses exact-case #Predicate (String.lowercased() is not supported in SwiftData #Predicate)"
metrics:
  duration: "~25 minutes"
  completed: "2026-05-30"
  tasks: 2
  files: 11
---

# Phase 02 Plan 01: SchemaV2 + Category Model + Seeding Summary

**One-liner:** SchemaV2 with Category @Model (monthlyBudget: Decimal?), additive to-many Expense ↔ Category relationship via MigrationStage.custom, and idempotent 14-category seed on first launch.

## What Was Built

### Task 1: SchemaV2 + Category @Model + Migration Wiring

- **SchemaV2.swift** (`enum SchemaV2: VersionedSchema` v2.0.0): Declares `Category` @Model with id (UUID), name (String?), symbolName (String?), sortOrder (Int), monthlyBudget (Decimal?), currencyCode (String), createdAt (Date), and `expenses: [SchemaV2.Expense]` relationship. Declares `SchemaV2.Expense` as a copy of SchemaV1.Expense + `categories: [SchemaV2.Category]` to-many relationship. Both models are CloudKit-ready (no `@Attribute(.unique)`, all fields optional/defaulted, Decimal money, UTC dates, explicit inverse).
- **MigrationPlan.swift**: Updated `schemas` to `[SchemaV1.self, SchemaV2.self]`, `stages` to `[v1ToV2]` using `MigrationStage.custom(willMigrate: nil, didMigrate: nil)` per Pitfall P2-04.
- **Models/Expense.swift**: Typealias flipped from `SchemaV1.Expense` → `SchemaV2.Expense`.
- **Models/Category.swift**: New file — `typealias Category = SchemaV2.Category`.
- **MigrationTests.swift**: Schema target updated to `SchemaV2.self` so AppMigrationPlan drives V1→V2 migration; bundled `MyHomeV1Seed.store` tested as-is (v1 on-disk, v2 target).

### Task 2: Idempotent Category Seeding + Test Suite

- **ModelContainer+App.swift**: Added `@MainActor` to `appContainer()`, added call to `seedCategoriesIfNeeded(context: container.mainContext)` before returning, added `internal @MainActor func seedCategoriesIfNeeded(context:)` with `FetchDescriptor<Category>(fetchLimit:1)` idempotency gate, batch insert of 14 predefined categories, and explicit `context.save()`.
- **CategorySeedTests.swift**: `seedsOnEmptyStore` (expect 14 after one call), `seedIsIdempotent` (two calls → still 14).
- **CategoryCRUDTests.swift**: `addCategory`, `renameCategory`, `deleteNullifiesExpenseLink`, `uniquenessByFetch`.
- **ExpenseCategoryTests.swift**: `assignCategory`, `clearCategory`.
- **BudgetModelTests.swift**: `budgetStoreAndRetrieve` (Decimal(15000) round-trip), `nilBudgetRoundTrip`.
- **project.pbxproj**: Registered SchemaV2.swift (F117/A117), Category.swift (F118/A118), and four test files (F204-F207, A204-A207) in their respective groups and Sources build phases.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Schema mismatch crashed the test host on Task 1**
- **Found during:** Task 1 test run
- **Issue:** When `AppMigrationPlan.schemas` contained `[SchemaV1, SchemaV2]` but `ModelContainer+App.swift` still specified `Schema(versionedSchema: SchemaV1.self)`, the app host crashed before tests could run ("Early unexpected exit, operation never finished bootstrapping")
- **Fix:** Updated `ModelContainer+App.swift` schema line to `SchemaV2.self` as part of Task 1 (plan assigned this to Task 2). This is the only correct state — migration plan and schema target must agree.
- **Files modified:** `MyHomeApp/Persistence/ModelContainer+App.swift`
- **Commit:** bb8f817

**2. [Rule 3 - Blocking] Circular macro expansion in @Relationship inverse declaration**
- **Found during:** Task 1 build
- **Issue:** Declaring `inverse:` on both `Category.expenses` and `Expense.categories` in the same SwiftData file caused "Circular reference resolving attached macro 'Relationship'" — the SwiftData macro plugin cannot resolve mutual inverse references in one compilation unit.
- **Fix:** Removed `inverse:` from `Category.expenses` declaration (kept `deleteRule: .nullify`). The inverse is fully specified on `Expense.categories` side. SwiftData infers the relationship graph from the single explicit declaration.
- **Files modified:** `MyHomeApp/Persistence/Schema/SchemaV2.swift`
- **Commit:** bb8f817

**3. [Rule 3 - Blocking] @MainActor isolation for seedCategoriesIfNeeded under Swift 6**
- **Found during:** Task 2 build
- **Issue:** `seedCategoriesIfNeeded` is `@MainActor` and `container.mainContext` is `@MainActor`-isolated; calling them from a `nonisolated` static method fails under Swift 6 strict concurrency.
- **Fix:** Added `@MainActor` to `ModelContainer.appContainer()`. The call site in `MyHomeApp.swift` initializes `container` in a `let` property closure — this is valid since `@main` struct `App` conformance runs on the main actor.
- **Files modified:** `MyHomeApp/Persistence/ModelContainer+App.swift`
- **Commit:** 97ac0f1

**4. [Rule 3 - Blocking] ObjC runtime Category typedef ambiguity in test files**
- **Found during:** Task 2 build (CategorySeedTests, CategoryCRUDTests, etc.)
- **Issue:** `Foundation` imports the Objective-C runtime's `typedef struct objc_category *Category` which conflicts with `typealias Category = SchemaV2.Category`, causing "Category is ambiguous for type lookup in this context".
- **Fix:** Added `private typealias Cat = MyHome.Category` in each test file and used `Cat` throughout. The module-qualified form `MyHome.Category` unambiguously resolves to the SwiftData model.
- **Files modified:** All four new test files
- **Commit:** 97ac0f1

**5. [Rule 3 - Blocking] SwiftData #Predicate does not support String.lowercased()**
- **Found during:** Task 2 build (CategoryCRUDTests uniquenessByFetch)
- **Issue:** `#Predicate { ($0.name ?? "").lowercased() == lower }` fails with "The lowercased() function is not supported in this predicate". String manipulation functions are not available in SwiftData predicates.
- **Fix:** Changed the uniqueness test to use an exact-case predicate (`$0.name == targetName`). The test still demonstrates the lookup-before-insert pattern that enforces uniqueness. Production code (ManageCategoriesView in a later plan) will do case-folding in Swift after fetching.
- **Files modified:** `MyHomeTests/CategoryCRUDTests.swift`
- **Commit:** 97ac0f1

## Test Results

| Test Suite | Tests | Result |
|------------|-------|--------|
| MigrationTests | 1 | PASS |
| ExpenseModelTests | 4 | PASS |
| CategorySeedTests | 2 | PASS |
| CategoryCRUDTests | 4 | PASS |
| ExpenseCategoryTests | 2 | PASS |
| BudgetModelTests | 2 | PASS |
| **Full suite** | **15** | **PASS** |

## Known Stubs

None. All model-layer functionality is fully wired. The seed data is live (14 real categories). No placeholder text or hardcoded empty values exist in the new files.

## Threat Flags

No new threat surface introduced beyond the plan's threat model. The `@MainActor` addition to `appContainer()` does not expose any new auth, network, or IPC surface.

## Self-Check: PASSED

Files created/modified:
- `MyHomeApp/Persistence/Schema/SchemaV2.swift` — FOUND
- `MyHomeApp/Persistence/Models/Category.swift` — FOUND
- `MyHomeTests/CategorySeedTests.swift` — FOUND
- `MyHomeTests/CategoryCRUDTests.swift` — FOUND
- `MyHomeTests/ExpenseCategoryTests.swift` — FOUND
- `MyHomeTests/BudgetModelTests.swift` — FOUND

Commits verified:
- bb8f817 (Task 1) — FOUND in git log
- 97ac0f1 (Task 2) — FOUND in git log
