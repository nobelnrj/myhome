import Testing
import SwiftData
import Foundation
@testable import MyHome

/// V8→V9 migration fixture tests — proves additive migration does not corrupt data (D-06, D-04, Phase 12).
///
/// BLOCKING: All tests in this suite must pass before any Wave 2 plan (StreakCalculator,
/// RoutineNotificationService, CalendarView routine surfacing) is executed.
///
/// Migration is purely additive:
///   - routineDailyReminderTime: Date? = nil on Note (D-04); nil after migration for all existing rows.
///   - RoutineCompletion: new entity; no backfill; queryable immediately.
///   - No didMigrate closure — SchemaV9 stage uses .custom with nil closures (FB13812722).
///
/// STAB-08 guard: this suite round-trips Note inserts under SchemaV9 to verify
/// the atomic typealias flip (Task 1) is consistent. A partial flip would crash here.
@MainActor
struct SchemaV9MigrationTests {

    // MARK: - V8→V9 additive migration test (BLOCKING)

    @Test("V8→V9: existing Note rows survive migration with routineDailyReminderTime == nil")
    func v8StoreNoteSurvivesWithNilReminderTime() throws {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v8seed-\(UUID()).store")
        let migrateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v8tov9-\(UUID()).store")
        defer {
            try? FileManager.default.removeItem(at: seedURL)
            try? FileManager.default.removeItem(at: migrateURL)
        }

        // 1. Build a genuine V8 store with one Note row.
        //    Use MigrationTestsPlanV8 (trimmed plan stopping at V8) so SchemaV9 migration is NOT triggered here.
        try {
            let v8Schema = Schema(versionedSchema: SchemaV8.self)
            let config = ModelConfiguration(schema: v8Schema, url: seedURL)
            let container = try ModelContainer(
                for: v8Schema,
                migrationPlan: MigrationTestsPlanV8.self,
                configurations: [config]
            )
            let ctx = container.mainContext

            let note = SchemaV8.Note(title: "Morning Routine")
            note.isDailyRoutine = true
            ctx.insert(note)

            let block = SchemaV8.NoteBlock(kindRaw: "checkbox", text: "Brush teeth", order: 0)
            block.note = note
            ctx.insert(block)

            try ctx.save()
            try ctx.save()  // second save flushes WAL to main store file (mirrors SchemaV8MigrationTests pattern)
        }()

        // 2. Copy the seed store to a fresh URL before opening under V9.
        //    (avoids container lock contention — mirrors SchemaV8MigrationTests.swift pattern)
        try FileManager.default.copyItem(at: seedURL, to: migrateURL)

        // 3. Migrate to V9 using the production AppMigrationPlan (SchemaV8 → SchemaV9).
        let v9Schema = Schema(versionedSchema: SchemaV9.self)
        let migrateConfig = ModelConfiguration(schema: v9Schema, url: migrateURL)
        let container = try ModelContainer(
            for: v9Schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [migrateConfig]
        )
        let ctx = container.mainContext

        // 4. Assert the existing Note row survived with routineDailyReminderTime == nil (D-04).
        let notes = try ctx.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1, "Exactly 1 note row must survive V8→V9 migration")

        let migratedNote = notes.first
        #expect(migratedNote?.title == "Morning Routine",
                "Note title must be preserved byte-for-byte through migration")
        #expect(migratedNote?.isDailyRoutine == true,
                "isDailyRoutine must be preserved through migration")
        #expect(migratedNote?.routineDailyReminderTime == nil,
                "routineDailyReminderTime must be nil on existing V8 notes after V9 migration (additive, no backfill)")
    }

    // MARK: - RoutineCompletion queryable after migration (BLOCKING)

    @Test("V8→V9: RoutineCompletion entity queryable after migration")
    func routineCompletionQueryableAfterMigration() throws {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v8seed-rc-\(UUID()).store")
        let migrateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v8tov9-rc-\(UUID()).store")
        defer {
            try? FileManager.default.removeItem(at: seedURL)
            try? FileManager.default.removeItem(at: migrateURL)
        }

        // 1. Build a V8 store (no RoutineCompletion entity at V8).
        try {
            let v8Schema = Schema(versionedSchema: SchemaV8.self)
            let config = ModelConfiguration(schema: v8Schema, url: seedURL)
            let container = try ModelContainer(
                for: v8Schema,
                migrationPlan: MigrationTestsPlanV8.self,
                configurations: [config]
            )
            let ctx = container.mainContext
            let note = SchemaV8.Note(title: "Daily Checklist")
            note.isDailyRoutine = true
            ctx.insert(note)
            try ctx.save()
            try ctx.save()  // flush WAL
        }()

        try FileManager.default.copyItem(at: seedURL, to: migrateURL)

        // 2. Migrate to V9 and verify RoutineCompletion entity is accessible.
        let v9Schema = Schema(versionedSchema: SchemaV9.self)
        let config = ModelConfiguration(schema: v9Schema, url: migrateURL)
        let container = try ModelContainer(
            for: v9Schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        let ctx = container.mainContext

        // FetchDescriptor MUST NOT crash — must return empty array (new entity, no rows).
        let completions = try ctx.fetch(FetchDescriptor<RoutineCompletion>())
        #expect(completions.isEmpty, "RoutineCompletion must return empty array (not crash) after V8→V9 migration")
    }
}

// ---------------------------------------------------------------------------
// MigrationTestsPlanV8 — trimmed migration plan stopping at SchemaV8.
//
// Mirrors MigrationTestsPlanV7 (SchemaV8MigrationTests.swift) exactly.
// Used to seed genuine V8 stores in tests without triggering the V9 migration.
// ---------------------------------------------------------------------------
enum MigrationTestsPlanV8: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self, SchemaV7.self, SchemaV8.self]
    }
    static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3, v3ToV4, v4ToV5, v5ToV6, v6ToV7, v7ToV8]
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
}
