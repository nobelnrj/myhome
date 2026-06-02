# Phase 7: Bank Parsers & Ingestion Pipeline - Research

**Researched:** 2026-06-02
**Domain:** SwiftData schema migration, Gmail API email fetch, email parsing/confidence scoring, BGAppRefreshTask, SwiftUI ingestion pipeline
**Confidence:** HIGH (core patterns), MEDIUM (HDFC/ICICI email format specifics — real corpus required)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Target Banks (D7-01/02/03):**
- v1 ships HDFC + ICICI parsers only. Alert types: credit-card spends, account/debit alerts, UPI transaction emails. Let real email corpus drive which templates get written. Collect 50+ real anonymized emails per bank BEFORE building parsers. Confidence threshold (0.85) needs real-data calibration after first week.

**Review Inbox (D7-04/05/06/07):**
- Inbox lives as a count badge on the Expenses tab, opening a "Needs Review" section at the top of the expense list — no new tab.
- Each review row shows parsed fields only (amount, normalized merchant, suggested category, date, source label). No raw-email snippet, no low-confidence-reason text.
- Triage actions: one-tap-accept, tap-to-edit, swipe-to-discard.
- Swipe-to-discard records email's message-ID as dismissed. Dismissed IDs never re-surface on next sync.

**Auto-save feedback (D7-08/09):**
- High-confidence expenses appear in the list with a subtle "auto" marker (envelope glyph). No notifications. Source distinction derivable from presence of parserID.
- Best-guess category from merchant seed (static). Falls back to Uncategorized when no seed hint.

**Forensics and merchant data (D7-10/11/12):**
- Store full raw email body against each ingested expense. Local-only, Face ID gated. No cloud in v1.
- Store parserID + parserVersion on every ingested expense.
- Claude-curated, hardcoded ~20-30 Indian-merchant seed table. Not user-editable in v1.

**Duplicate handling (D7-13/14):**
- Dedup key: (amount + merchant-substring + date ±1 day).
- Flagged duplicate lands in Review Inbox marked "Possible duplicate of <existing expense>", shown side-by-side.
- Never silent-merge. User swipes-discard or accepts.

**Account/Source label (D7-15):**
- Persist parsed card/account string ("HDFC ••1234", "a/c XX5678") on each ingested expense. Display on expense row/detail. No Account entity, no balance tracking. Full account management deferred to v2.

**Schema (D7-16):**
- SchemaV4 extends Expense @Model additively: raw email body, parserID, parserVersion, source/account label, ingestion state (auto-saved / needs-review / possible-duplicate). Plus dismissed-message-ID tracking.
- Must obey CloudKit-ready rules (all optional/defaulted, no @Attribute(.unique)).
- Chain existing AppMigrationPlan V3→V4.

**UAT carry-over (UAT-6-05):**
- Populate GmailSyncController.connectedEmail via Gmail users.getProfile (emailAddress). This is the first real Gmail API call in this project; wired in Phase 7.

### Claude's Discretion

- Confidence-scoring mechanics (how 0.85 is computed).
- Reversal/refund matching logic (standalone negative vs matched reversal).
- BGAppRefreshTask cadence (must be device-verified overnight; simulator not representative).
- Review Inbox / "auto" marker / source-label exact visual treatment — UI-SPEC.
- Exact model shape: new fields on Expense vs separate ReviewItem/PendingExpense @Model.

### Deferred Ideas (OUT OF SCOPE)

- Account management + balance tracking (v2 phase).
- User-editable merchant seed (v2).
- Per-merchant learned category memory (v2).
- Inbox/budget push notifications (v2).
- More bank parsers beyond HDFC + ICICI (v2).
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ING-04 | BGAppRefreshTask registered, runs ingestion opportunistically | BGAppRefreshTask registration pattern (§BGAppRefreshTask) |
| ING-06 | v1 ships HDFC + ICICI parsers | Parser architecture (§Parser Architecture) |
| ING-07 | Whole-template fingerprint matching separate from value extraction | Two-stage parse pattern (§Confidence Scoring) |
| ING-08 | Parsers reject OTP / promotional / verification emails via sender+subject pre-filters | Pre-filter pattern (§Parser Architecture) |
| ING-09 | Reversal/refund emails create negative-amount entries | Reversal detection (§Parser Architecture) |
| ING-10 | Raw email body stored against every ingested expense | SchemaV4 rawEmailBody field (§SchemaV4 Migration) |
| ING-11 | Every ingested expense records parserID and parserVersion | SchemaV4 parserID/parserVersion fields (§SchemaV4 Migration) |
| ING-12 | Confidence ≥ 0.85 auto-saves; below threshold → Review Inbox | Confidence model + ingestionStateRaw (§Confidence Scoring, §SchemaV4) |
| ING-13 | Review Inbox: one-tap-accept, tap-to-edit, swipe-to-discard | GmailIngestionController + dismissed-ID tracking (§Dismissed ID Tracking) |
| ING-14 | Dedup: (amount + merchant-substring + date ±1 day), duplicates flag inbox | Dedup algorithm (§Dedup Logic) |
| ING-15 | Merchant-normalization seed table (~20-30 Indian merchants) applied at parse time | MerchantNormalizer (§Merchant Normalization) |
</phase_requirements>

---

## Summary

Phase 7 connects Phase 6's OAuth token to real Gmail email retrieval, runs those emails through per-bank parsers, and writes the results into a SchemaV4 SwiftData store. The primary challenges are (1) designing the schema extension that survives a CloudKit-ready V3→V4 migration, (2) building parsers against a real email corpus that doesn't yet exist, and (3) wiring a best-effort BGAppRefreshTask that won't confuse Reo when it doesn't fire reliably on simulator.

The good news is that every non-trivial piece of new logic — parsers, confidence scorer, dedup, merchant normalizer, dismissed-ID tracker — can be written as a pure Swift function and table-tested in Swift Testing without touching the network. The network is already behind the GmailAuthPort seam; Phase 7 adds a parallel GmailFetchPort seam for email retrieval. The GmailSyncController's `sync()` method is where the pipeline gets wired together.

Because real bank email formats are not known until a corpus is collected, the planner must sequence the parser work AFTER a corpus-collection task. Parser code that is not validated against real emails is guesswork; the 0.85 threshold is similarly uncalibratable without real data. The plan should name this explicitly and put a human checkpoint before parser implementation.

**Primary recommendation:** SchemaV4 puts all new ingestion fields on the existing Expense @Model as optional/defaulted properties (not a separate ReviewItem model), using a custom nil-nil MigrationStage that sidesteps the iOS 17.0-17.3 SchemaMigrationPlan bug already documented in this codebase (see MigrationPlan.swift comment re: FB13812722). A separate in-memory/UserDefaults dismissed-ID set handles swipe-to-discard persistence without touching SwiftData.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Gmail email retrieval (messages.list/get, getProfile) | GmailFetchPort (network port seam) | GmailSyncController (orchestrator) | Network must be behind a port for testability; controller owns pipeline state |
| Email-to-ParsedExpense conversion (HDFC/ICICI parsers) | Pure Swift functions (BankEmailParser) | GmailSyncController (caller) | Pure functions are table-testable; no actor needed for parsing |
| Confidence scoring | Pure Swift function (ConfidenceScorer) | BankEmailParser (consumer) | Deterministic math, no state |
| Ingestion triage (auto-save / inbox / discard) | GmailSyncController | SwiftData (persistence) | Controller owns the state machine; SwiftData owns durable storage |
| Review Inbox UI (badge, section, triage actions) | Expenses tab / ExpenseListView | GmailSyncController (state source) | Expense-related content stays in Expenses tab (D7-04) |
| Dedup check | Pure Swift function (DedupChecker) | GmailSyncController (caller) | Query + predicate logic; needs ModelContext injection for tests |
| Merchant normalization | Pure Swift struct (MerchantNormalizer) | BankEmailParser (consumer) | Static lookup table, no I/O |
| Dismissed message-ID tracking | App Group UserDefaults | GmailSyncController (reader/writer) | Lightweight set; no SwiftData @Model needed |
| BGAppRefreshTask registration + scheduling | App entry point (MyHomeApp.swift) | GmailSyncController (work target) | Registration must happen at app launch, before end of launch sequence |
| SchemaV4 migration | AppMigrationPlan (V3→V4 stage) | SchemaV4.swift | Follows the existing V1/V2/V3 chaining pattern |

