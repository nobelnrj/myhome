# Phase 9: SchemaV6 & Accounts Management — Pattern Map

**Mapped:** 2026-06-09
**Files analyzed:** 17
**Analogs found:** 17 / 17

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `MyHomeApp/Persistence/Schema/SchemaV6.swift` | schema | batch (additive migration) | `MyHomeApp/Persistence/Schema/SchemaV5.swift` | exact |
| `MyHomeApp/Persistence/Schema/MigrationPlan.swift` | config | batch | `MyHomeApp/Persistence/Schema/MigrationPlan.swift` (self, edit) | exact |
| `MyHomeApp/Persistence/Models/Account.swift` | model | CRUD | `MyHomeApp/Persistence/Models/Expense.swift` (typealias pattern) | exact |
| `MyHomeApp/Persistence/Models/Asset.swift` | model | CRUD | `MyHomeApp/Persistence/Models/Expense.swift` (typealias pattern) | exact |
| `MyHomeApp/Persistence/Models/Expense.swift` | model | CRUD | `MyHomeApp/Persistence/Models/Note.swift` (typealias flip) | exact |
| `MyHomeApp/Persistence/Models/Note.swift` | model | CRUD | `MyHomeApp/Persistence/Models/Note.swift` (self, typealias flip) | exact |
| `MyHomeApp/Persistence/Models/NoteBlock.swift` | model | CRUD | `MyHomeApp/Persistence/Models/Note.swift` (typealias flip) | exact |
| `MyHomeApp/Persistence/Models/Category.swift` | model | CRUD | `MyHomeApp/Persistence/Models/Expense.swift` (typealias flip) | exact |
| `MyHomeApp/Features/Settings/SettingsView.swift` | component | request-response | `MyHomeApp/Features/Settings/SettingsView.swift` (self, edit) | exact |
| `MyHomeApp/Features/Settings/AccountsListView.swift` | component | CRUD | `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` | exact |
| `MyHomeApp/Features/Settings/AccountDetailView.swift` | component | request-response | `MyHomeApp/Features/Expenses/ExpenseListView.swift` | role-match |
| `MyHomeApp/Features/Settings/EditAccountView.swift` | component | CRUD | `MyHomeApp/Features/Expenses/AddExpenseView.swift` | role-match |
| `MyHomeApp/Features/Expenses/ExpenseListView.swift` | component | request-response | `MyHomeApp/Features/Expenses/ExpenseListView.swift` (self, edit) | exact |
| `MyHomeApp/Features/Expenses/AddExpenseView.swift` | component | request-response | `MyHomeApp/Features/Expenses/AddExpenseView.swift` (self, edit) | exact |
| `MyHomeApp/Features/Expenses/EditExpenseView.swift` | component | request-response | `MyHomeApp/Features/Expenses/AddExpenseView.swift` | exact |
| `MyHomeApp/Features/Expenses/AccountPickerView.swift` | component | request-response | `MyHomeApp/Features/Expenses/CategoryPickerView.swift` | exact |
| `MyHomeApp/Features/Notes/RoutineResetService.swift` | service | event-driven | `MyHomeApp/Features/Notes/RoutineResetService.swift` (self, fill stub) | exact |
| `MyHomeApp/Features/Gmail/GmailSyncController.swift` | service | batch | `MyHomeApp/Features/Gmail/GmailSyncController.swift` (self, edit) | exact |
| `MyHomeTests/SchemaV6MigrationTests.swift` | test | batch | `MyHomeTests/MigrationTests.swift` | exact |

---

## Pattern Assignments

### `MyHomeApp/Persistence/Schema/SchemaV6.swift` (schema, additive migration)

**Analog:** `MyHomeApp/Persistence/Schema/SchemaV5.swift`

**Entire-file structure** (lines 1–30 of SchemaV5):
```swift
import SwiftData
import Foundation

/// VersionedSchema v6.0.0 — copies V5's models verbatim, adds Account + Asset models
/// and additive fields to Expense and Note.
///
/// Rules: (same CloudKit-readiness rules 1–8 as SchemaV5)
/// 1. Every stored property has a default or is optional.
/// 2. No @Attribute(.unique).
/// 3. Decimal for money.
/// 4. Full UTC timestamp for dates.
/// 5. currencyCode: String for multi-currency-readiness.
/// 6. UUID primary key on all @Model types.
/// 7. @Relationship inverse declared on ONE side only.
/// 8. No stored enums — use String raw values.
enum SchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV6.Expense.self,
            SchemaV6.Category.self,
            SchemaV6.Note.self,
            SchemaV6.NoteBlock.self,
            SchemaV6.Account.self,   // NEW
            SchemaV6.Asset.self,     // NEW (scaffold only)
        ]
    }
    // ... model definitions below
}
```

