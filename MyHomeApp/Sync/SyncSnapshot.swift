import Foundation

/// SYNC-02 — the transport-agnostic snapshot document layer.
///
/// This file is a PURE value layer: Foundation only, zero SwiftData / UIKit imports.
/// It defines the wire format that Phase 19's MultipeerConnectivity transport and
/// AirDrop reuse byte-for-byte. Everything here is testable with plain value types —
/// no ModelContainer, no device.
///
/// Two classes of bug are killed at the source here:
///   1. Money corruption — every `Decimal` crosses JSON as a `String` (SyncDecimal),
///      NEVER as a JSON number, so a JSON floating-point value can never round-trip a
///      rupee-and-paise amount into drift.
///   2. Non-deterministic merges — `SnapshotCodec` uses a canonical encoder
///      (`.sortedKeys` + `.millisecondsSince1970` dates) so the same snapshot always
///      produces byte-identical `Data`, which the LWW tiebreak (SyncMergePolicy) relies on.

// MARK: - SyncEntityKind

/// The syncable entity kinds. `DeletionLog.entityKindRaw` stores these rawValues so a
/// tombstone can name which kind of record it deleted (rule 8: String raw, not a stored enum).
public enum SyncEntityKind: String, Codable, CaseIterable, Sendable {
    case category
    case expense
    case note
    case noteBlock
    case account
    case asset
    case netWorthSnapshot
    case sip
    case sipAmountChange
    case contribution
    case routineCompletion
}

// MARK: - SyncDecimal

/// Locale-independent Decimal <-> String bridge. Money NEVER crosses the wire as a
/// JSON number — only as a canonical decimal String — so no floating-point value can
/// ever corrupt an amount. `string(from:)` and `decimal(from:)` are exact inverses for
/// every value SwiftData stores in a money field.
public enum SyncDecimal {
    /// Canonical, locale-independent string form (e.g. "1234.56", "-14000", "0").
    public static func string(from d: Decimal) -> String {
        // NSDecimalNumber.stringValue is locale-independent (always '.' as separator,
        // no grouping) and preserves the full decimal magnitude with no rounding.
        NSDecimalNumber(decimal: d).stringValue
    }

    /// Parse a canonical string back to Decimal. POSIX locale forces '.' as the decimal
    /// separator regardless of device region. Returns nil only for genuinely malformed input.
    public static func decimal(from s: String) -> Decimal? {
        Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))
    }
}

// MARK: - SyncError

/// Errors surfaced by SnapshotCodec when decoding untrusted bytes (the phase's primary
/// untrusted-input gate — anyone can AirDrop a file). Both cases are Equatable so tests
/// can assert exact associated values.
public enum SyncError: Error, Equatable {
    /// The snapshot's stamped schema version does not match this build's. Thrown from the
    /// version probe BEFORE any entity data is decoded — a mismatched snapshot never reaches
    /// the store even partially.
    case schemaVersionMismatch(found: Int, expected: Int)
    /// The bytes could not be decoded into a well-formed snapshot (truncated / garbage /
    /// wrong shape). Wraps the underlying DecodingError description.
    case malformedSnapshot(String)
}

// MARK: - Entity DTOs
//
// One DTO per SchemaV10 @Model, mirroring EVERY stored property with the same name.
// Mapping rules:
//   - Decimal      -> String  (via SyncDecimal); optional Decimal -> String?
//   - Data?        -> Data?   (JSON base64 — reminder recurrence / end-rule blobs)
//   - @Relationship never crosses directly; replaced by syncID / id back-refs
//   - Bare-UUID back-refs (accountID, assetID, sipID, noteID, transferPairID, npsAsset*)
//     pass through unchanged — they key on `id`, preserved by import
//   - UUID/Date/String/Int/Bool pass through unchanged
// Every DTO carries id, syncID, updatedAt.

public struct CategoryDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var syncID: UUID
    public var updatedAt: Date
    public var name: String?
    public var symbolName: String?
    public var sortOrder: Int
    public var monthlyBudget: String?   // Decimal -> String (SyncDecimal)
    public var currencyCode: String
    public var createdAt: Date
}

public struct ExpenseDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var syncID: UUID
    public var updatedAt: Date
    public var amount: String           // Decimal -> String (SyncDecimal)
    public var currencyCode: String
    public var date: Date
    public var note: String?
    public var createdAt: Date
    /// Replaces the `categories` @Relationship — the syncIDs of the linked categories.
    public var categorySyncIDs: [UUID]
    public var rawEmailBody: String?
    public var parserID: String?
    public var parserVersion: String?
    public var sourceLabel: String?
    public var gmailMessageID: String?
    public var ingestionStateRaw: String?
    public var parseConfidence: Double?  // ratio 0.0–1.0 — NOT money, so this scalar type is correct
    public var sourceAccount: String?
    public var accountID: UUID?
    public var isTransfer: Bool?
    public var transferPairID: UUID?
}

