---
phase: 02-categories-tags-budgets
audited: 2026-05-30
auditor: gsd-security-auditor
asvs_level: 1
block_on: high
threats_total: 16
threats_closed: 16
threats_open: 0
result: SECURED
---

# Phase 02 Security Audit

**Phase:** 02 — categories-tags-budgets
**ASVS Level:** 1
**Block on:** high
**Audit date:** 2026-05-30

## Threat Verification

| Threat ID | Category | Disposition | Status | Evidence |
|-----------|----------|-------------|--------|----------|
| T-02-01 | Tampering (data loss) | mitigate | CLOSED | `MigrationPlan.swift:8–9` — `schemas` = `[SchemaV1.self, SchemaV2.self]` (SchemaV1 never removed). `MigrationPlan.swift:19–24` — `MigrationStage.custom(willMigrate: nil, didMigrate: nil)` with FB13812722 comment. `MigrationTests.swift:38,53–55` — opens bundled v1 store under `SchemaV2` target, asserts `amount == 100`, `note == "Seed"`, `currencyCode == "INR"`. |
| T-02-02 | Tampering | mitigate | CLOSED | `ModelContainer+App.swift:65–68` — `FetchDescriptor<Category>()` with `fetchLimit = 1`, `guard existing.isEmpty else { return }` before any insert. `CategorySeedTests.swift:34–37` (seedIsIdempotent) verifies two calls yield exactly 14 categories. |
| T-02-03 | Tampering | accept | CLOSED | `SchemaV2.swift:38` — `var monthlyBudget: Decimal? = nil` (type is `Decimal`, not `Double`). Range guard `abs(amount) < Decimal(1_000_000_000)` enforced at `EditBudgetSheet.swift:172`. Accepted risk documented: model layer carries no range constraint by design; UI entry boundary is the declared enforcement point. |
| T-02-04 | Tampering | accept | CLOSED | `BudgetCalculator.swift:41–43` — `fractionUsed: Double?` is the sole `Double` in the file; `spent: Decimal`, `remaining: Decimal?`, and all aggregation in `monthlySpend`/`uncategorizedSpend` operate on `Decimal`. `remaining` and `spent` fields in `BudgetProgressData` are `Decimal` (`BudgetCalculator.swift:27–29`). Accepted risk documented: Double precision loss is limited to the visual progress bar; no money amount stored as Double. |
| T-02-05 | Tampering | mitigate | CLOSED | `BudgetCalculator.swift:42` — `guard let b = budget, b > 0 else { return nil }` in `fractionUsed`. `BudgetCalculatorTests.swift:109–119` (zeroBudgetGuard) — `BudgetProgressData(spent: 100, budget: 0).fractionUsed == nil`. |
| T-02-06 | Tampering | mitigate | CLOSED | `BudgetCalculator.swift:106–107` — `var cal = Calendar.current; cal.timeZone = TimeZone.current` before computing month start/end. Comment: `// T-02-06: user's timezone for correct month edges`. |
| T-02-07 | Spoofing/Tampering | mitigate | CLOSED | `CategoryPickerView.swift:64` — `Text(category.name ?? "")`. No `AttributedString(markdown:)` anywhere in the file. All 14 category ForEach rows use the same plain `Text` call. Comment at line 63 tags T-02-07. |
| T-02-08 | Tampering | mitigate | CLOSED | `AddExpenseView.swift:230` — `expense.categories = selectedCategory.map { [$0] } ?? []` (nil-safe map). `AddExpenseView.swift:232–241` — `try context.save()` in `do/catch` with `assertionFailure` on error. `EditExpenseView.swift:293,297` — same pattern on the edit path. |
| T-02-09 | Tampering | mitigate | CLOSED | `EditBudgetSheet.swift:167–173` — `guard let amount = parsedAmount, amount > 0` (non-positive guard), then `guard abs(amount) < Decimal(1_000_000_000)` (overflow guard). Both guards call `shakeAmount()` on failure and return without saving. |
| T-02-10 | Tampering | mitigate | CLOSED | `EditBudgetSheet.swift:179` — `try context.save()` on the save path; `EditBudgetSheet.swift:98` — `try context.save()` inside the `.confirmationDialog` destructive button (remove path). Remove is gated behind `showRemoveConfirmation = true` (line 141) + `confirmationDialog` dialog (lines 89–108). Both paths use explicit save with `assertionFailure` on catch. |
| T-02-11 | Spoofing/Tampering | mitigate | CLOSED | `BudgetCategoryCard.swift:30` — `Text(progressData.category.name ?? "")`. `EditBudgetSheet.swift:55` — `Text("for \(category.name ?? "")") `. No `AttributedString(markdown:)` call in either file. |
| T-02-12 | Tampering | mitigate | CLOSED | `ManageCategoriesView.swift:185` — `context.fetch(FetchDescriptor<Category>())` followed by `all.first { ($0.name ?? "").lowercased() == lower }` before insert. Duplicate returns `nameError = "A category with that name already exists."` without inserting (line 187–189). Rename path (lines 212–228) repeats the same lookup excluding self. No `@Attribute(.unique)` anywhere in `SchemaV2.swift`. |
| T-02-13 | Tampering | mitigate | CLOSED | `SchemaV2.swift:47` — `@Relationship(deleteRule: .nullify)` on `Category.expenses`. `ManageCategoriesView.swift:93–106` — `confirmationDialog("Delete Category?", …)` before `deleteCategory(_:)` is called. `ManageCategoriesView.swift:242–249` — `context.delete(category)` then `try context.save()` in `do/catch`. `CategoryCRUDTests.swift:deleteNullifiesExpenseLink` verifies nullify behavior. |
| T-02-14 | Tampering/DoS | mitigate | CLOSED | `FilteredExpenseListView.swift:29–34` — date-only `@Query` predicate (no relationship-contains). `FilteredExpenseListView.swift:40–44` — in-memory `.filter { $0.categories.contains(where: { $0.persistentModelID == catID }) }` fallback for category membership. `UncategorizedExpenseListView.swift:96–98` — same in-memory `.filter { $0.categories.isEmpty }` pattern. |
| T-02-15 | Spoofing/Tampering | mitigate | CLOSED | `CategoryPickerView.swift:64` — `Text(category.name ?? "")`. `BudgetCategoryCard.swift:30` — `Text(progressData.category.name ?? "")`. `EditBudgetSheet.swift:55` — `Text("for \(category.name ?? "")") `. `ManageCategoriesView.swift:160` — `Text(category.name ?? "")`. No `AttributedString(markdown:)` in any of the four rendering sites. |
| T-02-SC | n/a | n/a | CLOSED | Zero `XCRemoteSwiftPackageReference` entries in `project.pbxproj` (grep count: 0). All imports across implementation files are first-party: `SwiftUI`, `SwiftData`, `Foundation` only. |

