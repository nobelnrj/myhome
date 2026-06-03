# Phase 7: Bank Parsers & Ingestion Pipeline - Pattern Map

**Mapped:** 2026-06-02
**Files analyzed:** 17 new/modified files
**Analogs found:** 17 / 17

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `MyHomeApp/Gmail/GmailFetchPort.swift` | port/protocol | request-response | `MyHomeApp/Gmail/GmailAuthPort.swift` | exact |
| `MyHomeApp/Features/Ingestion/BankEmailParser.swift` | protocol + value types | transform | `MyHomeApp/Gmail/GmailAuthPort.swift` (protocol seam) | role-match |
| `MyHomeApp/Features/Ingestion/HDFCParser.swift` | pure logic | transform | `MyHomeApp/Support/BudgetCalculator.swift` | role-match |
| `MyHomeApp/Features/Ingestion/ICICIParser.swift` | pure logic | transform | `MyHomeApp/Support/BudgetCalculator.swift` | role-match |
| `MyHomeApp/Features/Ingestion/ConfidenceScorer.swift` | pure logic | transform | `MyHomeApp/Support/BudgetCalculator.swift` | exact |
| `MyHomeApp/Features/Ingestion/DedupChecker.swift` | pure logic | transform | `MyHomeApp/Support/BudgetCalculator.swift` | exact |
| `MyHomeApp/Features/Ingestion/MerchantNormalizer.swift` | pure logic | transform | `MyHomeApp/Support/BudgetCalculator.swift` | exact |
| `MyHomeApp/Features/Ingestion/DismissedMessageStore.swift` | utility/store | CRUD | `MyHomeApp/Features/Gmail/GmailSyncController.swift` (UserDefaults pattern) | role-match |
| `MyHomeApp/Features/Gmail/GmailSyncController.swift` | controller | request-response | `MyHomeApp/Features/Gmail/GmailSyncController.swift` (extend existing) | exact |
| `MyHomeApp/Persistence/Schema/SchemaV4.swift` | model/migration | CRUD | `MyHomeApp/Persistence/Schema/SchemaV3.swift` | exact |
| `MyHomeApp/Persistence/Schema/MigrationPlan.swift` | migration | CRUD | `MyHomeApp/Persistence/Schema/MigrationPlan.swift` (extend existing) | exact |
| `MyHomeApp/MyHomeApp.swift` | app entry point | event-driven | `MyHomeApp/MyHomeApp.swift` (extend existing) | exact |
| `MyHomeApp/Features/Expenses/ExpenseListView.swift` | view | request-response | `MyHomeApp/Features/Expenses/ExpenseListView.swift` (extend existing) | exact |
| `MyHomeApp/Features/Expenses/ReviewInboxRow.swift` | component | request-response | `MyHomeApp/Features/Expenses/ExpenseRow.swift` | exact |
| `MyHomeApp/Features/Expenses/ExpenseRow.swift` | component | request-response | `MyHomeApp/Features/Expenses/ExpenseRow.swift` (extend existing) | exact |
| `MyHomeTests/Support/SpyGmailFetch.swift` | test double | request-response | `MyHomeTests/Support/SpyGmailAuth.swift` | exact |
| `MyHomeTests/HDFCParserTests.swift` + `ICICIParserTests.swift` + `ConfidenceScorerTests.swift` + `DedupCheckerTests.swift` + `MerchantNormalizerTests.swift` + `IngestionPipelineTests.swift` | tests | transform | `MyHomeTests/BudgetCalculatorTests.swift` + `MyHomeTests/GmailSyncControllerTests.swift` | exact |

---

## Pattern Assignments

### `MyHomeApp/Gmail/GmailFetchPort.swift` (port/protocol, request-response)

**Analog:** `MyHomeApp/Gmail/GmailAuthPort.swift`

**Imports pattern** (lines 1-4):
```swift
import Foundation
import AuthenticationServices
import UIKit
```
For GmailFetchPort, use:
```swift
import Foundation
```

