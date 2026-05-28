# Architecture Research

**Domain:** Personal iOS household-ops app (SwiftUI + SwiftData, CloudKit-ready, Gmail-ingested expense tracker + notes, future watchOS/widgets/sharing)
**Researched:** 2026-05-28
**Confidence:** HIGH for the SwiftUI/SwiftData/CloudKit shape (stable Apple-blessed APIs since iOS 17 with iOS 18/26 polish). MEDIUM for the Gmail ingestion pipeline (BackgroundTasks is well-trod, but Gmail-on-iOS specifically has fewer canonical references — design borrows from generic background-refresh + REST-client patterns).

> **Source caveat:** WebSearch was unavailable in this research run. Recommendations rely on Apple's published HIG / SwiftData / CloudKit / WidgetKit documentation patterns and conventional community guidance through iOS 18 / iOS 26 era (2024–2026). Anything marked **VERIFY** below should be re-checked against Apple's current docs before committing code.

---

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│  App Target (MyHomeApp)                                                  │
│  ┌───────────────────────────────────────────────────────────────────┐   │
│  │  Presentation Layer (SwiftUI)                                     │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌────────┐   │   │
│  │  │ Overview│  │Expenses │  │ Notes   │  │ Inbox   │  │Settings│   │   │
│  │  │  Tab    │  │  Tab    │  │  Tab    │  │ (review)│  │  Tab   │   │   │
│  │  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘  └────┬───┘   │   │
│  │       └────────────┴────────────┴────────────┴────────────┘       │   │
│  │                          @Query / @Environment                    │   │
│  └────────────────────────────┬──────────────────────────────────────┘   │
│                               │                                          │
│  ┌────────────────────────────┴──────────────────────────────────────┐   │
│  │  Domain Layer (pure Swift, no SwiftUI, no SwiftData imports)      │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────────┐ ┌─────────────────┐   │   │
│  │  │ Budget   │ │ Tag      │ │ Parse        │ │ ExpenseCandidate│   │   │
│  │  │ rules    │ │ suggest  │ │ confidence   │ │ (DTO)           │   │   │
│  │  └──────────┘ └──────────┘ └──────────────┘ └─────────────────┘   │   │
│  └────────────────────────────┬──────────────────────────────────────┘   │
│                               │                                          │
│  ┌────────────────────────────┴──────────────────────────────────────┐   │
│  │  Data Layer (SwiftData ModelContainer + thin stores)              │   │
│  │  ┌──────────────────────────────────────────────────────────────┐ │   │
│  │  │  ModelContainer (CloudKit-ready schema, App Group URL)       │ │   │
│  │  │  Expense · Category · Tag · Account · Note · ChecklistItem  │ │   │
│  │  │  ParsedEmailRecord · ProcessedEmailMarker                    │ │   │
│  │  └──────────────────────────────────────────────────────────────┘ │   │
│  └───────────────────┬───────────────────────────────┬──────────────┘   │
│                      │                               │                   │
│  ┌───────────────────┴──────────────┐  ┌─────────────┴──────────────┐    │
│  │  Ingestion Pipeline              │  │  Security / Platform       │    │
│  │  ┌─────────────────────────────┐ │  │  ┌───────────────────────┐ │    │
│  │  │ BackgroundTask scheduler    │ │  │  │ Face ID gate          │ │    │
│  │  │   ↓                         │ │  │  │ Keychain (OAuth)      │ │    │
│  │  │ GmailClient (REST + OAuth)  │ │  │  │ App Group container   │ │    │
│  │  │   ↓                         │ │  │  └───────────────────────┘ │    │
│  │  │ ParserRegistry → BankParser │ │  └────────────────────────────┘    │
│  │  │   ↓                         │ │                                    │
│  │  │ ExpenseCandidate            │ │                                    │
│  │  │   ↓ (confidence ≥ thresh)   │ │                                    │
│  │  │ ExpenseStore.save / Inbox   │ │                                    │
│  │  └─────────────────────────────┘ │                                    │
│  └──────────────────────────────────┘                                    │
└──────────────────────────────────────────────────────────────────────────┘
            │                                              │
   ┌────────┴─────────┐                          ┌────────┴────────┐
   │ Widget Extension │                          │ Watch App (post)│
   │  (reads shared   │                          │  (reads shared  │
   │   container)     │                          │   container)    │
   └──────────────────┘                          └─────────────────┘