## Accepted Risks

| Threat ID | Condition | Documented |
|-----------|-----------|------------|
| T-02-03 | `monthlyBudget` stored as `Decimal` at the model layer with no range constraint; range guard `abs < 1e9` is enforced exclusively at `EditBudgetSheet.saveBudget()`. Any future code path that writes `category.monthlyBudget` directly bypasses the UI guard. | Yes — declared accepted at plan time; UI boundary is the single enforcement point for this phase. |
| T-02-04 | `fractionUsed` converts `Decimal` to `Double` via `NSDecimalNumber`; precision loss is bounded to the visual progress bar fraction. No monetary amount is stored or computed as `Double`. | Yes — declared accepted at plan time; `remaining` and `spent` remain `Decimal` throughout. |

## Unregistered Flags

None. All five SUMMARY.md `## Threat Flags` sections report no new threat surface:
- 02-01-SUMMARY: "No new threat surface introduced beyond the plan's threat model."
- 02-02-SUMMARY: No Threat Flags section (implicitly none).
- 02-03-SUMMARY: No new threat surface beyond T-02-07/T-02-08.
- 02-04-SUMMARY: No new threat surface beyond T-02-09/T-02-10/T-02-11.
- 02-05-SUMMARY: "None — no new network endpoints, auth paths, file access patterns, or schema changes introduced in this plan."

## Verification Notes

- **T-02-03 scope caveat:** The `accept` disposition holds only while `EditBudgetSheet` is the sole write path for `category.monthlyBudget`. If a future plan adds a second write path, T-02-03 must be re-evaluated to confirm the range guard covers the new path.
- **T-02-12 rename path verified:** `saveRename(for:)` at `ManageCategoriesView.swift:206` runs the same case-insensitive lookup, excluding the category being renamed from the duplicate check (`$0.persistentModelID != category.persistentModelID`). Both add and rename paths are covered.
- **T-02-08 both sheets verified:** The nil-safe `selectedCategory.map { [$0] } ?? []` and `try context.save()` pattern was confirmed present in both `AddExpenseView.saveExpense()` (line 230, 232) and `EditExpenseView.saveExpense()` (line 293, 297).