**Copy V5 models verbatim pattern** (SchemaV5 lines 36–189):
- Copy `Category` @Model verbatim (no V6 changes).
- Copy `NoteBlock` @Model verbatim (no V6 changes).
- Copy `Expense` @Model verbatim from V5, then append three new fields at the end:
```swift
// NEW in SchemaV6 — append AFTER all V5 fields (additive only — never reorder/remove)
var accountID: UUID? = nil              // links to Account.id; nil = Unassigned (D-01)
var isTransfer: Bool? = nil             // Phase 10 scaffold; nil = not evaluated
var transferPairID: UUID? = nil         // Phase 10 scaffold; links paired expense
```
- Copy `Note` @Model verbatim from V5, then append two new fields at the end:
```swift
// NEW in SchemaV6 — append AFTER all V5 fields
var isDailyRoutine: Bool = false           // D-11: flags note for RoutineResetService
var routineLastResetDate: Date? = nil      // D-12: note-level reset marker; nil = never reset
```

**New Account @Model** (derived from CloudKit rules in SchemaV5 lines 1–20 and Category pattern lines 36–68):
```swift
@Model
final class Account {
    var id: UUID = UUID()
    var name: String? = nil               // optional per CloudKit rule 2
    var typeRaw: String? = nil            // "savings" | "current" | "credit_card" (rule 8: String not enum)
    var symbolName: String? = nil         // SF Symbol name
    var colorHex: String? = nil           // hex string e.g. "#FF3B30" (rule 8: String not Color)
    var last4: String? = nil              // optional last 4 digits
    var balanceBaseline: Decimal? = nil   // Decimal not Double (rule 3); nil = no baseline set
    var balanceAsOfDate: Date? = nil      // UTC (rule 4)
    var isArchived: Bool = false          // D-08: archive hides from pickers
    var sortOrder: Int = 0               // STAB-03 footgun: pass sortOrder explicitly at every call site
    var sourceLabel: String? = nil        // set by migration for auto-created accounts; nil for manual
    var createdAt: Date = Date()          // UTC (rule 4)

    // Inverse relationship — declared on THIS side only (rule 7; avoids circular macro error)
    // deleteRule: .nullify — deleting an account clears expense.account link (does not delete expenses)
    @Relationship(deleteRule: .nullify)
    var expenses: [SchemaV6.Expense] = []

    init(name: String, typeRaw: String = "savings", sourceLabel: String? = nil) {
        self.id = UUID()
        self.name = name
        self.typeRaw = typeRaw
        self.sourceLabel = sourceLabel
        self.createdAt = Date()
    }
}
```

**New Asset @Model** (scaffold only — no UI in Phase 9):
```swift
@Model
final class Asset {
    var id: UUID = UUID()
    var name: String? = nil
    var assetClassRaw: String? = nil   // "mutual_fund" | "stock" | "nps" — Phase 11 populates
    var units: Decimal? = nil
    var costBasisPerUnit: Decimal? = nil
    var currentNAV: Decimal? = nil
    var navAsOfDate: Date? = nil
    var createdAt: Date = Date()
    init() { self.id = UUID(); self.createdAt = Date() }
}
```

---

### `MyHomeApp/Persistence/Schema/MigrationPlan.swift` (config, edit)

**Analog:** `MyHomeApp/Persistence/Schema/MigrationPlan.swift` (self)

**schemas array extension** (analog: line 10):
```swift
// Before (V5):
static var schemas: [any VersionedSchema.Type] {
    [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self]
}
// After (V6 — append SchemaV6.self; never remove V1–V5):
static var schemas: [any VersionedSchema.Type] {
    [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self]
}
```

**stages array extension** (analog: line 14):
```swift
static var stages: [MigrationStage] {
    [v1ToV2, v2ToV3, v3ToV4, v4ToV5, v5ToV6]   // append v5ToV6
}
```

**New v5ToV6 stage with non-nil didMigrate** (analog: lines 20–25 for .custom pattern, plus lines 46–52):
```swift
// V6 adds Account + Asset models and backfills accountID on existing expenses.
// FIRST non-nil didMigrate in this codebase. .custom over .lightweight: FB13812722 workaround preserved.
// didMigrate is synchronous (throws, NOT async throws). Never attempt await inside.
static let v5ToV6 = MigrationStage.custom(
    fromVersion: SchemaV5.self,
    toVersion: SchemaV6.self,
    willMigrate: nil,
    didMigrate: { context in
        // 1. Fetch all V6 expenses (sourceLabel field is retained verbatim from V5)
        let expenses = try context.fetch(FetchDescriptor<SchemaV6.Expense>())

        // 2. Build idempotency map: existing accounts keyed by sourceLabel
        //    MUST fetch before inserting — prevents duplicate rows on retry (Pitfall 2)
        let existingAccounts = try context.fetch(FetchDescriptor<SchemaV6.Account>())
        var accountByLabel: [String: SchemaV6.Account] = [:]
        for account in existingAccounts {
            if let label = account.sourceLabel { accountByLabel[label] = account }
        }

        // 3. Create missing accounts for distinct non-nil sourceLabels (D-01, D-03)
        var didCreateAny = false
        let labels = Set(expenses.compactMap(\.sourceLabel))
        for label in labels {
            if accountByLabel[label] == nil {
                let typeRaw = inferAccountType(from: label)   // "credit_card" or "savings"
                let account = SchemaV6.Account(name: label, typeRaw: typeRaw, sourceLabel: label)
                context.insert(account)
                accountByLabel[label] = account
                didCreateAny = true
            }
        }

        // 4. Backfill Expense.accountID (idempotent: skip expenses already attributed — Pitfall 2)
        for expense in expenses {
            guard expense.accountID == nil, let label = expense.sourceLabel else { continue }
            expense.accountID = accountByLabel[label]?.id
        }

        // 5. Explicit save — REQUIRED; migration context does NOT auto-commit (Pitfall 3)
        try context.save()

        // 6. Flag first-launch review if accounts were auto-created (D-02)
        if didCreateAny {
            UserDefaults.standard.set(true, forKey: "accountReviewPending")
        }
    }
)

/// D-03: Infer account type from sourceLabel string (case-insensitive keyword match).
private static func inferAccountType(from label: String) -> String {
    let lower = label.lowercased()
    if lower.contains("cc") || lower.contains("credit") || lower.contains("card") {
        return "credit_card"
    }
    return "savings"
}
```

