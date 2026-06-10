# Phase 10: Self-Transfer Detection - Pattern Map

**Mapped:** 2026-06-10
**Files analyzed:** 12 new/modified files
**Analogs found:** 12 / 12

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `MyHomeApp/Features/Gmail/TransferDetectionScorer.swift` | utility (pure helper) | transform | `MyHomeApp/Features/Gmail/AccountAttributionHelper.swift` | exact |
| `MyHomeApp/Features/Gmail/TransferScanService.swift` | service | event-driven | `MyHomeApp/Features/Notes/RoutineResetService.swift` | exact |
| `MyHomeApp/Features/Expenses/TransferPairRow.swift` | component | request-response | `MyHomeApp/Features/Expenses/ReviewInboxRow.swift` | exact |
| `MyHomeApp/Features/Expenses/ReviewInboxRow.swift` *(modify)* | component | request-response | self | exact |
| `MyHomeApp/Features/Expenses/ExpenseListView.swift` *(modify)* | component | CRUD | self — `AccountFilter` enum | exact |
| `MyHomeApp/Features/Expenses/EditExpenseView.swift` *(modify)* | component | CRUD | self — `optionalSection`/`saveExpense` | exact |
| `MyHomeApp/Support/BudgetCalculator.swift` *(modify)* | utility | transform | self — `monthlySpend`/`uncategorizedSpend` | exact |
| `MyHomeApp/Support/SpendOverTimeAggregator.swift` *(modify)* | utility | transform | self — `bucket(expenses:range:calendar:)` | exact |
| `MyHomeApp/Support/OverviewAggregation.swift` *(modify)* | utility | transform | `MyHomeApp/Support/BudgetCalculator.swift` | role-match |
| `MyHomeApp/Support/AccountBalance.swift` *(modify — verify only)* | utility | transform | self — `compute` | exact |
| `MyHomeApp/Features/Gmail/GmailSyncController.swift` *(modify)* | service | event-driven | self — `syncAccount` / `setContext` | exact |
| `MyHomeTests/TransferDetectionScorerTests.swift` | test | batch | `MyHomeTests/AccountTypeInferenceTests.swift` | exact |
| `MyHomeTests/TransferScanServiceTests.swift` | test | batch | `MyHomeTests/AccountBalanceTests.swift` | exact |
| `MyHomeTests/AccountBalanceTransferTests.swift` | test | batch | `MyHomeTests/AccountBalanceTests.swift` | exact |

---

## Pattern Assignments

### `MyHomeApp/Features/Gmail/TransferDetectionScorer.swift` (utility, transform)

**Analog:** `MyHomeApp/Features/Gmail/AccountAttributionHelper.swift`

**Imports pattern** (lines 1):
```swift
import Foundation
```

**Core pure-enum shape** (AccountAttributionHelper.swift lines 19–51):
```swift
enum AccountAttributionHelper {
    static func buildAccountIDsByLabel(from accounts: [Account]) -> [String: UUID] { ... }
    static func accountID(forSourceLabel label: String, in map: [String: UUID]) -> UUID? { ... }
}
```
Mirror this exactly: `enum TransferDetectionScorer` with only `static func` methods, no stored properties, no SwiftData imports, no `@Model` references. All inputs and outputs are value types (`[Expense]`, `UUID`, `Calendar`, `[CandidatePair]`).

**Header comment pattern** (AccountAttributionHelper.swift lines 1–18):
```swift
/// Pure helper for mapping a parsed sourceLabel (from a bank email) to an Account UUID.
///
/// Design (D-05, STAB-02):
/// - Operates on plain `[Account]` values — no @Model refs held.
/// - All outputs are `UUID` scalars — safe to capture before an `await` suspension.
```
Apply the same doc-comment style: cite the decision numbers, call out the STAB safety guarantee explicitly.

**Decimal grouping / abs() rule:**
```swift
// CORRECT — group credits by abs(credit.amount), look up by debit.amount (positive)
var creditsByAmount: [Decimal: [Expense]] = [:]
for credit in credits {
    creditsByAmount[abs(credit.amount), default: []].append(credit)
}
// Tie-break secondary key — mirrors OverviewAggregation.topCategories UUID sort:
// credit.id.uuidString ascending (stable total order)
```