public struct NoteDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var syncID: UUID
    public var updatedAt: Date
    public var title: String
    public var isPinned: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    public var reminderEnabled: Bool
    public var reminderDate: Date?
    public var reminderIsAllDay: Bool
    public var reminderRecurrenceData: Data?
    public var reminderEndRuleData: Data?
    public var reminderLeadMinutes: Int
    public var isDailyRoutine: Bool
    public var routineLastResetDate: Date?
    public var routineDailyReminderTime: Date?
    // `blocks` omitted — NoteBlocks live in the top-level noteBlocks array, keyed back by noteSyncID.
}

public struct NoteBlockDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var syncID: UUID
    public var updatedAt: Date
    public var kindRaw: String
    public var text: String
    public var isChecked: Bool
    public var order: Int
    /// Replaces the `note` @Relationship — the syncID of the owning Note.
    public var noteSyncID: UUID?
    public var reminderEnabled: Bool
    public var reminderDate: Date?
    public var reminderIsAllDay: Bool
    public var reminderRecurrenceData: Data?
    public var reminderEndRuleData: Data?
    public var reminderLeadMinutes: Int
}

public struct AccountDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var syncID: UUID
    public var updatedAt: Date
    public var name: String?
    public var typeRaw: String?
    public var symbolName: String?
    public var colorHex: String?
    public var last4: String?
    public var balanceBaseline: String?   // Decimal -> String (SyncDecimal)
    public var balanceAsOfDate: Date?
    public var isArchived: Bool
    public var sortOrder: Int
    public var sourceLabel: String?
    public var createdAt: Date
    // `expenses` inverse omitted — Expense carries accountID back-ref.
}

public struct AssetDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var syncID: UUID
    public var updatedAt: Date
    public var name: String?
    public var assetClassRaw: String?
    public var units: String?             // Decimal -> String (SyncDecimal)
    public var costBasisPerUnit: String?  // Decimal -> String (SyncDecimal)
    public var currentNAV: String?        // Decimal -> String (SyncDecimal)
    public var navAsOfDate: Date?
    public var createdAt: Date
    public var amfiSchemeCode: String?
    public var npsSchemeCode: String?
}

public struct NetWorthSnapshotDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var syncID: UUID
    public var updatedAt: Date
    public var date: Date
    public var totalNetWorth: String      // Decimal -> String (SyncDecimal)
    public var mfValue: String            // Decimal -> String
    public var stockValue: String         // Decimal -> String
    public var npsValue: String           // Decimal -> String
    public var cashValue: String          // Decimal -> String
    public var createdAt: Date
}

public struct SIPDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var syncID: UUID
    public var updatedAt: Date
    public var assetID: UUID
    public var dayOfMonth: Int
    public var amount: String             // Decimal -> String (SyncDecimal)
    public var startDate: Date
    public var isActive: Bool
    public var lastAccruedDate: Date?
    public var reminderNotificationID: String?
    public var createdAt: Date
    public var npsAllocationE: Int
    public var npsAllocationC: Int
    public var npsAllocationG: Int
    public var npsAssetE: UUID?
    public var npsAssetC: UUID?
    public var npsAssetG: UUID?
}

public struct SIPAmountChangeDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var syncID: UUID
    public var updatedAt: Date
    public var sipID: UUID
    public var effectiveFrom: Date
    public var amount: String             // Decimal -> String (SyncDecimal)
    public var createdAt: Date
}

public struct ContributionDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var syncID: UUID
    public var updatedAt: Date
    public var assetID: UUID
    public var sipID: UUID
    public var date: Date
    public var amount: String             // Decimal -> String (SyncDecimal)
    public var navUsed: String            // Decimal -> String
    public var navDate: Date
    public var unitsAdded: String         // Decimal -> String
    public var isEstimate: Bool
    public var createdAt: Date
}

public struct RoutineCompletionDTO: Codable, Equatable, Sendable {
    public var id: UUID
    public var syncID: UUID
    public var updatedAt: Date
    public var noteID: UUID
    public var dayKey: Date
    public var completedAt: Date
    public var createdAt: Date
}

/// Tombstone carried on the wire — mirrors DeletionLog's cross-device fields.
/// `entityKindRaw` holds a `SyncEntityKind` rawValue.
public struct DeletionDTO: Codable, Equatable, Sendable {
    public var entitySyncID: UUID
    public var entityKindRaw: String
    public var deletedAt: Date
}

// MARK: - SyncSnapshot

