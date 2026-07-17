import Testing
import SwiftData
import Foundation
@testable import MyHome

/// `Category` is ambiguous at type-lookup in test scope — disambiguate as the repo does elsewhere.
private typealias Cat = MyHome.Category

/// V9→V10 migration fixture tests — proves the sync-identity migration is additive and, above
/// all, that every migrated row lands with a DISTINCT syncID (SYNC-01, Phase 18).
///
/// BLOCKING: All tests in this suite must pass before any later Phase 18 plan is executed —
/// the merge engine (plan 18-03) is keyed entirely on syncID identity and updatedAt LWW.
///
/// The migration is additive (syncID + updatedAt appended, DeletionLog introduced).
///
/// On the constant-default footgun the v9ToV10 didMigrate backfill defends against: it does NOT
/// reproduce on this toolchain (Xcode 26.5 / iOS 26 simulator). Verified by disabling the
/// backfill and re-running `distinctSyncIDsAcrossAllRows` — it still passed, i.e. SwiftData
/// assigned a distinct UUID per migrated row here. So these tests assert the PROPERTY the merge
/// engine needs (distinct + persisted + stable syncIDs), not the mechanism that supplies it, and
/// they will not catch the backfill being deleted. The backfill is retained anyway: it is
/// idempotent, costs one fetch per table on a one-time migration, and is cheap insurance against
/// the footgun appearing on another OS version or a device migration path we cannot test here.
///
/// STAB-08 guard: this suite inserts and fetches through the bare `Expense` typealias under the
/// production AppMigrationPlan. A partial typealias flip would crash there.
@MainActor
struct SchemaV10MigrationTests {

    // MARK: - Fixture

    /// Seeds a genuine V9 store (3 Expenses, 2 Categories, 1 Note + 1 NoteBlock, 1 Account),
    /// copies it to a fresh URL, and reopens it under the production plan at V10.
    ///
    /// Seeding uses MigrationTestsPlanV9 (trimmed, stops at V9) so the V10 migration is not
    /// triggered until the reopen. The copy avoids container lock contention.
    private func migratedV10Container(
        label: String,
        knownExpenseUpdatedAt: Date
    ) throws -> (container: ModelContainer, storeURL: URL, cleanup: () -> Void) {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v9seed-\(label)-\(UUID()).store")
        let migrateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v9tov10-\(label)-\(UUID()).store")
        let cleanup = {
            try? FileManager.default.removeItem(at: seedURL)
            try? FileManager.default.removeItem(at: migrateURL)
        }

        // 1. Build a genuine V9 store.
        try {
            let v9Schema = Schema(versionedSchema: SchemaV9.self)
            let config = ModelConfiguration(schema: v9Schema, url: seedURL)
            let container = try ModelContainer(
                for: v9Schema,
                migrationPlan: MigrationTestsPlanV9.self,
                configurations: [config]
            )
            let ctx = container.mainContext

            // 3 Expenses with distinct amounts — ≥3 rows of one type proves the backfill is
            // per-row, not per-table.
            let lunch = SchemaV9.Expense(amount: Decimal(9500), note: "Lunch")
            lunch.updatedAt = knownExpenseUpdatedAt   // known value — preservation must be provable
            ctx.insert(lunch)
            ctx.insert(SchemaV9.Expense(amount: Decimal(2500), note: "Coffee"))
            ctx.insert(SchemaV9.Expense(amount: Decimal(41000), note: "Groceries"))

            ctx.insert(SchemaV9.Category(name: "Food", symbolName: "fork.knife"))
            ctx.insert(SchemaV9.Category(name: "Transport", symbolName: "car"))

            let note = SchemaV9.Note(title: "Morning Routine")
            ctx.insert(note)
            let block = SchemaV9.NoteBlock(kindRaw: "checkbox", text: "Brush teeth", order: 0)
            block.note = note
            ctx.insert(block)

            ctx.insert(SchemaV9.Account(name: "HDFC Savings", typeRaw: "savings"))

            try ctx.save()
            try ctx.save()  // second save flushes WAL to the main store file
        }()

        // 2. Copy before opening under V10.
        try FileManager.default.copyItem(at: seedURL, to: migrateURL)

        // 3. Reopen under the production AppMigrationPlan — runs V9→V10.
        let v10Schema = Schema(versionedSchema: SchemaV10.self)
        let migrateConfig = ModelConfiguration(schema: v10Schema, url: migrateURL)
        let container = try ModelContainer(
            for: v10Schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [migrateConfig]
        )
        return (container, migrateURL, cleanup)
    }

    // MARK: - syncID backfill (BLOCKING — the constant-default footgun)