**IST calendar — inject for testability:**
```swift
static func findCandidatePairs(
    from expenses: [Expense],
    calendar: Calendar    // inject; caller passes an IST Calendar
) -> [CandidatePair] { ... }

static func istDayDistance(_ a: Date, _ b: Date, calendar: Calendar) -> Int {
    let dayA = calendar.startOfDay(for: a)
    let dayB = calendar.startOfDay(for: b)
    return abs(calendar.dateComponents([.day], from: dayA, to: dayB).day ?? Int.max)
}
```

---

### `MyHomeApp/Features/Gmail/TransferScanService.swift` (service, event-driven)

**Analog:** `MyHomeApp/Features/Notes/RoutineResetService.swift`

**Imports pattern** (RoutineResetService.swift lines 1–3):
```swift
import Foundation
import SwiftData
```

**Class declaration + modelContext injection** (RoutineResetService.swift lines 18–23):
```swift
@MainActor
@Observable
final class RoutineResetService {
    // Injected by RootView.onAppear (same pattern as gmailSyncController.setContext — RootView line 86)
    var modelContext: ModelContext?
```
Mirror exactly: `@MainActor @Observable final class TransferScanService` with `var modelContext: ModelContext?`.

**IST calendar construction** (RoutineResetService.swift lines 27–29):
```swift
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!   // IST — household timezone
let startOfTodayIST = cal.startOfDay(for: Date())
```
Use this exact pattern. Pass `cal` into `TransferDetectionScorer.findCandidatePairs(from:calendar:)`.

**Fetch-then-filter-in-Swift pattern (STAB-08)** (RoutineResetService.swift lines 33–35):
```swift
let notes = try context.fetch(
    FetchDescriptor<Note>(predicate: #Predicate { $0.isDailyRoutine == true })
)
```
**Do NOT copy the predicate** — `isDailyRoutine` is `Bool` (non-optional), STAB-08 only applies to `Bool?`. For `isTransfer: Bool?` use:
```swift
// STAB-08 safe: fetch all, filter in Swift — do NOT use #Predicate on Bool?
let all = try context.fetch(FetchDescriptor<Expense>())
let candidates = all.filter { $0.isTransfer == nil }
```

**Explicit save pattern (CR-01)** (RoutineResetService.swift lines 53):
```swift
if didChange { try context.save() }   // CR-01: explicit save
```
For `TransferScanService`, save is always needed after writing `transferPairID` pairs — use `try context.save()` unconditionally after the loop (pairs may be zero but save is cheap; or guard on `!pairs.isEmpty`).

**Error handling** (RoutineResetService.swift lines 55–57):
```swift
} catch {
    // Non-fatal: log and return — never crash the app on scene activation (T-09-14)
    print("[RoutineResetService] reset failed: \(error)")
}
```
Use `print("[TransferScanService] scan failed: \(error)")`.

**sync() is synchronous — no `async`** (Pitfall 5): mirrors `resetIfNeeded()` which has no `await`. All work is synchronous within `@MainActor`.

---

### `MyHomeApp/Features/Expenses/TransferPairRow.swift` (component, request-response)

**Analog:** `MyHomeApp/Features/Expenses/ReviewInboxRow.swift`

**Imports + struct declaration** (ReviewInboxRow.swift lines 1–4, 16–19):
```swift
import SwiftUI
import SwiftData

struct ReviewInboxRow: View {
    let expense: Expense
    @Environment(\.modelContext) private var context
```
Mirror: `struct TransferPairRow: View` with `let debit: Expense`, `let credit: Expense`, `@Environment(\.modelContext) private var context`.

**VStack + HStack layout skeleton** (ReviewInboxRow.swift lines 24–50):
```swift
VStack(alignment: .leading, spacing: 4) {
    HStack(alignment: .center, spacing: 12) {
        IconTile(category: category, size: 38, cornerRadius: 10)
        VStack(alignment: .leading, spacing: 2) {
            Text(note).font(.headline).lineLimit(1).truncationMode(.tail)
            Text(subtitleText).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 4) {
            Text(expense.amount.formattedINR()).font(.headline)
            Text("Review")
                .font(.caption2).foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.accentColor, in: Capsule())
        }
    }
}
.padding(.vertical, 2)
```
For `TransferPairRow`, adapt the trailing badge to `"Transfer?"` with `Color.purple` background (Capsule), and replace the single-expense layout with a two-leg summary row (debit account → credit account, arrow, dates).