---

### `MyHomeApp/Persistence/Models/Account.swift` (model, new file)

**Analog:** `MyHomeApp/Persistence/Models/Expense.swift` (typealias pattern, line 14)

**Copy the typealias pattern verbatim** (Expense.swift lines 1–14):
```swift
import SwiftData

/// Convenience typealias so views and tests use bare `Account` without the version prefix.
///
/// New in Phase 9 (SchemaV6). All views and tests that use `Account` continue to compile
/// unchanged if the schema version is bumped later — only this file needs updating.
///
/// STAB-08 lesson: flip ALL typealiases together in the same commit that updates
/// AppMigrationPlan.schemas to include SchemaV6.self. Mismatched typealiases cause
/// save/query crashes.
///
/// Usage:
///   let account = Account(name: "HDFC CC", typeRaw: "credit_card")
///   @Query var accounts: [Account]
typealias Account = SchemaV6.Account
```

---

### `MyHomeApp/Persistence/Models/Asset.swift` (model, new file)

**Analog:** `MyHomeApp/Persistence/Models/Expense.swift` (typealias pattern)

```swift
import SwiftData

/// Convenience typealias for the Phase 11 Asset model (scaffold only in Phase 9).
typealias Asset = SchemaV6.Asset
```

---

### `MyHomeApp/Persistence/Models/Expense.swift`, `Note.swift`, `NoteBlock.swift`, `Category.swift` (model, typealias flip)

**Analog:** `MyHomeApp/Persistence/Models/Note.swift` (self, lines 1–19) — the STAB-08 typealias-flip pattern.

**All four files flip in one atomic commit** (STAB-08 footgun — see memory entry):
```swift
// Expense.swift line 14:
typealias Expense = SchemaV6.Expense    // was SchemaV5.Expense

// Note.swift line 19:
typealias Note = SchemaV6.Note          // was SchemaV5.Note

// NoteBlock.swift (equivalent line):
typealias NoteBlock = SchemaV6.NoteBlock  // was SchemaV5.NoteBlock

// Category.swift (equivalent line):
typealias Category = SchemaV6.Category  // was SchemaV5.Category
```

