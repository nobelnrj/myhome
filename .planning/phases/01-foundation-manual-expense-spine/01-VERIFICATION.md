---
phase: 01-foundation-manual-expense-spine
verified: 2026-05-29T11:10:00Z
status: passed
human_verified: 2026-05-29T11:08:00Z
human_verified_note: "All 5 runtime UAT items (cold-launch persistence, en-IN lakh rendering, <=3-tap add, edit flow, both delete paths) approved by the user on 2026-05-29. See 01-HUMAN-UAT.md."
score: 5/5
overrides_applied: 0
human_verification:
  - test: "Run app on iOS 17+ simulator or device; add an expense using the custom keypad and verify it persists after app termination"
    expected: "The new expense appears in the list after cold-starting the app again, confirming on-device SwiftData persistence across termination events"
    why_human: "grep cannot simulate a process kill + relaunch cycle; autosave timing and file-system flush are only observable at runtime"
  - test: "Add an expense with amount 100000; confirm the formatted display shows the lakh grouping symbol (₹1,00,000.00) with the correct rupee symbol"
    expected: "Amount renders as ₹1,00,000.00 (en-IN lakh grouping), not ₹100,000.00 (Western thousand grouping)"
    why_human: "The unit test asserts the substring '1,00,000' and the '₹' character (currencyFormatting PASSED), but visual correctness of the rendered cell in a live simulator — including font, color, and exact symbol — requires a human eye. The PLAN itself gates this on device verification (Plan 03 Task 3 checkpoint)."
  - test: "Perform the <=3-tap add-expense flow: tap '+' (tap 1), type an amount on the custom keypad (tap 2 counts only as entering digits), tap 'Save Expense' (tap 3). Confirm the new row appears at the top of the list."
    expected: "User completes add in exactly 3 taps or fewer; new expense appears at top of reverse-chronological list. Custom keypad is visible without invoking the system keyboard."
    why_human: "Tap-count and custom-keypad-only policy cannot be verified by grep or build checks alone; a human must observe the UI flow on a running simulator or device."
  - test: "Tap a row, edit the amount, tap 'Save Expense'. Verify the updated amount appears in the list (EXP-02)."
    expected: "Edited expense shows the new amount; updatedAt is advanced."
    why_human: "End-to-end edit flow through the running app; specifically confirms @Bindable live-editing and save round-trip are correct on a real container."
  - test: "Swipe a row to delete it. Then add another expense, open it in the Edit sheet, tap 'Delete Expense', confirm the action sheet. Confirm both rows are gone (EXP-03)."
    expected: "Both delete paths (swipe and Edit-sheet confirmed delete) remove the expense from the list and from the persistent store."
    why_human: "Two delete code paths and their explicit context.save() calls; correct behaviour requires runtime observation including the confirmationDialog dismissal sequence."
---

# Phase 01: Foundation Manual Expense Spine — Verification Report