```

### Component Responsibilities

| Component | Owns | Implementation |
|-----------|------|----------------|
| **MyHomeApp (App target)** | Lifecycle, `ModelContainer` injection, BG task registration, root view | `@main App`, `.modelContainer(...)`, `.backgroundTask(.appRefresh)` |
| **Presentation views** | Rendering, user input, navigation, simple local UI state | `View` + `@Query` + `@State` + `@Environment(\.modelContext)` |
| **Domain services** | Business rules (budget math, tag suggestion, confidence scoring) — no UI, no persistence | Pure Swift `struct`/`enum` + free functions in a Swift Package |
| **Data layer (`@Model` types)** | Persistence, schema, CloudKit-compatible shape | SwiftData `@Model` classes in the app target |
| **Stores (thin)** | Imperative writes that span multiple models (e.g. "save expense + create tag if missing") | Small `actor` or `struct` wrappers over `ModelContext` |
| **GmailClient** | OAuth token refresh, history list, message fetch | `URLSession` + `async/await`; isolated as a Swift Package |
| **ParserRegistry** | Picks the right `BankParser` for a given email (sender + subject heuristic) | Plain Swift struct holding `[BankParser]` |
| **BankParser (protocol)** | Turns one raw email into an `ExpenseCandidate` with a confidence score | Per-bank concrete types (`HDFCParser`, `ICICIParser`, …) |
| **IngestionCoordinator** | Orchestrates: fetch → parse → triage → persist; tracks "last processed" marker | Single `actor` owned by the BG task entry point |
| **Security** | Face ID gate, Keychain wrapper for OAuth refresh token | `LocalAuthentication` + small Keychain helper |
| **WidgetExtension (later)** | Read-only snapshot views (current spend, top category, pinned note) | `WidgetKit` timeline; reads same SwiftData container via App Group |
| **WatchApp (later)** | Quick-glance views; in v1 of watch, simply mirrors widget content | SwiftUI on watchOS; shared container if possible, else snapshot file |

---

## Recommended Project Structure

```
MyHome/
├── MyHome.xcodeproj
├── MyHomeApp/                        # iOS app target
│   ├── MyHomeApp.swift               # @main, ModelContainer, BG task registration
│   ├── RootView.swift                # TabView host + Face ID gate
│   ├── Features/                     # Vertical slices, one folder per tab
│   │   ├── Overview/
│   │   │   ├── OverviewView.swift
│   │   │   └── OverviewViewModel.swift  # @Observable, only if logic > trivial
│   │   ├── Expenses/
│   │   │   ├── ExpensesListView.swift
│   │   │   ├── ExpenseDetailView.swift
│   │   │   ├── ExpenseEditView.swift
│   │   │   ├── BudgetProgressView.swift
│   │   │   └── ExpenseChartsView.swift
│   │   ├── Notes/
│   │   │   ├── NotesListView.swift
│   │   │   ├── NoteEditorView.swift
│   │   │   └── ChecklistRow.swift
│   │   ├── Inbox/
│   │   │   ├── ReviewInboxView.swift     # low-confidence parses to confirm
│   │   │   └── CandidateReviewRow.swift
│   │   └── Settings/
│   │       ├── SettingsView.swift
│   │       ├── GmailAccountView.swift
│   │       └── FaceIDToggleView.swift
│   ├── Persistence/                  # SwiftData layer
│   │   ├── ModelContainer+App.swift  # Container factory (CloudKit-ready config)
│   │   ├── Models/
│   │   │   ├── Expense.swift
│   │   │   ├── Category.swift
│   │   │   ├── Tag.swift
│   │   │   ├── Account.swift
│   │   │   ├── Note.swift
│   │   │   ├── ChecklistItem.swift
│   │   │   ├── ParsedEmailRecord.swift
│   │   │   └── ProcessedEmailMarker.swift
│   │   └── Stores/
│   │       ├── ExpenseStore.swift   # actor over ModelContext for multi-step writes
│   │       └── NoteStore.swift
│   ├── Ingestion/                    # Wires Gmail → Parser → Store
│   │   ├── IngestionCoordinator.swift
│   │   ├── ProcessedEmailTracker.swift
│   │   └── BackgroundTaskScheduler.swift
│   ├── Security/
│   │   ├── FaceIDGate.swift
│   │   └── KeychainStore.swift
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   └── Localizable.xcstrings
│   └── Previews/
│       └── PreviewSampleData.swift   # In-memory ModelContainer with fixtures
├── Packages/                         # Local Swift Packages (added only when boundary earns it)
│   ├── BankParsers/                  # Pure Swift, depends only on Foundation
│   │   ├── Package.swift
│   │   ├── Sources/BankParsers/
│   │   │   ├── BankParser.swift      # protocol
│   │   │   ├── ParserRegistry.swift
│   │   │   ├── ExpenseCandidate.swift
│   │   │   ├── HDFC/HDFCParser.swift
│   │   │   ├── ICICI/ICICIParser.swift
│   │   │   └── SBI/SBIParser.swift
│   │   └── Tests/BankParsersTests/   # Golden-file tests: real email → expected candidate
│   └── GmailClient/                  # URLSession + OAuth wrapper
│       ├── Package.swift
│       ├── Sources/GmailClient/
│       │   ├── GmailClient.swift     # protocol + live implementation
│       │   ├── OAuthCoordinator.swift
│       │   └── DTO/GmailMessage.swift
│       └── Tests/GmailClientTests/   # URLProtocol stubs
├── WidgetExtension/                  # Added at the widget phase
└── WatchApp/                         # Added at the watch phase
```

### Structure Rationale

- **Vertical feature folders (`Features/<Tab>/`)**, not horizontal "Views/", "ViewModels/", "Models/". Cuts navigation friction; matches how features actually evolve (you change one feature at a time, not "all view models").
- **Persistence isolated in `Persistence/`** so the data layer stays auditable in one place. CloudKit migration only ever touches files inside this folder.
- **`Packages/` contains exactly two SPM modules to start: `BankParsers` and `GmailClient`.** Both have crisp, real boundaries: `BankParsers` is pure Swift with zero Apple-framework deps (testable on Linux even), and `GmailClient` is the network edge. Splitting these out pays for itself immediately because parser tests run in milliseconds without booting an iOS simulator.
- **Do NOT extract a `Persistence` package, a `DomainLogic` package, or a `UIComponents` package on day one.** SwiftData models live happily in the app target; the moment you put `@Model` types in a separate module you fight Xcode previews, schema migrations, and CloudKit entitlement scoping. Extract only if/when watch + widget + main app all need to share the same model code (and even then prefer App Group + same target source files via "Target Membership" first).
- **`Previews/PreviewSampleData.swift`** with an in-memory `ModelContainer` makes every SwiftUI preview fast and deterministic. Set this up on day one; it pays for itself within a week.

---

## Architectural Patterns

### Pattern 1: SwiftData `@Query` + thin actor stores (NOT MVVM with repositories)

**What:** Read paths use SwiftUI's `@Query` directly inside views. Write paths that touch more than one model go through a small `actor` "store" that wraps a `ModelContext`. No `Repository<Expense>` generic. No view model in between view and `@Query`.

**When to use:** Always, in this app. A two-user CRUD app does not benefit from a repository abstraction over SwiftData.

**Trade-offs:**
- **Pro:** Code is half the size; previews and `@Query` "just work"; less indirection to debug.
- **Pro:** SwiftData already *is* the repository — wrapping it in another layer is duplicate work that breaks live updates.
- **Con:** Views know about `@Model` types directly. That is the price of admission for SwiftData's reactivity; trying to hide it produces ceremony with no upside at this scale.
- **Con:** If you ever swap SwiftData for something else, you rewrite views. At two users, that's acceptable. (CloudKit-backed SwiftData is the actual future, not a swap.)

**Example:**
```swift
// Read path — directly in the view
struct ExpensesListView: View {
    @Query(sort: \Expense.occurredAt, order: .reverse) private var expenses: [Expense]