**Protocol declaration pattern** (lines 5-17):
```swift
// MARK: - GmailAuthPort

/// Protocol seam that abstracts the three OAuth operations required by GmailSyncController.
/// Injecting this protocol lets unit tests run without touching the OS authentication stack
/// (SpyGmailAuth in MyHomeTests).
///
/// NOTE: This protocol is defined here for the production conformer.
/// The test double (SpyGmailAuth) in MyHomeTests/Support/SpyGmailAuth.swift also conforms.
/// SpyGmailAuth.swift declares `@testable import MyHome` — the protocol must be public.
///
/// D6-01: Use ASWebAuthenticationSession (no Google SignIn SDK).
/// D6-23: Wrap URLSession/OAuth behind a port/protocol (mirrors NotificationCenterPort).
public protocol GmailAuthPort: Sendable {
```

Mirror this exactly for GmailFetchPort:
```swift
// MARK: - GmailFetchPort

/// Protocol seam that abstracts Gmail API calls for email retrieval and profile.
/// Mirrors GmailAuthPort pattern (D6-23). Injected into GmailSyncController.
/// The test double (SpyGmailFetch) lives in MyHomeTests/Support/SpyGmailFetch.swift.
public protocol GmailFetchPort: Sendable {
    func getProfile(accessToken: String) async throws -> GmailProfile
    func listMessageIDs(accessToken: String, q: String, maxResults: Int) async throws -> [String]
    func getRawMessage(accessToken: String, messageID: String) async throws -> String
}

public struct GmailProfile: Decodable, Sendable {
    public let emailAddress: String
}
```

**Production conformer pattern** (lines 131-272 in GmailAuthPort.swift):
```swift
// MARK: - SystemGmailAuth

public final class SystemGmailAuth: GmailAuthPort, @unchecked Sendable {
    public init() {}
    // ...
}
```
Mirror as `SystemGmailFetch: GmailFetchPort, @unchecked Sendable`.

**URLSession request pattern** (lines 200-235 in GmailAuthPort.swift):
```swift
let url = URL(string: "https://oauth2.googleapis.com/token")!
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.timeoutInterval = 60
request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
// ...
do {
    let (data, response) = try await URLSession.shared.data(for: request)
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 400 {
        if let body = try? JSONDecoder().decode([String: String].self, from: data),
           let errorMsg = body["error"] {
            throw GmailAuthError.oauthError(errorMsg)
        }
    }
    return try JSONDecoder().decode(TokenResponse.self, from: data)
} catch let gmailError as GmailAuthError {
    throw gmailError
} catch {
    throw GmailAuthError.networkError(error)
}
```
For GET requests in SystemGmailFetch, use `Authorization: Bearer \(accessToken)` header instead of POST body. Same error-wrapping structure.

---

### `MyHomeApp/Features/Ingestion/BankEmailParser.swift` (protocol + value types, transform)

**Analog:** `MyHomeApp/Gmail/GmailAuthPort.swift` + `MyHomeApp/Gmail/NotificationCenterPort.swift`

**Protocol + value type pattern** (GmailAuthPort.swift lines 47-81):
```swift
// MARK: - TokenResponse

public struct TokenResponse: Decodable, Sendable {
    public let access_token: String
    public let expires_in: Int
    // ...
    public init(access_token: String, ...) { ... }
}
```

Apply the same structure for `ParsedExpense` (value type, Sendable) and `BankEmailParser` (protocol, Sendable):
```swift
public struct ParsedExpense: Sendable {
    public let amount: Decimal          // never Double (Pitfall 17)
    public let rawMerchant: String
    public let normalizedMerchant: String
    public let categoryHint: String?
    public let date: Date
    public let rawSourceLabel: String
    public let isReversal: Bool
    public let fingerprintScore: Double
    public let extractionScore: Double
}

public protocol BankEmailParser: Sendable {
    var parserID: String { get }
    var parserVersion: String { get }
    func canHandle(sender: String, subject: String) -> Bool
    func parse(rawEmail: String) -> ParsedExpense?
}
```

---

### `MyHomeApp/Features/Ingestion/HDFCParser.swift` + `ICICIParser.swift` (pure logic, transform)

**Analog:** `MyHomeApp/Support/BudgetCalculator.swift`

