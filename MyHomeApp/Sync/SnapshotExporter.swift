import Foundation
import SwiftData

/// SYNC-02 — full-store → deterministic `SyncSnapshot` exporter (Plan 03).
///
/// This is the model→wire half of the merge engine. It fetches every syncable row plus the
/// tombstone log and maps each to its Plan-02 DTO, converting `Decimal` money fields to canonical
/// strings (`SyncDecimal`) and replacing the two cross-wire `@Relationship`s
/// (`Expense.categories`, `NoteBlock.note`) with syncID references.
///
/// DETERMINISM CONTRACT: every array is sorted by `syncID.uuidString` (deletions by
/// `entitySyncID.uuidString` then `deletedAt`) and `categorySyncIDs` is sorted by `uuidString`,
/// so two stores holding the same logical rows always export byte-identical canonical `Data`.
/// The golden round-trip test (Plan 03, Task 3) and the LWW canonical-bytes tiebreak
/// (`SyncMergePolicy`) both depend on this.
///
/// SINGLE SOURCE OF model→DTO TRUTH: the per-entity `dto(_:)` mappers are `internal` (not
/// private) so `SnapshotImporter` reuses the EXACT same mapping to build local-side canonical
/// bytes for LWW tiebreaks — if export and the tiebreak disagreed by one field, ties would
/// resolve inconsistently across devices.
@MainActor
enum SnapshotExporter {

    // MARK: - Per-entity DTO mappers (reused by SnapshotImporter for local canonical bytes)

    static func dto(_ c: Category) -> CategoryDTO {
        CategoryDTO(
            id: c.id,
            syncID: c.syncID,
            updatedAt: c.updatedAt,
            name: c.name,
            symbolName: c.symbolName,
            sortOrder: c.sortOrder,
            monthlyBudget: c.monthlyBudget.map(SyncDecimal.string(from:)),
            currencyCode: c.currencyCode,
            createdAt: c.createdAt
        )
    }

    static func dto(_ e: Expense) -> ExpenseDTO {
        ExpenseDTO(
            id: e.id,
            syncID: e.syncID,
            updatedAt: e.updatedAt,
            amount: SyncDecimal.string(from: e.amount),
            currencyCode: e.currencyCode,
            date: e.date,
            note: e.note,
            createdAt: e.createdAt,
            categorySyncIDs: e.categories
                .map(\.syncID)
                .sorted { $0.uuidString < $1.uuidString },
            rawEmailBody: e.rawEmailBody,
            parserID: e.parserID,
            parserVersion: e.parserVersion,
            sourceLabel: e.sourceLabel,
            gmailMessageID: e.gmailMessageID,
            ingestionStateRaw: e.ingestionStateRaw,
            parseConfidence: e.parseConfidence,
            sourceAccount: e.sourceAccount,
            accountID: e.accountID,
            isTransfer: e.isTransfer,
            transferPairID: e.transferPairID
        )
    }

    static func dto(_ n: Note) -> NoteDTO {
        NoteDTO(
            id: n.id,
            syncID: n.syncID,
            updatedAt: n.updatedAt,
            title: n.title,
            isPinned: n.isPinned,
            createdAt: n.createdAt,
            modifiedAt: n.modifiedAt,
            reminderEnabled: n.reminderEnabled,
            reminderDate: n.reminderDate,
            reminderIsAllDay: n.reminderIsAllDay,
            reminderRecurrenceData: n.reminderRecurrenceData,
            reminderEndRuleData: n.reminderEndRuleData,
            reminderLeadMinutes: n.reminderLeadMinutes,
            isDailyRoutine: n.isDailyRoutine,
            routineLastResetDate: n.routineLastResetDate,
            routineDailyReminderTime: n.routineDailyReminderTime
        )
    }

    static func dto(_ b: NoteBlock) -> NoteBlockDTO {
        NoteBlockDTO(
            id: b.id,
            syncID: b.syncID,
            updatedAt: b.updatedAt,
            kindRaw: b.kindRaw,
            text: b.text,
            isChecked: b.isChecked,
            order: b.order,
            noteSyncID: b.note?.syncID,
            reminderEnabled: b.reminderEnabled,
            reminderDate: b.reminderDate,
            reminderIsAllDay: b.reminderIsAllDay,
            reminderRecurrenceData: b.reminderRecurrenceData,
            reminderEndRuleData: b.reminderEndRuleData,
            reminderLeadMinutes: b.reminderLeadMinutes
        )
    }