The flip comment to add (mirror Note.swift's comment style):
```swift
/// Flipped from SchemaV5.X → SchemaV6.X in Phase 9 (plan 09-XX).
/// The production container is built with Schema(versionedSchema: SchemaV6.self),
/// so the app MUST use SchemaV6.X. SchemaV6.X is a superset of SchemaV5.X — new
/// fields only, no removals. All views and tests continue to compile unchanged.
```

---

### `MyHomeApp/Features/Settings/AccountsListView.swift` (component, CRUD, new file)

**Analog:** `MyHomeApp/Features/Budgets/ManageCategoriesView.swift`

**Imports + @Query + @Environment pattern** (ManageCategoriesView lines 1–26):
```swift
import SwiftUI
import SwiftData

struct AccountsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // Active accounts sorted by sortOrder (ascending — new accounts prepend via min-1)
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]

    // In-memory split: active vs archived (D-08)
    private var activeAccounts: [Account] { allAccounts.filter { !$0.isArchived } }
    private var archivedAccounts: [Account] { allAccounts.filter { $0.isArchived } }
```

**NavigationStack + List structure** (ManageCategoriesView lines 29–110):
```swift
    var body: some View {
        NavigationStack {
            List {
                // Active accounts section
                ForEach(activeAccounts) { account in
                    NavigationLink(destination: AccountDetailView(account: account)) {
                        accountRow(account)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            accountToDelete = account
                            showDeleteConfirmation = true
                        } label: { Label("Delete", systemImage: "trash") }

                        Button {
                            account.isArchived = true
                            try? context.save()
                        } label: { Label("Archive", systemImage: "archivebox") }
                        .tint(.orange)
                    }
                }

                // Archived accounts — collapsed DisclosureGroup (D-08)
                if !archivedAccounts.isEmpty {
                    DisclosureGroup("Archived") {
                        ForEach(archivedAccounts) { account in
                            accountRow(account)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddSheet = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add Account")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                EditAccountView(account: nil)   // nil = create mode
            }
            .confirmationDialog(
                "Delete Account?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    if let acc = accountToDelete { deleteAccount(acc) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Past transactions remain but will no longer be attributed to this account.")
            }
        }
    }
```

**lookup-before-insert / sortOrder prepend pattern** (ManageCategoriesView lines 177–205):
```swift
private func addAccount(name: String, typeRaw: String) {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { nameError = "Account name cannot be empty."; return }
    // Lookup-before-insert (case-insensitive) — T-02-12 pattern
    let lower = trimmed.lowercased()
    do {
        let all = try context.fetch(FetchDescriptor<Account>())
        guard all.first(where: { ($0.name ?? "").lowercased() == lower }) == nil else {
            nameError = "An account with that name already exists."
            return
        }
        // min(existing.sortOrder) - 1 — prepends to top of ascending list (STAB-03 pattern)
        let nextSortOrder = (all.map(\.sortOrder).min() ?? 0) - 1
        let account = Account(name: trimmed, typeRaw: typeRaw)
        account.sortOrder = nextSortOrder
        context.insert(account)
        try context.save()   // CR-01: explicit save
    } catch {
        assertionFailure("Failed to save new account: \(error)")
    }
}

private func deleteAccount(_ account: Account) {
    context.delete(account)
    do { try context.save() } catch {
        assertionFailure("Failed to delete account: \(error)")
    }
}
```

**IconTile rowLabel pattern for account color/icon** (SettingsView lines 302–308):
```swift
private func accountRowLabel(_ account: Account) -> some View {
    HStack(spacing: 12) {
        IconTile(
            symbol: account.symbolName ?? "creditcard",
            color: Color(hex: account.colorHex ?? "#636366"),
            size: 29
        )
        VStack(alignment: .leading, spacing: 2) {
            Text(account.name ?? "")
                .foregroundStyle(.primary)   // T-02-15: plain Text — never AttributedString(markdown:)
            Text(displayType(account.typeRaw))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

---

### `MyHomeApp/Features/Settings/EditAccountView.swift` (component, CRUD, new file)

**Analog:** `MyHomeApp/Features/Expenses/AddExpenseView.swift`

**NavigationStack-in-sheet structure** (AddExpenseView lines 53–82):
```swift
import SwiftUI
import SwiftData

struct EditAccountView: View {
    var account: Account?   // nil = create mode, non-nil = edit mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var typeRaw: String = "savings"   // "savings" | "current" | "credit_card"
    @State private var symbolName: String = "creditcard"
    @State private var colorHex: String = "#636366"
    @State private var last4: String = ""
    @State private var balanceBaseline: Decimal = 0
    @State private var balanceAsOfDate: Date = Date()
    @State private var nameError: String? = nil

    // Amount validation (mirrors T-01-03 from AddExpenseView):
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        abs(balanceBaseline) < 1_000_000_000
    }

    var body: some View {
        NavigationStack {
            Form {
                // Name + type + last4 fields
                Section("Account Details") {
                    TextField("Account name", text: $name)
                    Picker("Type", selection: $typeRaw) {
                        Text("Savings").tag("savings")
                        Text("Current").tag("current")
                        Text("Credit Card").tag("credit_card")
                    }
                    TextField("Last 4 digits (optional)", text: $last4)
                        .keyboardType(.numberPad)
                }

                // Balance baseline (D-09: CC label = "Amount owed", others = "Opening balance")
                Section("Balance") {
                    HStack {
                        Text(typeRaw == "credit_card" ? "Amount owed" : "Opening balance")
                        Spacer()
                        // Use DecimalKeypad or TextField for Decimal entry
                    }
                    DatePicker("As of", selection: $balanceAsOfDate, displayedComponents: .date)
                }

                // Color/icon picker — follow ManageCategoriesView symbolName pattern
                Section("Appearance") {
                    // Color and SF Symbol picker rows
                }
            }
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAccount() }
                        .disabled(!isValid)
                        .tint(.accentColor)
                }
            }
        }
    }