**Swipe actions pattern** (ReviewInboxRow.swift lines 81–96):
```swift
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    Button(role: .destructive) { discardExpense() }
    label: { Label("Discard", systemImage: "trash") }

    Button { acceptExpense() }
    label: { Label("Accept", systemImage: "checkmark") }
    .tint(.green)
}
```
Mirror exactly with `rejectPair()` (destructive, `"xmark"`) and `confirmPair()` (non-destructive, `"checkmark"`, `.tint(.green)`). Keep `allowsFullSwipe: false`.

**Accept action mutation + save** (ReviewInboxRow.swift lines 113–120):
```swift
private func acceptExpense() {
    expense.ingestionStateRaw = nil
    expense.updatedAt = Date()
    do {
        try context.save()
    } catch {
        print("ReviewInboxRow: failed to accept expense: \(error)")
    }
}
```
For `confirmPair()` / `rejectPair()`:
```swift
private func confirmPair() {
    debit.isTransfer = true
    credit.isTransfer = true
    // transferPairID already set by scorer — no change needed
    debit.updatedAt = Date()
    credit.updatedAt = Date()
    do { try context.save() } catch { print("TransferPairRow: confirmPair failed: \(error)") }
}

private func rejectPair() {
    debit.isTransfer = false
    credit.isTransfer = false
    debit.transferPairID = nil
    credit.transferPairID = nil
    debit.updatedAt = Date()
    credit.updatedAt = Date()
    do { try context.save() } catch { print("TransferPairRow: rejectPair failed: \(error)") }
}
```
Always mutate BOTH legs BEFORE the single `ctx.save()` (Pitfall 4 / CR-01).

**Amount formatting:**
```swift
// Existing helper — use identical call
Text(expense.amount.formattedINR())
```

---

### `MyHomeApp/Features/Expenses/ReviewInboxRow.swift` *(modify — add TransferPairRow section)*

**Analog:** self

No change to `ReviewInboxRow.swift` itself. The change is in `ExpenseListView.swift` which contains the inbox Section. Add a second Section above or below `"Needs Review"`:
```swift
// Pending transfer pairs section (D-11)
if !pendingDebitLegs.isEmpty {
    Section("Possible Transfers") {
        ForEach(pendingDebitLegs) { debit in
            // defensive: find credit leg in-memory
            if let creditID = debit.transferPairID,
               let credit = expenses.first(where: { $0.id == creditID }) {
                TransferPairRow(debit: debit, credit: credit)
            }
        }
    }
}
```

---

### `MyHomeApp/Features/Expenses/ExpenseListView.swift` *(modify — TransferFilter + pending pair section + badge)*

**Analog:** self — `AccountFilter` enum (lines 61–65)

**AccountFilter enum to mirror** (ExpenseListView.swift lines 61–65):
```swift
private enum AccountFilter: Hashable {
    case all
    case unassigned       // accountID == nil
    case account(UUID)    // accountID == specific UUID
}
```
Add alongside it:
```swift
private enum TransferFilter: Hashable {
    case normal      // default — EXCLUDES isTransfer == true from the main list (D-12)
    case transfers   // shows only isTransfer == true
}
@State private var transferFilter: TransferFilter = .normal
```

**filteredExpenses chaining** (ExpenseListView.swift lines 203–225):
```swift
private var filteredExpenses: [Expense] {
    // 1. Category filter (existing)
    // 2. Account filter chained (existing, lines 217–224)
    // 3. Transfer filter — chain as THIRD step:
    switch transferFilter {
    case .normal:
        return accountFiltered.filter { $0.isTransfer != true }
    case .transfers:
        return accountFiltered.filter { $0.isTransfer == true }
    }
}
```

**Filter menu Picker to extend** (ExpenseListView.swift lines 168–198):
```swift
// Add a Divider() + Picker for Transfer filter in the Menu, after the Account Picker section:
Divider()
Picker("Transfers", selection: $transferFilter) {
    Label("Normal Expenses", systemImage: "dollarsign.circle").tag(TransferFilter.normal)
    Label("Transfers", systemImage: "arrow.left.arrow.right").tag(TransferFilter.transfers)
}
```
The filled-icon logic (line 192–196) that checks `categoryFilter == .all && accountFilter == .all` must also check `transferFilter == .normal` to fill the icon when the transfer filter is active.