/// A complete, transport-agnostic export of one device's syncable state at a point in time.
/// Version-stamped so a peer refuses a snapshot from an incompatible schema before decoding
/// any entity data.
public struct SyncSnapshot: Codable, Equatable, Sendable {
    /// Tracks the SchemaV10 major version. Bump this in lockstep with every future schema bump
    /// so the version probe refuses cross-schema snapshots.
    public static let currentSchemaVersion = 10

    public var schemaVersion: Int
    public var exportedAt: Date
    public var deviceName: String

    public var categories: [CategoryDTO]
    public var expenses: [ExpenseDTO]
    public var notes: [NoteDTO]
    public var noteBlocks: [NoteBlockDTO]
    public var accounts: [AccountDTO]
    public var assets: [AssetDTO]
    public var netWorthSnapshots: [NetWorthSnapshotDTO]
    public var sips: [SIPDTO]
    public var sipAmountChanges: [SIPAmountChangeDTO]
    public var contributions: [ContributionDTO]
    public var routineCompletions: [RoutineCompletionDTO]

    public var deletions: [DeletionDTO]

    public init(
        schemaVersion: Int = SyncSnapshot.currentSchemaVersion,
        exportedAt: Date,
        deviceName: String,
        categories: [CategoryDTO] = [],
        expenses: [ExpenseDTO] = [],
        notes: [NoteDTO] = [],
        noteBlocks: [NoteBlockDTO] = [],
        accounts: [AccountDTO] = [],
        assets: [AssetDTO] = [],
        netWorthSnapshots: [NetWorthSnapshotDTO] = [],
        sips: [SIPDTO] = [],
        sipAmountChanges: [SIPAmountChangeDTO] = [],
        contributions: [ContributionDTO] = [],
        routineCompletions: [RoutineCompletionDTO] = [],
        deletions: [DeletionDTO] = []
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.deviceName = deviceName
        self.categories = categories
        self.expenses = expenses
        self.notes = notes
        self.noteBlocks = noteBlocks
        self.accounts = accounts
        self.assets = assets
        self.netWorthSnapshots = netWorthSnapshots
        self.sips = sips
        self.sipAmountChanges = sipAmountChanges
        self.contributions = contributions
        self.routineCompletions = routineCompletions
        self.deletions = deletions
    }
}

// MARK: - SnapshotCodec

/// Deterministic canonical encode/decode for SyncSnapshot.
///
/// The encoder is canonical (`.sortedKeys` + `.millisecondsSince1970` dates) so the same
/// snapshot always produces byte-identical `Data`. This is a hard requirement of the LWW
/// tiebreak in `SyncMergePolicy`, which compares canonical bytes on exact-timestamp ties.
/// `.iso8601` is deliberately NOT used — it drops sub-second precision inconsistently across
/// encode paths and would break byte-determinism.
public enum SnapshotCodec {

    /// Canonical encoder used everywhere — a single source of encoding truth so `encode`,
    /// `canonicalData`, and the merge tiebreak all agree byte-for-byte.
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    /// Only the version field — decoded FIRST so a schema mismatch is refused before any
    /// entity data is parsed.
    private struct VersionProbe: Codable {
        let schemaVersion: Int
    }

    /// Encode a snapshot to canonical, deterministic bytes.
    public static func encode(_ snapshot: SyncSnapshot) throws -> Data {
        try makeEncoder().encode(snapshot)
    }

    /// Decode untrusted bytes into a SyncSnapshot.
    ///
    /// Order matters: probe the version FIRST and refuse a mismatch before attempting a full
    /// decode, so a snapshot from an incompatible schema never partially populates. Any
    /// DecodingError from the full decode is wrapped as `.malformedSnapshot`.
    public static func decode(_ data: Data) throws -> SyncSnapshot {
        let decoder = makeDecoder()

        // 1. Version gate — refuse mismatched schema before decoding entity data.
        let probe: VersionProbe
        do {
            probe = try decoder.decode(VersionProbe.self, from: data)
        } catch {
            throw SyncError.malformedSnapshot(String(describing: error))
        }
        guard probe.schemaVersion == SyncSnapshot.currentSchemaVersion else {
            throw SyncError.schemaVersionMismatch(
                found: probe.schemaVersion,
                expected: SyncSnapshot.currentSchemaVersion
            )
        }

        // 2. Full decode — wrap any structural failure as malformedSnapshot.
        do {
            return try decoder.decode(SyncSnapshot.self, from: data)
        } catch {
            throw SyncError.malformedSnapshot(String(describing: error))
        }
    }

    /// Canonical bytes for any Encodable value — the exact-tie tiebreak input used by the
    /// merge engine (Plan 03). Same `.sortedKeys` + `.millisecondsSince1970` encoder as
    /// `encode`, so per-record canonical bytes are stable and comparable across devices.
    public static func canonicalData<T: Encodable>(_ value: T) throws -> Data {
        try makeEncoder().encode(value)
    }
}