---

## Standard Stack

### Core — all Apple-native, zero third-party

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftData | iOS 17+ (built-in) | Persistence; SchemaV4 Expense extension | Already in use; VersionedSchema V1-V3 chained |
| BackgroundTasks | iOS 13+ (built-in) | BGAppRefreshTask registration + scheduling | Only Apple API for background fetch on iOS |
| Foundation (URLSession) | iOS 17+ (built-in) | Gmail API HTTP calls via GmailFetchPort | Already used in GmailAuthPort/SystemGmailAuth |
| Swift Testing | iOS 17+ (built-in) | Table-driven parser + scoring tests | Already the project's test framework (FND-06) |
| SwiftUI | iOS 17+ (built-in) | Review Inbox UI, badge, triage row | Project-wide UI framework |

### No Third-Party Dependencies

This project has a hard constraint against third-party SDKs (PROJECT.md: "No analytics, no telemetry, no third-party SDKs"). The Gmail API is accessed via raw URLSession (matching the Phase 6 pattern). MIME parsing (extracting plain-text body from raw RFC 2822 email) is hand-rolled as a small utility — acceptable here because bank alert emails are simple single-part or multipart/alternative with a plain-text body.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled MIME body extractor | MimeParser (github.com/miximka/MimeParser) | External dep; bank emails are simple enough to extract with a targeted string search for Content-Type: text/plain bodies |
| App Group UserDefaults for dismissed IDs | SwiftData @Model | Model adds migration complexity; a simple Set<String> in UserDefaults is sufficient for a dismissal-only list |
| New fields on Expense @Model | Separate ReviewItem @Model | Two models means a relationship, two SwiftData queries, and more migration complexity. Single-model approach is simpler and keeps expense identity stable |

---

## Package Legitimacy Audit

> No third-party packages are installed in this phase. All functionality uses Apple-native frameworks.

| Package | Registry | Disposition |
|---------|----------|-------------|
| (none) | — | No external packages — Apple frameworks only |

---

## Architecture Patterns

### System Architecture Diagram

```
 SYNC TRIGGER
 (manual or BGAppRefreshTask)
          │
          ▼
 GmailSyncController.sync()
          │
          ├─[UAT-6-05]──► GmailFetchPort.getProfile()
          │                  └─► connectedEmail → UserDefaults
          │
          ├──────────────► GmailFetchPort.listMessages(q: "from:... newer_than:Nd")
          │                  └─► [MessageID]
          │
          │  for each MessageID:
          ├──────────────► dismissedIDs.contains(id)? → skip
          │
          ├──────────────► GmailFetchPort.getRawMessage(id)
          │                  └─► rawEmailString (base64url decoded RFC 2822)
          │
          ├──────────────► HDFCParser.parse(raw) or ICICIParser.parse(raw)
          │                  ├─ Pre-filter: sender+subject → reject OTP/promo/verification
          │                  ├─ Fingerprint match (template recognition)
          │                  ├─ Value extraction (amount, merchant, date, card/account)
          │                  ├─ MerchantNormalizer.normalize(raw merchant)
          │                  └─► ParseResult { fields, fingerprintScore, extractionScore }
          │
          ├──────────────► ConfidenceScorer.score(result)
          │                  └─► confidence: Double (0.0–1.0)
          │
          ├──────────────► DedupChecker.isDuplicate(parsed, existingExpenses)
          │                  └─► Bool + existing Expense? (for side-by-side display)
          │
          └──────────────► Triage:
                            confidence ≥ 0.85 AND NOT duplicate
                              → Expense saved (ingestionState = .autoSaved)
                            confidence < 0.85 OR duplicate
                              → Expense saved (ingestionState = .needsReview or .possibleDuplicate)
                                (Review Inbox count badge increments)

 REVIEW INBOX (ExpenseListView)
   "Needs Review" section at top
     Row: parsed fields → one-tap-accept / tap-to-edit / swipe-to-discard
     Swipe-to-discard → messageID added to dismissedIDs (App Group UserDefaults)
```

### Recommended Project Structure

```
MyHomeApp/
├── Gmail/
│   ├── GmailAuthPort.swift         (existing — Phase 6)
│   ├── GmailFetchPort.swift        (NEW — email list/get/getProfile port)
│   ├── GmailOAuthConfig.swift      (existing)
│   ├── KeychainPort.swift          (existing)
│   ├── PKCE.swift                  (existing)
│   └── RelativeTimestamp.swift     (existing)
├── Features/
│   ├── Gmail/
│   │   └── GmailSyncController.swift  (existing — extended with pipeline)
│   ├── Ingestion/
│   │   ├── BankEmailParser.swift      (NEW — protocol + per-bank parsers)
│   │   ├── HDFCParser.swift           (NEW — pure parser)
│   │   ├── ICICIParser.swift          (NEW — pure parser)
│   │   ├── ConfidenceScorer.swift     (NEW — pure scoring)
│   │   ├── DedupChecker.swift         (NEW — pure dedup)
│   │   ├── MerchantNormalizer.swift   (NEW — static seed table)
│   │   └── DismissedMessageStore.swift (NEW — UserDefaults wrapper)
│   ├── Expenses/
│   │   ├── ExpenseListView.swift      (existing — gains Review Inbox section + badge)
│   │   ├── ReviewInboxRow.swift       (NEW — triage row UI)
│   │   └── ExpenseRow.swift           (existing — gains "auto" marker)
│   └── ...
├── Persistence/
│   └── Schema/
│       ├── SchemaV4.swift             (NEW — additive Expense fields)
│       └── MigrationPlan.swift        (UPDATED — append V3→V4 stage)
└── MyHomeApp.swift                    (UPDATED — BGAppRefreshTask registration)

MyHomeTests/
├── Support/
│   ├── SpyGmailFetch.swift            (NEW — test double for GmailFetchPort)
│   └── ...
├── HDFCParserTests.swift              (NEW — table-driven fixture tests)
├── ICICIParserTests.swift             (NEW — table-driven fixture tests)
├── ConfidenceScorerTests.swift        (NEW)
├── DedupCheckerTests.swift            (NEW)
├── MerchantNormalizerTests.swift      (NEW)
└── GmailSyncControllerTests.swift     (existing — extended with pipeline tests)

MyHomeTests/Fixtures/
├── hdfc_credit_card_spend.eml         (real anonymized email fixtures)
├── hdfc_upi_debit.eml
├── icici_credit_card_spend.eml
└── icici_otp.eml   (rejection fixture)
```