**@Query for pending debit legs** — add alongside `reviewItems` @Query (lines 29–33):
```swift
// Pending transfer pairs: debit leg only (amount > 0), transferPairID set, isTransfer nil.
// Uses UUID? predicate (not Bool?) — STAB-08 does not apply (A2).
@Query(
    filter: #Predicate<Expense> { $0.transferPairID != nil && $0.amount > 0 },
    sort: \Expense.date,
    order: .reverse
) private var pendingDebitLegs: [Expense]
```

**Badge count** — extend the existing `onChange(of: reviewItems.count)` pattern (lines 157–163):
```swift
// Also sync pending transfer pair count to badge:
.onChange(of: pendingDebitLegs.count) { _, _ in
    reviewBadgeCount = reviewItems.count + pendingDebitLegs.count
}
.onAppear {
    reviewBadgeCount = reviewItems.count + pendingDebitLegs.count
}
```

---

### `MyHomeApp/Features/Expenses/EditExpenseView.swift` *(modify — isTransfer toggle, D-14)*

**Analog:** self — `optionalSection` (lines 152–296), `initializeFields` (lines 300–324), `saveExpense` (lines 326–363)

**@State local mirror pattern** (EditExpenseView.swift lines 21–32):
```swift
@State private var isNegative: Bool = false
@State private var selectedAccount: Account? = nil
@State private var showAccountPicker: Bool = false
```
Add:
```swift
@State private var isMarkedTransfer: Bool = false
```

**initializeFields — seed new state** (EditExpenseView.swift lines 300–324):
```swift
// D-04: Seed selectedAccount from expense.accountID (active accounts only — T-09-09)
if let accountID = expense.accountID {
    selectedAccount = activeAccounts.first { $0.id == accountID }
}
```
Add after the account seed:
```swift
// D-14: Seed isMarkedTransfer from expense.isTransfer
isMarkedTransfer = expense.isTransfer == true
```

**optionalSection — new Toggle row** (mirrors Account row style, EditExpenseView.swift lines 228–263):
```swift
// Transfer toggle row — append after the Account row, inside optionalSection VStack
Toggle(isOn: $isMarkedTransfer) {
    Text("Mark as Transfer")
        .foregroundStyle(.primary)
}
.toggleStyle(.switch)
.padding(.vertical, 12)
.padding(.horizontal, 16)
.frame(minHeight: 44)
.background(Color(.secondarySystemBackground))
.clipShape(RoundedRectangle(cornerRadius: 12))
.padding(.top, 8)
```

**saveExpense — write isTransfer** (EditExpenseView.swift lines 326–363):
```swift
// D-04: Write account attribution
if let acc = selectedAccount, !acc.isArchived {
    expense.accountID = acc.id
} else {
    expense.accountID = nil
}
expense.updatedAt = Date()
// CR-01: persist explicitly
do { try context.save() } catch { ... }
```
Append before `updatedAt`:
```swift
// D-14: Write isTransfer solo flag
if isMarkedTransfer {
    expense.isTransfer = true
    // Solo flag — transferPairID stays as-is (may be nil or paired)
} else if expense.isTransfer == true {
    // Unmarking: reset to nil + cascade-unlink counterpart (D-14)
    if let partnerID = expense.transferPairID {
        let all = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        if let partner = all.first(where: { $0.id == partnerID }) {
            partner.isTransfer = nil
            partner.transferPairID = nil
        }
    }
    expense.isTransfer = nil
    expense.transferPairID = nil
}
```

**isDirty must include isMarkedTransfer** (EditExpenseView.swift lines 45–52):
```swift
private var isDirty: Bool {
    // ...existing checks...
    || isMarkedTransfer != (expense.isTransfer == true)
}
```

---

### `MyHomeApp/Support/BudgetCalculator.swift` *(modify — isTransfer exclusion, D-15)*

**Analog:** self

**monthlySpend method** (BudgetCalculator.swift lines 75–86):
```swift
static func monthlySpend(
    for expenses: [Expense],
    categories: [Category]
) -> [PersistentIdentifier: Decimal] {
    var totals: [PersistentIdentifier: Decimal] = [:]
    for expense in expenses {
        guard let category = expense.categories.first else { continue }
        let key = category.persistentModelID
        totals[key, default: .zero] += expense.amount
    }
    return totals
}
```
Add a pre-filter at the top of the method body:
```swift
// D-15: exclude confirmed self-transfers from budget math
let expenses = expenses.filter { $0.isTransfer != true }
```

