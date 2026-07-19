import Foundation
import SwiftData

/// Result of one `SnapshotImporter.merge` — surfaced to the UI/transport for visibility and
/// asserted directly by the golden round-trip / idempotency tests.
struct MergeStats: Equatable, Sendable {
    var inserted = 0
    var updated = 0
    var deleted = 0
    var skipped = 0
    var adopted = 0
}

/// SYNC-02 — the transport-agnostic merge engine (Plan 03).
///
/// Applies a decoded `SyncSnapshot` to a local store with these invariants, in this EXACT order:
///   1. Tombstone union — remote DeletionLog rows merge into the local log (max deletedAt wins).
///   2. Apply tombstones — local rows whose deletion `tombstoneWins` are deleted BEFORE any upsert
///      (no-resurrection, SYNC criterion 2).
///   3. Identity adoption — a remote row created independently on both phones (Category by name,
///      Expense by (sourceAccount, gmailMessageID)) is paired to its local twin and both converge
///      to `min(uuidString)` syncID (vantage-independent, no day-one duplicates).
///   4. Upsert pass 1 (scalars) — fetch-all-then-index-by-syncID, then insert-or-LWW-overwrite.
///   5. Wiring pass 2 (create-then-link) — resolve Expense↔Category and NoteBlock→Note by syncID
///      only after every row exists.
///   6. A single `try context.save()` — any thrown error leaves the store unsaved (atomic merge).
///
/// Every conflict DECISION lives in `SyncMergePolicy` (pure); this file only fetches, indexes,
/// applies, and counts — that split keeps the engine unit-testable and transport-agnostic.
@MainActor
enum SnapshotImporter {

    // MARK: - Public entry points (Phase 19 transport calls exactly these)

    /// Decode untrusted bytes (version refusal happens in `SnapshotCodec.decode` BEFORE any store
    /// mutation) then merge.
    static func mergeData(_ data: Data, into context: ModelContext) throws -> MergeStats {
        let snapshot = try SnapshotCodec.decode(data)
        return try merge(snapshot, into: context)
    }