---

## SchemaV4 Migration

### V3 → V4 Additive Extension to Expense @Model

All new fields are **optional or defaulted** (CloudKit-readiness rule FND-03). No `@Attribute(.unique)`. The `ingestionStateRaw` field stores the state as a String (never a stored enum — CloudKit rule 8).

**Decision: New fields on existing Expense @Model (not a separate ReviewItem model)**

Rationale:
- Keeps expense identity stable (one UUID, one delete, one list query).
- Avoids a relationship between Expense and ReviewItem, which would require inverse declarations, CloudKit-compatible nullify rules, and a more complex migration.
- `ingestionStateRaw` is nil for all manual expenses — the schema cleanly handles both manual and ingested expenses in one model.
- The "auto" marker (D7-08) is derivable from `parserID != nil`.

```swift
// SchemaV4.swift — additive superset of V3

enum SchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV4.Expense.self,
            SchemaV4.Category.self,
            SchemaV4.Note.self,
            SchemaV4.NoteBlock.self,
        ]
    }

    // Category, Note, NoteBlock: copied verbatim from SchemaV3 (no changes)

    @Model
    final class Expense {
        // --- All fields from SchemaV3 (copied verbatim) ---
        var id: UUID = UUID()
        var amount: Decimal = Decimal(0)
        var currencyCode: String = "INR"
        var date: Date = Date()
        var note: String? = nil
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        @Relationship(deleteRule: .nullify, inverse: \SchemaV4.Category.expenses)
        var categories: [SchemaV4.Category] = []

        // --- New in SchemaV4: ingestion fields (ING-10/11/12/15, D7-08/10/11/15) ---

        /// Full raw email body (RFC 2822 decoded). nil for manual expenses. (ING-10, D7-10)
        var rawEmailBody: String? = nil

        /// Parser identifier string, e.g., "hdfc-v1", "icici-v1". nil for manual. (ING-11, D7-11)
        var parserID: String? = nil

        /// Parser version string, e.g., "1.0". nil for manual. (ING-11, D7-11)
        var parserVersion: String? = nil

        /// Parsed source label, e.g., "HDFC ••1234", "a/c XX5678". nil for manual. (D7-15)
        var sourceLabel: String? = nil

        /// Gmail message ID — used for dedup and dismissed-ID lookup. nil for manual. (ING-14, D7-07)
        var gmailMessageID: String? = nil

        /// Ingestion state stored as String raw value. nil for manual expenses.
        /// Values: "autoSaved" | "needsReview" | "possibleDuplicate" (ING-12/13/14)
        var ingestionStateRaw: String? = nil

        /// Confidence score at parse time (0.0–1.0). nil for manual. (ING-12)
        var parseConfidence: Double? = nil
    }
}
```

**Note on `rawEmailBody` size:** Full raw emails for Indian bank transaction alerts are typically 5-30 KB. For a household expense app with dozens of expenses per month, total storage impact is negligible (a few MB/year). Acceptable per D7-10 rationale.

### V3→V4 Migration Stage

```swift
// MigrationPlan.swift — append V3→V4, never remove V1/V2/V3

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3, v3ToV4]
    }

    // ... existing v1ToV2, v2ToV3 stages unchanged ...

    // V4 adds only new optional/defaulted fields to Expense.
    // willMigrate/didMigrate are nil — purely additive, new fields default to nil.
    // .custom over .lightweight deliberately sidesteps FB13812722 (same rationale as v1ToV2).
    static let v3ToV4 = MigrationStage.custom(
        fromVersion: SchemaV3.self,
        toVersion: SchemaV4.self,
        willMigrate: nil,
        didMigrate: nil
    )
}
```

[VERIFIED: existing MigrationPlan.swift in codebase uses exactly this pattern for V1→V2 and V2→V3]

**CloudKit-readiness checklist for new fields:**
- All new fields: optional or defaulted ✓
- No `@Attribute(.unique)` ✓
- `parseConfidence` stored as `Double?` (not Decimal — this is a ratio 0.0–1.0, not money) ✓
- `ingestionStateRaw` stored as `String?` (not enum) ✓
- No new relationships ✓

---

## GmailFetchPort — Email Retrieval Seam

Mirrors GmailAuthPort exactly in structure: a public protocol, a production conformer (SystemGmailFetch), and a spy test double (SpyGmailFetch).

```swift
// GmailFetchPort.swift (new file in MyHomeApp/Gmail/)

/// Protocol seam that abstracts Gmail API calls for email retrieval and profile.
/// Mirrors GmailAuthPort pattern (D6-23). Injected into GmailSyncController.
public protocol GmailFetchPort: Sendable {

    /// Returns the email address of the authenticated user. (UAT-6-05)
    func getProfile(accessToken: String) async throws -> GmailProfile

    /// Lists message IDs matching the query. Handles pagination internally.
    /// - Parameter q: Gmail search query, e.g., "from:alerts@hdfcbank.com newer_than:7d"
    func listMessageIDs(
        accessToken: String,
        q: String,
        maxResults: Int
    ) async throws -> [String]

    /// Returns the raw RFC 2822 email body for a message ID.
    func getRawMessage(accessToken: String, messageID: String) async throws -> String
}

public struct GmailProfile: Decodable, Sendable {
    public let emailAddress: String
}
```

**API calls under the hood (SystemGmailFetch):**

1. `GET https://gmail.googleapis.com/gmail/v1/users/me/profile`
   Authorization: Bearer {accessToken}
   → Response: `{ "emailAddress": "user@gmail.com", ... }`

2. `GET https://gmail.googleapis.com/gmail/v1/users/me/messages?q={q}&maxResults={n}`
   → Response: `{ "messages": [{"id": "...", "threadId": "..."}], "nextPageToken": "..." }`
   Paginate via `nextPageToken` until exhausted.

3. `GET https://gmail.googleapis.com/gmail/v1/users/me/messages/{id}?format=RAW`
   → Response: `{ "raw": "<base64url encoded RFC 2822 string>", ... }`
   Decode: replace `-` with `+`, `_` with `/`, pad to multiple of 4, then `Data(base64Encoded:)`.

[VERIFIED: developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages — format=RAW returns base64url-encoded RFC 2822 string]
[VERIFIED: developers.google.com/workspace/gmail/api/reference/rest/v1/users/getProfile — returns emailAddress field]

**Pagination pattern:** `listMessageIDs` must page through `nextPageToken` responses to handle cases where more than `maxResults` messages match (e.g., on initial 30-day backfill). Recommended: up to 500 results per page (API maximum), up to 3 pages (practical cap for household use; bank sends at most a few per day).

**Base64url decoding in Swift:**
```swift
func decodeBase64URL(_ base64url: String) -> Data? {
    var base64 = base64url
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    // Pad to multiple of 4
    let remainder = base64.count % 4
    if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
    return Data(base64Encoded: base64)
}
```

[ASSUMED] The `format=RAW` response field is named `raw` (lowercase) in the JSON response.

---

## Parser Architecture

### Two-Stage Parse Pattern (ING-07)

The key design constraint is that fingerprint matching and value extraction are SEPARATE stages. If the fingerprint fails, we never attempt extraction — this fails loudly (no match, no expense created) rather than silently mis-parsing a new email format.