**uncategorizedSpend method** (BudgetCalculator.swift lines 91–95):
```swift
static func uncategorizedSpend(for expenses: [Expense]) -> Decimal {
    expenses
        .filter { $0.categories.isEmpty }
        .reduce(.zero) { $0 + $1.amount }
}
```
Add transfer exclusion:
```swift
static func uncategorizedSpend(for expenses: [Expense]) -> Decimal {
    expenses
        .filter { $0.categories.isEmpty && $0.isTransfer != true }  // D-15
        .reduce(.zero) { $0 + $1.amount }
}
```

---

### `MyHomeApp/Support/SpendOverTimeAggregator.swift` *(modify — isTransfer exclusion, D-15)*

**Analog:** self

**Public bucket() method** (SpendOverTimeAggregator.swift lines 199–209):
```swift
static func bucket(
    expenses: [Expense],
    range: SpendRange,
    calendar: Calendar = .current
) -> [SpendBucket] {
    switch range {
    case .week:  return weekBuckets(expenses: expenses, calendar: calendar)
    case .month: return monthBuckets(expenses: expenses, calendar: calendar)
    case .year:  return yearBuckets(expenses: expenses, calendar: calendar)
    }
}
```
Add pre-filter before the switch:
```swift
// D-15: exclude confirmed self-transfers from spend chart
let spendable = expenses.filter { $0.isTransfer != true }
switch range {
case .week:  return weekBuckets(expenses: spendable, calendar: calendar)
case .month: return monthBuckets(expenses: spendable, calendar: calendar)
case .year:  return yearBuckets(expenses: spendable, calendar: calendar)
}
```
This is the single safest insertion point — all three range helpers receive only spendable expenses; no changes needed inside `weekBuckets`, `monthBuckets`, `yearBuckets`.

---

### `MyHomeApp/Support/OverviewAggregation.swift` *(modify — verify no direct change needed)*

**Analog:** `MyHomeApp/Support/BudgetCalculator.swift`

`OverviewAggregation` consumes output from `BudgetCalculator.monthlySpend` (its `spendByCategory` parameter) and `BudgetCalculator.uncategorizedSpend` (caller-computed `totalSpend`). Fixing both `BudgetCalculator` methods (D-15) automatically fixes `OverviewAggregation`. No direct code change is needed in `OverviewAggregation.swift` unless a caller passes a raw `[Expense]` array to `topCategories` or `aggregateThreshold` without going through `BudgetCalculator`.

Verify the callers of `OverviewAggregation` in `OverviewView` pass `BudgetCalculator`-computed maps, not raw expense arrays.

---

### `MyHomeApp/Support/AccountBalance.swift` *(verify — D-16 is implicit, no formula change)*

**Analog:** self

**Current formula** (AccountBalance.swift lines 20–34):
```swift
static func compute(
    baseline: Decimal?,
    asOf: Date?,
    expenses: [Expense],
    accountID: UUID
) -> Decimal {
    guard let baseline = baseline, let asOf = asOf else { return Decimal(0) }
    let net = expenses
        .filter { $0.accountID == accountID && $0.date >= asOf }
        .reduce(Decimal(0)) { $0 + $1.amount }
    return baseline + net
}
```
**Do NOT exclude `isTransfer == true` from this formula.** Per RESEARCH Critical Finding 4 (Pitfall 2): confirmed transfer legs ARE attributed to their accounts and MUST remain in the balance formula so the balance reflects the actual flow. The transfer debit reduces its account; the credit increases its account; net worth is unchanged. This is handled automatically by the existing sign convention.

**The only Phase 10 work here:** write `AccountBalanceTransferTests` to verify this behavior with confirmed-pair fixtures. No formula change.

---

### `MyHomeApp/Features/Gmail/GmailSyncController.swift` *(modify — post-sync hook, D-08)*

**Analog:** self — `setContext` method (lines 205–214) and `syncAccount` save (lines 561–564)

**modelContext injection pattern** (GmailSyncController.swift lines 141, 205–214):
```swift
var modelContext: ModelContext? = nil

func setContext(_ context: ModelContext) {
    self.modelContext = context
    // ...
}
```
Add `transferScanService` as an optional injected property the same way:
```swift
var transferScanService: TransferScanService? = nil
```
Set it from `RootView` alongside the `setContext` call.