    @Test("V9→V10: every migrated row has a distinct syncID within its table")
    func distinctSyncIDsAcrossAllRows() throws {
        let (container, _, cleanup) = try migratedV10Container(
            label: "syncid", knownExpenseUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        defer { cleanup() }
        let ctx = container.mainContext

        // 3 Expenses — the load-bearing case: distinctness must hold per row, not per table.
        let expenses = try ctx.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 3, "All 3 expense rows must survive V9→V10 migration")
        #expect(Set(expenses.map(\.syncID)).count == 3,
                "Each migrated Expense must have a DISTINCT syncID — rows sharing one syncID would make the merge engine treat different expenses as the same record")

        let categories = try ctx.fetch(FetchDescriptor<Cat>())
        #expect(categories.count == 2, "Both category rows must survive migration")
        #expect(Set(categories.map(\.syncID)).count == 2,
                "Each migrated Category must have a distinct syncID")

        // Cross-table: a single shared default would collide across tables too.
        // Accumulated stepwise — one concatenated expression exceeds the type-checker's budget.
        let notes = try ctx.fetch(FetchDescriptor<Note>())
        let blocks = try ctx.fetch(FetchDescriptor<NoteBlock>())
        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        var allIDs: [UUID] = expenses.map(\.syncID)
        allIDs += categories.map(\.syncID)
        allIDs += notes.map(\.syncID)
        allIDs += blocks.map(\.syncID)
        allIDs += accounts.map(\.syncID)
        #expect(Set(allIDs).count == allIDs.count,
                "syncIDs must be distinct across every migrated row of every table")
    }

    // MARK: - syncID persistence (BLOCKING — identity must survive a relaunch)

    @Test("V9→V10: migrated syncIDs are persisted and identical after closing and reopening the store")
    func syncIDsStableAcrossReopen() throws {
        // Record identity as the migration left it, keyed by a field that is stable by
        // construction. The migrating container is confined to this scope so ARC releases it
        // before the reopen below: two live containers on ONE store file contend for the SQLite
        // lock and destabilise the whole test process, not just this test.
        var idsByNote: [String: UUID] = [:]
        let storeURL: URL
        let cleanup: () -> Void
        do {
            let (container, url, cl) = try migratedV10Container(
                label: "stable", knownExpenseUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000))
            storeURL = url
            cleanup = cl
            for expense in try container.mainContext.fetch(FetchDescriptor<Expense>()) {
                idsByNote[expense.note ?? ""] = expense.syncID
            }
        }
        defer { cleanup() }
        #expect(idsByNote.count == 3, "Fixture must yield 3 distinguishable expenses")

        // Reopen the same store file in a fresh container — simulates an app relaunch. If the
        // syncID default were evaluated lazily per read rather than written by the migration,
        // identity would silently change here and every device would resync as new records.
        let reopened = try ModelContainer(
            for: Schema(versionedSchema: SchemaV10.self),
            migrationPlan: AppMigrationPlan.self,
            configurations: [ModelConfiguration(
                schema: Schema(versionedSchema: SchemaV10.self), url: storeURL)]
        )
        for expense in try reopened.mainContext.fetch(FetchDescriptor<Expense>()) {
            #expect(expense.syncID == idsByNote[expense.note ?? ""],
                    "syncID for '\(expense.note ?? "")' changed across a reopen — migrated identity was not persisted")
        }
    }

    // MARK: - updatedAt backfill

    @Test("V9→V10: Expense keeps its pre-migration updatedAt; others backfill from their own clock")
    func updatedAtBackfillPerModel() throws {
        let known = Date(timeIntervalSince1970: 1_700_000_000)
        let (container, _, cleanup) = try migratedV10Container(
            label: "updatedat", knownExpenseUpdatedAt: known)
        defer { cleanup() }
        let ctx = container.mainContext

        // Expense has carried a real updatedAt since V4 — the migration must NOT overwrite it.
        let lunch = try ctx.fetch(FetchDescriptor<Expense>()).first { $0.note == "Lunch" }
        #expect(lunch?.updatedAt == known,
                "Migration must preserve an Expense's existing updatedAt, not stamp it with Date()")

        // Note.updatedAt = modifiedAt
        let note = try ctx.fetch(FetchDescriptor<Note>()).first
        #expect(note?.updatedAt == note?.modifiedAt,
                "Migrated Note.updatedAt must be backfilled from modifiedAt")

        // NoteBlock.updatedAt = owning note's modifiedAt
        let block = try ctx.fetch(FetchDescriptor<NoteBlock>()).first
        #expect(block?.updatedAt == note?.modifiedAt,
                "Migrated NoteBlock.updatedAt must be backfilled from its owning note's modifiedAt")

        // Account.updatedAt = createdAt
        let account = try ctx.fetch(FetchDescriptor<Account>()).first
        #expect(account?.updatedAt == account?.createdAt,
                "Migrated Account.updatedAt must be backfilled from createdAt")
    }

    // MARK: - DeletionLog

    @Test("V9→V10: DeletionLog is queryable and round-trips after migration")
    func deletionLogQueryableAndRoundTrips() throws {
        let (container, _, cleanup) = try migratedV10Container(
            label: "deletionlog", knownExpenseUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        defer { cleanup() }
        let ctx = container.mainContext

        // New entity with no rows — the fetch must return empty, not crash.
        #expect(try ctx.fetch(FetchDescriptor<DeletionLog>()).isEmpty,
                "DeletionLog must return an empty array (not crash) after V9→V10 migration")

        let tombstoneID = UUID()
        ctx.insert(DeletionLog(entitySyncID: tombstoneID, entityKindRaw: "expense"))
        try ctx.save()

        let logs = try ctx.fetch(FetchDescriptor<DeletionLog>())
        #expect(logs.count == 1, "An inserted DeletionLog must round-trip through the V10 store")
        #expect(logs.first?.entitySyncID == tombstoneID,
                "DeletionLog.entitySyncID must round-trip unchanged")
        #expect(logs.first?.entityKindRaw == "expense",
                "DeletionLog.entityKindRaw must round-trip unchanged")
    }

    // MARK: - STAB-08 guard

    @Test("V9→V10: bare Expense typealias inserts and fetches under the production plan (STAB-08)")
    func bareTypealiasRoundTripsUnderProductionPlan() throws {
        let (container, _, cleanup) = try migratedV10Container(
            label: "stab08", knownExpenseUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        defer { cleanup() }
        let ctx = container.mainContext

        // A typealias still pointing at SchemaV9 would make this an entity absent from the V10
        // store schema — save()/fetch() would trap here.
        let fresh = Expense(amount: Decimal(1250), note: "Post-migration insert")
        ctx.insert(fresh)
        try ctx.save()

        let inserted = try ctx.fetch(FetchDescriptor<Expense>())
            .first { $0.note == "Post-migration insert" }
        #expect(inserted != nil, "A newly inserted Expense must be fetchable via the bare typealias")
        #expect(inserted?.amount == Decimal(1250),
                "Amount must round-trip — compare against Decimal(1250), never a bare literal")
    }
}