    static func merge(_ snapshot: SyncSnapshot, into context: ModelContext) throws -> MergeStats {
        var stats = MergeStats()

        // ── 1. Tombstone union ────────────────────────────────────────────────────────────────
        // Index local tombstones by entitySyncID; insert missing remote ones, keep max deletedAt.
        var localDeletions = try context.fetch(FetchDescriptor<DeletionLog>())
        var deletionByEntity: [UUID: DeletionLog] = [:]
        for d in localDeletions { deletionByEntity[d.entitySyncID] = d }

        for remote in snapshot.deletions {
            if let existing = deletionByEntity[remote.entitySyncID] {
                if remote.deletedAt > existing.deletedAt { existing.deletedAt = remote.deletedAt }
            } else {
                let row = DeletionLog(
                    entitySyncID: remote.entitySyncID,
                    entityKindRaw: remote.entityKindRaw,
                    deletedAt: remote.deletedAt
                )
                context.insert(row)
                deletionByEntity[remote.entitySyncID] = row
                localDeletions.append(row)
            }
        }

        // The unified tombstone set: latest deletedAt per (kind, syncID).
        // Keyed by "kind\u{1F}syncID" so a syncID reused across kinds never cross-deletes.
        var tombstone: [String: Date] = [:]
        for d in localDeletions {
            let key = tombstoneKey(kindRaw: d.entityKindRaw, syncID: d.entitySyncID)
            if let existing = tombstone[key] { tombstone[key] = max(existing, d.deletedAt) }
            else { tombstone[key] = d.deletedAt }
        }

        // ── 2. Apply tombstones to local rows (before any upsert) ───────────────────────────────
        stats.deleted += applyTombstones(
            kind: .category, tombstone: tombstone, context: context,
            rows: try context.fetch(FetchDescriptor<Category>())
        ) { $0.syncID } updatedAt: { $0.updatedAt }
        stats.deleted += applyTombstones(
            kind: .expense, tombstone: tombstone, context: context,
            rows: try context.fetch(FetchDescriptor<Expense>())
        ) { $0.syncID } updatedAt: { $0.updatedAt }
        stats.deleted += applyTombstones(
            kind: .note, tombstone: tombstone, context: context,
            rows: try context.fetch(FetchDescriptor<Note>())
        ) { $0.syncID } updatedAt: { $0.updatedAt }
        stats.deleted += applyTombstones(
            kind: .noteBlock, tombstone: tombstone, context: context,
            rows: try context.fetch(FetchDescriptor<NoteBlock>())
        ) { $0.syncID } updatedAt: { $0.updatedAt }
        stats.deleted += applyTombstones(
            kind: .account, tombstone: tombstone, context: context,
            rows: try context.fetch(FetchDescriptor<Account>())
        ) { $0.syncID } updatedAt: { $0.updatedAt }
        stats.deleted += applyTombstones(
            kind: .asset, tombstone: tombstone, context: context,
            rows: try context.fetch(FetchDescriptor<Asset>())
        ) { $0.syncID } updatedAt: { $0.updatedAt }
        stats.deleted += applyTombstones(
            kind: .netWorthSnapshot, tombstone: tombstone, context: context,
            rows: try context.fetch(FetchDescriptor<NetWorthSnapshot>())
        ) { $0.syncID } updatedAt: { $0.updatedAt }
        stats.deleted += applyTombstones(
            kind: .sip, tombstone: tombstone, context: context,
            rows: try context.fetch(FetchDescriptor<SIP>())
        ) { $0.syncID } updatedAt: { $0.updatedAt }
        stats.deleted += applyTombstones(
            kind: .sipAmountChange, tombstone: tombstone, context: context,
            rows: try context.fetch(FetchDescriptor<SIPAmountChange>())
        ) { $0.syncID } updatedAt: { $0.updatedAt }
        stats.deleted += applyTombstones(
            kind: .contribution, tombstone: tombstone, context: context,
            rows: try context.fetch(FetchDescriptor<Contribution>())
        ) { $0.syncID } updatedAt: { $0.updatedAt }
        stats.deleted += applyTombstones(
            kind: .routineCompletion, tombstone: tombstone, context: context,
            rows: try context.fetch(FetchDescriptor<RoutineCompletion>())
        ) { $0.syncID } updatedAt: { $0.updatedAt }

        // ── 3. Identity adoption (Category by name, Expense by (sourceAccount, gmailMessageID)) ──
        // Adopt BEFORE the upsert: pair a remote row to its independently-created local twin,
        // converge BOTH to min(uuidString) syncID, and REWRITE the remote DTO's syncID to the
        // winner so the upsert matches the twin (LWW) instead of inserting a duplicate.
        let (adoptedCategories, catAdopts) = adoptCategories(snapshot.categories, context: context)
        let (adoptedExpenses, expAdopts) = adoptExpenses(snapshot.expenses, context: context)
        stats.adopted += catAdopts + expAdopts

        // ── 4. Upsert pass 1 (scalars only) ─────────────────────────────────────────────────────
        // Track which rows pass 2 must wire (only inserted/updated Expenses and NoteBlocks).
        var categoryBySyncID: [UUID: Category] = [:]
        var noteBySyncID: [UUID: Note] = [:]
        var expensesToWire: [(Expense, ExpenseDTO)] = []
        var blocksToWire: [(NoteBlock, NoteBlockDTO)] = []

        // Category (adoption-rewritten syncIDs)
        upsert(
            adoptedCategories, kind: .category, tombstone: tombstone, context: context,
            local: try context.fetch(FetchDescriptor<Category>()), syncID: { $0.syncID },
            updatedAt: { $0.updatedAt }, localDTO: SnapshotExporter.dto, dtoUpdatedAt: { $0.updatedAt },
            stats: &stats,
            make: { _ in Category(name: "", symbolName: nil) },
            apply: { row, dto in applyCategory(dto, to: row) }
        )
        // Index all categories (existing + inserted) for wiring pass.
        for c in try context.fetch(FetchDescriptor<Category>()) { categoryBySyncID[c.syncID] = c }

        // Note
        upsert(
            snapshot.notes, kind: .note, tombstone: tombstone, context: context,
            local: try context.fetch(FetchDescriptor<Note>()), syncID: { $0.syncID },
            updatedAt: { $0.updatedAt }, localDTO: SnapshotExporter.dto, dtoUpdatedAt: { $0.updatedAt },
            stats: &stats,
            make: { _ in Note() },
            apply: { row, dto in applyNote(dto, to: row) }
        )
        for n in try context.fetch(FetchDescriptor<Note>()) { noteBySyncID[n.syncID] = n }

        // Expense (adoption-rewritten syncIDs; defer relationship wiring to pass 2)
        upsert(
            adoptedExpenses, kind: .expense, tombstone: tombstone, context: context,
            local: try context.fetch(FetchDescriptor<Expense>()), syncID: { $0.syncID },
            updatedAt: { $0.updatedAt }, localDTO: SnapshotExporter.dto, dtoUpdatedAt: { $0.updatedAt },
            stats: &stats,
            make: { dto in Expense(amount: Decimal(0)) },
            apply: { row, dto in
                applyExpense(dto, to: row)
                expensesToWire.append((row, dto))
            }
        )

        // NoteBlock — skip orphans (noteSyncID nil / tombstoned / unresolvable) so no orphan rows.
        upsert(
            snapshot.noteBlocks, kind: .noteBlock, tombstone: tombstone, context: context,
            local: try context.fetch(FetchDescriptor<NoteBlock>()), syncID: { $0.syncID },
            updatedAt: { $0.updatedAt }, localDTO: SnapshotExporter.dto, dtoUpdatedAt: { $0.updatedAt },
            stats: &stats,
            skip: { dto in
                guard let nsid = dto.noteSyncID, noteBySyncID[nsid] != nil else { return true }
                return false
            },
            make: { _ in NoteBlock() },
            apply: { row, dto in
                applyNoteBlock(dto, to: row)
                blocksToWire.append((row, dto))
            }
        )

        // Account
        upsert(
            snapshot.accounts, kind: .account, tombstone: tombstone, context: context,
            local: try context.fetch(FetchDescriptor<Account>()), syncID: { $0.syncID },
            updatedAt: { $0.updatedAt }, localDTO: SnapshotExporter.dto, dtoUpdatedAt: { $0.updatedAt },
            stats: &stats,
            make: { _ in Account(name: "") },
            apply: { row, dto in applyAccount(dto, to: row) }
        )

        // Asset
        upsert(
            snapshot.assets, kind: .asset, tombstone: tombstone, context: context,
            local: try context.fetch(FetchDescriptor<Asset>()), syncID: { $0.syncID },
            updatedAt: { $0.updatedAt }, localDTO: SnapshotExporter.dto, dtoUpdatedAt: { $0.updatedAt },
            stats: &stats,
            make: { _ in Asset() },
            apply: { row, dto in applyAsset(dto, to: row) }
        )

        // NetWorthSnapshot (apply can throw on a malformed non-optional Decimal)
        try upsert(
            snapshot.netWorthSnapshots, kind: .netWorthSnapshot, tombstone: tombstone, context: context,
            local: try context.fetch(FetchDescriptor<NetWorthSnapshot>()), syncID: { $0.syncID },
            updatedAt: { $0.updatedAt }, localDTO: SnapshotExporter.dto, dtoUpdatedAt: { $0.updatedAt },
            stats: &stats,
            make: { _ in NetWorthSnapshot() },
            apply: { row, dto in try applyNetWorth(dto, to: row) }
        )

        // SIP
        upsert(
            snapshot.sips, kind: .sip, tombstone: tombstone, context: context,
            local: try context.fetch(FetchDescriptor<SIP>()), syncID: { $0.syncID },
            updatedAt: { $0.updatedAt }, localDTO: SnapshotExporter.dto, dtoUpdatedAt: { $0.updatedAt },
            stats: &stats,
            make: { _ in SIP() },
            apply: { row, dto in applySIP(dto, to: row) }
        )

        // SIPAmountChange
        upsert(
            snapshot.sipAmountChanges, kind: .sipAmountChange, tombstone: tombstone, context: context,
            local: try context.fetch(FetchDescriptor<SIPAmountChange>()), syncID: { $0.syncID },
            updatedAt: { $0.updatedAt }, localDTO: SnapshotExporter.dto, dtoUpdatedAt: { $0.updatedAt },
            stats: &stats,
            make: { _ in SIPAmountChange() },
            apply: { row, dto in applySIPAmountChange(dto, to: row) }
        )

        // Contribution
        upsert(
            snapshot.contributions, kind: .contribution, tombstone: tombstone, context: context,
            local: try context.fetch(FetchDescriptor<Contribution>()), syncID: { $0.syncID },
            updatedAt: { $0.updatedAt }, localDTO: SnapshotExporter.dto, dtoUpdatedAt: { $0.updatedAt },
            stats: &stats,
            make: { _ in Contribution() },
            apply: { row, dto in applyContribution(dto, to: row) }
        )

        // RoutineCompletion
        upsert(
            snapshot.routineCompletions, kind: .routineCompletion, tombstone: tombstone, context: context,
            local: try context.fetch(FetchDescriptor<RoutineCompletion>()), syncID: { $0.syncID },
            updatedAt: { $0.updatedAt }, localDTO: SnapshotExporter.dto, dtoUpdatedAt: { $0.updatedAt },
            stats: &stats,
            make: { _ in RoutineCompletion(noteID: UUID(), dayKey: Date()) },
            apply: { row, dto in applyRoutineCompletion(dto, to: row) }
        )

        // ── 5. Wiring pass 2 (create-then-link) — only rows touched in pass 1 ────────────────────
        for (expense, dto) in expensesToWire {
            expense.categories = dto.categorySyncIDs.compactMap { categoryBySyncID[$0] }
        }
        for (block, dto) in blocksToWire {
            block.note = dto.noteSyncID.flatMap { noteBySyncID[$0] }
        }

        // ── 6. Single atomic save ───────────────────────────────────────────────────────────────
        try context.save()
        return stats
    }

