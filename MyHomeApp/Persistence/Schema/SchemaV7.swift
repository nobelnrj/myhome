import SwiftData
import Foundation

/// VersionedSchema v7.0.0 — copies V6's models verbatim, adds amfiSchemeCode to Asset,
/// and introduces the NetWorthSnapshot @Model (D-03, Phase 11).
///
/// Rules:
/// - SchemaV1.swift through SchemaV6.swift are IMMUTABLE after they ship. Never edit them.
/// - SchemaV7 is an additive superset: it copies SchemaV6's models verbatim and
///   appends new optional/defaulted fields (CloudKit-readiness rules enforced below).
///
/// CloudKit-readiness rules enforced (FND-03, ARCHITECTURE.md):
/// 1. Every stored property has a default or is optional.
/// 2. No @Attribute(.unique) anywhere (CloudKit does not support uniqueness constraints).
/// 3. Decimal for money (never Double — Pitfall 17).
/// 4. Full UTC timestamp for dates.
/// 5. currencyCode: String present for multi-currency-readiness.
/// 6. UUID primary key on all @Model types.
/// 7. @Relationship inverse declared on ONE side only per relationship (avoids circular macro
///    expansion error "Circular reference resolving attached macro 'Relationship'").
/// 8. No stored enums — use String raw values or Codable value types serialized to Data?.
enum SchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV7.Expense.self,
            SchemaV7.Category.self,
            SchemaV7.Note.self,
            SchemaV7.NoteBlock.self,
            SchemaV7.Account.self,
            SchemaV7.Asset.self,
            SchemaV7.NetWorthSnapshot.self,  // NEW in V7 (D-03, ASSET-08)
        ]
    }

    // MARK: - Category @Model (copied verbatim from SchemaV6 — no V7 changes)

    @Model
    final class Category {
        // No @Attribute(.unique) — CloudKit does not support unique constraints.
        // Uniqueness enforced via lookup-before-insert in application code (P2-06).
        var id: UUID = UUID()
        var name: String? = nil                 // optional per CloudKit rule 2
        var symbolName: String? = nil           // SF Symbol name, e.g. "cart"
        var sortOrder: Int = 0                  // for predefined list ordering
        var monthlyBudget: Decimal? = nil       // nil = no budget set (D2-06); Decimal not Double (Pitfall 17)
        var currencyCode: String = "INR"        // schema-forward: multi-currency-ready
        var createdAt: Date = Date()            // UTC timestamp (CloudKit rule 4)

        // Inverse side of the to-many relationship (CloudKit rule 7: inverse declared on one side).
        // deleteRule: .nullify — removing a category clears the link on expenses (D2-04).
        // Note: inverse: is declared on Expense.categories; SwiftData infers the inverse here
        // from that declaration. Declaring inverse: on both sides in the same file causes a
        // circular macro expansion error ("Circular reference resolving attached macro 'Relationship'").
        @Relationship(deleteRule: .nullify)
        var expenses: [SchemaV7.Expense] = []

        // STAB-03 footgun: sortOrder defaults to 0. Any caller that OMITS sortOrder
        // lands among the seeded 0..13 rows in the @Query(sort: \Category.sortOrder) list,
        // not at a predictable edge. New custom categories MUST pass min(existing.sortOrder)-1
        // (see ManageCategoriesView.addCategory) to surface at the TOP of the list. Default
        // left at 0 (changing it would break the seed path and SchemaV6 identity) — pass
        // sortOrder explicitly at every call site.
        init(name: String, symbolName: String?, sortOrder: Int = 0) {
            self.id = UUID()
            self.name = name
            self.symbolName = symbolName
            self.sortOrder = sortOrder
            self.createdAt = Date()
        }
    }

    // MARK: - Expense @Model (copied verbatim from SchemaV6 — no V7 changes)

    @Model
    final class Expense {
        // No @Attribute(.unique) — CloudKit does not support unique constraints.
        var id: UUID = UUID()
        var amount: Decimal = Decimal(0)        // never Double (Pitfall 17)
        var currencyCode: String = "INR"        // schema-forward: multi-currency-ready
        var date: Date = Date()                 // UTC timestamp; format at display time (D-02)
        var note: String? = nil                 // optional free-form memo / payee (D-05, D-06)
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        // to-many relationship to Category (D2-02, CloudKit rule 7).
        // deleteRule: .nullify — deleting a Category clears this array (does not delete the expense).
        @Relationship(deleteRule: .nullify, inverse: \SchemaV7.Category.expenses)
        var categories: [SchemaV7.Category] = []

        // --- Inherited from SchemaV4: ingestion fields (D7-10/11/12/13/14/15/16) ---
        // All fields are optional/defaulted (CloudKit rule 1). No @Attribute(.unique). No stored enums.
        var rawEmailBody: String? = nil         // ING-10, D7-10 — raw email text stored for audit
        var parserID: String? = nil             // ING-11, D7-11 — parser that created this expense
        var parserVersion: String? = nil        // ING-11, D7-11 — version of the parser
        var sourceLabel: String? = nil          // D7-15 — human-readable source (e.g. "HDFC CC")
        var gmailMessageID: String? = nil       // ING-14, D7-07 — Gmail message ID for dedup
        /// Ingestion state stored as String raw value. nil for manual expenses (rule 8: String not enum).
        /// Values: "autoSaved" | "needsReview" | "possibleDuplicate"
        var ingestionStateRaw: String? = nil    // ING-12/13/14
        var parseConfidence: Double? = nil      // ING-12 — ratio 0.0–1.0 (NOT money — Double ok here)

        // --- Inherited from SchemaV5: multi-account dedup field (D-MA-03) ---
        /// The email address of the Gmail account that ingested this expense.
        /// nil for manual expenses and legacy expenses ingested before multi-account support.
        /// Used as part of the (sourceAccount, gmailMessageID) idempotency key — D-MA-01/03.
        var sourceAccount: String? = nil        // D-MA-03 — owning Gmail account email; nil for manual/legacy

        // --- Inherited from SchemaV6: account attribution + transfer scaffold (ACCT-08, Phase 10) ---
        // Append AFTER all V5 fields (additive only — never reorder/remove existing fields).
        // accountID uses a bare UUID (NOT a @Relationship) per Pitfall 5 / CloudKit rule 7:
        // Account declares the inverse @Relationship on Account.expenses to avoid circular macro error.
        var accountID: UUID? = nil              // D-01: links to Account.id; nil = Unassigned
        var isTransfer: Bool? = nil             // Phase 10 transfer scaffold; nil = not evaluated
        var transferPairID: UUID? = nil         // Phase 10 transfer scaffold; links paired expense UUID

        init(
            id: UUID = UUID(),
            amount: Decimal,
            currencyCode: String = "INR",
            date: Date = Date(),
            note: String? = nil
        ) {
            self.id = id
            self.amount = amount
            self.currencyCode = currencyCode
            self.date = date
            self.note = note
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }

    // MARK: - Note @Model (copied verbatim from SchemaV6 — no V7 changes)

    @Model
    final class Note {
        // No @Attribute(.unique) — CloudKit does not support unique constraints.
        var id: UUID = UUID()
        /// Required at the UX layer; defaults to "" so CloudKit can store a reminder-less note.
        var title: String = ""
        /// Ordered block list. Cascade-deletes all NoteBlocks when the Note is deleted.
        /// inverse: declared on THIS side only (CloudKit rule 7 / SchemaV2 caveat at lines 42-48/75).
        @Relationship(deleteRule: .cascade, inverse: \SchemaV7.NoteBlock.note)
        var blocks: [SchemaV7.NoteBlock]? = []
        var isPinned: Bool = false
        var createdAt: Date = Date()            // UTC
        var modifiedAt: Date = Date()           // UTC

        // Reminder fields (note-level reminder — D3-02)
        var reminderEnabled: Bool = false
        var reminderDate: Date? = nil           // UTC; nil if no reminder
        var reminderIsAllDay: Bool = false
        /// JSON-encoded ReminderRecurrence value type (never a stored enum — rule 8).
        var reminderRecurrenceData: Data? = nil
        /// JSON-encoded ReminderEndRule value type (never a stored enum — rule 8).
        var reminderEndRuleData: Data? = nil
        var reminderLeadMinutes: Int = 0        // 0 = no advance alert

        // --- Inherited from SchemaV6: daily routine fields (D-11, D-12, STAB-04 / NOTE-02) ---
        // Append AFTER all V5 fields (additive only — never reorder/remove existing fields).
        /// Flags this note for RoutineResetService. False by default — ordinary notes are never auto-reset.
        /// Phase 12 UI toggle simply flips this flag; the reset logic lives in RoutineResetService.
        var isDailyRoutine: Bool = false        // D-11: flags note for RoutineResetService
        /// Note-level reset marker. On scenePhase .active, if routineLastResetDate < startOfToday (IST),
        /// RoutineResetService sets isChecked = false on all checklist blocks and stamps today's date.
        /// nil = note has never been reset (treated as .distantPast in RoutineResetService).
        var routineLastResetDate: Date? = nil   // D-12: note-level reset marker; nil = never reset

        init(title: String = "") {
            self.id = UUID()
            self.title = title
            self.createdAt = Date()
            self.modifiedAt = Date()
        }
    }

    // MARK: - NoteBlock @Model (copied verbatim from SchemaV6 — no V7 changes)

    @Model
    final class NoteBlock {
        // No @Attribute(.unique) — CloudKit does not support unique constraints.
        var id: UUID = UUID()
        /// Block type stored as String raw value (NOT a stored enum — rule 8 / Pitfall 6).
        /// Values: "text" | "checkbox"
        var kindRaw: String = "text"
        var text: String = ""
        var isChecked: Bool = false             // checkboxes only; false on text blocks
        var order: Int = 0                      // position in note's block list; allows drag-reorder
        /// Back-reference to the owning Note.
        /// inverse: is declared on Note.blocks — do NOT add inverse: here (circular macro error).
        var note: SchemaV7.Note? = nil

        // Reminder fields (block-level reminder — D3-02)
        var reminderEnabled: Bool = false
        var reminderDate: Date? = nil           // UTC; nil if no reminder
        var reminderIsAllDay: Bool = false
        /// JSON-encoded ReminderRecurrence value type (never a stored enum — rule 8).
        var reminderRecurrenceData: Data? = nil
        /// JSON-encoded ReminderEndRule value type (never a stored enum — rule 8).
        var reminderEndRuleData: Data? = nil
        var reminderLeadMinutes: Int = 0        // 0 = no advance alert

        init(kindRaw: String = "text", text: String = "", order: Int = 0) {
            self.id = UUID()
            self.kindRaw = kindRaw
            self.text = text
            self.order = order
        }
    }

    // MARK: - Account @Model (copied verbatim from SchemaV6 — no V7 changes)

    @Model
    final class Account {
        // No @Attribute(.unique) — CloudKit does not support unique constraints (rule 2).
        // Uniqueness enforced via lookup-before-insert in AccountsListView (mirrors Category pattern).
        var id: UUID = UUID()                   // UUID primary key (rule 6)
        var name: String? = nil                 // optional per CloudKit rule 2
        var typeRaw: String? = nil              // "savings" | "current" | "credit_card" (rule 8: String not enum)
        var symbolName: String? = nil           // SF Symbol name, e.g. "creditcard"
        var colorHex: String? = nil             // hex string e.g. "#FF3B30" (rule 8: String not Color)
        var last4: String? = nil                // optional last 4 digits of account number
        var balanceBaseline: Decimal? = nil     // Decimal not Double (rule 3); nil = no baseline set (ACCT-04)
        var balanceAsOfDate: Date? = nil        // UTC (rule 4); baseline anchor date (D-10)
        var isArchived: Bool = false            // D-08: archive hides from pickers; past transactions retained
        var sortOrder: Int = 0                  // STAB-03 footgun: pass sortOrder explicitly at every call site
        var sourceLabel: String? = nil          // set by migration for auto-created accounts; nil for manual
        var createdAt: Date = Date()            // UTC (rule 4)

        // Inverse relationship to Expense.accountID — declared on THIS side only (rule 7).
        // Expense uses bare accountID: UUID? (NOT a @Relationship) to avoid circular macro error (Pitfall 5).
        // deleteRule: .nullify — deleting an Account clears Expense.account link (does not delete expenses).
        @Relationship(deleteRule: .nullify)
        var expenses: [SchemaV7.Expense] = []

        init(name: String, typeRaw: String = "savings", sourceLabel: String? = nil) {
            self.id = UUID()
            self.name = name
            self.typeRaw = typeRaw
            self.sourceLabel = sourceLabel
            self.createdAt = Date()
        }
    }

    // MARK: - Asset @Model (additive V7 change: amfiSchemeCode appended — D-01, ASSET-01/02/04)

    @Model
    final class Asset {
        // No @Attribute(.unique) — CloudKit does not support unique constraints (rule 2).
        var id: UUID = UUID()                   // UUID primary key (rule 6)
        var name: String? = nil                 // optional per CloudKit rule 2
        var assetClassRaw: String? = nil        // "mutual_fund" | "stock" | "nps" — Phase 11 populates (rule 8)
        var units: Decimal? = nil               // Decimal not Double (rule 3); nil = not set
        var costBasisPerUnit: Decimal? = nil    // Decimal (rule 3)
        var currentNAV: Decimal? = nil          // Decimal (rule 3); Phase 11 sets via auto-fetch or manual
        var navAsOfDate: Date? = nil            // UTC (rule 4); nil = NAV never set
        var createdAt: Date = Date()            // UTC (rule 4)
        // --- NEW in SchemaV7: AMFI scheme code (D-01) ---
        // Append AFTER all V6 Asset fields (additive only — never reorder/remove existing fields).
        // nil for stocks, NPS, and manually-managed MF holdings that haven't been linked yet.
        var amfiSchemeCode: String? = nil       // D-01: AMFI scheme code for exact NAV matching; nil = not linked

        init() {
            self.id = UUID()
            self.createdAt = Date()
        }
    }

    // MARK: - NetWorthSnapshot @Model (NEW in SchemaV7 — D-03, D-08, D-09, ASSET-08)

    /// One snapshot per day (upserted via NetWorthSnapshotService — no @Attribute(.unique) per CloudKit rule 2).
    /// `date` holds the start-of-day in IST converted to UTC; serves as the upsert key.
    /// All money fields use Decimal (rule 3). Per-class breakdown per D-09.
    @Model
    final class NetWorthSnapshot {
        // No @Attribute(.unique) — CloudKit does not support uniqueness constraints (rule 2).
        // Upsert dedup is implemented via fetch-before-insert in NetWorthSnapshotService.
        var id: UUID = UUID()                   // UUID primary key (rule 6)
        var date: Date = Date()                 // UTC; represents start-of-day IST (upsert key, D-08)
        var totalNetWorth: Decimal = Decimal(0) // Decimal (rule 3); MF + stock + NPS + cash total (D-09)
        // Per-class sub-totals (D-09) — separate Decimal fields, simpler to query than a Codable blob
        var mfValue: Decimal = Decimal(0)       // sum of mutual fund holding values
        var stockValue: Decimal = Decimal(0)    // sum of stock holding values
        var npsValue: Decimal = Decimal(0)      // sum of NPS holding values
        var cashValue: Decimal = Decimal(0)     // sum of AccountBalance.compute() for all active accounts (D-11)
        var createdAt: Date = Date()            // UTC (rule 4)

        init() {
            self.id = UUID()
            self.createdAt = Date()
        }
    }
}
