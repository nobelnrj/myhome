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

    /// Fetch ALL rows of the 11 syncable models plus DeletionLog, map to DTOs, and sort every
    /// array deterministically by syncID so identical stores export identical canonical bytes.
    static func makeSnapshot(
        context: ModelContext,
        deviceName: String,
        exportedAt: Date = Date()
    ) throws -> SyncSnapshot {
        let categories = try context.fetch(FetchDescriptor<Category>())
            .map(dto).sorted { $0.syncID.uuidString < $1.syncID.uuidString }
        let expenses = try context.fetch(FetchDescriptor<Expense>())
            .map(dto).sorted { $0.syncID.uuidString < $1.syncID.uuidString }
        let notes = try context.fetch(FetchDescriptor<Note>())
            .map(dto).sorted { $0.syncID.uuidString < $1.syncID.uuidString }
        let noteBlocks = try context.fetch(FetchDescriptor<NoteBlock>())
            .map(dto).sorted { $0.syncID.uuidString < $1.syncID.uuidString }
        let accounts = try context.fetch(FetchDescriptor<Account>())
            .map(dto).sorted { $0.syncID.uuidString < $1.syncID.uuidString }
        let assets = try context.fetch(FetchDescriptor<Asset>())
            .map(dto).sorted { $0.syncID.uuidString < $1.syncID.uuidString }
        let netWorthSnapshots = try context.fetch(FetchDescriptor<NetWorthSnapshot>())
            .map(dto).sorted { $0.syncID.uuidString < $1.syncID.uuidString }
        let sips = try context.fetch(FetchDescriptor<SIP>())
            .map(dto).sorted { $0.syncID.uuidString < $1.syncID.uuidString }
        let sipAmountChanges = try context.fetch(FetchDescriptor<SIPAmountChange>())
            .map(dto).sorted { $0.syncID.uuidString < $1.syncID.uuidString }
        let contributions = try context.fetch(FetchDescriptor<Contribution>())
            .map(dto).sorted { $0.syncID.uuidString < $1.syncID.uuidString }
        let routineCompletions = try context.fetch(FetchDescriptor<RoutineCompletion>())
            .map(dto).sorted { $0.syncID.uuidString < $1.syncID.uuidString }
        let deletions = try context.fetch(FetchDescriptor<DeletionLog>())
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
    static func exportData(context: ModelContext, deviceName: String) throws -> Data {
        try SnapshotCodec.encode(makeSnapshot(context: context, deviceName: deviceName))
    }
}