    // MARK: - Tombstone helpers

    private static func tombstoneKey(kindRaw: String, syncID: UUID) -> String {
        "\(kindRaw)\u{1F}\(syncID.uuidString)"
    }

    /// Delete every local row of `kind` whose tombstone `tombstoneWins` over its updatedAt.
    private static func applyTombstones<Row>(
        kind: SyncEntityKind,
        tombstone: [String: Date],
        context: ModelContext,
        rows: [Row],
        syncID: (Row) -> UUID,
        updatedAt: (Row) -> Date
    ) -> Int where Row: PersistentModel {
        var deleted = 0
        for row in rows {
            let key = tombstoneKey(kindRaw: kind.rawValue, syncID: syncID(row))
            guard let deletedAt = tombstone[key] else { continue }
            if SyncMergePolicy.tombstoneWins(deletedAt: deletedAt, recordUpdatedAt: updatedAt(row)) {
                // Engine-side application of an already-recorded tombstone — NOT a user delete.
                // deleteAppliedTombstone avoids writing a duplicate/fresher DeletionLog (see DeletionTracker).
                context.deleteAppliedTombstone(row)
                deleted += 1
            }
        }
        return deleted
    }

    // MARK: - Generic upsert (fetch-then-upsert on syncID, LWW via SyncMergePolicy)