    var body: some View {
        List(expenses) { ExpenseRow(expense: $0) }
    }
}

// Write path — actor store, only when the write spans concerns
actor ExpenseStore {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func save(_ candidate: ExpenseCandidate, suggesting tag: Tag?) throws -> Expense {
        let expense = Expense(
            id: UUID(),
            amount: candidate.amount,
            occurredAt: candidate.occurredAt,
            merchant: candidate.merchant,
            sourceEmailID: candidate.sourceEmailID
        )
        if let tag { expense.tags.append(tag) }
        context.insert(expense)
        try context.save()
        return expense
    }
}
```

### Pattern 2: `@Observable` view models — only when a view's state is genuinely complex

**What:** Default to "stateful views" (plain SwiftUI views with `@State`, `@Query`, `@Environment`). Promote to an `@Observable` view model only when (a) the view has 3+ pieces of derived state, (b) the logic is independently testable, or (c) the same logic feeds two views.

**When to use:** `ExpenseEditView` with confidence-driven tag suggestion + form validation: yes, view model. `NotesListView` showing a `@Query` result: no, no view model.

**Trade-offs:**
- **Pro:** New-to-Swift developer learns SwiftUI idioms first, not architectural patterns.
- **Pro:** `@Observable` (iOS 17+) removes the `@Published` boilerplate of the Combine era.
- **Con:** "When is the view too big?" requires judgement. Heuristic: > 150 lines and > 3 `@State` fields = consider extracting.

**Example:**
```swift
@Observable
final class ExpenseEditViewModel {
    var amount: Decimal = 0
    var merchant: String = ""
    var selectedTag: Tag?
    var suggestedTags: [Tag] = []

    private let suggester: TagSuggester  // pure Swift, testable

    init(suggester: TagSuggester) { self.suggester = suggester }

    func merchantChanged() {
        suggestedTags = suggester.suggest(forMerchant: merchant)
    }

    var canSave: Bool { amount > 0 && !merchant.isEmpty }
}
```

### Pattern 3: Strategy-pattern bank parsers behind a `ParserRegistry`

**What:** Each bank gets one `BankParser` conformer. A `ParserRegistry` holds them all in priority order and picks the first whose `canHandle(_:)` returns true. Adding a new bank = add one file + register it in one line.

**When to use:** Always. This is exactly the kind of plugin shape email parsing wants.

**Trade-offs:**
- **Pro:** Zero churn in the ingestion pipeline when adding HDFC v2 or a new bank.
- **Pro:** Each parser is pure (`(email) -> ExpenseCandidate?`) and trivially golden-tested with stored fixture emails.
- **Con:** Two parsers can claim the same email. Mitigation: order the registry; log when multiple match in development builds.

**Example:**
```swift
public protocol BankParser: Sendable {
    /// Stable identifier, e.g. "hdfc.cc.v1".
    var id: String { get }
    /// Cheap pre-check (sender domain, subject keyword) before regex.
    func canHandle(_ email: RawEmail) -> Bool
    /// Returns nil if the email doesn't look parseable, even if canHandle was true.
    func parse(_ email: RawEmail) -> ExpenseCandidate?
}

public struct ExpenseCandidate: Sendable, Equatable {
    public let parserID: String
    public let amount: Decimal
    public let currency: String        // "INR" in v1
    public let occurredAt: Date
    public let merchant: String?
    public let accountHint: String?    // last 4 digits, "Credit Card", etc.
    public let confidence: Double      // 0.0 ... 1.0
    public let sourceEmailID: String
    public let rawSnippet: String      // for the review UI
}