```

**Save pattern** (mirrors AddExpenseView's `saveExpense()` + ManageCategoriesView's explicit save):
```swift
    private func saveAccount() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { nameError = "Account name cannot be empty."; return }
        // T-01-03 equivalent: reject unreasonably large baseline
        guard abs(balanceBaseline) < 1_000_000_000 else { nameError = "Balance is too large."; return }

        let target = account ?? Account(name: trimmed)
        target.name = trimmed
        target.typeRaw = typeRaw
        target.last4 = last4.isEmpty ? nil : last4
        target.balanceBaseline = balanceBaseline
        target.balanceAsOfDate = balanceAsOfDate
        target.symbolName = symbolName
        target.colorHex = colorHex

        if account == nil { context.insert(target) }
        do {
            try context.save()   // CR-01: explicit save
            dismiss()
        } catch {
            assertionFailure("Failed to save account: \(error)")
        }
    }
}
```

---

### `MyHomeApp/Features/Settings/AccountDetailView.swift` (component, request-response, new file)

**Analog:** `MyHomeApp/Features/Expenses/ExpenseListView.swift`

**@Query + in-memory computed balance pattern** (ExpenseListView lines 22–46, plus RESEARCH Critical Pattern 4):
```swift
import SwiftUI
import SwiftData

struct AccountDetailView: View {
    var account: Account

    // Fetch all expenses — filter in-memory (mirrors CategoryFilter pattern in ExpenseListView)
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]

    private var attributedExpenses: [Expense] {
        allExpenses.filter { $0.accountID == account.id }
    }

    // ACCT-05: computed (never stored) — reactive because @Query updates trigger body re-eval
    private var liveBalance: Decimal {
        guard let baseline = account.balanceBaseline,
              let asOf = account.balanceAsOfDate else { return Decimal(0) }
        let attributed = attributedExpenses.filter { $0.date >= asOf }
        let net = attributed.reduce(Decimal(0)) { $0 + $1.amount }
        return baseline + net   // D-09: sign semantics in data, not formula
    }
```

**EditAccountView sheet presentation** (mirrors AddExpenseView's sheet pattern, ExpenseListView lines 136–141):
```swift
    @State private var showEditSheet = false

    var body: some View {
        List {
            Section("Balance") {
                HStack {
                    Text("Current balance")
                    Spacer()
                    Text(liveBalance.formattedINR())
                        .foregroundStyle(liveBalance < 0 ? .red : .primary)
                }
                if let asOf = account.balanceAsOfDate {
                    Text("As of \(asOf.formattedForDatePickerRow())")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Transactions") {
                ForEach(attributedExpenses) { expense in
                    ExpenseRow(expense: expense)
                }
            }
        }
        .navigationTitle(account.name ?? "Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEditSheet = true }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditAccountView(account: account)
        }
    }
}
```

---

### `MyHomeApp/Features/Expenses/AccountPickerView.swift` (component, request-response, new file)

**Analog:** `MyHomeApp/Features/Expenses/CategoryPickerView.swift` — copy almost verbatim.

**Full structure** (CategoryPickerView lines 1–99):
```swift
import SwiftUI
import SwiftData

/// Sheet for picking (or clearing) an account on an expense.
/// Mirrors CategoryPickerView exactly — substitutes Account for Category.
/// Filter: only active (non-archived) accounts shown (D-08 / Pitfall 6).
struct AccountPickerView: View {

    @Binding var selectedAccount: Account?
    @Environment(\.dismiss) private var dismiss
    // Filter archived accounts from picker (D-08 / Pitfall 6)
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var activeAccounts: [Account]