    /// Insert-or-LWW-overwrite `dtos` into the store. Never inserts before checking the local
    /// syncID index. A tombstone winning over `dtoUpdatedAt` skips the row entirely (no
    /// resurrection). `skip` lets an entity refuse a row for its own reason (orphan NoteBlock).
    private static func upsert<Row, DTO>(
        _ dtos: [DTO],
        kind: SyncEntityKind,
        tombstone: [String: Date],
        context: ModelContext,
        local: [Row],
        syncID: (Row) -> UUID,
        updatedAt: (Row) -> Date,
        localDTO: (Row) -> DTO,
        dtoUpdatedAt: (DTO) -> Date,
        stats: inout MergeStats,
        skip: (DTO) -> Bool = { _ in false },
        make: (DTO) -> Row,
        apply: (Row, DTO) throws -> Void
    ) rethrows where Row: PersistentModel, DTO: Encodable {
        var index: [UUID: Row] = [:]
        for row in local { index[syncID(row)] = row }

        for dto in dtos {
            if skip(dto) { stats.skipped += 1; continue }

            let dtoSync = dtoSyncID(dto)

            // No-resurrection: a tombstone winning over this DTO's updatedAt skips it.
            let key = tombstoneKey(kindRaw: kind.rawValue, syncID: dtoSync)
            if let deletedAt = tombstone[key],
               SyncMergePolicy.tombstoneWins(deletedAt: deletedAt, recordUpdatedAt: dtoUpdatedAt(dto)) {
                stats.skipped += 1
                continue
            }

            if let existing = index[dtoSync] {
                // LWW: overwrite only if remote wins (or deterministic tie win).
                let remoteWins: Bool = {
                    guard let localCanon = try? SnapshotCodec.canonicalData(localDTO(existing)),
                          let remoteCanon = try? SnapshotCodec.canonicalData(dto) else { return true }
                    return SyncMergePolicy.remoteWins(
                        localUpdatedAt: updatedAt(existing),
                        localCanonical: localCanon,
                        remoteUpdatedAt: dtoUpdatedAt(dto),
                        remoteCanonical: remoteCanon
                    )
                }()
                if remoteWins {
                    try apply(existing, dto)
                    stats.updated += 1
                } else {
                    stats.skipped += 1
                }
            } else {
                let row = make(dto)
                try apply(row, dto)
                context.insert(row)
                index[dtoSync] = row
                stats.inserted += 1
            }
        }
    }