public struct ParserRegistry: Sendable {
    public let parsers: [any BankParser]
    public func parse(_ email: RawEmail) -> ExpenseCandidate? {
        parsers.first(where: { $0.canHandle(email) })?.parse(email)
    }
}
```

### Pattern 4: Ingestion as an `actor` orchestrating typed steps

**What:** `IngestionCoordinator` is one `actor` that owns the pipeline: fetch new emails since marker → parse → bucket (auto-save vs. review) → persist → advance marker. Each step is a function whose inputs/outputs are value types — directly unit-testable with a fake `GmailClient`.

**When to use:** Always. Background-task entry point is a single line that calls `coordinator.runOnce()`.

**Trade-offs:**
- **Pro:** One reentrancy-safe place to reason about "did I process this email yet?".
- **Pro:** BGTask handler stays five lines; everything substantive is in the coordinator and is testable without `BGTaskScheduler`.
- **Con:** Actor hops have a tiny perf cost. Irrelevant at this volume.

### Pattern 5: Per-feature `@Model` types with shared protocols — NOT a generic `HouseholdItem` superclass

**What:** Each domain concept gets its own `@Model` class (`Expense`, `Note`, `ChecklistItem`). Cross-cutting concerns (timestamps, soft delete, search) are expressed as Swift protocols that the models conform to, not as inheritance.

**When to use:** Always, for this app. A `HouseholdItem` superclass with a `type` enum and a `payload: Data` blob is the seductively wrong design — it gives you "flexibility" today and a CloudKit migration nightmare tomorrow.

**Trade-offs of doing it right (per-feature models):**
- **Pro:** Strong types in queries, predicates, and views; no `if item.type == .expense` casting.
- **Pro:** CloudKit gives each entity its own `CKRecord` type — clean private→shared zone migration.
- **Pro:** Adding "chores" later = add `Chore.swift` + a tab. Zero blast radius on existing features.
- **Con:** A bit more typing up front. Worth it.

**Example shared concern as protocol:**
```swift
protocol Timestamped {
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
}

@Model final class Expense: Timestamped { /* … */ }
@Model final class Note: Timestamped { /* … */ }
```

---

## Data Layer Detail

### Model design rules (CloudKit-ready from day one)

These rules apply to every `@Model` class you write, even though v1 is local-only. They are cheap upfront and remove the migration tax later.

1. **Every model has a `id: UUID` you generate**, not just SwiftData's hidden persistent ID. CloudKit identifies records by name; using your own UUID lets you map deterministically.
2. **All non-relationship properties are optional or have defaults.** When SwiftData adopts CloudKit, the underlying `CKRecord` model treats all fields as optional. A non-optional, no-default field will refuse to migrate. Use `String?`, `Decimal?` with sane defaults, or initialize in the designated init.
3. **No `@Attribute(.unique)` on anything you plan to sync.** CloudKit does not support unique constraints on synced fields. Enforce uniqueness in code at write time (lookup-then-insert) instead. **VERIFY** against current SwiftData/CloudKit docs at implementation time — this is one of the most common breakages.
4. **All relationships are optional and have inverses declared.** CloudKit requires both sides of the relationship to be modeled; SwiftData's `@Relationship(inverse: \...)` does this. To-many relationships default to empty arrays; never make a relationship `let`.
5. **No `Codable`-only blob properties for things you might query later.** Store them as first-class fields. Use blobs only for genuinely opaque payloads (e.g. `rawEmailHTML`).
6. **No enums stored directly; store the raw value.** Save `categoryKind: String` (or `Int`), reconstruct the enum in Swift. CloudKit will round-trip strings/ints cleanly; custom enum coding is fragile under sync.
7. **Dates in UTC.** Never store local-time dates. The display layer formats with the user's locale.
8. **Money as `Decimal`, never `Double`.** Currency stored alongside as `String` (`"INR"`).

### Concrete schema sketch

```swift
@Model final class Expense {
    @Attribute(.unique) var id: UUID = UUID()   // remove .unique before enabling CloudKit
    var amount: Decimal = 0
    var currency: String = "INR"
    var occurredAt: Date = Date()
    var merchant: String?
    var note: String?
    var sourceEmailID: String?              // Gmail message id, nil for manual entry
    var parserID: String?                   // which BankParser produced it
    var confidence: Double = 1.0            // 1.0 for manual
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship var account: Account?
    @Relationship(inverse: \Tag.expenses) var tags: [Tag] = []
    @Relationship var category: Category?
}

@Model final class Tag {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var colorHex: String?
    @Relationship var expenses: [Expense] = []
}

@Model final class Category {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var isUserCreated: Bool = false
    var monthlyBudget: Decimal?
    var currency: String = "INR"
}

@Model final class Note {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var isPinned: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \ChecklistItem.note)
    var checklistItems: [ChecklistItem] = []
}

@Model final class ChecklistItem {
    @Attribute(.unique) var id: UUID = UUID()
    var text: String = ""
    var isDone: Bool = false
    var orderIndex: Int = 0
    @Relationship var note: Note?
}