    static func dto(_ a: Account) -> AccountDTO {
        AccountDTO(
            id: a.id,
            syncID: a.syncID,
            updatedAt: a.updatedAt,
            name: a.name,
            typeRaw: a.typeRaw,
            symbolName: a.symbolName,
            colorHex: a.colorHex,
            last4: a.last4,
            balanceBaseline: a.balanceBaseline.map(SyncDecimal.string(from:)),
            balanceAsOfDate: a.balanceAsOfDate,
            isArchived: a.isArchived,
            sortOrder: a.sortOrder,
            sourceLabel: a.sourceLabel,
            createdAt: a.createdAt
        )
    }

    static func dto(_ a: Asset) -> AssetDTO {
        AssetDTO(
            id: a.id,
            syncID: a.syncID,
            updatedAt: a.updatedAt,
            name: a.name,
            assetClassRaw: a.assetClassRaw,
            units: a.units.map(SyncDecimal.string(from:)),
            costBasisPerUnit: a.costBasisPerUnit.map(SyncDecimal.string(from:)),
            currentNAV: a.currentNAV.map(SyncDecimal.string(from:)),
            navAsOfDate: a.navAsOfDate,
            createdAt: a.createdAt,
            amfiSchemeCode: a.amfiSchemeCode,
            npsSchemeCode: a.npsSchemeCode
        )
    }

    static func dto(_ s: NetWorthSnapshot) -> NetWorthSnapshotDTO {
        NetWorthSnapshotDTO(
            id: s.id,
            syncID: s.syncID,
            updatedAt: s.updatedAt,
            date: s.date,
            totalNetWorth: SyncDecimal.string(from: s.totalNetWorth),
            mfValue: SyncDecimal.string(from: s.mfValue),
            stockValue: SyncDecimal.string(from: s.stockValue),
            npsValue: SyncDecimal.string(from: s.npsValue),
            cashValue: SyncDecimal.string(from: s.cashValue),
            createdAt: s.createdAt
        )
    }

    static func dto(_ s: SIP) -> SIPDTO {
        SIPDTO(
            id: s.id,
            syncID: s.syncID,
            updatedAt: s.updatedAt,
            assetID: s.assetID,
            dayOfMonth: s.dayOfMonth,
            amount: SyncDecimal.string(from: s.amount),
            startDate: s.startDate,
            isActive: s.isActive,
            lastAccruedDate: s.lastAccruedDate,
            reminderNotificationID: s.reminderNotificationID,
            createdAt: s.createdAt,
            npsAllocationE: s.npsAllocationE,
            npsAllocationC: s.npsAllocationC,
            npsAllocationG: s.npsAllocationG,
            npsAssetE: s.npsAssetE,
            npsAssetC: s.npsAssetC,
            npsAssetG: s.npsAssetG
        )
    }

    static func dto(_ s: SIPAmountChange) -> SIPAmountChangeDTO {
        SIPAmountChangeDTO(
            id: s.id,
            syncID: s.syncID,
            updatedAt: s.updatedAt,
            sipID: s.sipID,
            effectiveFrom: s.effectiveFrom,
            amount: SyncDecimal.string(from: s.amount),
            createdAt: s.createdAt
        )
    }

    static func dto(_ c: Contribution) -> ContributionDTO {
        ContributionDTO(
            id: c.id,
            syncID: c.syncID,
            updatedAt: c.updatedAt,
            assetID: c.assetID,
            sipID: c.sipID,
            date: c.date,
            amount: SyncDecimal.string(from: c.amount),
            navUsed: SyncDecimal.string(from: c.navUsed),
            navDate: c.navDate,
            unitsAdded: SyncDecimal.string(from: c.unitsAdded),
            isEstimate: c.isEstimate,
            createdAt: c.createdAt
        )
    }

    static func dto(_ r: RoutineCompletion) -> RoutineCompletionDTO {
        RoutineCompletionDTO(
            id: r.id,
            syncID: r.syncID,
            updatedAt: r.updatedAt,
            noteID: r.noteID,
            dayKey: r.dayKey,
            completedAt: r.completedAt,
            createdAt: r.createdAt
        )
    }