    /// Every DTO carries a `syncID` — pull it via the exact-key JSON shape (all DTOs encode it).
    /// A tiny decode keeps `upsert` generic without a `HasSyncID` protocol retrofit on Plan 02.
    private static func dtoSyncID<DTO: Encodable>(_ dto: DTO) -> UUID {
        guard let data = try? SnapshotCodec.canonicalData(dto),
              let probe = try? JSONDecoder().decode(SyncIDProbe.self, from: data) else {
            return UUID()
        }
        return probe.syncID
    }

    /// Minimal shape to pull `syncID` out of any DTO's canonical JSON (all DTOs encode it).
    private struct SyncIDProbe: Decodable { let syncID: UUID }

    // MARK: - Identity adoption

    /// Category adoption: a remote category with no local syncID match but an equal trimmed,
    /// case-insensitive name is the SAME seeded category on both phones. Converge the local twin's
    /// syncID to min(uuidString) and REWRITE the remote DTO's syncID to the same winner so the
    /// upsert matches the twin. Returns (rewritten dtos, adopted count).
    private static func adoptCategories(
        _ dtos: [CategoryDTO], context: ModelContext
    ) -> ([CategoryDTO], Int) {
        guard let locals = try? context.fetch(FetchDescriptor<Category>()) else { return (dtos, 0) }
        var localBySync: [UUID: Category] = [:]
        var localByName: [String: Category] = [:]
        for c in locals {
            localBySync[c.syncID] = c
            if let n = normalized(c.name) { localByName[n] = c }
        }
        var rewritten = dtos
        var adopted = 0
        for i in rewritten.indices {
            let dto = rewritten[i]
            guard localBySync[dto.syncID] == nil,
                  let n = normalized(dto.name),
                  let twin = localByName[n] else { continue }
            let winner = minSyncID(twin.syncID, dto.syncID)
            localBySync[twin.syncID] = nil
            twin.syncID = winner
            localBySync[winner] = twin
            localByName[n] = nil                // one remote row per twin
            rewritten[i].syncID = winner        // upsert now matches the twin, not inserts
            adopted += 1
        }
        return (rewritten, adopted)
    }

    /// Expense adoption: a remote expense with no local syncID match but an equal non-nil
    /// (sourceAccount, gmailMessageID) pair is the SAME bank mail ingested independently on both
    /// phones. Converge to min(uuidString) syncID and rewrite the remote DTO to match.
    private static func adoptExpenses(
        _ dtos: [ExpenseDTO], context: ModelContext
    ) -> ([ExpenseDTO], Int) {
        guard let locals = try? context.fetch(FetchDescriptor<Expense>()) else { return (dtos, 0) }
        var localBySync: [UUID: Expense] = [:]
        var localByIdentity: [String: Expense] = [:]
        for e in locals {
            localBySync[e.syncID] = e
            if let key = expenseIdentity(sourceAccount: e.sourceAccount, gmailMessageID: e.gmailMessageID) {
                localByIdentity[key] = e
            }
        }
        var rewritten = dtos
        var adopted = 0
        for i in rewritten.indices {
            let dto = rewritten[i]
            guard localBySync[dto.syncID] == nil,
                  let key = expenseIdentity(sourceAccount: dto.sourceAccount, gmailMessageID: dto.gmailMessageID),
                  let twin = localByIdentity[key] else { continue }
            let winner = minSyncID(twin.syncID, dto.syncID)
            localBySync[twin.syncID] = nil
            twin.syncID = winner
            localBySync[winner] = twin
            localByIdentity[key] = nil          // one remote row per twin
            rewritten[i].syncID = winner        // upsert now matches the twin, not inserts
            adopted += 1
        }
        return (rewritten, adopted)
    }

    private static func normalized(_ name: String?) -> String? {
        guard let n = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !n.isEmpty
        else { return nil }
        return n
    }

