import SwiftData
import Foundation

/// VersionedSchema v5.0.0 — copies V4's models verbatim, adds sourceAccount to Expense.
///
/// Rules:
/// - SchemaV1.swift, SchemaV2.swift, SchemaV3.swift, and SchemaV4.swift are IMMUTABLE after they ship. Never edit them.
/// - SchemaV5 is an additive superset: it copies SchemaV4's models verbatim
///   and adds ONE new optional field to Expense (sourceAccount — D-MA-03).
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
enum SchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV5.Expense.self,
            SchemaV5.Category.self,
            SchemaV5.Note.self,
            SchemaV5.NoteBlock.self,
        ]
    }

    // MARK: - Category @Model (copied verbatim from SchemaV4)

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
        var expenses: [SchemaV5.Expense] = []

        // STAB-03 footgun: sortOrder defaults to 0. Any caller that OMITS sortOrder
        // lands among the seeded 0..13 rows in the @Query(sort: \Category.sortOrder) list,
        // not at a predictable edge. New custom categories MUST pass min(existing.sortOrder)-1
        // (see ManageCategoriesView.addCategory) to surface at the TOP of the list. Default
        // left at 0 (changing it would break the seed path and SchemaV5 identity) — pass
        // sortOrder explicitly at every call site.
        init(name: String, symbolName: String?, sortOrder: Int = 0) {
            self.id = UUID()
            self.name = name
            self.symbolName = symbolName
            self.sortOrder = sortOrder
            self.createdAt = Date()
        }
    }

    // MARK: - Expense @Model (copied verbatim from SchemaV4; sourceAccount appended — D-MA-03)

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
        @Relationship(deleteRule: .nullify, inverse: \SchemaV5.Category.expenses)
        var categories: [SchemaV5.Category] = []

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

        // --- New in SchemaV5: multi-account dedup field (D-MA-03) ---
        /// The email address of the Gmail account that ingested this expense.
        /// nil for manual expenses and legacy expenses ingested before multi-account support.
        /// Used as part of the (sourceAccount, gmailMessageID) idempotency key — D-MA-01/03.
        var sourceAccount: String? = nil        // D-MA-03 — owning Gmail account email; nil for manual/legacy

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

    // MARK: - Note @Model (copied verbatim from SchemaV4)

    @Model
    final class Note {
        // No @Attribute(.unique) — CloudKit does not support unique constraints.
        var id: UUID = UUID()
        /// Required at the UX layer; defaults to "" so CloudKit can store a reminder-less note.
        var title: String = ""
        /// Ordered block list. Cascade-deletes all NoteBlocks when the Note is deleted.
        /// inverse: declared on THIS side only (CloudKit rule 7 / SchemaV2 caveat at lines 42-48/75).
        @Relationship(deleteRule: .cascade, inverse: \SchemaV5.NoteBlock.note)
        var blocks: [SchemaV5.NoteBlock]? = []
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

        init(title: String = "") {
            self.id = UUID()
            self.title = title
            self.createdAt = Date()
            self.modifiedAt = Date()
        }
    }

    // MARK: - NoteBlock @Model (copied verbatim from SchemaV4)

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
        var note: SchemaV5.Note? = nil

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
}