**Pure struct pattern** (BudgetCalculator.swift lines 67-116):
```swift
/// Pure static aggregation helpers for budget math.
///
/// All methods operate on already-fetched expense arrays (in-memory reduce).
/// No direct SwiftData fetching — callers supply the arrays (decouples math from @Query).
struct BudgetCalculator {
    static func monthlySpend(
        for expenses: [Expense],
        categories: [Category]
    ) -> [PersistentIdentifier: Decimal] { ... }
}
```

For parsers, use a `struct` (not `class`) conforming to `BankEmailParser`. No actor isolation needed — pure functions.

**Guard-and-return-nil pattern** (from BudgetCalculator):
```swift
// In BudgetCalculator: guard let category = expense.categories.first else { continue }
// In HDFCParser.parse(): early return nil on fingerprint failure:
guard allRequiredLiteralsPresent(in: body) else { return nil }
```

**Static constants for pre-filter** (mirroring BudgetCalculator static let):
```swift
struct HDFCParser: BankEmailParser {
    let parserID = "hdfc-v1"
    let parserVersion = "1.0"

    private static let allowedSenders: Set<String> = [
        "alerts@hdfcbank.com",   // [ASSUMED — confirm from corpus, D7-03]
        "notify@hdfcbank.com",
    ]
    private static let blockedSubjectKeywords: [String] = [
        "otp", "one time password", "verification code",
        "promotional", "offer", "statement",
    ]
    // ...
}
```

---

### `MyHomeApp/Features/Ingestion/ConfidenceScorer.swift` (pure logic, transform)

**Analog:** `MyHomeApp/Support/BudgetCalculator.swift`

**Exact structural mirror:**
```swift
// BudgetCalculator.swift lines 60-96:
struct BudgetCalculator {
    static func monthlySpend(...) -> [PersistentIdentifier: Decimal] { ... }
    static func uncategorizedSpend(for expenses: [Expense]) -> Decimal { ... }
    static func monthBoundaries(for month: DateComponents) -> (start: Date, end: Date)? { ... }
}
```

ConfidenceScorer follows same pattern — pure `struct` with `static func`:
```swift
public struct ConfidenceScorer {
    public static func score(_ result: ParsedExpense) -> Double {
        let extractionScore = computeExtractionScore(result)
        return result.fingerprintScore * 0.5 + extractionScore * 0.5
    }
    static func computeExtractionScore(_ result: ParsedExpense) -> Double { ... }
}
```

---

### `MyHomeApp/Features/Ingestion/DedupChecker.swift` (pure logic, transform)

**Analog:** `MyHomeApp/Support/BudgetCalculator.swift`

Same pure `struct` + `static func` pattern. Takes `[Expense]` as input (caller supplies array from SwiftData fetch, DedupChecker does not fetch):
```swift
// Mirrors BudgetCalculator.monthlySpend signature:
// static func monthlySpend(for expenses: [Expense], categories: [Category]) -> ...
public struct DedupChecker {
    public static func findDuplicate(
        of candidate: ParsedExpense,
        in existingExpenses: [Expense]
    ) -> Expense? { ... }
}
```

---

### `MyHomeApp/Features/Ingestion/MerchantNormalizer.swift` (pure logic, transform)

**Analog:** `MyHomeApp/Support/BudgetCalculator.swift`

Pure `struct` with `static let` seed table and `static func normalize`. The seed table pattern mirrors `BudgetColor`'s `enum` approach — static constants. No I/O, no SwiftData.

---

### `MyHomeApp/Features/Ingestion/DismissedMessageStore.swift` (utility/store, CRUD)

**Analog:** `GmailSyncController.swift` UserDefaults properties (lines 43-62)

**App Group UserDefaults pattern** (GmailSyncController.swift lines 107-109):
```swift
private var defaults: UserDefaults {
    UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
}
```

Apply the same suiteName `"group.com.reojacob.myhome"` in DismissedMessageStore. Pattern for set persistence mirrors the `stringArray` round-trip already used in the project:
```swift
public struct DismissedMessageStore {
    private static let key = "gmail_dismissed_message_ids"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
    }
    public static func isDismissed(_ messageID: String) -> Bool { ... }
    public static func dismiss(_ messageID: String) { ... }
    static func dismissed() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }
}
```