```swift
// BankEmailParser.swift

public struct ParsedExpense {
    public let amount: Decimal
    public let rawMerchant: String         // before normalization
    public let normalizedMerchant: String  // after MerchantNormalizer
    public let categoryHint: String?       // from merchant seed, nil if unknown
    public let date: Date
    public let rawSourceLabel: String      // e.g., "HDFC ••1234", "a/c XX5678"
    public let isReversal: Bool            // true for refund/reversal (ING-09)
    public let fingerprintScore: Double    // 0.0–1.0: how well the template matched
    public let extractionScore: Double     // 0.0–1.0: how complete the field extraction was
}

public protocol BankEmailParser: Sendable {
    var parserID: String { get }       // e.g., "hdfc-v1"
    var parserVersion: String { get }  // e.g., "1.0"

    /// Pre-filter: returns true if this email is potentially a transaction email.
    /// Checks sender address + subject line BEFORE any body parsing.
    func canHandle(sender: String, subject: String) -> Bool

    /// Two-stage parse. Returns nil if fingerprint does not match.
    func parse(rawEmail: String) -> ParsedExpense?
}
```

### Pre-Filter Logic (ING-08)

Applied BEFORE fingerprint matching to discard obvious non-transaction emails:

```swift
// In HDFCParser.canHandle / ICICIParser.canHandle

static let allowedSenders: Set<String> = [
    // [ASSUMED] Actual senders must be confirmed from real corpus
    "alerts@hdfcbank.com",
    "notify@hdfcbank.com",
]

static let blockedSubjectKeywords: [String] = [
    "OTP", "One Time Password", "verification code",
    "promotional", "offer", "cashback offer",
    "statement", "e-statement",   // ING-08: not transaction alerts
]

func canHandle(sender: String, subject: String) -> Bool {
    guard allowedSenders.contains(sender.lowercased()) else { return false }
    let subjectLower = subject.lowercased()
    for blocked in Self.blockedSubjectKeywords {
        if subjectLower.contains(blocked.lowercased()) { return false }
    }
    return true
}
```

**Important:** The actual HDFC/ICICI sender addresses and subject patterns are `[ASSUMED]` — the real corpus (D7-03) must confirm these before parsers are finalized.

### Reversal/Refund Detection (ING-09)

Checked during value extraction, AFTER fingerprint match. Reversal → `isReversal = true` → amount stored as negative Decimal:

```swift
static let reversalKeywords = [
    "reversed", "reversal of", "refund", "credited back",
    "refund credited", "reversal credited"
]

// In parse():
let isReversal = reversalKeywords.contains { keyword in
    bodyText.lowercased().contains(keyword)
}
let finalAmount = isReversal ? -abs(extractedAmount) : extractedAmount
```