    /// The (sourceAccount, gmailMessageID) idempotency key — nil unless BOTH are non-nil (a
    /// manual expense has no gmailMessageID and must never adopt).
    private static func expenseIdentity(sourceAccount: String?, gmailMessageID: String?) -> String? {
        guard let msgID = gmailMessageID, let acct = sourceAccount else { return nil }
        return "\(acct)\u{1F}\(msgID)"
    }

    private static func minSyncID(_ a: UUID, _ b: UUID) -> UUID {
        a.uuidString <= b.uuidString ? a : b
    }

    // MARK: - Per-entity scalar appliers (assign EVERY stored field from the DTO)

    private static func applyCategory(_ dto: CategoryDTO, to c: Category) {
        c.id = dto.id
        c.syncID = dto.syncID
        c.updatedAt = dto.updatedAt
        c.name = dto.name
        c.symbolName = dto.symbolName
        c.sortOrder = dto.sortOrder
        c.monthlyBudget = dto.monthlyBudget.flatMap(SyncDecimal.decimal(from:))
        c.currencyCode = dto.currencyCode
        c.createdAt = dto.createdAt
    }

    private static func applyExpense(_ dto: ExpenseDTO, to e: Expense) {
        e.id = dto.id
        e.syncID = dto.syncID
        e.updatedAt = dto.updatedAt
        e.amount = SyncDecimal.decimal(from: dto.amount) ?? Decimal(0)
        e.currencyCode = dto.currencyCode
        e.date = dto.date
        e.note = dto.note
        e.createdAt = dto.createdAt
        e.rawEmailBody = dto.rawEmailBody
        e.parserID = dto.parserID
        e.parserVersion = dto.parserVersion
        e.sourceLabel = dto.sourceLabel
        e.gmailMessageID = dto.gmailMessageID
        e.ingestionStateRaw = dto.ingestionStateRaw
        e.parseConfidence = dto.parseConfidence
        e.sourceAccount = dto.sourceAccount
        e.accountID = dto.accountID
        e.isTransfer = dto.isTransfer
        e.transferPairID = dto.transferPairID
        // categories wired in pass 2
    }

    private static func applyNote(_ dto: NoteDTO, to n: Note) {
        n.id = dto.id
        n.syncID = dto.syncID
        n.updatedAt = dto.updatedAt
        n.title = dto.title
        n.isPinned = dto.isPinned
        n.createdAt = dto.createdAt
        n.modifiedAt = dto.modifiedAt
        n.reminderEnabled = dto.reminderEnabled
        n.reminderDate = dto.reminderDate
        n.reminderIsAllDay = dto.reminderIsAllDay
        n.reminderRecurrenceData = dto.reminderRecurrenceData
        n.reminderEndRuleData = dto.reminderEndRuleData
        n.reminderLeadMinutes = dto.reminderLeadMinutes
        n.isDailyRoutine = dto.isDailyRoutine
        n.routineLastResetDate = dto.routineLastResetDate
        n.routineDailyReminderTime = dto.routineDailyReminderTime
    }

    private static func applyNoteBlock(_ dto: NoteBlockDTO, to b: NoteBlock) {
        b.id = dto.id
        b.syncID = dto.syncID
        b.updatedAt = dto.updatedAt
        b.kindRaw = dto.kindRaw
        b.text = dto.text
        b.isChecked = dto.isChecked
        b.order = dto.order
        b.reminderEnabled = dto.reminderEnabled
        b.reminderDate = dto.reminderDate
        b.reminderIsAllDay = dto.reminderIsAllDay
        b.reminderRecurrenceData = dto.reminderRecurrenceData
        b.reminderEndRuleData = dto.reminderEndRuleData
        b.reminderLeadMinutes = dto.reminderLeadMinutes
        // note wired in pass 2
    }

    private static func applyAccount(_ dto: AccountDTO, to a: Account) {
        a.id = dto.id
        a.syncID = dto.syncID
        a.updatedAt = dto.updatedAt
        a.name = dto.name
        a.typeRaw = dto.typeRaw
        a.symbolName = dto.symbolName
        a.colorHex = dto.colorHex
        a.last4 = dto.last4
        a.balanceBaseline = dto.balanceBaseline.flatMap(SyncDecimal.decimal(from:))
        a.balanceAsOfDate = dto.balanceAsOfDate
        a.isArchived = dto.isArchived
        a.sortOrder = dto.sortOrder
        a.sourceLabel = dto.sourceLabel
        a.createdAt = dto.createdAt
    }