    static func dto(_ d: DeletionLog) -> DeletionDTO {
        DeletionDTO(
            entitySyncID: d.entitySyncID,
            entityKindRaw: d.entityKindRaw,
            deletedAt: d.deletedAt
        )
    }

    // MARK: - Full-store snapshot

    /// Fetch every IN-SCOPE row (see `SyncScope`) plus the matching tombstones, map to DTOs, and
    /// sort every array deterministically by syncID so identical stores export identical
    /// canonical bytes. Out-of-scope kinds — all financial data in v1.3 — are not fetched, so
    /// they never leave the device.
    static func makeSnapshot(
        context: ModelContext,
        deviceName: String,
        exportedAt: Date = Date(),
        scope: SyncScope = .production
    ) throws -> SyncSnapshot {
        // Out-of-scope kinds are never fetched, so their rows cannot leave this device even
        // in memory. `SyncScope` is the single source of truth; see its doc comment.
        func rows<Model: PersistentModel, D>(
            _ kind: SyncEntityKind,
            _ map: (Model) -> D,
            _ syncID: (D) -> UUID
        ) throws -> [D] {
            guard scope.isSynced(kind) else { return [] }
            return try context.fetch(FetchDescriptor<Model>())
                .map(map)
                .sorted { syncID($0).uuidString < syncID($1).uuidString }
        }

        let categories = try rows(.category, dto(_:) as (Category) -> CategoryDTO, \.syncID)
        let expenses = try rows(.expense, dto(_:) as (Expense) -> ExpenseDTO, \.syncID)
        let notes = try rows(.note, dto(_:) as (Note) -> NoteDTO, \.syncID)
        let noteBlocks = try rows(.noteBlock, dto(_:) as (NoteBlock) -> NoteBlockDTO, \.syncID)
        let accounts = try rows(.account, dto(_:) as (Account) -> AccountDTO, \.syncID)
        let assets = try rows(.asset, dto(_:) as (Asset) -> AssetDTO, \.syncID)
        let netWorthSnapshots = try rows(
            .netWorthSnapshot, dto(_:) as (NetWorthSnapshot) -> NetWorthSnapshotDTO, \.syncID
        )
        let sips = try rows(.sip, dto(_:) as (SIP) -> SIPDTO, \.syncID)
        let sipAmountChanges = try rows(
            .sipAmountChange, dto(_:) as (SIPAmountChange) -> SIPAmountChangeDTO, \.syncID
        )
        let contributions = try rows(
            .contribution, dto(_:) as (Contribution) -> ContributionDTO, \.syncID
        )
        let routineCompletions = try rows(
            .routineCompletion, dto(_:) as (RoutineCompletion) -> RoutineCompletionDTO, \.syncID
        )
        // Tombstones for out-of-scope kinds are dropped too — an excluded deletion must not
        // travel, or one phone could delete rows of a kind it is not allowed to see.
        let deletions = try context.fetch(FetchDescriptor<DeletionLog>())
            .filter { SyncEntityKind(rawValue: $0.entityKindRaw).map(scope.isSynced) ?? false }
            .map(dto)
            .sorted {
                if $0.entitySyncID.uuidString != $1.entitySyncID.uuidString {
                    return $0.entitySyncID.uuidString < $1.entitySyncID.uuidString
                }
                return $0.deletedAt < $1.deletedAt
            }

        return SyncSnapshot(
            schemaVersion: SyncSnapshot.currentSchemaVersion,
            exportedAt: exportedAt,
            deviceName: deviceName,
            categories: categories,
            expenses: expenses,
            notes: notes,
            noteBlocks: noteBlocks,
            accounts: accounts,
            assets: assets,
            netWorthSnapshots: netWorthSnapshots,
            sips: sips,
            sipAmountChanges: sipAmountChanges,
            contributions: contributions,
            routineCompletions: routineCompletions,
            deletions: deletions
        )
    }

    /// Canonical bytes of the full-store snapshot — what Phase 19's transport sends on the wire.
    static func exportData(
        context: ModelContext,
        deviceName: String,
        scope: SyncScope = .production
    ) throws -> Data {
        try SnapshotCodec.encode(
            makeSnapshot(context: context, deviceName: deviceName, scope: scope)
        )
    }
}