**Post-sync hook location** (GmailSyncController.swift lines 561–564):
```swift
// D-04: Single batched save after the loop (not inside the per-message loop).
if let ctx = modelContext {
    try ctx.save()
}
return true
```
Add the scan call AFTER the save, BEFORE `return true`:
```swift
if let ctx = modelContext {
    try ctx.save()
}
// D-08: run transfer scorer after each sync
transferScanService?.scan()
return true
```
`scan()` is synchronous — no `await`, no actor boundary. Safe to call from within this `async` function because `GmailSyncController` is `@MainActor` and `TransferScanService` is also `@MainActor`.

**STAB-02 note:** The pre-loop UUID capture pattern is already present in `syncAccount` (lines 540–545 — `accountIDsByLabel` captured before the async loop). The `scan()` call is AFTER all `await` boundaries, so no STAB-02 risk for it.

---

### `MyHomeTests/TransferDetectionScorerTests.swift` (test, batch)

**Analog:** `MyHomeTests/AccountTypeInferenceTests.swift`

**File header + import** (AccountTypeInferenceTests.swift lines 1–9):
```swift
import Testing
import Foundation
@testable import MyHome

struct AccountTypeInferenceTests {
    @Test("inference: CC/credit/card keywords → credit_card; others → savings (D-03)")
    func inference() {
        #expect(inferAccountType(from: "HDFC CC") == "credit_card", "...")
    }
}
```
Mirror exactly for the pure scorer:
```swift
import Testing
import Foundation
@testable import MyHome

struct TransferDetectionScorerTests {
    // Helpers: makeExpense(amount:accountID:daysOffset:isTransfer:) factory
    // No ModelContainer needed — pure value function

    @Test("detectsExactAmountPair: matching debit+credit on two different accounts")
    func detectsExactAmountPair() {
        let accountA = UUID(); let accountB = UUID()
        var istCal = Calendar(identifier: .gregorian)
        istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        // construct Expense values, call TransferDetectionScorer.findCandidatePairs
        #expect(pairs.count == 1)
        #expect(pairs[0].debitID == debit.id)
        #expect(pairs[0].creditID == credit.id)
    }
}
```
No `@MainActor` required (pure function, no SwiftData). No `makeContainer()` needed.

---

### `MyHomeTests/TransferScanServiceTests.swift` (test, batch — integration)

**Analog:** `MyHomeTests/AccountBalanceTests.swift`

**File header + container fixture** (AccountBalanceTests.swift lines 1–15):
```swift
import Testing
import SwiftData
import Foundation
@testable import MyHome

@MainActor
struct AccountBalanceTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Account.self, Expense.self, configurations: config)
    }
```
Mirror exactly — `@MainActor` is required because `TransferScanService` is `@MainActor`:
```swift
import Testing
import SwiftData
import Foundation
@testable import MyHome

@MainActor
struct TransferScanServiceTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Account.self, Expense.self, configurations: config)
    }
```

**Test body pattern** (AccountBalanceTests.swift lines 19–59):
```swift
@Test("liveBalance equals baseline plus net...")
func liveBalanceEqualsBaselinePlusNet() throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    let account = Account(name: "Test Savings")
    account.id = UUID()
    ctx.insert(account)
    // ...insert expenses...
    try ctx.save()
    let allExpenses = try ctx.fetch(FetchDescriptor<Expense>())
    let balance = AccountBalance.compute(baseline: Decimal(1000), asOf: asOf, expenses: allExpenses, accountID: account.id)
    #expect(balance == Decimal(750), "Expected 750 but got \(balance)")
}
```
For scan tests: insert expenses, create `TransferScanService`, inject `ctx`, call `service.scan()`, fetch expenses, assert `transferPairID` was set. Use `#expect` throughout, never `XCTAssert`.

---

### `MyHomeTests/AccountBalanceTransferTests.swift` (test, batch)

**Analog:** `MyHomeTests/AccountBalanceTests.swift`

Append or create new file using the exact same `makeContainer()` + `@MainActor struct` + `@Test` + `#expect` pattern. Key tests:
- `confirmedTransferIncludedInBalance`: debit leg with `isTransfer = true` is included in compute; balance changes by `amount`.
- `netWorthUnchangedByTransfer`: debit account balance change + credit account balance change sums to zero.

---

## Shared Patterns