---

### `MyHomeApp/Features/Gmail/GmailSyncController.swift` — EXTENDED (controller, request-response)

**Analog:** `MyHomeApp/Features/Gmail/GmailSyncController.swift` (the file itself — extend, don't replace)

**Dependency injection pattern** (lines 102-128):
```swift
// MARK: - Dependencies
private let auth: any GmailAuthPort
private let keychain: any KeychainPort
private let now: () -> Date

init(
    auth: any GmailAuthPort = SystemGmailAuth(),
    keychain: any KeychainPort = SystemKeychainStore(),
    now: @escaping () -> Date = Date.init
) {
    self.auth = auth
    self.keychain = keychain
    self.now = now
    self.isConnected = (try? keychain.load(forKey: "refresh_token")) != nil
}
```

Add `fetch: any GmailFetchPort = SystemGmailFetch()` as the **third** init parameter, following the exact same defaulted-parameter pattern.

**sync() method stub site** (lines 231-275):
```swift
func sync() async {
    // ... proactive refresh ...
    syncStatus = .syncing
    let query: String
    // D6-10: compute query ...
    // Phase 6 stub: the actual Gmail API listMessages call is wired in plan 04.
    _ = query
    lastSyncedAt = now()
    syncStatus = .done
}
```

Replace the stub with the real pipeline. The `syncStatus = .syncing` / `syncStatus = .done` state-machine transitions stay.

**connectedEmail UserDefaults property** (lines 58-62):
```swift
var connectedEmail: String? {
    get { defaults.string(forKey: "gmail_connected_email") }
    set { defaults.set(newValue, forKey: "gmail_connected_email") }
}
```

UAT-6-05: populate this via `fetch.getProfile(accessToken:)` at the start of `sync()`.

---

### `MyHomeApp/Persistence/Schema/SchemaV4.swift` (model/schema, CRUD)

**Analog:** `MyHomeApp/Persistence/Schema/SchemaV3.swift`

**VersionedSchema declaration pattern** (SchemaV3.swift lines 21-31):
```swift
enum SchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV3.Expense.self,
            SchemaV3.Category.self,
            SchemaV3.Note.self,
            SchemaV3.NoteBlock.self,
        ]
    }
```

SchemaV4 mirrors this exactly with `Schema.Version(4, 0, 0)` and same four model types.

**Immutability comment** (SchemaV3.swift lines 4-9):
```swift
/// VersionedSchema v3.0.0 — copies V2's Expense + Category verbatim, adds Note + NoteBlock.
///
/// Rules:
/// - SchemaV1.swift and SchemaV2.swift are IMMUTABLE after they ship. Never edit them.
/// - SchemaV3 is an additive superset: it copies SchemaV2's Expense + Category verbatim
```
SchemaV4 must carry analogous header: "SchemaV3 is IMMUTABLE after it ships. SchemaV4 copies SchemaV3's models verbatim and adds ingestion fields to Expense."

**CloudKit-readiness rules comment** (SchemaV3.swift lines 10-20 — COPY VERBATIM):
```swift
/// CloudKit-readiness rules enforced (FND-03, ARCHITECTURE.md):
/// 1. Every stored property has a default or is optional.
/// 2. No @Attribute(.unique) anywhere (CloudKit does not support uniqueness constraints).
/// 3. Decimal for money (never Double — Pitfall 17).
/// 4. Full UTC timestamp for dates.
/// 5. currencyCode: String present for multi-currency-readiness.
/// 6. UUID primary key on all @Model types.
/// 7. @Relationship inverse declared on ONE side only per relationship ...
/// 8. No stored enums — use String raw values or Codable value types serialized to Data?.
```

**Expense @Model base fields pattern** (SchemaV3.swift lines 66-97 — COPY VERBATIM into SchemaV4.Expense):
```swift
@Model
final class Expense {
    var id: UUID = UUID()
    var amount: Decimal = Decimal(0)
    var currencyCode: String = "INR"
    var date: Date = Date()
    var note: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \SchemaV3.Category.expenses)
    var categories: [SchemaV3.Category] = []
    init(id: UUID = UUID(), amount: Decimal, ...) { ... }
}
```

Update relationship to `\SchemaV4.Category.expenses`. Then add the new ingestion fields after the existing ones (all `var fieldName: Type? = nil` pattern — CloudKit rule 1):
```swift
// --- New in SchemaV4: ingestion fields ---
var rawEmailBody: String? = nil      // ING-10, D7-10
var parserID: String? = nil          // ING-11, D7-11
var parserVersion: String? = nil     // ING-11, D7-11
var sourceLabel: String? = nil       // D7-15
var gmailMessageID: String? = nil    // ING-14, D7-07
var ingestionStateRaw: String? = nil // ING-12/13/14 — "autoSaved"|"needsReview"|"possibleDuplicate" (rule 8: String not enum)
var parseConfidence: Double? = nil   // ING-12 (ratio 0.0–1.0, not money — Double? ok here)
```

**kindRaw: String pattern** (SchemaV3.swift line 141 — confirms `ingestionStateRaw: String?` approach):
```swift
/// Block type stored as String raw value (NOT a stored enum — rule 8 / Pitfall 6).
/// Values: "text" | "checkbox"
var kindRaw: String = "text"
```

**reminderRecurrenceData: Data? pattern** (SchemaV3.swift line 120 — confirms nil-defaulted optional approach):
```swift
/// JSON-encoded ReminderRecurrence value type (never a stored enum — rule 8).
var reminderRecurrenceData: Data? = nil
```

---

### `MyHomeApp/Persistence/Schema/MigrationPlan.swift` — EXTENDED (migration, CRUD)

**Analog:** `MyHomeApp/Persistence/Schema/MigrationPlan.swift` (the file itself — append, never remove)

**schemas array append pattern** (MigrationPlan.swift lines 9-11):
```swift
static var schemas: [any VersionedSchema.Type] {
    [SchemaV1.self, SchemaV2.self, SchemaV3.self]   // append V3 — never remove V1/V2
}
```
Becomes:
```swift
static var schemas: [any VersionedSchema.Type] {
    [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self]
}
```

**stages array append pattern** (MigrationPlan.swift line 14):
```swift
static var stages: [MigrationStage] {
    [v1ToV2, v2ToV3]
}
```
Becomes `[v1ToV2, v2ToV3, v3ToV4]`.

**Custom stage pattern — COPY EXACTLY** (MigrationPlan.swift lines 17-25):
```swift
// Use .custom(willMigrate: nil, didMigrate: nil) rather than .lightweight
// to sidestep the iOS 17.0–17.3 SchemaMigrationPlan interaction bug (FB13812722).
// Semantically identical for additive-only changes (new entity + new optional relationship).
static let v1ToV2 = MigrationStage.custom(
    fromVersion: SchemaV1.self,
    toVersion: SchemaV2.self,
    willMigrate: nil,
    didMigrate: nil
)
```

V3→V4 stage (add after v2ToV3):
```swift
// V4 adds only new optional/defaulted fields to Expense — purely additive.
// willMigrate/didMigrate are nil. .custom over .lightweight sidesteps FB13812722.
static let v3ToV4 = MigrationStage.custom(
    fromVersion: SchemaV3.self,
    toVersion: SchemaV4.self,
    willMigrate: nil,
    didMigrate: nil
)
```

---

### `MyHomeApp/MyHomeApp.swift` — EXTENDED (app entry point, event-driven)

**Analog:** `MyHomeApp/MyHomeApp.swift` (the file itself — add BGTask registration)

**Current body structure** (MyHomeApp.swift lines 22-46):
```swift
var body: some Scene {
    WindowGroup {
        RootView()
            .onAppear {
                setupNotifications()
            }
    }
    .modelContainer(container)
}
```

Add BGAppRefreshTask handler and `@Environment(\.scenePhase)` to the Scene. The `.backgroundTask(.appRefresh(...))` modifier chains after `.modelContainer(container)`:
```swift
.backgroundTask(.appRefresh("com.reojacob.myhome.emailrefresh")) {
    await MainActor.run {
        // access gmailSyncController and call sync()
    }
}
```

**`@State` pattern for controller ownership** (currently in RootView — may need to move to MyHomeApp for BGTask access — see RESEARCH Open Question 2):
The existing `let container: ModelContainer` and `@State private var notificationDelegate` pattern shows how top-level state is held. `gmailSyncController` moves here from RootView as `@State private var gmailSyncController = GmailSyncController()`.

---

### `MyHomeApp/Features/Expenses/ExpenseListView.swift` — EXTENDED (view, request-response)

**Analog:** `MyHomeApp/Features/Expenses/ExpenseListView.swift` (the file itself)

**@Query + List pattern** (ExpenseListView.swift lines 18-82):
```swift
@Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
@Environment(\.modelContext) private var context

var body: some View {
    NavigationStack {
        Group {
            if expenses.isEmpty {
                ContentUnavailableView(...)
            } else {
                List {
                    ForEach(expenses) { expense in
                        ExpenseRow(expense: expense)
                            .contentShape(Rectangle())
                            .onTapGesture { editingExpense = expense }
                    }
                    .onDelete(perform: deleteExpenses)
                }
                .listStyle(.insetGrouped)
            }
        }
    }
}
```

Phase 7 adds a second `@Query` (or computed filter on existing query) for review items. The "Needs Review" section inserts before the main `ForEach`:
```swift
// Add above the main ForEach:
if !reviewItems.isEmpty {
    Section("Needs Review") {
        ForEach(reviewItems) { expense in
            ReviewInboxRow(expense: expense)
        }
    }
}
```

Badge count: derive from `reviewItems.count` bound to the tab item badge.

---

### `MyHomeApp/Features/Expenses/ReviewInboxRow.swift` (component, request-response)

**Analog:** `MyHomeApp/Features/Expenses/ExpenseRow.swift`

**Row layout pattern** (ExpenseRow.swift lines 1-43 — COPY STRUCTURE):
```swift
import SwiftUI

struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(expense.amount.formattedINR())
                .font(.headline)
                .foregroundStyle(expense.amount < 0 ? Color(.systemGreen) : Color(.label))
                .frame(width: 100, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            VStack(alignment: .leading, spacing: 2) {
                if let note = expense.note, !note.isEmpty {
                    Text(note).font(.body).lineLimit(1).truncationMode(.tail)
                }
                Text(expense.date.formattedForExpenseList())
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
```

ReviewInboxRow uses the same `HStack` skeleton. Add:
- `sourceLabel` text below date (secondary, caption weight)
- Swipe actions (`.swipeActions(edge: .trailing)`) for accept/discard

**"auto" marker in ExpenseRow** (extend existing ExpenseRow): add a conditional envelope glyph when `expense.parserID != nil` (or `ingestionStateRaw == "autoSaved"`):
```swift
// Add to the trailing VStack, after date:
if expense.ingestionStateRaw == "autoSaved" {
    Image(systemName: "envelope")
        .font(.caption2)
        .foregroundStyle(.secondary)
}
```

---

### `MyHomeTests/Support/SpyGmailFetch.swift` (test double, request-response)

**Analog:** `MyHomeTests/Support/SpyGmailAuth.swift` — COPY STRUCTURE EXACTLY

**Full spy pattern** (SpyGmailAuth.swift lines 1-93):
```swift
import Testing
import AuthenticationServices
@testable import MyHome

/// In-memory spy that returns canned results ...
public final class SpyGmailAuth: GmailAuthPort, @unchecked Sendable {

    // MARK: - Settable stubs
    public var authorizeResult: String = "stub_code"
    // ...

    /// When non-nil, authorize() throws this error instead of returning authorizeResult.
    public var shouldThrowOnAuthorize: Error? = nil

    // MARK: - Recorded calls
    public private(set) var authorizeCalls: [(URL, String, String)] = []

    public init() {}

    // MARK: - GmailAuthPort
    public func authorize(...) async throws -> String {
        authorizeCalls.append(...)
        if let error = shouldThrowOnAuthorize { throw error }
        return authorizeResult
    }

    // MARK: - Reset
    public func reset() {
        authorizeCalls = []
        shouldThrowOnAuthorize = nil
    }
}
```

SpyGmailFetch mirrors this with three methods (getProfile, listMessageIDs, getRawMessage), three result stubs, three shouldThrow properties, three recorded-call arrays, and a reset() method. Import is `@testable import MyHome` (no AuthenticationServices needed).

---

### Test files: `HDFCParserTests.swift`, `ICICIParserTests.swift`, `ConfidenceScorerTests.swift`, `DedupCheckerTests.swift`, `MerchantNormalizerTests.swift`, `IngestionPipelineTests.swift`

**Analog A (pure logic, no SwiftData):** `MyHomeTests/NotificationSchedulerTests.swift`

**Test suite header + SpyCenter injection pattern** (NotificationSchedulerTests.swift lines 1-17):
```swift
import Testing
import UserNotifications
import Foundation
@testable import MyHome

/// NotificationSchedulerTests — unit tests for NotificationScheduler via SpyCenter seam.
@MainActor
struct NotificationSchedulerTests {
```

Parser/scorer/dedup/normalizer tests: same header, substitute `import Foundation` (no UserNotifications), inject `SpyGmailFetch` or no spy (for pure functions).

**@Test naming pattern** (NotificationSchedulerTests.swift line 22):
```swift
@Test("buildRequestsLeadAlerts: timed reminder with 2 lead offsets builds 3 requests — SC-R1")
func buildRequestsLeadAlerts() throws {
```
Follow same `"description: expectation — REQ-ID"` naming convention.

**Analog B (with SwiftData in-memory container):** `MyHomeTests/BudgetCalculatorTests.swift`

**makeContainer() + @MainActor pattern** (BudgetCalculatorTests.swift lines 15-21):
```swift
@MainActor
struct BudgetCalculatorTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Cat.self, configurations: config)
    }
```

`IngestionPipelineTests.swift` (which tests full pipeline including SwiftData insert) uses this exact makeContainer pattern.

**`GmailSyncControllerTests.swift` extension pattern** (GmailSyncControllerTests.swift lines 21-35):
```swift
@MainActor
struct GmailSyncControllerTests {
    private var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
    }
    private func resetDefaults() {
        defaults.removeObject(forKey: "gmail_last_synced_at")
        // ...
    }
    @Test("...")
    func someTest() async {
        resetDefaults()
        defer { resetDefaults() }
        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let controller = GmailSyncController(auth: spy, keychain: keychain, now: { fixedNow })
        // ...
    }
}
```

When extending GmailSyncControllerTests for Phase 7 (pipeline tests, UAT-6-05), inject `SpyGmailFetch` as third parameter:
```swift
let fetch = SpyGmailFetch()
let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch, now: { fixedNow })
```

**Table-driven test with `arguments:` pattern** (from RESEARCH.md Code Example 3 — mirrors BudgetCalculatorTests approach):
```swift
@Test("parse credit-card spend from fixture", arguments: [
    ("hdfc_cc_spend_1.eml", Decimal(1250.00), "Zomato", false),
    ("hdfc_refund.eml",     Decimal(-450.00),  "HPCL",   true),
])
func parsesKnownFixtures(filename: String, expectedAmount: Decimal, expectedMerchant: String, isReversal: Bool) throws {
    let raw = try loadFixture(filename)
    let sut = HDFCParser()
    let result = try #require(sut.parse(rawEmail: raw))
    #expect(result.amount == expectedAmount)
    #expect(result.normalizedMerchant == expectedMerchant)
    #expect(result.isReversal == isReversal)
}
```
Fixtures live in `MyHomeTests/Fixtures/*.eml` (resource bundle). `loadFixture(_:)` is a shared test helper that loads from `Bundle(for: ...)`.

---

## Shared Patterns

### `@MainActor @Observable` Controller
**Source:** `MyHomeApp/Features/Gmail/GmailSyncController.swift` lines 39-41 + `MyHomeApp/Security/LockController.swift` lines 33-34
**Apply to:** GmailSyncController (existing), any new controller managing Review Inbox observable state
```swift
@MainActor
@Observable
final class GmailSyncController {
```

### Dependency Injection via Defaulted Init Parameters
**Source:** `GmailSyncController.swift` lines 118-128 and `LockController.swift` lines 77-82
**Apply to:** GmailSyncController (add `fetch:` parameter), any new controller
```swift
init(
    auth: any GmailAuthPort = SystemGmailAuth(),
    keychain: any KeychainPort = SystemKeychainStore(),
    now: @escaping () -> Date = Date.init
) {
    self.auth = auth
    self.keychain = keychain
    self.now = now
    // ...
}
```

### App Group UserDefaults Access
**Source:** `GmailSyncController.swift` lines 107-109 and `LockController.swift` lines 67-69
**Apply to:** GmailSyncController, DismissedMessageStore, any new UserDefaults-backed state
```swift
private var defaults: UserDefaults {
    UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
}
```

### CloudKit-Safe @Model Fields
**Source:** `SchemaV3.swift` lines 10-20 (rules header) and lines 66-97 (Expense model)
**Apply to:** SchemaV4.Expense new fields
Rules: all optional/defaulted, no `@Attribute(.unique)`, no stored enums (use `String? = nil` raw values), Decimal for money, Double only for ratios.

### String Raw Value for State (Not Stored Enum)
**Source:** `SchemaV3.swift` line 141 (`kindRaw: String = "text"`) and line 120 (`reminderRecurrenceData: Data? = nil`)
**Apply to:** SchemaV4.Expense.ingestionStateRaw
```swift
/// Ingestion state stored as String raw value. nil for manual expenses.
/// Values: "autoSaved" | "needsReview" | "possibleDuplicate"
var ingestionStateRaw: String? = nil
```

### Public Protocol + @unchecked Sendable Conformer
**Source:** `GmailAuthPort.swift` lines 17-44 (protocol) + lines 131-132 (conformer)
**Apply to:** GmailFetchPort + SystemGmailFetch, BankEmailParser + HDFCParser/ICICIParser
```swift
public protocol XPort: Sendable { ... }
public final class SystemX: XPort, @unchecked Sendable {
    public init() {}
}
```

### Test Isolation with resetDefaults() + defer
**Source:** `GmailSyncControllerTests.swift` lines 26-34 and pattern at lines 38-46
**Apply to:** All test files that touch App Group UserDefaults
```swift
private func resetDefaults() {
    defaults.removeObject(forKey: "gmail_last_synced_at")
    defaults.removeObject(forKey: "gmail_access_token_expiry")
    // ... all touched keys
}

@Test("...")
func someTest() async {
    resetDefaults()
    defer { resetDefaults() }
    // test body
}
```

### URLSession GET with Bearer Token
**Source:** `GmailAuthPort.swift` lines 200-235 (POST pattern) — adapt for GET
**Apply to:** SystemGmailFetch.getProfile, listMessageIDs, getRawMessage
```swift
var request = URLRequest(url: url)
request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
request.timeoutInterval = 60
let (data, _) = try await URLSession.shared.data(for: request)
return try JSONDecoder().decode(SomeDecodable.self, from: data)
```

---

## No Analog Found

All Phase 7 files have close analogs in the existing codebase. No files require falling back to RESEARCH.md patterns exclusively — however, the following have partial coverage only:

| File | Role | Data Flow | Note |
|------|------|-----------|------|
| `MyHomeTests/Fixtures/*.eml` | test fixture | n/a | No fixture files exist yet; pattern is straightforward Bundle resource loading, not code |
| `Info.plist` BGTask additions | config | n/a | No existing BGTask keys in Info.plist; follows Apple documentation pattern (RESEARCH.md §BGAppRefreshTask) |

---

## Metadata

**Analog search scope:** `MyHomeApp/Gmail/`, `MyHomeApp/Features/`, `MyHomeApp/Persistence/Schema/`, `MyHomeApp/Support/`, `MyHomeApp/Security/`, `MyHomeTests/Support/`, `MyHomeTests/`
**Files scanned:** 14 source files read in full
**Pattern extraction date:** 2026-06-02