A reversal-flagged ParsedExpense still goes through confidence triage (ING-12). If high confidence, it auto-saves as a negative entry. No attempt to match the reversal to its original expense — stored as a standalone negative (per Claude's discretion; matching originals is v2 complexity).

### Fingerprint Matching (ING-07)

A template fingerprint is a set of structural anchors that should appear in a genuine bank alert email. Example concept (actual values must be derived from real corpus):

```swift
// Template fingerprint: a list of required string literals or regex patterns
// that identify this specific bank alert template.
// NOT the same regexes used for value extraction.

struct EmailTemplate {
    let requiredLiterals: [String]    // must all be present in body
    let optionalLiterals: [String]    // contribute to fingerprintScore
    let valuePatterns: [String: NSRegularExpression]  // field → extraction regex
}

// fingerprintScore = (matched required count / required count)
//                   * weight + (matched optional / optional count) * weight
// A single missed required literal → fingerprintScore = 0.0 → nil returned
```

The fingerprint fails loudly: if any required literal is absent, `parse()` returns nil immediately (no extraction attempted). This is what ING-07 means by "format drift fails the fingerprint" — a template change at the bank causes a nil result and the email lands in the Review Inbox rather than mis-parsing.

---

## Confidence Scoring Mechanics (Claude's Discretion)

### Proposed Model

```
confidence = fingerprintScore * 0.5 + extractionScore * 0.5

fingerprintScore (0.0–1.0):
  - All required fingerprint literals present: 1.0
  - Any required literal missing: 0.0 (fingerprint fails → nil returned, no score needed)
  - Optional literals boost if present

extractionScore (0.0–1.0):
  = (weight of successfully extracted fields) / (total weight)

Field weights:
  amount:   0.40  (most critical)
  date:     0.25
  merchant: 0.20
  card/acct: 0.15
```

**Why 0.85 threshold:** A score of 0.85 means all required fingerprint literals matched AND at least amount + date + merchant were extracted. A missing card/account label alone (weight 0.15) drops score to 0.925 — still auto-saves. This is reasonable initial calibration; real-data tuning after first week (D7-03).

**Implementation as pure function:**

```swift
// ConfidenceScorer.swift
public struct ConfidenceScorer {
    public static func score(_ result: ParsedExpense) -> Double {
        // fingerprintScore is passed through from parser; extractionScore computed here
        let extractionScore = computeExtractionScore(result)
        return result.fingerprintScore * 0.5 + extractionScore * 0.5
    }

    static func computeExtractionScore(_ result: ParsedExpense) -> Double {
        var score = 0.0
        if result.amount != 0 { score += 0.40 }
        // date always extracted (parser sets to message internalDate if missing)
        score += 0.25
        if !result.rawMerchant.isEmpty { score += 0.20 }
        if !result.rawSourceLabel.isEmpty { score += 0.15 }
        return score
    }
}
```

[ASSUMED] The 0.5/0.5 weighting and per-field weights above are initial estimates; calibrate against real corpus per D7-03.

---

## Dedup Logic (ING-14)

```swift
// DedupChecker.swift — pure function, takes fetched expenses as input

public struct DedupChecker {

    /// Returns an existing expense that is a probable duplicate, or nil.
    /// Dedup key: (amount + merchant-substring + date ±1 day).
    public static func findDuplicate(
        of candidate: ParsedExpense,
        in existingExpenses: [Expense]
    ) -> Expense? {
        let candidateDate = candidate.date
        let oneDaySeconds: TimeInterval = 86400

        return existingExpenses.first { existing in
            guard existing.amount == candidate.amount else { return false }
            // merchant-substring match (case-insensitive)
            let existingMerchant = existing.note?.lowercased() ?? ""
            let candidateMerchant = candidate.normalizedMerchant.lowercased()
            guard !candidateMerchant.isEmpty,
                  existingMerchant.contains(candidateMerchant) ||
                  candidateMerchant.contains(existingMerchant)
            else { return false }
            // date ±1 day
            let delta = abs(existing.date.timeIntervalSince(candidateDate))
            return delta <= oneDaySeconds
        }
    }
}
```

**Dedup is NOT a blocker for auto-save:** A possible duplicate always routes to Review Inbox regardless of confidence score. The `ingestionStateRaw` is set to `"possibleDuplicate"`. The duplicate expense's ID is stored alongside (in a separate transient field or as a reference in the expense note) so the UI can show "Possible duplicate of [existing merchant] on [date]".

[VERIFIED: ING-14 requirement text — "duplicates flag in inbox, never silent merge"]

---

## Merchant Normalization (ING-15)

```swift
// MerchantNormalizer.swift — pure struct, static seed table

public struct MerchantSeedEntry {
    public let normalizedName: String
    public let categoryHint: String?   // nil = Uncategorized fallback (D7-09)
}

public struct MerchantNormalizer {

    // ~20-30 Indian merchant seeds (D7-12, Claude-curated, not user-editable in v1)
    // Raw strings are uppercase substrings that appear in bank email merchant fields.
    static let seed: [String: MerchantSeedEntry] = [
        "AMAZON": .init(normalizedName: "Amazon", categoryHint: "Shopping"),
        "AMAZON IN": .init(normalizedName: "Amazon", categoryHint: "Shopping"),
        "FLIPKART": .init(normalizedName: "Flipkart", categoryHint: "Shopping"),
        "ZOMATO": .init(normalizedName: "Zomato", categoryHint: "Dining"),
        "SWIGGY": .init(normalizedName: "Swiggy", categoryHint: "Dining"),
        "UBER": .init(normalizedName: "Uber", categoryHint: "Auto/Cab"),
        "OLA": .init(normalizedName: "Ola", categoryHint: "Auto/Cab"),
        "RAPIDO": .init(normalizedName: "Rapido", categoryHint: "Auto/Cab"),
        "HPCL": .init(normalizedName: "HPCL", categoryHint: "Fuel"),
        "BPCL": .init(normalizedName: "BPCL", categoryHint: "Fuel"),
        "INDIAN OIL": .init(normalizedName: "Indian Oil", categoryHint: "Fuel"),
        "NYKAA": .init(normalizedName: "Nykaa", categoryHint: "Shopping"),
        "MYNTRA": .init(normalizedName: "Myntra", categoryHint: "Shopping"),
        "BIGBASKET": .init(normalizedName: "BigBasket", categoryHint: "Groceries"),
        "BLINKIT": .init(normalizedName: "Blinkit", categoryHint: "Groceries"),
        "ZEPTO": .init(normalizedName: "Zepto", categoryHint: "Groceries"),
        "INSTAMART": .init(normalizedName: "Swiggy Instamart", categoryHint: "Groceries"),
        "NETFLIX": .init(normalizedName: "Netflix", categoryHint: "Entertainment"),
        "SPOTIFY": .init(normalizedName: "Spotify", categoryHint: "Entertainment"),
        "HOTSTAR": .init(normalizedName: "Disney+ Hotstar", categoryHint: "Entertainment"),
        "JIOCINEMA": .init(normalizedName: "JioCinema", categoryHint: "Entertainment"),
        "IRCTC": .init(normalizedName: "IRCTC", categoryHint: "Travel"),
        "MAKEMYTRIP": .init(normalizedName: "MakeMyTrip", categoryHint: "Travel"),
        "GOIBIBO": .init(normalizedName: "Goibibo", categoryHint: "Travel"),
        "APOLLO": .init(normalizedName: "Apollo Pharmacy", categoryHint: "Health/Pharmacy"),
        "MEDPLUS": .init(normalizedName: "MedPlus", categoryHint: "Health/Pharmacy"),
        "PHONEPE": .init(normalizedName: "PhonePe", categoryHint: "UPI to Person"),
        "GPAY": .init(normalizedName: "Google Pay", categoryHint: "UPI to Person"),
        "PAYTM": .init(normalizedName: "Paytm", categoryHint: "UPI to Person"),
    ]

    /// Returns (normalizedName, categoryHint) for a raw merchant string.
    /// Matches longest seed key first (AMAZON IN before AMAZON).
    public static func normalize(_ rawMerchant: String) -> MerchantSeedEntry {
        let upper = rawMerchant.uppercased()
        // Sort by key length descending to prefer longer (more specific) matches
        let hit = seed.keys
            .sorted { $0.count > $1.count }
            .first { upper.contains($0) }
        return hit.map { seed[$0]! } ?? .init(normalizedName: rawMerchant, categoryHint: nil)
    }
}
```

[ASSUMED] The exact raw merchant strings that appear in HDFC/ICICI emails. The seed table above uses common substrings; must be refined from real corpus (D7-03).

---

## Dismissed Message-ID Tracking (D7-07)

Swipe-to-discard records the Gmail message ID so the next sync never re-surfaces it.

```swift
// DismissedMessageStore.swift

public struct DismissedMessageStore {
    private static let key = "gmail_dismissed_message_ids"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
    }

    public static func isDismissed(_ messageID: String) -> Bool {
        dismissed().contains(messageID)
    }

    public static func dismiss(_ messageID: String) {
        var set = dismissed()
        set.insert(messageID)
        defaults.set(Array(set), forKey: key)
    }

    static func dismissed() -> Set<String> {
        let array = defaults.stringArray(forKey: key) ?? []
        return Set(array)
    }
}
```

**Why App Group UserDefaults (not SwiftData):** Dismissed IDs are opaque string tokens — no relationship to expenses, no querying, no CloudKit sync needed. A `Set<String>` in UserDefaults is simpler and adds no migration burden. If the dismissed set grows large (unlikely for a household app), it can be pruned: remove IDs older than 60 days by pairing each ID with a timestamp.

[VERIFIED: App Group ID "group.com.reojacob.myhome" confirmed from GmailSyncController.swift in codebase]

---

## BGAppRefreshTask (ING-04)

### Registration Pattern for SwiftUI @main App

The modern SwiftUI approach (iOS 16+) uses the `.backgroundTask(.appRefresh(...))` scene modifier — no AppDelegate needed.

```swift
// MyHomeApp.swift (UPDATED)

import BackgroundTasks

@main
struct MyHomeApp: App {
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .background {
                scheduleBackgroundRefresh()
            }
        }
        // Register the handler — must be declared here, not inside a view
        .backgroundTask(.appRefresh("com.reojacob.myhome.emailrefresh")) {
            // GmailSyncController is @MainActor; must hop to main actor
            await MainActor.run {
                // Access the shared controller and run sync
                // (Exact injection pattern TBD by planner — depends on controller ownership)
            }
        }
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(
            identifier: "com.reojacob.myhome.emailrefresh"
        )
        // earliestBeginDate: don't run more often than once per hour
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
```

**Info.plist additions required:**
```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.reojacob.myhome.emailrefresh</string>
</array>
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>
```

[VERIFIED: Apple BackgroundTasks documentation — BGTaskSchedulerPermittedIdentifiers key name, UIBackgroundModes: fetch, registration must happen before end of app launch sequence]
[CITED: swiftwithmajid.com/2022/07/06/background-tasks-in-swiftui/]
[CITED: nilcoalescing.com/blog/SchedulingAndHandlingBackgroundAppRefreshInSwiftUI/]

### Triggering from Xcode Debugger (Simulator / Device)

```
// In LLDB console while app is paused after backgrounding:
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.reojacob.myhome.emailrefresh"]
```

This is the ONLY way to trigger background tasks in the simulator. The simulator does not run background tasks autonomously. [CITED: andyibanez.com/posts/modern-background-tasks-ios13/]

### Reliability Gotchas (CRITICAL for Reo)

1. **Simulator: zero autonomous execution.** The simulator NEVER fires BGAppRefreshTask automatically. The LLDB command above is the only simulator test path. Real-device testing overnight unplugged is the only way to verify it actually runs. This is the carried blocker from STATE.md.

2. **30-second time limit.** The system grants approximately 30 seconds. If `sync()` takes longer, the task is killed. The sync path must be fast: list messages → filter dismissed → fetch raws → parse → triage. No heavy I/O or retries in the background path.

3. **No scheduling guarantee.** `earliestBeginDate` is a minimum delay, not a schedule. iOS uses battery level, usage patterns, and machine learning heuristics to decide when to actually run the task. A task may not run for days.

4. **Must reschedule inside handler.** After the task runs, schedule the next one inside the handler or it will never run again.

5. **Registration crash if handler missing.** If the identifier is in Info.plist but no `.backgroundTask` handler is registered, the app will crash: "No launch handler registered for task with identifier...". Register before the end of app launch.

6. **"Sync now" is the primary path (D7-ING-04 intent).** BGAppRefreshTask is strictly a bonus. Plan messaging and UI should never imply it is reliable.

[VERIFIED: developer.apple.com/documentation/backgroundtasks/bgtaskscheduler]

---

## UAT-6-05 Carry-Over — connectedEmail Population

This is the first real Gmail API network call in this app (Phase 6 stubbed everything). Implementation:

```swift
// In GmailSyncController.sync() — after token refresh, before messages.list:

let profile = try await fetch.getProfile(accessToken: accessToken!)
connectedEmail = profile.emailAddress   // writes to App Group UserDefaults
```

The `fetch` dependency is the new `GmailFetchPort` injected into `GmailSyncController` (alongside the existing `auth: GmailAuthPort` and `keychain: KeychainPort`). Same pattern: protocol + spy test double + real conformer.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Base64url decoding | Custom bit-shifting decoder | Swift Foundation `Data(base64Encoded:)` after substituting `-`→`+` and `_`→`/` | Foundation handles the heavy lifting; just needs alphabet fix |
| MIME parsing for full email structure | Full RFC 2822 MIME parser | Extract plain-text body with targeted `Content-Type: text/plain` search | Bank alert emails are simple; full MIME parsing is overkill |
| BGAppRefreshTask timing precision | Custom wake-up scheduling | BGAppRefreshTask with `earliestBeginDate` | iOS owns the scheduler; attempting to fight it wastes effort |
| Token refresh in background handler | Re-implementing refresh logic | Reuse existing `GmailSyncController.sync()` which already handles proactive refresh | DRY; the sync state machine already handles this correctly |
| Confidence scoring ML model | Core ML or trained classifier | Pure deterministic score (fingerprint + extraction completeness) | Training a model requires 1000s of examples; weighted formula is calibratable with 50+ |

---

## Common Pitfalls

### Pitfall 1: Building Parsers Before Corpus Exists

**What goes wrong:** Parser regexes are written against imagined email formats, then fail or mis-parse real emails when the app is used for the first time.
**Why it happens:** There is no HDFC/ICICI transaction email corpus available without enabling alerts and collecting real emails.
**How to avoid:** The plan MUST include a corpus-collection task BEFORE parser implementation tasks. Parsers are written against fixture `.eml` files extracted from the corpus.
**Warning signs:** Any parser test that uses invented example text rather than a real email.

### Pitfall 2: BGAppRefreshTask Tested Only on Simulator

**What goes wrong:** Background sync appears to "work" in development (via LLDB trigger) but never fires in real use.
**Why it happens:** Simulator does not model iOS battery/usage heuristics.
**How to avoid:** Add a real-device overnight test checkpoint in UAT. The plan should include explicit "run on device overnight unplugged" step.
**Warning signs:** Planning to sign off on ING-04 without device verification.

### Pitfall 3: Using .lightweight Migration on iOS 17.0–17.3

**What goes wrong:** App crashes on migration with "Circular reference" or "Expected only Arrays for Relationships" errors.
**Why it happens:** FB13812722 — `.lightweight` migration stages have a bug in iOS 17.0–17.3.
**How to avoid:** Use `.custom(willMigrate: nil, didMigrate: nil)` — already the pattern in this codebase (MigrationPlan.swift comment). Replicate exactly for V3→V4.
**Warning signs:** Any new migration stage using `.lightweight`.

[VERIFIED: MigrationPlan.swift in codebase — explicit comment about FB13812722 and use of .custom over .lightweight]

### Pitfall 4: Storing Ingestion State as a SwiftData Enum

**What goes wrong:** `@Model` stored enum causes CloudKit sync errors or migration issues.
**Why it happens:** CloudKit does not support stored enums in SwiftData models (FND-03 rule 8).
**How to avoid:** Use `ingestionStateRaw: String?` and convert to/from a value-type enum at the application layer.
**Warning signs:** `enum IngestionState { case autoSaved, needsReview, possibleDuplicate }` appearing as a stored property on an @Model.

[VERIFIED: SchemaV3.swift — `kindRaw: String` and `reminderRecurrenceData: Data?` patterns already established]

### Pitfall 5: GmailSyncController @MainActor Concurrency in BGAppRefreshTask

**What goes wrong:** Calling `@MainActor` methods from a background task closure without a proper hop causes concurrency warnings or deadlocks.
**Why it happens:** `GmailSyncController` is declared `@MainActor`; `.backgroundTask` handlers run on a non-main actor by default in the SwiftUI lifecycle.
**How to avoid:** Explicitly hop to MainActor inside the handler: `await MainActor.run { ... }`.
**Warning signs:** Swift 6 concurrency errors when calling sync() from the background task closure.

### Pitfall 6: Blocking the Sync on Missing Real-Data Corpus

**What goes wrong:** Phase 7 plan stalls because the 50-email corpus hasn't been collected yet.
**Why it happens:** Corpus collection is a human action (enable HDFC/ICICI email alerts, wait for transactions, export emails) that can't be automated.
**How to avoid:** Plan includes Wave 0 as corpus-collection + schema/port scaffold work. Parser implementation blocked on corpus. Schedule parsers in a later wave.
**Warning signs:** Parser implementation starting before fixture `.eml` files exist.

### Pitfall 7: Pagination Not Implemented for messages.list

**What goes wrong:** Only the first 100 (default) or 500 (max) messages are processed; older ones are silently dropped.
**Why it happens:** The API returns a `nextPageToken` that must be followed to get all results.
**How to avoid:** `SystemGmailFetch.listMessageIDs` must loop while `nextPageToken` is non-nil (up to a reasonable cap).
**Warning signs:** A `listMessages` implementation that makes a single API call and returns.

### Pitfall 8: rawEmailBody Stored as String in SchemaV4 — Large Payload for Some Emails

**What goes wrong:** HTML-heavy bank emails balloon rawEmailBody to 100+ KB per expense.
**Why it happens:** Some bank alert emails are HTML-only with no plain-text alternative; the entire HTML is stored.
**How to avoid:** Store only the plain-text body portion (extracted during MIME parsing) rather than the full RFC 2822 raw. If no plain-text body exists, store the first 2000 chars of the decoded payload with a note. Per D7-10, full fidelity is the intent — this is a documentation note, not a change.
**Warning signs:** iOS storage warnings after a few months of use.

---

## Code Examples

### Pattern 1: Adding Expense to Review Inbox (ingestionStateRaw)

```swift
// Source: derived from existing Expense @Model pattern in SchemaV3.swift

// In GmailSyncController.sync() after triage:
let expense = Expense()   // SchemaV4.Expense
expense.amount = isReversal ? -abs(parsed.amount) : parsed.amount
expense.date = parsed.date
expense.note = parsed.normalizedMerchant
expense.parserID = parser.parserID
expense.parserVersion = parser.parserVersion
expense.rawEmailBody = rawEmailString
expense.sourceLabel = parsed.rawSourceLabel
expense.gmailMessageID = messageID
expense.parseConfidence = confidence
expense.ingestionStateRaw = confidence >= 0.85 && !isDuplicate ? "autoSaved" : "needsReview"
modelContext.insert(expense)
```

### Pattern 2: Query Review Inbox Items

```swift
// Fetch all non-nil ingestionState expenses (pending review):
let descriptor = FetchDescriptor<Expense>(
    predicate: #Predicate { $0.ingestionStateRaw != nil && $0.ingestionStateRaw != "autoSaved" },
    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
)
let reviewItems = try modelContext.fetch(descriptor)
```

### Pattern 3: Table-Driven Parser Test (Swift Testing)

```swift
// Source: pattern mirrors BudgetCalculatorTests.swift in this codebase

@Suite("HDFCParser")
struct HDFCParserTests {

    @Test("parse credit-card spend from fixture", arguments: [
        ("hdfc_cc_spend_1.eml", Decimal(1250.00), "Zomato", false),
        ("hdfc_cc_spend_2.eml", Decimal(89.00),   "Amazon", false),
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
}
```

### Pattern 4: SpyGmailFetch (mirrors SpyGmailAuth exactly)

```swift
// SpyGmailFetch.swift — test double for GmailFetchPort

public final class SpyGmailFetch: GmailFetchPort, @unchecked Sendable {
    public var profileResult: GmailProfile = GmailProfile(emailAddress: "test@gmail.com")
    public var messageIDsResult: [String] = []
    public var rawMessageResult: String = ""
    public var shouldThrowOnGetProfile: Error? = nil
    public var shouldThrowOnListMessages: Error? = nil
    public var shouldThrowOnGetRaw: Error? = nil

    public func getProfile(accessToken: String) async throws -> GmailProfile {
        if let e = shouldThrowOnGetProfile { throw e }
        return profileResult
    }
    public func listMessageIDs(accessToken: String, q: String, maxResults: Int) async throws -> [String] {
        if let e = shouldThrowOnListMessages { throw e }
        return messageIDsResult
    }
    public func getRawMessage(accessToken: String, messageID: String) async throws -> String {
        if let e = shouldThrowOnGetRaw { throw e }
        return rawMessageResult
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| AppDelegate-based BGTask registration | SwiftUI `.backgroundTask(.appRefresh(...))` scene modifier | iOS 16 / SwiftUI 4 | No AppDelegate needed; `@main` struct owns registration |
| `.lightweight` SwiftData migrations | `.custom(willMigrate:nil, didMigrate:nil)` for additive changes | iOS 17.0 bug FB13812722 | Sidesteps crash; already in use in this codebase |
| Google SDK for Gmail access | Raw URLSession with `Authorization: Bearer` header | Project decision D6-01 | Zero third-party deps; full control |
| Stored enums in @Model | String raw values + application-layer enum | SwiftData/CloudKit constraint | CloudKit does not support stored enums |

**Deprecated/outdated:**
- `UIApplication.setMinimumBackgroundFetchInterval`: Deprecated, replaced by BGTaskScheduler. Do not use.
- AppDelegate `application(_:performFetchWithCompletionHandler:)`: Old background fetch API, replaced by BGAppRefreshTask.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | HDFC transaction alert sender address is "alerts@hdfcbank.com" or "notify@hdfcbank.com" | Parser Architecture / Pre-Filter | Parser rejects all HDFC emails; canHandle always returns false |
| A2 | ICICI transaction alert sender address follows pattern "@icicibank.com" | Parser Architecture / Pre-Filter | Same as A1 for ICICI |
| A3 | format=RAW JSON response field is named "raw" (lowercase) | GmailFetchPort | JSON decode fails silently; getRawMessage returns empty string |
| A4 | 0.5/0.5 fingerprint/extraction split and per-field weights produce good real-world calibration | Confidence Scoring | Threshold needs re-tuning; may auto-save bad parses or over-route to inbox |
| A5 | Raw merchant strings in HDFC/ICICI emails contain the uppercase substrings in the seed table | Merchant Normalization | Normalization never matches; all merchants show as raw strings |
| A6 | Bank alert emails are multipart/alternative with a plain-text body extractable by searching for "Content-Type: text/plain" | GmailFetchPort / Parser Architecture | Parser receives garbled text or no body |
| A7 | Phone-Pe, GPay, Paytm UPI debit emails arrive from bank senders (not from the UPI app itself) | Parser Architecture | UPI transactions not captured at all if they come from different senders |

**If this table is empty:** All claims in this research were verified or cited — no user confirmation needed. (Table is NOT empty — A1-A7 need corpus confirmation per D7-03.)

---

## Open Questions

1. **GmailSyncController dependency injection of GmailFetchPort**
   - What we know: GmailSyncController currently takes `auth: GmailAuthPort` and `keychain: KeychainPort` in init.
   - What's unclear: Should `fetch: GmailFetchPort` be a third init parameter (matching the spy pattern), or should GmailSyncController create it internally? The existing `sync()` stub says "the actual Gmail API listMessages call is wired in plan 04."
   - Recommendation: Add `fetch: any GmailFetchPort = SystemGmailFetch()` as a third init parameter, matching the auth/keychain pattern exactly.

2. **Where GmailSyncController is owned in the app (for BGAppRefreshTask access)**
   - What we know: RootView owns `@State private var gmailSyncController = GmailSyncController()`.
   - What's unclear: How does the `.backgroundTask` handler in `MyHomeApp.swift` access the same controller instance?
   - Recommendation: Move `gmailSyncController` to `@State` on `MyHomeApp` (passed as environment object or via RootView init) so the `.backgroundTask` closure captures it.

3. **ModelContext access in BGAppRefreshTask handler**
   - What we know: SwiftData requires a ModelContext to save new expenses.
   - What's unclear: How to get a fresh ModelContext inside the background task handler.
   - Recommendation: Create a new ModelContainer + ModelContext inside the background handler using the same factory pattern from Phase 1. The background task runs in its own process continuation; it cannot use the app's existing ModelContainer safely.

4. **ingestionStateRaw for the "auto" marker**
   - What we know: D7-08 says source distinction is derivable from presence of `parserID`.
   - What's unclear: Whether to use `parserID != nil` as the sole "auto" marker, or `ingestionStateRaw == "autoSaved"` as the distinguisher.
   - Recommendation: Use `ingestionStateRaw == "autoSaved"` — more explicit, handles the case where a manually-edited ingested expense remains discoverable.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 26.5 | iOS build, BGTask LLDB testing | ✓ | 26.5 | — |
| iPhone 17 Simulator | Unit tests, simulator builds | ✓ | (from memory file) | — |
| Real iOS device (unplugged overnight) | BGAppRefreshTask device verification (ING-04) | [ASSUMED] Available | Unknown | No fallback — BGTask reliability cannot be verified without real device |
| Google Cloud Console OAuth client | Gmail API access | ✓ | (Phase 6 set up, confirmed in 06-UAT.md) | — |
| Gmail API (gmail.readonly scope) | Email fetch | ✓ | (Phase 6 OAuth proven live) | — |
| HDFC/ICICI real email corpus (50+ per bank) | Parser calibration (D7-03) | ✗ | — | Cannot build calibrated parsers — must collect first |

**Missing dependencies with no fallback:**
- Real email corpus: parser and confidence threshold work is blocked until collected. Plan must include a corpus-collection task before parser tasks.
- Real device for BGAppRefreshTask overnight test: ING-04 UAT cannot be completed without physical hardware.

**Missing dependencies with fallback:**
- None that block core pipeline work (schema, ports, pure logic).

---

## Validation Architecture

> nyquist_validation is enabled (config.json).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (already in use — FND-06) |
| Config file | None — Swift Testing integrated via Xcode 16+ |
| Quick run command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/HDFCParserTests` |
| Full suite command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ING-04 | BGAppRefreshTask registers without crash | manual (device) | LLDB trigger on simulator; overnight on device | ❌ Wave 0 |
| ING-06 | HDFC + ICICI parsers return ParsedExpense from fixtures | unit | `…/HDFCParserTests` `…/ICICIParserTests` | ❌ Wave 0 |
| ING-07 | Fingerprint fail returns nil; extraction independently tested | unit | `…/HDFCParserTests` (fingerprint table) | ❌ Wave 0 |
| ING-08 | OTP/promo/verification emails return canHandle=false | unit | `…/HDFCParserTests/canHandleTests` | ❌ Wave 0 |
| ING-09 | Reversal keywords produce negative amount in ParsedExpense | unit | `…/HDFCParserTests/reversalTests` | ❌ Wave 0 |
| ING-10 | rawEmailBody stored on Expense after ingestion | unit (in-memory SwiftData) | `…/IngestionPipelineTests` | ❌ Wave 0 |
| ING-11 | parserID + parserVersion stored on Expense | unit (in-memory SwiftData) | `…/IngestionPipelineTests` | ❌ Wave 0 |
| ING-12 | confidence ≥ 0.85 → autoSaved; below → needsReview | unit | `…/ConfidenceScorerTests` | ❌ Wave 0 |
| ING-13 | Discard sets dismissed ID; re-sync skips dismissed ID | unit | `…/GmailSyncControllerTests` (extended) | ❌ Wave 0 |
| ING-14 | Dedup match routes to possibleDuplicate, not autoSaved | unit | `…/DedupCheckerTests` | ❌ Wave 0 |
| ING-15 | "ZOMATO ONL BANGAL" normalizes to "Zomato", category "Dining" | unit | `…/MerchantNormalizerTests` | ❌ Wave 0 |
| UAT-6-05 | connectedEmail populated after sync | unit (SpyGmailFetch) | `…/GmailSyncControllerTests` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** Full parser test suite for whichever parser is being worked on + MerchantNormalizerTests
- **Per wave merge:** `xcodebuild test …` (full suite — 53 existing + new)
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps (test stubs to create before implementation)

- [ ] `MyHomeTests/HDFCParserTests.swift` — stub `@Test` functions for canHandle, parse, fingerprint, extraction, reversal
- [ ] `MyHomeTests/ICICIParserTests.swift` — same structure
- [ ] `MyHomeTests/ConfidenceScorerTests.swift` — stub table tests for threshold boundary
- [ ] `MyHomeTests/DedupCheckerTests.swift` — stub table tests for match/no-match
- [ ] `MyHomeTests/MerchantNormalizerTests.swift` — stub table tests for seed entries
- [ ] `MyHomeTests/IngestionPipelineTests.swift` — stub SwiftData in-memory tests for full pipeline
- [ ] `MyHomeTests/Support/SpyGmailFetch.swift` — test double for GmailFetchPort
- [ ] `MyHomeTests/Fixtures/` — directory for `.eml` fixture files (populated after corpus collection)

---

## Security Domain

> security_enforcement is enabled (config.json). ASVS Level 1.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No new auth | Existing OAuth token (Phase 6) |
| V3 Session Management | Partial | Access token in memory only (D6-07) — unchanged |
| V4 Access Control | Yes | rawEmailBody is Face ID gated (D7-10) — existing LockController |
| V5 Input Validation | Yes | Email body input: never executed, only string-matched |
| V6 Cryptography | No new crypto | No new crypto; raw email stored as plain String locally |
| V9 Communications | Yes | All Gmail API calls over HTTPS via URLSession (automatic) |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malicious email body executing code | Tampering | Parser treats email as plain string — no eval, no HTML rendering, no script execution |
| rawEmailBody leaked via CloudKit | Information Disclosure | rawEmailBody is local-only (D7-10); CloudKit sync is v2 and would require explicit exclusion |
| Dismissed IDs manipulated via UserDefaults | Tampering | Dismissed IDs are non-security state (worst case: re-shows a dismissed email); no security impact |
| Over-broad Gmail q query returning non-bank emails | Information Disclosure | Pre-filter (ING-08) rejects non-bank senders; raw email stored only for matched emails |
| Access token used in background task after expiry | Authentication Bypass | GmailSyncController.sync() already proactively refreshes before API calls (D6-06) |

**Regarding rawEmailBody and Face ID gate:** The Face ID gate (LockController) already protects the app at launch. `rawEmailBody` does not need a separate access control beyond what LockController provides — the same Face ID prompt that protects expense amounts also protects the stored raw email.

---

## Sources

### Primary (HIGH confidence)

- MigrationPlan.swift (in codebase) — existing V1→V2, V2→V3 custom migration pattern; FB13812722 comment
- SchemaV3.swift (in codebase) — existing Expense @Model, CloudKit-readiness rules, String raw value pattern
- GmailAuthPort.swift, GmailSyncController.swift, KeychainPort.swift (in codebase) — protocol-port seam pattern, SpyGmailAuth pattern
- developer.apple.com/documentation/backgroundtasks/bgtaskscheduler — BGAppRefreshTask registration, 30s limit, no simulator support
- developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages — format=RAW, base64url encoding
- developers.google.com/workspace/gmail/api/reference/rest/v1/users/getProfile — emailAddress field
- developers.google.com/workspace/gmail/api/guides/filtering — q parameter, from: operator, newer_than:

### Secondary (MEDIUM confidence)

- swiftwithmajid.com/2022/07/06/background-tasks-in-swiftui/ — SwiftUI backgroundTask scene modifier code pattern
- nilcoalescing.com/blog/SchedulingAndHandlingBackgroundAppRefreshInSwiftUI/ — scheduling pattern, no execution guarantees
- andyibanez.com/posts/modern-background-tasks-ios13/ — simulator LLDB trigger command, "does not work on simulator at all"
- donnywals.com/a-deep-dive-into-swiftdata-migrations/ — optional fields migrate automatically with .custom(nil, nil)

### Tertiary (LOW confidence — marked ASSUMED)

- HDFC/ICICI email sender addresses and subject patterns (A1, A2) — must be confirmed from real corpus
- Confidence scoring weights (A4) — initial estimates, needs real-data calibration
- Merchant seed raw strings (A5) — common substrings, needs corpus confirmation

---

## Metadata

**Confidence breakdown:**
- SchemaV4 migration pattern: HIGH — exact same pattern already in codebase twice
- GmailFetchPort design: HIGH — mirrors GmailAuthPort exactly
- BGAppRefreshTask registration/scheduling: HIGH — verified against official Apple docs
- Parser architecture: HIGH (design), LOW (actual bank-specific patterns — corpus required)
- Confidence scoring: MEDIUM — design is sound, weights are estimated
- Merchant normalization seed: MEDIUM — common merchants identified, raw strings assumed

**Research date:** 2026-06-02
**Valid until:** Stable patterns (SwiftData, BGTask): 60 days. Gmail API: 30 days. Bank email formats: must be refreshed against real corpus — no expiry concept applies.