    private static func applyAsset(_ dto: AssetDTO, to a: Asset) {
        a.id = dto.id
        a.syncID = dto.syncID
        a.updatedAt = dto.updatedAt
        a.name = dto.name
        a.assetClassRaw = dto.assetClassRaw
        a.units = dto.units.flatMap(SyncDecimal.decimal(from:))
        a.costBasisPerUnit = dto.costBasisPerUnit.flatMap(SyncDecimal.decimal(from:))
        a.currentNAV = dto.currentNAV.flatMap(SyncDecimal.decimal(from:))
        a.navAsOfDate = dto.navAsOfDate
        a.createdAt = dto.createdAt
        a.amfiSchemeCode = dto.amfiSchemeCode
        a.npsSchemeCode = dto.npsSchemeCode
    }

    private static func applyNetWorth(_ dto: NetWorthSnapshotDTO, to s: NetWorthSnapshot) throws {
        s.id = dto.id
        s.syncID = dto.syncID
        s.updatedAt = dto.updatedAt
        s.date = dto.date
        s.totalNetWorth = try requireDecimal(dto.totalNetWorth)
        s.mfValue = try requireDecimal(dto.mfValue)
        s.stockValue = try requireDecimal(dto.stockValue)
        s.npsValue = try requireDecimal(dto.npsValue)
        s.cashValue = try requireDecimal(dto.cashValue)
        s.createdAt = dto.createdAt
    }

    private static func applySIP(_ dto: SIPDTO, to s: SIP) {
        s.id = dto.id
        s.syncID = dto.syncID
        s.updatedAt = dto.updatedAt
        s.assetID = dto.assetID
        s.dayOfMonth = dto.dayOfMonth
        s.amount = SyncDecimal.decimal(from: dto.amount) ?? Decimal(0)
        s.startDate = dto.startDate
        s.isActive = dto.isActive
        s.lastAccruedDate = dto.lastAccruedDate
        s.reminderNotificationID = dto.reminderNotificationID
        s.createdAt = dto.createdAt
        s.npsAllocationE = dto.npsAllocationE
        s.npsAllocationC = dto.npsAllocationC
        s.npsAllocationG = dto.npsAllocationG
        s.npsAssetE = dto.npsAssetE
        s.npsAssetC = dto.npsAssetC
        s.npsAssetG = dto.npsAssetG
    }

    private static func applySIPAmountChange(_ dto: SIPAmountChangeDTO, to s: SIPAmountChange) {
        s.id = dto.id
        s.syncID = dto.syncID
        s.updatedAt = dto.updatedAt
        s.sipID = dto.sipID
        s.effectiveFrom = dto.effectiveFrom
        s.amount = SyncDecimal.decimal(from: dto.amount) ?? Decimal(0)
        s.createdAt = dto.createdAt
    }

    private static func applyContribution(_ dto: ContributionDTO, to c: Contribution) {
        c.id = dto.id
        c.syncID = dto.syncID
        c.updatedAt = dto.updatedAt
        c.assetID = dto.assetID
        c.sipID = dto.sipID
        c.date = dto.date
        c.amount = SyncDecimal.decimal(from: dto.amount) ?? Decimal(0)
        c.navUsed = SyncDecimal.decimal(from: dto.navUsed) ?? Decimal(0)
        c.navDate = dto.navDate
        c.unitsAdded = SyncDecimal.decimal(from: dto.unitsAdded) ?? Decimal(0)
        c.isEstimate = dto.isEstimate
        c.createdAt = dto.createdAt
    }

    private static func applyRoutineCompletion(_ dto: RoutineCompletionDTO, to r: RoutineCompletion) {
        r.id = dto.id
        r.syncID = dto.syncID
        r.updatedAt = dto.updatedAt
        r.noteID = dto.noteID
        r.dayKey = dto.dayKey
        r.completedAt = dto.completedAt
        r.createdAt = dto.createdAt
    }

    /// Money fields that are non-optional in the model: a malformed string aborts the merge
    /// (T-18-06 — a bad Decimal must not silently become 0 in a financial store).
    private static func requireDecimal(_ s: String) throws -> Decimal {
        guard let d = SyncDecimal.decimal(from: s) else {
            throw SyncError.malformedSnapshot("Unparseable Decimal string: \(s)")
        }
        return d
    }
}