**Phase Goal:** A user can add, edit, and delete a manual expense end-to-end on a CloudKit-ready SwiftData spine, with all immutable lock-in decisions made on day one.
**Verified:** 2026-05-29T11:10:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User can add a manual expense (open → amount keypad → save) and see it in list in <=3 taps | VERIFIED (automated partial) / human_needed (runtime) | AddExpenseView.swift: `saveExpense()` calls `context.insert(expense)` + `try context.save()` + `dismiss()`. DecimalKeypadView always visible, no system keyboard. ExpenseListView uses `@Query(sort: \Expense.date, order: .reverse)`. Build SUCCEEDED. Runtime tap-count and persistence-across-termination require human check. |
| 2 | User can edit and delete any expense they created | VERIFIED (automated partial) / human_needed (runtime) | EditExpenseView.swift: `@Bindable var expense`, `saveExpense()` writes back + `try context.save()`, `deleteExpense()` calls `context.delete` + `try context.save()`. SwipeDelete path in ExpenseListView also calls `try context.save()`. Confirmation dialog present. Runtime flow requires human check. |
| 3 | Currency renders in en-IN format (₹1,00,000.00), money stored as Decimal, dates stored UTC | VERIFIED | `currencyFormatting` test PASSED (live run 2026-05-29). SchemaV1.swift: `amount: Decimal`, `date: Date = Date()` (UTC). `Decimal+INR.swift`: `.currency(code: "INR").locale(Locale(identifier: "en_IN"))`. No `Double` in `MyHomeApp/Persistence/`. Visual rendering needs human check (SC#3 automated portion is green). |
| 4 | Every @Model type passes reflection-based test asserting all properties are optional/defaulted with no @Attribute(.unique), AND the VersionedSchema migration plan loads a bundled v1 store successfully | VERIFIED | `expensePropertiesAreCloudKitReady` PASSED: uses `entity.attributes` loop asserting `isOptional || hasDefault` — real non-tautological assertions (CR-02 fixed). `entity.uniquenessConstraints.isEmpty` asserted. `v1StoreMigratesCleanly` PASSED: opens real 69 KB SQLite v1 store via `AppMigrationPlan`, asserts non-empty fetch with seed values `amount=100, note="Seed", currencyCode="INR"`. Full test suite: ** TEST SUCCEEDED ** (5/5 tests). |
| 5 | App targets iOS 17+ on Swift 6 strict concurrency / SwiftUI / SwiftData with PrivacyInfo.xcprivacy declaring required-reason APIs and NSPrivacyTracking false | VERIFIED | pbxproj: `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_VERSION = 6.0`. PrivacyInfo.xcprivacy: `NSPrivacyTracking = false`, `NSPrivacyAccessedAPICategoryUserDefaults / CA92.1`, `NSPrivacyAccessedAPICategoryFileTimestamp / C617.1`. Zero `@StateObject/@ObservedObject/@Published` in MyHomeApp/. `PRODUCT_BUNDLE_IDENTIFIER = com.reojacob.myhome`. |

**Score:** 4/5 truths VERIFIED by automated checks. Truth 1 and 2 are substantively implemented and wired; they remain in human_needed only for the on-device runtime portions their PLAN explicitly gates on a human-verify checkpoint.

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `MyHomeApp/Resources/PrivacyInfo.xcprivacy` | Required-reason API manifest | VERIFIED | NSPrivacyTracking false, CA92.1, C617.1 — exact values present |
| `MyHomeApp/Persistence/Schema/SchemaV1.swift` | VersionedSchema v1 with Expense @Model | VERIFIED | `enum SchemaV1: VersionedSchema`, `Schema.Version(1, 0, 0)`, all 8 CloudKit-readiness rules applied |
| `MyHomeApp/Persistence/Schema/MigrationPlan.swift` | SchemaMigrationPlan with empty stages | VERIFIED | `enum AppMigrationPlan: SchemaMigrationPlan`, `stages = []` |
| `MyHomeApp/Persistence/Models/Expense.swift` | typealias Expense = SchemaV1.Expense | VERIFIED | `typealias Expense = SchemaV1.Expense` present |
| `MyHomeApp/Persistence/ModelContainer+App.swift` | appContainer() factory | VERIFIED | `Schema(versionedSchema: SchemaV1.self)`, App Group URL + fallback, `migrationPlan: AppMigrationPlan.self`, `cloudKitDatabase: .none` |
| `MyHomeApp/Support/Decimal+INR.swift` | en-IN currency formatting | VERIFIED | `en_IN`, `.currency(code: "INR")`, FormatStyle not NumberFormatter |
| `MyHomeApp/Support/Date+Display.swift` | UTC-store / local-display date helpers | VERIFIED | `formattedForExpenseList()` + `formattedForDatePickerRow()` present |
| `MyHomeApp/Features/Expenses/DecimalKeypadView.swift` | Custom always-visible 3-col keypad | VERIFIED | `displayString` binding, `LazyVGrid`, `handleKey()`, no `keyboardType` |
| `MyHomeApp/Features/Expenses/AddExpenseView.swift` | Add sheet with keypad and Save Expense | VERIFIED | "Save Expense", "Cancel", `DecimalKeypadView`, `plus.slash.minus`, `try context.save()`, guard abs < 1_000_000_000 |
| `MyHomeApp/Features/Expenses/ExpenseListView.swift` | @Query list with swipe-delete + sheets | VERIFIED | `@Query(sort: \Expense.date, order: .reverse)`, `.onDelete(perform:)`, `try context.save()`, ContentUnavailableView |
| `MyHomeApp/Features/Expenses/ExpenseRow.swift` | Row rendering formattedINR + systemGreen negative | VERIFIED | `expense.amount.formattedINR()`, `.systemGreen` for `amount < 0`, `accessibilityElement(children: .combine)` |
| `MyHomeApp/Features/Expenses/EditExpenseView.swift` | Edit sheet with @Bindable + destructive Delete | VERIFIED | `@Bindable var expense`, "Edit Expense", "Save Expense", "Delete Expense", confirmationDialog "Delete Expense?", `try context.save()` on both save and delete paths |
| `MyHomeTests/ExpenseModelTests.swift` | 4 green model/format tests | VERIFIED | All 4 tests PASSED on iPhone 17 (2026-05-29 live run) |
| `MyHomeTests/MigrationTests.swift` | v1StoreMigratesCleanly green | VERIFIED | Test PASSED; real SQLite store loaded via AppMigrationPlan |
| `MyHomeTests/Resources/MyHomeV1Seed.store` | Bundled v1 seed store | VERIFIED | Real 69 KB SQLite 3.x file, schema 4, 17 pages; confirmed in test target Copy Bundle Resources (A203 in pbxproj P004) |
| `MyHomeApp/MyHome.entitlements` | App Group entitlement | VERIFIED | `com.apple.security.application-groups = group.com.reojacob.myhome` |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `MyHomeApp.swift` | `ModelContainer.appContainer()` | `.modelContainer(container)` | WIRED | `container = try ModelContainer.appContainer()` + `.modelContainer(container)` on WindowGroup |
| `Expense @Model` | `SchemaV1.models + ModelContainer schema` | `Schema(versionedSchema: SchemaV1.self)` | WIRED | `ModelContainer+App.swift:17: let schema = Schema(versionedSchema: SchemaV1.self)` |
| `ExpenseListView` | `modelContext.insert / .delete` | `modelContext` writes + `@Query` reads | WIRED | `context.insert(expense)` in Add, `context.delete` in swipe + Edit; `try context.save()` on all paths (CR-01) |
| `AddExpenseView amount field` | `DecimalKeypadView displayString parsed to Decimal on Save` | `amountString @State binding` | WIRED | `DecimalKeypadView(displayString: $amountString)` + `Decimal(string: amountString)` in `parsedAmount` |
| `Decimal+INR.swift` | `ExpenseRow amount display` | `expense.amount.formattedINR()` | WIRED | `Text(expense.amount.formattedINR())` in ExpenseRow.swift |
| `MigrationTests.v1StoreMigratesCleanly` | `AppMigrationPlan + SchemaV1` | `ModelContainer(for:migrationPlan:configurations:)` over bundled store | WIRED | Test opens temp copy of `MyHomeV1Seed.store` via `AppMigrationPlan`; asserts non-empty fetch |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `ExpenseListView` | `expenses: [Expense]` via `@Query` | SwiftData `ModelContainer` (production: `appContainer()`; tests: in-memory) | Yes — `@Query` drives live SwiftData fetch | FLOWING |
| `ExpenseRow` | `expense.amount`, `expense.note`, `expense.date` | `Expense @Model` fetched by parent `@Query` | Yes — props come directly from persisted model | FLOWING |
| `AddExpenseView` | `amountString`, `date`, `note` → `Expense(amount:date:note:)` | User keypad input → `context.insert` + `try context.save()` | Yes — real insert with explicit save | FLOWING |
| `EditExpenseView` | `expense.amount`, `.date`, `.note`, `.updatedAt` | `@Bindable expense` from `@Query`-sourced parent + `try context.save()` | Yes — real mutate with explicit save | FLOWING |
| `MigrationTests` | `expenses: [Expense]` | Bundled `MyHomeV1Seed.store` (real 69 KB SQLite) via `AppMigrationPlan` | Yes — seed data verified in assertions | FLOWING |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full test suite passes | `xcodebuild test -scheme MyHome -only-testing:MyHomeTests -destination 'platform=iOS Simulator,name=iPhone 17'` | ** TEST SUCCEEDED ** — 5/5 tests passed | PASS |
| App builds | Implicit from test run above | BUILD SUCCEEDED (test implies build) | PASS |
| No forbidden property wrappers | `grep -rn "@StateObject\|@ObservedObject\|@Published" MyHomeApp/` | Zero results | PASS |
| No @Attribute(.unique) in source | `grep -rn "@Attribute(.unique)" MyHomeApp/` | Only comment lines, zero actual usage | PASS |
| No Double money | `grep -rn ": Double" MyHomeApp/Persistence/` | Zero results | PASS |
| No system keyboard in Features | `grep -rn "keyboardType" MyHomeApp/Features/Expenses/` (non-comment) | Zero results | PASS |
| context.save() on all write paths | grep across Add/Edit/List .swift | 4 occurrences across 3 files (CR-01 confirmed) | PASS |
| CR-02 non-tautological test | grep `isOptional \|\| hasDefault` + `entity.attributes` loop | Real schema-metadata assertions present; tautology `isOptional \|\| !isOptional` removed | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| FND-01 | 01-01 | iOS 17+ / Swift 6.2 / SwiftUI / SwiftData | SATISFIED | `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete` in pbxproj |
| FND-02 | 01-01 | Bundle/CloudKit/App Group IDs locked on day one | SATISFIED | `com.reojacob.myhome`, `group.com.reojacob.myhome`, `iCloud.com.reojacob.myhome` committed in pbxproj and entitlements |
| FND-03 | 01-02 | 8 CloudKit-readiness rules on every @Model | SATISFIED | SchemaV1.Expense: all properties optional/defaulted, no @Attribute(.unique), Decimal money, UTC dates, UUID PK, currencyCode, no enums, no Codable blobs. `expensePropertiesAreCloudKitReady` PASSED with real schema-entity assertions (CR-02 resolved) |
| FND-04 | 01-01 | PrivacyInfo.xcprivacy with NSPrivacyTracking false + CA92.1 / C617.1 | SATISFIED | File present in Copy Bundle Resources; contains all required keys |
| FND-05 | 01-02, 01-04 | VersionedSchema + SchemaMigrationPlan scaffolded from v1.0 | SATISFIED | `SchemaV1: VersionedSchema`, `AppMigrationPlan: SchemaMigrationPlan`, bundled seed store loads cleanly via migration plan; `v1StoreMigratesCleanly` PASSED |
| FND-06 | 01-01, 01-02 | Swift Testing with in-memory ModelContainer for test fixtures | SATISFIED | `@Test` functions throughout; `ModelConfiguration(isStoredInMemoryOnly: true)` in `makeContainer()`; no XCTest base class |
| FND-07 | 01-02 | en-IN currency formatting (₹1,00,000.00); dates stored UTC, displayed user locale | SATISFIED (automated) + NEEDS HUMAN (visual) | `Decimal+INR.swift` uses `en_IN` FormatStyle. `currencyFormatting` test PASSED asserting lakh grouping. Visual rendering: human check below |
| EXP-01 | 01-03 | User can add a manual expense in <=4 taps (REQUIREMENTS.md says <=4; PLAN says <=3; both satisfied) | SATISFIED (code) + NEEDS HUMAN (tap count, persistence) | AddExpenseView full implementation with `try context.save()`. Human check below. Note: absence of category step is correct per phase 1 scope |
| EXP-02 | 01-03 | User can edit any expense | SATISFIED (code) + NEEDS HUMAN (runtime flow) | EditExpenseView with `@Bindable`, `saveExpense()` + `try context.save()`. Human check below |
| EXP-03 | 01-03 | User can delete any expense | SATISFIED (code) + NEEDS HUMAN (runtime flow) | Both swipe-delete (ExpenseListView) and confirmed delete button (EditExpenseView) with `try context.save()`. Human check below |

All 10 required Phase 1 requirements are satisfied in code. EXP-01/02/03 and the visual portion of FND-07 additionally require human runtime verification per the Plan 03 blocking human-verify checkpoint.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `ModelContainer+App.swift` | 15, 25 | `TODO: migrate to App Group URL when paid account active` | Info | Not a debt marker blocker — these are documented, intentional, deferred-to-paid-upgrade items. No `TBD`, `FIXME`, or `XXX` anywhere in the codebase. |
| `AddExpenseView.swift` | 209 | `DispatchQueue.main.asyncAfter` for shake timer (WR-02) | Warning | Timer not cancelled if view dismisses; code smell but not a must-have blocker. Documented in code review as WR-02. |
| `EditExpenseView.swift` | 220-223 | `String(describing: amount)` for round-trip (WR-01/WR-07) | Warning | Locale-fragile for values with > 2 fractional places; POSIX locale issue. Documented in code review as WR-01, WR-07. Not a Phase 1 goal blocker (no import path in v1; keypad enforces 2 decimal places on new entries). |
| `ModelContainer+App.swift` | 27 | `FileManager...urls.first!` force-unwrap (WR-04) | Warning | `.applicationSupportDirectory` path always non-empty on iOS; low crash risk but not graceful. Documented as WR-04. |

No `TBD`, `FIXME`, or `XXX` debt markers found. All `TODO` comments reference documented, specific deferred work. No blockers from debt-marker gate.

---

### Code Review Critical Issues — Confirmation

Both critical issues from `01-REVIEW.md` are confirmed resolved in the actual code:

**CR-01 (context.save() missing on writes) — CONFIRMED RESOLVED**

Verified by grep — `try context.save()` is present in all four write paths:
- `AddExpenseView.saveExpense()` line 192: `try context.save()` after `context.insert`
- `EditExpenseView.saveExpense()` line 254: `try context.save()` after field mutation
- `EditExpenseView.deleteExpense()` line 270: `try context.save()` after `context.delete`
- `ExpenseListView.deleteExpenses(at:)` line 75: `try context.save()` after delete loop

Each failure path calls `assertionFailure` + `print` and does NOT dismiss, so a failed write cannot be silently treated as success.

**CR-02 (CloudKit-readiness test was a tautology) — CONFIRMED RESOLVED**

The `expensePropertiesAreCloudKitReady` test no longer contains `isOptional || !isOptional`. It now:
1. Retrieves the `Schema.Entity` named "Expense" from a real `ModelContainer`
2. Loops over `entity.attributes` asserting `attribute.isOptional || (attribute.defaultValue != nil)` — genuinely falsifiable
3. Asserts `entity.uniquenessConstraints.isEmpty`
4. Asserts `type(of: expense.amount) == Decimal.self` and default values

This test passed on the live run and would fail if a non-optional, default-less attribute or a `@Attribute(.unique)` were introduced.

---

### Human Verification Required

The Plan 03 blocking `checkpoint:human-verify` task explicitly deferred these items to human review. They cover on-device runtime behaviour that cannot be verified programmatically.

#### 1. On-Device Persistence Across App Termination

**Test:** Run the app in a simulator, add one expense via the custom keypad, background the app, then terminate it from the task switcher (or via Xcode stop). Cold-launch again.
**Expected:** The expense appears in the list after cold restart, confirming the explicit `try context.save()` has flushed to the SwiftData store on disk.
**Why human:** Process-kill/relaunch cycle cannot be scripted in a build-time check; only observable at runtime.

#### 2. en-IN Lakh Grouping Visual Rendering

**Test:** Add an expense with amount 100000 (type "1", "0", "0", "0", "0", "0" on the keypad). Observe the amount displayed in the Add sheet and after saving in the list row.
**Expected:** Display shows `₹1,00,000.00` (lakh grouping with Indian comma placement), not `₹100,000.00` (Western grouping). Unit test asserts the substring but not the visual cell layout.
**Why human:** Font rendering, symbol alignment, and exact locale output in a live iOS context are beyond grep/build verification.

#### 3. <=3-Tap Add Flow and Custom Keypad Policy

**Test:** From the expense list, tap "+" (tap 1), type an amount using only the always-visible custom keypad — confirm the system keyboard never appears (tap 2 = digit entry), tap "Save Expense" (tap 3). Confirm new row appears at top of list.
**Expected:** Add flow completes in 3 taps; system keyboard is never shown; new expense is at top (reverse-chronological order).
**Why human:** Tap-count policy and keyboard-suppression are UI-mode behaviours not verifiable without a running simulator.

#### 4. Edit Flow End-to-End (EXP-02)

**Test:** Tap an existing expense row. Modify the amount (backspace, type new value). Tap "Save Expense". Verify the row reflects the new amount.
**Expected:** Updated amount shown; `updatedAt` advanced. No stale display.
**Why human:** @Bindable live-binding and save round-trip correctness requires running app observation.

#### 5. Both Delete Paths (EXP-03)

**Test:** (a) Swipe an expense row to the left and tap Delete. (b) Add a second expense, open it, tap the red "Delete Expense" button, confirm the "Delete Expense?" action sheet. Verify both expenses are gone.
**Expected:** Both delete paths remove the expense permanently. The `confirmationDialog` sheet appears with correct title and actions.
**Why human:** Two runtime UI flows (swipe gesture + confirmationDialog sequence) require human observation to confirm correct dismissal ordering and persistent deletion.

---

### Gaps Summary

No blocking gaps. All must-haves are satisfied in the codebase:

- All 5 success criteria are implemented and wired with substantive, non-stub code.
- Both critical code-review issues (CR-01: missing `context.save()`; CR-02: tautological reflection test) are confirmed resolved and verified by a live test run.
- The full 5-test suite runs green on iPhone 17 simulator as of 2026-05-29.
- All 10 Phase 1 requirement IDs (FND-01 through FND-07, EXP-01 through EXP-03) are satisfied in code.

The `human_needed` status reflects the Plan 03 blocking `checkpoint:human-verify` task explicitly requiring on-device runtime verification of the add/edit/delete flows and en-IN visual rendering. These are not code gaps — they are runtime correctness checks that require a human to operate the running app.

Warnings from the code review (WR-01 through WR-07) are documented and are not Phase 1 goal blockers. They are improvement items for future maintenance.

---

_Verified: 2026-05-29T11:10:00Z_
_Verifier: Claude (gsd-verifier)_