@Model final class ProcessedEmailMarker {
    @Attribute(.unique) var gmailHistoryID: String = ""
    var processedAt: Date = Date()
}
```

> **Note on `.unique`:** Use it locally for v1 to catch duplicate-insert bugs early. Before enabling CloudKit, remove every `.unique` attribute and enforce uniqueness via a lookup-before-insert helper. Plan one phase line item: "strip `.unique` attributes."

### ModelContainer setup

```swift
// Persistence/ModelContainer+App.swift
extension ModelContainer {
    static func appContainer() -> ModelContainer {
        let schema = Schema([
            Expense.self, Tag.self, Category.self, Account.self,
            Note.self, ChecklistItem.self, ProcessedEmailMarker.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            // App Group URL from day one — even before widgets exist.
            url: URL.appGroupContainer.appending(path: "MyHome.store"),
            cloudKitDatabase: .none  // flip to .private("iCloud.com.reo.myhome") later
        )
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
```

---

## Data Flow

### Path A: Email becomes an Expense (the load-bearing flow)

```
   ┌────────────────────────────┐
   │  iOS triggers BG task      │  BGAppRefreshTask scheduled hourly-ish
   └─────────────┬──────────────┘
                 ↓
   ┌────────────────────────────┐
   │ BackgroundTaskScheduler    │  Hands control to IngestionCoordinator
   └─────────────┬──────────────┘
                 ↓
   ┌────────────────────────────┐
   │ IngestionCoordinator       │  Reads last gmailHistoryID marker
   │  .runOnce()                │
   └─────────────┬──────────────┘
                 ↓
   ┌────────────────────────────┐
   │ GmailClient                │  history.list since marker → message.get
   │  .fetchNew(since:)         │  Returns [RawEmail]
   └─────────────┬──────────────┘
                 ↓ [RawEmail]
   ┌────────────────────────────┐
   │ ParserRegistry             │  For each: canHandle? → parse
   │  .parse(_)                 │  Returns ExpenseCandidate? per email
   └─────────────┬──────────────┘
                 ↓ [ExpenseCandidate]
   ┌────────────────────────────┐
   │ Triage (pure function)     │  if confidence ≥ 0.85 → auto-save
   │                            │  else → review queue
   └────────┬──────────┬────────┘
            ↓          ↓
   ┌─────────────┐ ┌─────────────────────┐
   │ ExpenseStore│ │ ReviewQueueStore     │
   │ .save(...)  │ │ .enqueue(candidate) │
   └──────┬──────┘ └──────────┬──────────┘
          ↓                   ↓
   ┌────────────────────────────┐
   │ ModelContext.save()        │
   │ Advance ProcessedEmail-    │
   │ Marker                     │
   └─────────────┬──────────────┘
                 ↓
   ┌────────────────────────────┐
   │ SwiftUI views auto-refresh │  Via @Query observing ModelContext
   └────────────────────────────┘
```

**Testability boundary:** every step from "fetch" downward is pure or actor-isolated and accepts injectable dependencies. The only piece you cannot unit-test cleanly is the BGTask handler itself; integration-test the rest by injecting a fake `GmailClient` that returns canned `RawEmail` fixtures.

### Path B: User creates a Note

```
NotesListView (@Query) ──► tap "+" ──► NoteEditorView (sheet)
                                            │
                                            │  @State: title, body, [ChecklistItem]
                                            ↓
                              ModelContext.insert(Note(...))
                                            ↓
                                  ModelContext.save()
                                            ↓
                       NotesListView re-queries automatically
```

No view model, no store. SwiftData + `@Query` is enough. Adding ceremony here is the anti-pattern.

### State management

There is no global state container. State lives where it is observed:
- **Persistent shared state** → SwiftData (`@Query` reads, `ModelContext.save` writes).
- **Per-screen UI state** → `@State` (or `@Observable` view model for complex screens).
- **Cross-screen app state** (e.g. "is Face ID locked") → small `@Observable` injected via `.environment(...)`.
- **No Redux, no TCA, no Combine pipelines.** All flow is `async/await` + SwiftUI observation.

---

## Build Order — What Unlocks What

Order matters more than picking the perfect first feature. The point is to get an end-to-end thin slice working that exercises persistence + UI + tests, then layer everything else on top of a proven spine.

### Phase 1 — "Hello, SwiftData" (build this FIRST)
1. Xcode project, single iOS target, iOS 17+ deployment.
2. `Expense`, `Tag`, `Category` `@Model` types (CloudKit rules applied).
3. `ModelContainer+App.swift` with App Group URL.
4. `ExpensesListView` showing `@Query` results.
5. `ExpenseEditView` allowing manual add/edit.
6. `PreviewSampleData.swift` for fast previews.
7. Unit test: insert + query + delete an `Expense` in an in-memory container.

**Why first:** This is the spine. Until this works, nothing else can be tested visually. Manual expense entry is also the irreducible fallback if Gmail ingestion ever breaks — building it first makes it a real, used path, not a forgotten safety net.

### Phase 2 — Categories, tags, budget visualization
- `Category`, `Tag`; tag-picker UI; `BudgetProgressView`.
- Pure Swift `BudgetCalculator` (testable without SwiftData).

**Why:** Closes the manual-expense loop. App is now usable end-to-end without any backend dependency.

### Phase 3 — Notes + checklists
- `Note`, `ChecklistItem`; list, editor, pinned-toggle.

**Why:** Independent of expenses; lets you ship the second core feature without coupling. Cheap win that proves "schema additivity" — adding Notes did not touch Expense code.

### Phase 4 — Overview / Home
- Aggregate queries (current month spend, top 3 categories, pinned notes).
- Charts via Swift Charts.

**Why:** Sells the app to the user (yourself + wife). High motivation payoff.

### Phase 5 — Face ID gate + Settings shell
- `LocalAuthentication` wrapper; `RootView` switches between locked/unlocked.
- Settings tab scaffolded for upcoming Gmail account screen.

**Why:** Must exist before any financial data feels "trusted." Doing it now also forces you to think about app lifecycle (scenePhase) before adding background tasks.

### Phase 6 — `GmailClient` Swift Package (NO ingestion yet)
- OAuth flow (web view or `ASWebAuthenticationSession`), token to Keychain.
- `history.list` + `messages.get` against a real Gmail account.
- Test target with `URLProtocol`-stubbed responses + a manual "fetch latest 10 emails" debug button in Settings.

**Why:** Network + auth is the riskiest unknown. Prove it as a package in isolation, with a debug surface, before wiring it to anything.

### Phase 7 — `BankParsers` Swift Package, first parser (the one bank you use most)
- `BankParser` protocol + `ParserRegistry`.
- One concrete parser (e.g. HDFC credit card).
- Golden tests: real (anonymized) sample emails → expected `ExpenseCandidate`.

**Why:** Per-bank parsers are the long-tail. One parser proves the shape; the rest are a steady drip. Parsers are pure Swift and the easiest piece to TDD.

### Phase 8 — `IngestionCoordinator` + Review Inbox
- Wires GmailClient + ParserRegistry + ExpenseStore.
- Triage: confidence ≥ threshold auto-saves, else into Review Inbox UI.
- Manual "Run ingestion now" button before BGTask.

**Why:** Get the pipeline working in the foreground first. Background scheduling adds nondeterminism — fight that battle separately, with a known-good pipeline.

### Phase 9 — `BackgroundTasks` registration
- `BGAppRefreshTask` registered at launch; calls `coordinator.runOnce()`.
- Settings shows "Last ingested at …"; that one timestamp is your debugging lifeline.

**Why:** Trivial code, huge testing pain. Doing it last means everything it depends on already works.

### Phase 10 — More bank parsers
- Add ICICI, SBI, Axis, etc. as separate plan items. Each is one file + one registry line + tests.

### Phase 11+ — Optional / future
- **Widgets:** App Group is already in place; add `WidgetExtension` target reading the same `ModelContainer`. **VERIFY** whether your iOS target version allows direct `@Model` access from a widget process; if not, write a small "snapshot" JSON to the App Group container on each save and have the widget read that. (This snapshot pattern is the safer assumption — adopt it from day one for the widget timeline if direct sharing flakes.)
- **CloudKit:** strip `.unique`, set `cloudKitDatabase: .private(...)`, add iCloud entitlement + container, test private DB sync.
- **Sharing zone:** once private works, add a sharing flow for the wife's Apple ID.
- **Watch app:** mirrors the widget surface initially; full app later.

### Build-first vs. build-last summary

| Build FIRST | Build LAST |
|------|------|
| Manual expense entry | Background scheduling |
| SwiftData spine with one model | CloudKit migration |
| Preview sample data | Sharing across Apple IDs |
| App Group container path | Widgets / Watch |
| Face ID gate | Multi-bank parser long-tail |
| First bank parser as a Swift Package | A Settings screen with every knob |

---

## CloudKit-Readiness — Concrete Choices Today

| Choice today | Why it matters for CloudKit later |
|--------------|------------------------------------|
| Own `id: UUID` on every model | Stable identity across local↔CloudKit |
| All fields optional or defaulted | CloudKit treats every field as optional; non-defaulted required fields fail migration |
| No `@Attribute(.unique)` on synced fields (or marked to strip later) | CloudKit doesn't enforce uniqueness; SwiftData rejects unique attrs when CloudKit is enabled |
| Relationships always have inverses | CloudKit requires bidirectional modeling |
| No relationship cycles you can't break | Avoids infinite-loop cascade-delete issues during sync |
| Dates in UTC | Sync conflicts across time zones become trivial |
| `Decimal` for money | `Double` would round-trip lossily through `CKRecord` (cf. NSNumber coercion) |
| App Group container URL from v1 | Switching the container path later forces a one-time data dance you don't want |
| No raw `Data` blobs for queryable info | CloudKit `CKAsset` is fine for opaque blobs but you can't predicate on them |
| Enums stored as raw values | CloudKit serializes primitives cleanly; custom encoding strategies have bitten people |

**What would force a rewrite (avoid these):**
- A class-based inheritance hierarchy (`HouseholdItem` superclass with subclasses). SwiftData supports inheritance but CloudKit zone sharing + inherited entities is a known sharp edge — when one model gets shared, the entire inheritance tree is dragged in.
- Storing JSON blobs as the canonical representation of structured data.
- Using `@Attribute(.unique)` on properties you query by, then discovering CloudKit won't let you keep them.
- Building a custom encryption layer on top of SwiftData. CloudKit private DB is already encrypted in transit + at rest; Face ID + iOS sandboxing covers local-at-rest.

---

## Watch / Widget Architecture — Decide NOW, Implement LATER

You don't build these in v1, but two architecture decisions today prevent pain.

### Decision 1 — App Group container from day one (zero cost, huge payoff)

Add the App Group entitlement (`group.com.reo.myhome`) to the app target on day one, even with no widget/watch yet. Point your `ModelContainer` URL at the App Group container. Cost: one Info.plist line + one entitlement. Payoff: when you add a widget or watch app later, they can share the *same* database without a data migration.

### Decision 2 — Treat widget timelines as snapshot consumers, not live readers

The cleanest widget architecture: on every meaningful write (`ExpenseStore.save`, budget update), the app writes a tiny JSON snapshot file (`overview-snapshot.json`) to the App Group container with exactly what the widget needs (this month's spend, top category name, top category amount). The widget timeline provider reads that JSON. Reasons:

- Widgets run in a **different process** with strict memory/time limits. Opening a full `ModelContainer` from the widget process can work but is heavier and changes over iOS versions. **VERIFY** at implementation time.
- The snapshot is also exactly the API the watch app and the Lock Screen widget will want.
- It decouples widget render performance from your full schema's evolution.

You do not write the snapshot file in v1 — but you carve out the function call site (`SnapshotPublisher.republish()`) inside `ExpenseStore.save()` and make it a no-op. Then in the widget phase you implement it. One line of plumbing now, zero refactor later.

---

## Anti-Patterns — Refuse These if a Future Phase Suggests Them

### Anti-Pattern 1: Over-modularization on day one
**What people do:** Split the app into 6 Swift Packages (Core, Networking, Persistence, Domain, UI, Features) before writing any feature.
**Why it's wrong:** SwiftData previews break across module boundaries, schema migration tooling gets harder, and you spend a week on `Package.swift` files before printing "hello world." Two-user app + new-to-Swift developer = highest possible cost, lowest possible benefit.
**Do this instead:** App target + two packages (`BankParsers`, `GmailClient`) that have *real* boundaries (pure Swift, network edge). Extract more only when shared between targets (e.g. watch + iOS).

### Anti-Pattern 2: Repository pattern over SwiftData
**What people do:** Write `protocol ExpenseRepository { func all() async -> [Expense] }` and a `LiveExpenseRepository` wrapping `ModelContext`, "for testability."
**Why it's wrong:** SwiftData *is* the repository. Wrapping it (a) breaks `@Query` live updates because your view sees stale snapshots, (b) doubles your write surface, and (c) the "testability" win is illusory — you can spin up an in-memory `ModelContainer` in tests faster than your protocol can be mocked.
**Do this instead:** `@Query` in views for reads; small `actor` stores only when a write touches multiple models. Test against in-memory `ModelContainer`.

### Anti-Pattern 3: Coordinator pattern for navigation
**What people do:** Build a `RootCoordinator`, `ExpensesCoordinator`, `NoteCoordinator` to centralize navigation.
**Why it's wrong:** Coordinator pattern was a UIKit workaround for storyboards. `NavigationStack` with `navigationDestination(for:)` and a typed `path: [Route]` covers every legitimate need in SwiftUI.
**Do this instead:** Per-tab `NavigationStack` with typed routes. If you need deep-linking, add it as a single `OpenURL` handler that mutates the path.

### Anti-Pattern 4: Dependency-injection container framework
**What people do:** Pull in Swinject / Factory / Resolver and register every type.
**Why it's wrong:** Two users. You have maybe 8 types worth injecting. SwiftUI's `@Environment` + initializer injection covers everything.
**Do this instead:** Pass dependencies as init parameters or via `.environment(\.someKey, value)`. For tests, construct with fakes directly.

### Anti-Pattern 5: Clean Architecture five-layer cake
**What people do:** Entities / UseCases / Interactors / Presenters / Views, each in their own folder, with mappers between every boundary.
**Why it's wrong:** You will write more mappers than features. The original Clean Architecture writeup was about decoupling from external frameworks in 100k-line enterprise systems. This app is 5k lines.
**Do this instead:** Three layers — Data (`@Model` types), Domain (pure Swift for non-trivial rules), Presentation (SwiftUI). Skip Domain when the rule is one line.

### Anti-Pattern 6: Combine where `async/await` suffices
**What people do:** Build `AnyPublisher<[Expense], Error>` pipelines for everything.
**Why it's wrong:** Combine is legacy in 2026. `async/await` + `AsyncSequence` + SwiftData's observation cover the same ground with less ceremony, better stack traces, and less Apple-API risk.
**Do this instead:** `async` functions everywhere. Use `AsyncSequence` if you genuinely need streams (Gmail ingestion does not).

### Anti-Pattern 7: `HouseholdItem` superclass with a `kind` enum and a payload blob
**What people do:** "Future-proof" by making one model that holds anything — Expense, Note, Chore — distinguished by a `kind`.
**Why it's wrong:** You lose type safety in every predicate; CloudKit migration becomes brittle; queries become slower because every read touches every kind; UI code grows giant `switch kind` statements. The supposed "additivity" win is illusory — adding a new feature already only takes one new `@Model` + one tab in the per-feature-models design.
**Do this instead:** Per-feature `@Model` types. Share concerns via Swift protocols (`Timestamped`, `Pinnable`).

### Anti-Pattern 8: Premature parser abstractions
**What people do:** Build a `ParserConfiguration` DSL, a `ParserMiddleware` chain, a YAML loader for parser rules — before any second bank exists.
**Why it's wrong:** You don't know what the abstractions should be until you've written three parsers. The shape of HDFC vs. ICICI vs. Axis emails will surprise you.
**Do this instead:** Write one parser as concrete Swift. Write the second as concrete Swift. *Then* look for the duplication and extract.

### Anti-Pattern 9: Hand-rolled OAuth / token storage
**What people do:** Implement OAuth from scratch including PKCE, refresh, storage.
**Why it's wrong:** Crypto/auth is the one place "it works on my machine" silently means "it leaks tokens." Google's published OAuth-for-installed-apps flow + `ASWebAuthenticationSession` + Keychain is the canonical path.
**Do this instead:** Use `ASWebAuthenticationSession` for the auth web flow. Use Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. **VERIFY** Google's current iOS OAuth client-type rules; they tighten periodically.

### Anti-Pattern 10: Mocking SwiftData
**What people do:** Wrap `ModelContext` in a protocol so they can mock it.
**Why it's wrong:** In-memory `ModelContainer(isStoredInMemoryOnly: true)` is faster than your mock and tests the real query semantics.
**Do this instead:** Real `ModelContainer` in tests, pre-populated with fixtures.

---

## Integration Points

### External services

| Service | Integration pattern | Notes |
|---------|---------------------|-------|
| Gmail REST API | `URLSession` + bearer token; `history.list` for delta polling | Use `historyId` watermark, not `internalDate` — far cheaper. Free quota is massive at this volume. **VERIFY** scopes: `gmail.readonly` should suffice. |
| Google OAuth | `ASWebAuthenticationSession` for the user flow; refresh-token exchange via plain URLSession | Store refresh token in Keychain; access tokens are ephemeral and can stay in memory. **VERIFY** Google's installed-app OAuth client guidance hasn't changed. |
| CloudKit (later) | SwiftData `ModelConfiguration(cloudKitDatabase: .private(...))` | Requires paid Apple Developer Program + iCloud entitlement + container. Test against a real CloudKit dashboard from day one of the migration phase. |
| Face ID | `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, ...)` | Wrap in a small class so previews can fake-bypass; gate `RootView` on success. |
| BGTaskScheduler | `BGAppRefreshTaskRequest`; register identifier in Info.plist | iOS schedules opportunistically; never assume it runs on time. Always also expose a manual "Refresh now" button. |

### Internal boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `GmailClient` → `IngestionCoordinator` | `async` calls; returns `[RawEmail]` | `GmailClient` knows nothing about parsers or storage |
| `IngestionCoordinator` → `ParserRegistry` | Pure function call | Registry is `Sendable`, can be reused |
| `ParserRegistry` → `BankParser` | Protocol dispatch | Parsers are stateless |
| `IngestionCoordinator` → `ExpenseStore` | `async` actor call | Store owns the `ModelContext` for write transactions |
| Views → `ModelContext` | `@Environment(\.modelContext)` for writes; `@Query` for reads | Direct — no view-model layer for simple cases |
| App → Widget (later) | Shared SwiftData container via App Group + snapshot JSON | Decide on snapshot pattern now, implement later |
| App → Watch (later) | Same App Group container; `WatchConnectivity` only for live commands | Reads from shared store; do not invent a sync protocol |

---

## Scaling Considerations

| Scale | Architecture adjustments |
|-------|--------------------------|
| 1–2 users (forever) | None. The app is fine as designed. |
| Hypothetical "more users" | Not applicable — this is a personal-household app by charter. Refuse re-scoping. |

### Realistic "what breaks first" at this scale

1. **First "bottleneck": Gmail rate limits during initial backfill.** When you first turn on ingestion against a 5-year-old inbox, you'll hit Gmail quota. Fix: backfill in batches (e.g. 100 messages at a time, sleep between batches) and persist the marker after every batch.
2. **Second "bottleneck": parser drift.** Banks change email formats without notice. Fix: every parser stores a `parserID + version`; failures get logged to the Review Inbox with the raw email available; tests pin the parser version against known-good fixtures.
3. **Third "bottleneck": SwiftData migration.** When you add a new field, write a `VersionedSchema` and a `MigrationPlan` from day one. The CloudKit phase will be the first real migration; treat it as a phase, not a side-quest.

Performance is not a constraint at two users with low-volume data. Do not optimize anything until something is measurably slow.

---

## Sources

WebSearch was unavailable for this research run; the following are the canonical references the implementor should re-read before each relevant phase. Items marked **VERIFY** in the document above are the highest-priority confirmations.

- Apple Developer — [SwiftData documentation](https://developer.apple.com/documentation/SwiftData) — model + container + migration APIs.
- Apple Developer — [SwiftData with CloudKit](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) — current constraints on `.unique`, optionality, inverse relationships.
- Apple Developer — [Observation framework / `@Observable`](https://developer.apple.com/documentation/observation) — replaces `ObservableObject`/`@Published` in iOS 17+.
- Apple Developer — [BackgroundTasks framework](https://developer.apple.com/documentation/backgroundtasks) — `BGAppRefreshTask` registration and scheduling semantics.
- Apple Developer — [WidgetKit timelines](https://developer.apple.com/documentation/widgetkit) — confirm current guidance on accessing SwiftData from widget extensions.
- Apple Developer — [App Groups + shared container](https://developer.apple.com/documentation/xcode/configuring-app-groups) — entitlement setup; required for widget/watch data sharing.
- Apple Developer — [`ASWebAuthenticationSession`](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession) — OAuth web flow.
- Apple Developer — [`LocalAuthentication` / Face ID](https://developer.apple.com/documentation/localauthentication) — biometric gate.
- Google — [Gmail API: history.list](https://developers.google.com/gmail/api/reference/rest/v1/users.history/list) — delta polling pattern.
- Google — [OAuth 2.0 for Mobile & Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app) — installed-app flow.
- Project files: `/Users/reo/My Projects/my-home/.planning/PROJECT.md`

---

*Architecture research for: personal iOS household-ops app (SwiftUI + SwiftData + CloudKit-ready, Gmail-ingested expense tracker + notes, future watchOS/widgets/sharing)*
*Researched: 2026-05-28*