    var body: some View {
        NavigationStack {
            List {
                // "None" row — mirrors CategoryPickerView lines 26–46
                Button(action: { selectedAccount = nil; dismiss() }) {
                    HStack {
                        Image(systemName: "circle.slash")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(width: 24, height: 24).accessibilityHidden(true)
                        Text("None").font(.body).foregroundStyle(.primary)
                        Spacer()
                        if selectedAccount == nil {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)

                // Account rows — mirrors CategoryPickerView lines 49–76
                ForEach(activeAccounts) { account in
                    Button(action: { selectedAccount = account; dismiss() }) {
                        HStack {
                            if let symbol = account.symbolName {
                                Image(systemName: symbol)
                                    .font(.subheadline).foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24).accessibilityHidden(true)
                            }
                            Text(account.name ?? "")   // T-02-15: plain Text
                                .font(.body).foregroundStyle(.primary)
                            Spacer()
                            if selectedAccount?.persistentModelID == account.persistentModelID {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if selectedAccount != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear") { selectedAccount = nil; dismiss() }
                            .tint(Color(.systemRed))
                    }
                }
            }
        }
    }
}
```

---

### `MyHomeApp/Features/Expenses/ExpenseListView.swift` (component, edit — add AccountFilter)

**Analog:** `MyHomeApp/Features/Expenses/ExpenseListView.swift` (self, lines 47–52)

**AccountFilter enum** (mirror CategoryFilter at lines 47–51):
```swift
// Add alongside existing CategoryFilter enum:
private enum AccountFilter: Hashable {
    case all
    case unassigned        // accountID == nil
    case account(UUID)     // accountID == specific UUID
}
```

**@State + filteredExpenses update** (mirror categoryFilter pattern at lines 41, 176–187):
```swift
@State private var accountFilter: AccountFilter = .all

// Add to filteredExpenses computed property (chained after category filter):
private var filteredExpenses: [Expense] {
    // existing category filter ...
    let categoryFiltered: [Expense] = /* existing switch */ ...

    // Account filter applied second (in-memory, same pattern)
    switch accountFilter {
    case .all:
        return categoryFiltered
    case .unassigned:
        return categoryFiltered.filter { $0.accountID == nil }
    case .account(let id):
        return categoryFiltered.filter { $0.accountID == id }
    }
}
```

**filterMenu extension** (mirror lines 154–171 for account filter Menu):
```swift
// Add a second Menu or Picker section in filterMenu for account filter
// Follows same Label/tag pattern as category picker at lines 157–164
```

---

### `MyHomeApp/Features/Expenses/AddExpenseView.swift` + `EditExpenseView.swift` (component, edit)

**Analog:** `MyHomeApp/Features/Expenses/AddExpenseView.swift` (self, lines 29–31, 157–190)

**Account picker @State** (mirror selectedCategory pattern at line 29):
```swift
@State private var selectedAccount: Account? = nil
@State private var showAccountPicker: Bool = false
```

**Last-used account default** (D-04 — UserDefaults, not a model field):
```swift
// In onAppear or init:
if let id = UserDefaults.standard.string(forKey: "lastUsedAccountID").flatMap(UUID.init) {
    selectedAccount = /* resolve from @Query results by id */
}
// In saveExpense(), after save succeeds:
if let acc = selectedAccount {
    UserDefaults.standard.set(acc.id.uuidString, forKey: "lastUsedAccountID")
}
```

**Account picker row** (mirror Category row at lines 158–190):
```swift
Button(action: { showAccountPicker = true }) {
    HStack {
        Text("Account")
            .foregroundStyle(.primary)
        Spacer()
        if let acc = selectedAccount, let name = acc.name {
            if let symbol = acc.symbolName {
                Image(systemName: symbol).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(name).foregroundStyle(.secondary).font(.subheadline)
        } else {
            Text("None").foregroundStyle(.secondary).font(.subheadline)
        }
        Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
    }
    .padding(.vertical, 12).padding(.horizontal, 16).frame(minHeight: 44)
}
.buttonStyle(.plain)
.background(Color(.secondarySystemBackground))
.clipShape(RoundedRectangle(cornerRadius: 12))
.padding(.top, 8)
.sheet(isPresented: $showAccountPicker) {
    AccountPickerView(selectedAccount: $selectedAccount)
}
```

**saveExpense() account field** (mirror category assignment in AddExpenseView):
```swift
expense.accountID = selectedAccount?.id   // nil if no account selected (Unassigned)
// Also validate: guard archived account not selected (Pitfall 6)
if let acc = selectedAccount, acc.isArchived {
    expense.accountID = nil
}
```

---

### `MyHomeApp/Features/Settings/SettingsView.swift` (component, edit — add Accounts row)

**Analog:** `MyHomeApp/Features/Settings/SettingsView.swift` (self)

**Data Section addition** (analog: lines 158–177):
```swift
// In the "Data" Section, add below "Manage Categories":
NavigationLink(destination: AccountsListView()) {
    HStack {
        rowLabel("Accounts", symbol: "creditcard", color: Color(.systemBlue))
        Spacer()
        // D-02: badge when accountReviewPending is true
        if accountReviewPending {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
        }
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
    }
}
.foregroundStyle(.primary)
```

**accountReviewPending @State** (mirrors existing @State pattern in SettingsView):
```swift
@State private var accountReviewPending: Bool =
    UserDefaults.standard.bool(forKey: "accountReviewPending")
```

---

### `MyHomeApp/Features/Notes/RoutineResetService.swift` (service, event-driven, fill stub)

**Analog:** `MyHomeApp/Features/Notes/RoutineResetService.swift` (self — fill the Phase 8 scaffold body)

**Full replacement body** (Phase 8 stub is lines 1–27; D-11/D-12 fill the body):
```swift
import Foundation
import SwiftData

@MainActor
@Observable
final class RoutineResetService {

    // Injected by RootView.onAppear (same pattern as gmailSyncController.setContext — RootView line 86)
    var modelContext: ModelContext?

    func resetIfNeeded() {
        guard let context = modelContext else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!   // IST — household timezone (line 20 of stub)
        let startOfTodayIST = cal.startOfDay(for: Date())

        do {
            // D-11: fetch only isDailyRoutine notes
            let notes = try context.fetch(
                FetchDescriptor<Note>(predicate: #Predicate { $0.isDailyRoutine == true })
            )
            var didChange = false
            for note in notes {
                // D-12: note-level routineLastResetDate (NOT per-block); nil = distantPast
                let lastReset = note.routineLastResetDate ?? .distantPast
                guard lastReset < startOfTodayIST else { continue }   // idempotent: same-day no-op

                // Reset all checkbox blocks on this note
                for block in note.blocks ?? [] {
                    if block.kindRaw == "checkbox" && block.isChecked {
                        block.isChecked = false
                        didChange = true
                    }
                }
                note.routineLastResetDate = startOfTodayIST
                didChange = true
            }
            if didChange { try context.save() }   // CR-01: explicit save
        } catch {
            print("[RoutineResetService] reset failed: \(error)")
        }
    }
}
```

**Injection point in RootView** (RootView lines 82–86):
```swift
// In RootView.onAppear (after gmailSyncController.setContext(modelContext)):
routineResetService.modelContext = modelContext
```

Add `var modelContext: ModelContext?` property to `RoutineResetService` (currently has no properties).

---

### `MyHomeApp/Features/Gmail/GmailSyncController.swift` (service, batch, edit — add D-05 attribution)

**Analog:** `MyHomeApp/Features/Gmail/GmailSyncController.swift` (self, lines 481–540)

**Pre-loop account ID capture** (mirror categoryIDsByName pattern at lines 481–486):
```swift
// Capture account sourceLabel → PersistentIdentifier BEFORE the per-message loop
// (STAB-02 lesson: captured @Model refs go stale after await suspension)
var accountIDsByLabel: [String: UUID] = [:]
if let ctx = modelContext {
    for acc in (try? ctx.fetch(FetchDescriptor<Account>())) ?? [] {
        if let label = acc.sourceLabel, !acc.isArchived, let id = acc.id as UUID? {
            accountIDsByLabel[label] = id
        }
        // Also index by name for new-ingestion matching (D-05):
        if let name = acc.name, !acc.isArchived {
            accountIDsByLabel[name.lowercased()] = acc.id
        }
    }
}
```

**Per-message attribution** (add after line 526 `expense.sourceAccount = confirmedEmail`):
```swift
// D-05: Auto-attribute to matching Account by sourceLabel
// UUID stored directly — no @Model reference across await boundary (STAB-02)
if let label = parsed.rawSourceLabel {
    expense.accountID = accountIDsByLabel[label] ?? accountIDsByLabel[label.lowercased()]
}
// No match → accountID stays nil (Unassigned) per D-05
```

---

### `MyHomeTests/SchemaV6MigrationTests.swift` (test, integration, new file)

**Analog:** `MyHomeTests/MigrationTests.swift` — copy the v3StoreMigratesToV4 pattern (lines 104–173).

**Test file structure** (MigrationTests.swift lines 15–16, import block lines 1–5):
```swift
import Testing
import SwiftData
import Foundation
@testable import MyHome

@MainActor
struct SchemaV6MigrationTests {
```

**Seed-copy-migrate harness** (MigrationTests.swift lines 110–172 — copy this pattern exactly):
```swift
    @Test("V5→V6: expenses with sourceLabel backfilled with accountID; sourceAccount unchanged (ACCT-08)")
    func v5StoreBackfillsAccountID() throws {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v5seed-\(UUID()).store")
        let migrateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v5tov6-\(UUID()).store")
        defer {
            try? FileManager.default.removeItem(at: seedURL)
            try? FileManager.default.removeItem(at: migrateURL)
        }

        // 1. Build V5 store and seed expenses (mirror v3StoreMigratesToV4 lines 122–137)
        try {
            let v5Schema = Schema(versionedSchema: SchemaV5.self)
            let config = ModelConfiguration(schema: v5Schema, url: seedURL)
            let container = try ModelContainer(
                for: v5Schema,
                migrationPlan: MigrationTestsPlanV5.self,   // stops at V5 (new helper — see below)
                configurations: [config]
            )
            let ctx = container.mainContext
            let e1 = SchemaV5.Expense(amount: Decimal(100))
            e1.sourceLabel = "HDFC CC"; e1.sourceAccount = "user@gmail.com"
            ctx.insert(e1)
            let e2 = SchemaV5.Expense(amount: Decimal(50))
            e2.sourceLabel = "ICICI Savings"; e2.sourceAccount = "user@gmail.com"
            ctx.insert(e2)
            let e3 = SchemaV5.Expense(amount: Decimal(25))   // nil sourceLabel — stays Unassigned
            ctx.insert(e3)
            try ctx.save(); try ctx.save()  // double-save flushes WAL (mirror line 136)
        }()

        try FileManager.default.copyItem(at: seedURL, to: migrateURL)  // mirror line 140

        // 2. Migrate to V6 (mirror lines 143–149)
        let v6Schema = Schema(versionedSchema: SchemaV6.self)
        let config = ModelConfiguration(schema: v6Schema, url: migrateURL)
        let container = try ModelContainer(
            for: v6Schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        let ctx = container.mainContext

        // 3. Assert (mirror lines 151–173 assertion pattern with #expect)
        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        #expect(accounts.count == 2, "Should create exactly 2 accounts")

        let expenses = try ctx.fetch(FetchDescriptor<Expense>())
        let hdfc = accounts.first { $0.sourceLabel == "HDFC CC" }
        let icici = accounts.first { $0.sourceLabel == "ICICI Savings" }

        let e1m = expenses.first { $0.amount == Decimal(100) }
        #expect(e1m?.accountID == hdfc?.id, "HDFC CC expense must be attributed")
        #expect(e1m?.sourceAccount == "user@gmail.com", "sourceAccount must be RETAINED unchanged (ACCT-08)")

        let e3m = expenses.first { $0.amount == Decimal(25) }
        #expect(e3m?.accountID == nil, "Nil-sourceLabel expense must remain Unassigned")

        #expect(hdfc?.typeRaw == "credit_card", "D-03: HDFC CC inferred as credit_card")
        #expect(icici?.typeRaw == "savings", "D-03: ICICI Savings inferred as savings")
    }
```

**MigrationTestsPlanV5 helper enum** (mirror MigrationTestsPlanV3 pattern at MigrationTests.swift lines 255–270):
```swift
/// Trimmed migration plan stopping at SchemaV5 — used to seed V5 stores in tests.
enum MigrationTestsPlanV5: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self]
    }
    static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3, v3ToV4, v4ToV5]
    }
    static let v1ToV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self, toVersion: SchemaV2.self, willMigrate: nil, didMigrate: nil)
    static let v2ToV3 = MigrationStage.custom(
        fromVersion: SchemaV2.self, toVersion: SchemaV3.self, willMigrate: nil, didMigrate: nil)
    static let v3ToV4 = MigrationStage.custom(
        fromVersion: SchemaV3.self, toVersion: SchemaV4.self, willMigrate: nil, didMigrate: nil)
    static let v4ToV5 = MigrationStage.custom(
        fromVersion: SchemaV4.self, toVersion: SchemaV5.self, willMigrate: nil, didMigrate: nil)
}
```

---

## Shared Patterns

### Typealias Flip (STAB-08 — Atomic Commit Requirement)
**Source:** `MyHomeApp/Persistence/Models/Note.swift` lines 1–19
**Apply to:** ALL six typealias files in a single commit that also updates `AppMigrationPlan.schemas`
- Expense.swift: `SchemaV5.Expense` → `SchemaV6.Expense`
- Note.swift: `SchemaV5.Note` → `SchemaV6.Note`
- NoteBlock.swift: `SchemaV5.NoteBlock` → `SchemaV6.NoteBlock`
- Category.swift: `SchemaV5.Category` → `SchemaV6.Category`
- Account.swift: (new) `typealias Account = SchemaV6.Account`
- Asset.swift: (new) `typealias Asset = SchemaV6.Asset`

### Explicit Save (CR-01)
**Source:** `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` lines 198, 235, 249
**Apply to:** All CRUD write operations in AccountsListView, EditAccountView, AccountDetailView, RoutineResetService
```swift
try context.save()   // CR-01: explicit save after every mutation
```

### Plain Text (T-02-15)
**Source:** `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` lines 162, 165
**Apply to:** All views displaying account name, type, balance — never `AttributedString(markdown:)`
```swift
Text(account.name ?? "")   // T-02-15: plain Text — never AttributedString(markdown:)
```

### Amount Guard (T-01-03)
**Source:** `MyHomeApp/Features/Expenses/AddExpenseView.swift` isSaveEnabled logic
**Apply to:** EditAccountView balance baseline validation
```swift
guard abs(balanceBaseline) < 1_000_000_000 else { /* reject */ }
```

### confirmationDialog for Delete
**Source:** `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` lines 95–109
**Apply to:** AccountsListView delete action

### NavigationStack-in-sheet
**Source:** `MyHomeApp/Features/Expenses/AddExpenseView.swift` line 54; `CategoryPickerView.swift` line 23
**Apply to:** EditAccountView, AccountPickerView

### @Observable + @MainActor service class
**Source:** `MyHomeApp/Features/Notes/RoutineResetService.swift` lines 12–14; `GmailSyncController.swift` lines 44–46
**Apply to:** RoutineResetService (keeping existing @Observable @MainActor markers)

### UserDefaults for device-local preferences
**Source:** `MyHomeApp/Features/Gmail/GmailSyncController.swift` (GmailAccountStore uses UserDefaults)
**Apply to:**
- `lastUsedAccountID` — last-used account for D-04 expense picker default
- `accountReviewPending` — D-02 first-launch review flag

### Pre-loop capture of @Model IDs before async boundary
**Source:** `MyHomeApp/Features/Gmail/GmailSyncController.swift` lines 481–486 (`categoryIDsByName`)
**Apply to:** GmailSyncController D-05 account attribution — capture `accountIDsByLabel: [String: UUID]` before the per-message loop, not inside it

---

## No Analog Found

All files in this phase have close analogs in the existing codebase. No new-territory patterns required.

---

## Metadata

**Analog search scope:** `MyHomeApp/Persistence/Schema/`, `MyHomeApp/Persistence/Models/`, `MyHomeApp/Features/Settings/`, `MyHomeApp/Features/Expenses/`, `MyHomeApp/Features/Budgets/`, `MyHomeApp/Features/Notes/`, `MyHomeApp/Features/Gmail/`, `MyHomeTests/`
**Files scanned:** 14 source files read in full
**Pattern extraction date:** 2026-06-09