### CR-01: Explicit save — never rely on autosave for financial writes
**Source:** `MyHomeApp/Features/Expenses/ReviewInboxRow.swift` lines 117–120; `MyHomeApp/Features/Notes/RoutineResetService.swift` line 53
**Apply to:** `TransferPairRow.confirmPair()`, `TransferPairRow.rejectPair()`, `TransferScanService.scan()`, `EditExpenseView.saveExpense()` isTransfer write
```swift
do {
    try context.save()
} catch {
    print("[FileName]: action failed: \(error)")
}
```
Always mutate ALL affected objects BEFORE the single `ctx.save()`. Never save inside a loop (CR-01 batch-save rule from GmailSyncController line 561–564).

### STAB-08: Bool? predicate safety
**Source:** `MyHomeApp/Features/Notes/RoutineResetService.swift` (uses `#Predicate` on non-optional `Bool` — safe); CONTEXT.md / RESEARCH.md STAB-08 note
**Apply to:** `TransferScanService.scan()` candidate fetch; inbox `@Query`
```swift
// SAFE — non-optional Bool predicate (RoutineResetService pattern):
FetchDescriptor<Note>(predicate: #Predicate { $0.isDailyRoutine == true })

// REQUIRED for Bool? (isTransfer) — fetch all, filter in Swift:
let all = try context.fetch(FetchDescriptor<Expense>())
let candidates = all.filter { $0.isTransfer == nil }

// SAFE for UUID? (transferPairID) — != nil on optional UUID has worked:
#Predicate<Expense> { $0.transferPairID != nil && $0.amount > 0 }
```

### STAB-02: No @Model refs across await
**Source:** `MyHomeApp/Features/Gmail/GmailSyncController.swift` line 540–542 (pre-loop UUID capture)
**Apply to:** `TransferScanService.scan()` (synchronous — no await, no risk); `GmailSyncController` hook (scan called after all awaits, safe)
```swift
// Pattern: capture UUIDs before any async boundary
let accountIDsByLabel = AccountAttributionHelper.buildAccountIDsByLabel(from: accounts)
// Use UUIDs, not @Model refs, across await
```
`TransferDetectionScorer.findCandidatePairs` accepts `[Expense]` (value snapshot) — safe even if called from an async context because the scorer itself has no `await`.

### Decimal money — never Double
**Source:** `MyHomeApp/Support/BudgetCalculator.swift` lines 24–56 (BudgetProgressData); `MyHomeApp/Support/SpendOverTimeAggregator.swift` lines 28–39
**Apply to:** `TransferDetectionScorer` amount grouping (`[Decimal: [Expense]]`), all balance-move math
```swift
// CORRECT: Decimal for all money math
let key = abs(credit.amount)  // Decimal — exact equality

// Convert to Double ONLY at Chart rendering boundary:
let doubleSpent = NSDecimalNumber(decimal: decimalSpent).doubleValue
```

### @State local mirror pattern for @Bindable forms
**Source:** `MyHomeApp/Features/Expenses/EditExpenseView.swift` lines 21–32, 300–324, 326–363
**Apply to:** `EditExpenseView` isTransfer toggle addition
```swift
// Local @State mirrors expense fields; initializeFields() seeds from the model;
// saveExpense() writes back to the @Bindable model before ctx.save()
@State private var isMarkedTransfer: Bool = false
// initializeFields:
isMarkedTransfer = expense.isTransfer == true
// saveExpense: write isTransfer before ctx.save()
```

### Swift Testing style (no XCTest)
**Source:** `MyHomeTests/AccountTypeInferenceTests.swift`; `MyHomeTests/AccountBalanceTests.swift`
**Apply to:** All Phase 10 test files
```swift
import Testing        // not XCTest
@testable import MyHome

struct FooTests {     // struct, not class
    @Test("description")
    func testName() throws {
        #expect(result == expected, "message")
    }
}
```
`@MainActor` on the struct is required when the subject is `@MainActor` (e.g., `TransferScanService`). For pure helpers (`TransferDetectionScorer`, `AccountBalance`), no `@MainActor` needed.

---

## No Analog Found

All Phase 10 files have strong analogs in the codebase. No files without analog.

---

## Metadata

**Analog search scope:** `MyHomeApp/Features/Gmail/`, `MyHomeApp/Features/Expenses/`, `MyHomeApp/Features/Notes/`, `MyHomeApp/Support/`, `MyHomeTests/`
**Files scanned:** 10 source files + 3 test files
**Pattern extraction date:** 2026-06-10
