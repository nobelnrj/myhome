import SwiftData
import Foundation

/// VersionedSchema v10.0.0 — copies V9's models VERBATIM and, per SYNC-01 (Phase 18),
/// appends two sync-identity fields to every syncable @Model and introduces the new
/// `DeletionLog` tombstone @Model.
///
/// NEW in SchemaV10 (SYNC-01, Phase 18):
/// - a defaulted `syncID` UUID on ALL 11 models — the stable cross-device identity key.
///   NO unique attribute (CloudKit rule 2); uniqueness is enforced by the merge
///   engine's fetch-then-upsert (Plan 03), NOT by the store.
/// - a defaulted `updatedAt` Date on the 10 models that lacked it — the LWW (last-writer-wins)
///   clock the merge engine compares. Expense ALREADY carried `updatedAt` since V4 — that field
///   is preserved verbatim (do NOT add a second one).
/// - `DeletionLog` @Model — tombstone rows recording deletions so deletes propagate across
///   devices (String raw `entityKindRaw`, rule 8; no stored enum).
///
/// CONSTANT-DEFAULT FOOTGUN: the `UUID()`/`Date()` default expressions above are evaluated
/// ONCE during an additive migration, so every migrated row would otherwise share ONE syncID.
/// The V9→V10 `didMigrate` closure (MigrationPlan.swift) backfills a DISTINCT syncID per row.
///
/// Rules: (all 8 CloudKit-readiness rules from V9 preserved verbatim)
/// - SchemaV1.swift through SchemaV9.swift are IMMUTABLE after they ship. Never edit them.
/// - SchemaV10 is an additive superset: copies SchemaV9's models verbatim and appends
///   two defaulted fields to every model plus one new @Model (DeletionLog).
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
enum SchemaV10: VersionedSchema {
    static let versionIdentifier = Schema.Version(10, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV10.Expense.self,
            SchemaV10.Category.self,
            SchemaV10.Note.self,
            SchemaV10.NoteBlock.self,
            SchemaV10.Account.self,
            SchemaV10.Asset.self,
            SchemaV10.NetWorthSnapshot.self,
            SchemaV10.SIP.self,
            SchemaV10.SIPAmountChange.self,
            SchemaV10.Contribution.self,
            SchemaV10.RoutineCompletion.self,
            // NEW in V10 (SYNC-01):
            SchemaV10.DeletionLog.self,
        ]
    }

    // MARK: - Category @Model (copied verbatim from SchemaV9 — + syncID/updatedAt, SYNC-01)

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
        var expenses: [SchemaV10.Expense] = []

        // NEW in SchemaV10 (SYNC-01, Phase 18): sync identity + LWW clock. Additive only.
        var syncID: UUID = UUID()               // cross-device identity; distinct per row via didMigrate backfill
        var updatedAt: Date = Date()            // LWW clock; backfilled from createdAt in migration

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

    // MARK: - Expense @Model (copied verbatim from SchemaV9 — + syncID, SYNC-01; updatedAt already present since V4)

    @Model
    final class Expense {
        // No @Attribute(.unique) — CloudKit does not support unique constraints.
        var id: UUID = UUID()
        var amount: Decimal = Decimal(0)        // never Double (Pitfall 17)
        var currencyCode: String = "INR"        // schema-forward: multi-currency-ready
        var date: Date = Date()                 // UTC timestamp; format at display time (D-02)
        var note: String? = nil                 // optional free-form memo / payee (D-05, D-06)
        var createdAt: Date = Date()
        var updatedAt: Date = Date()            // PRESENT SINCE V4 — SYNC-01 reuses this as the LWW clock; do NOT duplicate

        // to-many relationship to Category (D2-02, CloudKit rule 7).
        // deleteRule: .nullify — deleting a Category clears this array (does not delete the expense).
        @Relationship(deleteRule: .nullify, inverse: \SchemaV10.Category.expenses)
        var categories: [SchemaV10.Category] = []

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

        // NEW in SchemaV10 (SYNC-01, Phase 18): sync identity. Additive only.
        // NOTE: updatedAt is NOT added here — Expense already has one from V4 (used as the LWW clock).
        var syncID: UUID = UUID()               // cross-device identity; distinct per row via didMigrate backfill

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

    // MARK: - Note @Model (copied verbatim from SchemaV9 — + syncID/updatedAt, SYNC-01)

    @Model
    final class Note {
        // No @Attribute(.unique) — CloudKit does not support unique constraints.
        var id: UUID = UUID()
        /// Required at the UX layer; defaults to "" so CloudKit can store a reminder-less note.
        var title: String = ""
        /// Ordered block list. Cascade-deletes all NoteBlocks when the Note is deleted.
        /// inverse: declared on THIS side only (CloudKit rule 7 / SchemaV2 caveat at lines 42-48/75).
        @Relationship(deleteRule: .cascade, inverse: \SchemaV10.NoteBlock.note)
        var blocks: [SchemaV10.NoteBlock]? = []
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

        // --- NEW in SchemaV9: daily routine notification time (D-04, Phase 12) ---
        // Append AFTER all V8 Note fields (additive only — never reorder/remove existing fields).
        // nil = no daily reminder configured. Date value; only .hour and .minute components used at scheduling.
        var routineDailyReminderTime: Date? = nil   // D-04: optional daily fire time; nil = no reminder

        // NEW in SchemaV10 (SYNC-01, Phase 18): sync identity + LWW clock. Additive only.
        var syncID: UUID = UUID()               // cross-device identity; distinct per row via didMigrate backfill
        var updatedAt: Date = Date()            // LWW clock; backfilled from modifiedAt in migration

        init(title: String = "") {
            self.id = UUID()
            self.title = title
            self.createdAt = Date()
            self.modifiedAt = Date()
        }
    }

    // MARK: - NoteBlock @Model (copied verbatim from SchemaV9 — + syncID/updatedAt, SYNC-01)

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
        var note: SchemaV10.Note? = nil

        // Reminder fields (block-level reminder — D3-02)
        var reminderEnabled: Bool = false
        var reminderDate: Date? = nil           // UTC; nil if no reminder
        var reminderIsAllDay: Bool = false
        /// JSON-encoded ReminderRecurrence value type (never a stored enum — rule 8).
        var reminderRecurrenceData: Data? = nil
        /// JSON-encoded ReminderEndRule value type (never a stored enum — rule 8).
        var reminderEndRuleData: Data? = nil
        var reminderLeadMinutes: Int = 0        // 0 = no advance alert

        // NEW in SchemaV10 (SYNC-01, Phase 18): sync identity + LWW clock. Additive only.
        var syncID: UUID = UUID()               // cross-device identity; distinct per row via didMigrate backfill
        var updatedAt: Date = Date()            // LWW clock; backfilled from note?.modifiedAt in migration

        init(kindRaw: String = "text", text: String = "", order: Int = 0) {
            self.id = UUID()
            self.kindRaw = kindRaw
            self.text = text
            self.order = order
        }
    }

    // MARK: - Account @Model (copied verbatim from SchemaV9 — + syncID/updatedAt, SYNC-01)

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
        var expenses: [SchemaV10.Expense] = []

        // NEW in SchemaV10 (SYNC-01, Phase 18): sync identity + LWW clock. Additive only.
        var syncID: UUID = UUID()               // cross-device identity; distinct per row via didMigrate backfill
        var updatedAt: Date = Date()            // LWW clock; backfilled from createdAt in migration

        init(name: String, typeRaw: String = "savings", sourceLabel: String? = nil) {
            self.id = UUID()
            self.name = name
            self.typeRaw = typeRaw
            self.sourceLabel = sourceLabel
            self.createdAt = Date()
        }
    }

    // MARK: - Asset @Model (copied verbatim from SchemaV9 — + syncID/updatedAt, SYNC-01)

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
        // --- From SchemaV7: AMFI scheme code (D-01) ---
        var amfiSchemeCode: String? = nil       // D-01: AMFI scheme code for exact NAV matching; nil = not linked
        // --- From SchemaV8: NPS scheme code (D-01, D-08) ---
        var npsSchemeCode: String? = nil        // D-01/D-08: NPS scheme code; nil for non-NPS or unlinked

        // NEW in SchemaV10 (SYNC-01, Phase 18): sync identity + LWW clock. Additive only.
        var syncID: UUID = UUID()               // cross-device identity; distinct per row via didMigrate backfill
        var updatedAt: Date = Date()            // LWW clock; backfilled from createdAt in migration

        init() {
            self.id = UUID()
            self.createdAt = Date()
        }
    }

    // MARK: - NetWorthSnapshot @Model (copied verbatim from SchemaV9 — + syncID/updatedAt, SYNC-01)

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

        // NEW in SchemaV10 (SYNC-01, Phase 18): sync identity + LWW clock. Additive only.
        var syncID: UUID = UUID()               // cross-device identity; distinct per row via didMigrate backfill
        var updatedAt: Date = Date()            // LWW clock; backfilled from createdAt in migration

        init() {
            self.id = UUID()
            self.createdAt = Date()
        }
    }

    // MARK: - SIP @Model (copied verbatim from SchemaV9 — + syncID/updatedAt, SYNC-01)

    /// Represents one SIP definition tied to an Asset holding.
    /// Bare UUID back-references (NOT @Relationship) per Pitfall 5 / CloudKit rule 7.
    @Model
    final class SIP {
        // No @Attribute(.unique) — CloudKit does not support uniqueness constraints (rule 2).
        var id: UUID = UUID()                   // UUID primary key (rule 6)
        var assetID: UUID = UUID()              // bare UUID back-ref to Asset.id (NOT @Relationship — Pitfall 5)
        var dayOfMonth: Int = 1                 // installment day; 1–31 (Calendar clamps short months)
        var amount: Decimal = Decimal(0)        // Decimal not Double (rule 3); monthly installment amount
        var startDate: Date = Date()            // UTC; first possible installment date
        var isActive: Bool = true               // D-04: false = stop future accrual
        var lastAccruedDate: Date? = nil        // UTC; nil = never accrued; accrual cursor (exclusive lower bound)
        var reminderNotificationID: String? = nil // UNNotificationRequest.identifier for reconcile reminder
        var createdAt: Date = Date()            // UTC (rule 4)
        // NPS allocation % fields (Int percentages summing to 100; 0 for MF SIPs — D-01)
        var npsAllocationE: Int = 0             // Equity allocation %
        var npsAllocationC: Int = 0             // Corporate Debt allocation %
        var npsAllocationG: Int = 0             // Government Securities allocation %
        // Asset UUIDs for each NPS strategy holding (nil for MF SIPs)
        var npsAssetE: UUID? = nil              // Asset.id for Equity strategy holding
        var npsAssetC: UUID? = nil              // Asset.id for Corporate Debt strategy holding
        var npsAssetG: UUID? = nil              // Asset.id for Government Securities strategy holding

        // NEW in SchemaV10 (SYNC-01, Phase 18): sync identity + LWW clock. Additive only.
        var syncID: UUID = UUID()               // cross-device identity; distinct per row via didMigrate backfill
        var updatedAt: Date = Date()            // LWW clock; backfilled from createdAt in migration

        init(
            id: UUID = UUID(),
            assetID: UUID = UUID(),
            dayOfMonth: Int = 1,
            amount: Decimal = Decimal(0),
            startDate: Date = Date(),
            isActive: Bool = true,
            lastAccruedDate: Date? = nil,
            reminderNotificationID: String? = nil,
            npsAllocationE: Int = 0,
            npsAllocationC: Int = 0,
            npsAllocationG: Int = 0,
            npsAssetE: UUID? = nil,
            npsAssetC: UUID? = nil,
            npsAssetG: UUID? = nil
        ) {
            self.id = id
            self.assetID = assetID
            self.dayOfMonth = dayOfMonth
            self.amount = amount
            self.startDate = startDate
            self.isActive = isActive
            self.lastAccruedDate = lastAccruedDate
            self.reminderNotificationID = reminderNotificationID
            self.createdAt = Date()
            self.npsAllocationE = npsAllocationE
            self.npsAllocationC = npsAllocationC
            self.npsAllocationG = npsAllocationG
            self.npsAssetE = npsAssetE
            self.npsAssetC = npsAssetC
            self.npsAssetG = npsAssetG
        }
    }

    // MARK: - SIPAmountChange @Model (copied verbatim from SchemaV9 — + syncID/updatedAt, SYNC-01)

    /// Records a point-in-time SIP amount change; applies from next installment only (D-07).
    @Model
    final class SIPAmountChange {
        // No @Attribute(.unique) — CloudKit does not support uniqueness constraints (rule 2).
        var id: UUID = UUID()                   // UUID primary key (rule 6)
        var sipID: UUID = UUID()                // bare UUID back-ref to SIP.id (NOT @Relationship — Pitfall 5)
        var effectiveFrom: Date = Date()        // UTC; next installment on/after this date uses the new amount
        var amount: Decimal = Decimal(0)        // Decimal not Double (rule 3); new monthly installment amount
        var createdAt: Date = Date()            // UTC (rule 4)

        // NEW in SchemaV10 (SYNC-01, Phase 18): sync identity + LWW clock. Additive only.
        var syncID: UUID = UUID()               // cross-device identity; distinct per row via didMigrate backfill
        var updatedAt: Date = Date()            // LWW clock; backfilled from createdAt in migration

        init(
            id: UUID = UUID(),
            sipID: UUID = UUID(),
            effectiveFrom: Date = Date(),
            amount: Decimal = Decimal(0)
        ) {
            self.id = id
            self.sipID = sipID
            self.effectiveFrom = effectiveFrom
            self.amount = amount
            self.createdAt = Date()
        }
    }

    // MARK: - Contribution @Model (copied verbatim from SchemaV9 — + syncID/updatedAt, SYNC-01)

    /// One estimated or reconciled unit-purchase entry per installment date (D-03).
    /// isEstimate = true until the user performs a whole-holding reconcile (D-05).
    @Model
    final class Contribution {
        // No @Attribute(.unique) — CloudKit does not support uniqueness constraints (rule 2).
        var id: UUID = UUID()                   // UUID primary key (rule 6)
        var assetID: UUID = UUID()              // bare UUID back-ref to Asset.id (NOT @Relationship)
        var sipID: UUID = UUID()                // bare UUID back-ref to SIP.id (NOT @Relationship)
        var date: Date = Date()                 // UTC; IST start-of-day for installment date (rule 4)
        var amount: Decimal = Decimal(0)        // Decimal not Double (rule 3); installment amount for this entry
        var navUsed: Decimal = Decimal(0)       // Decimal; NAV fetched from historical endpoint
        var navDate: Date = Date()              // UTC; date the NAV was published (may differ from installment date)
        var unitsAdded: Decimal = Decimal(0)    // Decimal; amount ÷ navUsed (rounded down to 4dp)
        var isEstimate: Bool = true             // D-03: true until user reconciles total units (D-05)
        var createdAt: Date = Date()            // UTC (rule 4)

        // NEW in SchemaV10 (SYNC-01, Phase 18): sync identity + LWW clock. Additive only.
        var syncID: UUID = UUID()               // cross-device identity; distinct per row via didMigrate backfill
        var updatedAt: Date = Date()            // LWW clock; backfilled from createdAt in migration

        init(
            id: UUID = UUID(),
            assetID: UUID = UUID(),
            sipID: UUID = UUID(),
            date: Date = Date(),
            amount: Decimal = Decimal(0),
            navUsed: Decimal = Decimal(0),
            navDate: Date = Date(),
            unitsAdded: Decimal = Decimal(0),
            isEstimate: Bool = true
        ) {
            self.id = id
            self.assetID = assetID
            self.sipID = sipID
            self.date = date
            self.amount = amount
            self.navUsed = navUsed
            self.navDate = navDate
            self.unitsAdded = unitsAdded
            self.isEstimate = isEstimate
            self.createdAt = Date()
        }
    }

    // MARK: - RoutineCompletion @Model (copied verbatim from SchemaV9 — + syncID/updatedAt, SYNC-01)

    /// One completion record per routine note per IST day.
    /// Bare UUID back-reference (NOT @Relationship) per Pitfall 5 / CloudKit rule 7.
    /// dayKey stores IST start-of-day as UTC (same convention as NetWorthSnapshot.date).
    /// No @Attribute(.unique) — CloudKit rule 2; idempotency via fetch-before-insert (D-06).
    @Model
    final class RoutineCompletion {
        // No @Attribute(.unique) — CloudKit rule 2.
        var id: UUID = UUID()                      // UUID primary key (rule 6)
        var noteID: UUID = UUID()                  // bare UUID back-ref to Note.id (NOT @Relationship — Pitfall 5/rule 7)
        var dayKey: Date = Date()                  // UTC; represents IST start-of-day (upsert key)
        var completedAt: Date = Date()             // UTC; when the last box was ticked / "Done today" tapped
        var createdAt: Date = Date()               // UTC (rule 4)

        // NEW in SchemaV10 (SYNC-01, Phase 18): sync identity + LWW clock. Additive only.
        var syncID: UUID = UUID()                  // cross-device identity; distinct per row via didMigrate backfill
        var updatedAt: Date = Date()               // LWW clock; backfilled from createdAt in migration

        init(noteID: UUID, dayKey: Date, completedAt: Date = Date()) {
            self.id = UUID()
            self.noteID = noteID
            self.dayKey = dayKey
            self.completedAt = completedAt
            self.createdAt = Date()
        }
    }

    // MARK: - DeletionLog @Model (NEW in SchemaV10 — SYNC-01, Phase 18)

    /// Tombstone record: one row per deleted syncable entity, so deletions propagate across
    /// devices via the merge engine (Plan 03) instead of a delete looking like a "missing" row
    /// that the peer would resurrect.
    ///
    /// `entityKindRaw` is a String raw value (rule 8: NOT a stored enum) — the rawValues of the
    /// `SyncEntityKind` enum defined in Plan 02. No @Attribute(.unique); dedupe on `entitySyncID`
    /// is merge-engine logic (fetch-before-insert), not a store constraint (rule 2).
    @Model
    final class DeletionLog {
        // No @Attribute(.unique) — CloudKit rule 2; dedupe on entitySyncID is merge-engine logic.
        var id: UUID = UUID()                   // UUID primary key (rule 6)
        var entitySyncID: UUID = UUID()         // syncID of the deleted record (cross-device identity of the tombstone)
        var entityKindRaw: String = ""          // SyncEntityKind rawValue (rule 8: String not enum); defined in Plan 02
        var deletedAt: Date = Date()            // UTC; when the entity was deleted (LWW input for delete-vs-edit races)
        var createdAt: Date = Date()            // UTC (rule 4); when this tombstone row was written

        init(entitySyncID: UUID, entityKindRaw: String, deletedAt: Date = Date()) {
            self.id = UUID()
            self.entitySyncID = entitySyncID
            self.entityKindRaw = entityKindRaw
            self.deletedAt = deletedAt
            self.createdAt = Date()
        }
    }
}