// ---------------------------------------------------------------------------
// MigrationTestsPlanV9 — trimmed migration plan stopping at SchemaV9.
//
// Mirrors MigrationTestsPlanV8 (SchemaV9MigrationTests.swift) exactly, extended by v8ToV9.
// Used to seed genuine V9 stores in tests without triggering the V10 migration.
// ---------------------------------------------------------------------------
enum MigrationTestsPlanV9: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self,
         SchemaV6.self, SchemaV7.self, SchemaV8.self, SchemaV9.self]
    }
    static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3, v3ToV4, v4ToV5, v5ToV6, v6ToV7, v7ToV8, v8ToV9]
    }
    static let v1ToV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self, toVersion: SchemaV2.self, willMigrate: nil, didMigrate: nil)
    static let v2ToV3 = MigrationStage.custom(
        fromVersion: SchemaV2.self, toVersion: SchemaV3.self, willMigrate: nil, didMigrate: nil)
    static let v3ToV4 = MigrationStage.custom(
        fromVersion: SchemaV3.self, toVersion: SchemaV4.self, willMigrate: nil, didMigrate: nil)
    static let v4ToV5 = MigrationStage.custom(
        fromVersion: SchemaV4.self, toVersion: SchemaV5.self, willMigrate: nil, didMigrate: nil)
    static let v5ToV6 = MigrationStage.custom(
        fromVersion: SchemaV5.self,
        toVersion: SchemaV6.self,
        willMigrate: nil,
        didMigrate: { context in
            // Minimal idempotent backfill — mirrors AppMigrationPlan.v5ToV6
            let expenses = try context.fetch(FetchDescriptor<SchemaV6.Expense>())
            let existingAccounts = try context.fetch(FetchDescriptor<SchemaV6.Account>())
            var accountByLabel: [String: SchemaV6.Account] = [:]
            for account in existingAccounts {
                if let label = account.sourceLabel { accountByLabel[label] = account }
            }
            let labels = Set(expenses.compactMap(\.sourceLabel))
            for label in labels {
                if accountByLabel[label] == nil {
                    let typeRaw = inferAccountType(from: label)
                    let account = SchemaV6.Account(name: label, typeRaw: typeRaw, sourceLabel: label)
                    context.insert(account)
                    accountByLabel[label] = account
                }
            }
            for expense in expenses {
                guard expense.accountID == nil, let label = expense.sourceLabel else { continue }
                expense.accountID = accountByLabel[label]?.id
            }
            try context.save()
        }
    )
    static let v6ToV7 = MigrationStage.custom(
        fromVersion: SchemaV6.self, toVersion: SchemaV7.self, willMigrate: nil, didMigrate: nil)
    static let v7ToV8 = MigrationStage.custom(
        fromVersion: SchemaV7.self, toVersion: SchemaV8.self, willMigrate: nil, didMigrate: nil)
    static let v8ToV9 = MigrationStage.custom(
        fromVersion: SchemaV8.self, toVersion: SchemaV9.self, willMigrate: nil, didMigrate: nil)
}
