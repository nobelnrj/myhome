import SwiftData
import Foundation

/// SchemaMigrationPlan for MyHome.
///
/// v1 is the initial schema. v2 adds the Category model and the Expense ↔ Category
/// relationship. v3 adds Note + NoteBlock (additive superset; never remove or reorder
/// existing schema versions from this list).
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self, SchemaV7.self, SchemaV8.self, SchemaV9.self, SchemaV10.self, SchemaV11.self]   // append V11 — never remove V1–V10
    }

    static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3, v3ToV4, v4ToV5, v5ToV6, v6ToV7, v7ToV8, v8ToV9, v9ToV10, v10ToV11]   // append v10ToV11
    }

    // Use .custom(willMigrate: nil, didMigrate: nil) rather than .lightweight
    // to sidestep the iOS 17.0–17.3 SchemaMigrationPlan interaction bug (FB13812722).
    // Semantically identical for additive-only changes (new entity + new optional relationship).
    static let v1ToV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: nil,
        didMigrate: nil
    )

    // V3 adds only new models (Note + NoteBlock); willMigrate/didMigrate are nil — additive-only.
    // .custom over .lightweight deliberately sidesteps FB13812722 (same rationale as v1ToV2).
    static let v2ToV3 = MigrationStage.custom(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self,
        willMigrate: nil,
        didMigrate: nil
    )

    // V4 adds only new optional/defaulted fields to Expense — purely additive.
    // willMigrate/didMigrate are nil. .custom over .lightweight sidesteps FB13812722.
    static let v3ToV4 = MigrationStage.custom(
        fromVersion: SchemaV3.self,
        toVersion: SchemaV4.self,
        willMigrate: nil,
        didMigrate: nil
    )

    // V5 adds only one new optional/defaulted field to Expense (sourceAccount — D-MA-03).
    // Purely additive; willMigrate/didMigrate are nil. .custom over .lightweight sidesteps FB13812722.
    static let v4ToV5 = MigrationStage.custom(
        fromVersion: SchemaV4.self,
        toVersion: SchemaV5.self,
        willMigrate: nil,
        didMigrate: nil
    )

    // V6 adds Account + Asset models and backfills accountID on existing expenses (ACCT-08).
    //
    // FIRST non-nil didMigrate in this codebase. .custom over .lightweight: FB13812722 workaround preserved.
    // didMigrate is SYNCHRONOUS (throws, NOT async throws). Never attempt await inside it.
    //
    // Idempotency design (RESEARCH Pitfall 2 + T-09-01):
    //   - Step 2: fetch existing Account rows before inserting — prevents duplicates on retry.
    //   - Step 4: guard expense.accountID == nil — skips already-attributed expenses on retry.
    //   - Step 5: explicit try context.save() — REQUIRED; migration context does NOT auto-commit (Pitfall 3).
    //   - If this closure throws, SwiftData re-runs the stage on next launch (no documented rollback).
    //     The idempotency guards above make it safe to re-run.
    static let v5ToV6 = MigrationStage.custom(
        fromVersion: SchemaV5.self,
        toVersion: SchemaV6.self,
        willMigrate: nil,
        didMigrate: { context in
            // 1. Fetch all V6 expenses (sourceLabel field is retained verbatim from V5; ACCT-08)
            let expenses = try context.fetch(FetchDescriptor<SchemaV6.Expense>())

            // 2. Build idempotency map: existing accounts keyed by sourceLabel
            //    MUST fetch before inserting — prevents duplicate rows on retry (Pitfall 2, T-09-01)
            let existingAccounts = try context.fetch(FetchDescriptor<SchemaV6.Account>())
            var accountByLabel: [String: SchemaV6.Account] = [:]
            for account in existingAccounts {
                if let label = account.sourceLabel { accountByLabel[label] = account }
            }

            // 3. Create missing Account rows for each distinct non-nil sourceLabel (D-01, D-03)
            var didCreateAny = false
            let labels = Set(expenses.compactMap(\.sourceLabel))
            for label in labels {
                if accountByLabel[label] == nil {
                    let typeRaw = inferAccountType(from: label)   // "credit_card" or "savings" (D-03)
                    let account = SchemaV6.Account(name: label, typeRaw: typeRaw, sourceLabel: label)
                    context.insert(account)
                    accountByLabel[label] = account
                    didCreateAny = true
                }
            }

            // 4. Backfill Expense.accountID (idempotent: skip expenses already attributed — Pitfall 2)
            //    sourceAccount is NEVER touched here — it is the Gmail dedup key (ACCT-08 / T-09-02)
            for expense in expenses {
                guard expense.accountID == nil, let label = expense.sourceLabel else { continue }
                expense.accountID = accountByLabel[label]?.id
            }

            // 5. Explicit save — REQUIRED; migration context does NOT auto-commit (Pitfall 3, T-09-01)
            try context.save()

            // 6. Flag first-launch review if accounts were auto-created (D-02)
            if didCreateAny {
                UserDefaults.standard.set(true, forKey: "accountReviewPending")
            }
        }
    )

    // V7 adds amfiSchemeCode to Asset and introduces NetWorthSnapshot @Model (D-03, Phase 11).
    // Purely additive: amfiSchemeCode defaults nil; NetWorthSnapshot is a new entity.
    // willMigrate/didMigrate are nil — no backfill needed.
    // .custom over .lightweight: FB13812722 workaround preserved for all stages.
    static let v6ToV7 = MigrationStage.custom(
        fromVersion: SchemaV6.self,
        toVersion: SchemaV7.self,
        willMigrate: nil,
        didMigrate: nil   // amfiSchemeCode defaults nil; NetWorthSnapshot is new — no backfill
    )

    // V8 adds npsSchemeCode to Asset and introduces SIP/SIPAmountChange/Contribution @Models (D-08, Phase 11.1).
    // Purely additive: npsSchemeCode defaults nil; SIP/SIPAmountChange/Contribution are new empty tables.
    // willMigrate/didMigrate are nil — no backfill needed.
    // .custom over .lightweight: FB13812722 workaround preserved for all stages.
    static let v7ToV8 = MigrationStage.custom(
        fromVersion: SchemaV7.self,
        toVersion: SchemaV8.self,
        willMigrate: nil,
        didMigrate: nil   // npsSchemeCode defaults nil; SIP/Contribution are new — no backfill
    )

    // V9 adds routineDailyReminderTime to Note and introduces RoutineCompletion @Model (D-04, D-06, Phase 12).
    // Purely additive: routineDailyReminderTime defaults nil; RoutineCompletion is a new empty table.
    // willMigrate/didMigrate are nil — no backfill needed.
    // .custom over .lightweight: FB13812722 workaround preserved for all stages.
    static let v8ToV9 = MigrationStage.custom(
        fromVersion: SchemaV8.self,
        toVersion: SchemaV9.self,
        willMigrate: nil,
        didMigrate: nil   // routineDailyReminderTime defaults nil; RoutineCompletion is new — no backfill
    )

    // V10 makes every record syncable (SYNC-01, Phase 18): appends syncID + updatedAt to all 11
    // models and introduces the DeletionLog tombstone @Model. The fields are additive/defaulted,
    // BUT the didMigrate closure is REQUIRED (not nil) because of the SwiftData constant-default
    // footgun: a `UUID()`/`Date()` default expression added via additive migration is evaluated
    // ONCE, so every migrated row would otherwise share the SAME syncID/updatedAt — which breaks
    // the entire cross-device identity model that the merge engine (Plan 03) is keyed on.
    //
    // didMigrate is SYNCHRONOUS (throws, NOT async throws). Never attempt await inside it.
    // .custom over .lightweight: FB13812722 workaround preserved for all stages.
    //
    // Idempotency design (mirrors v5ToV6 discipline — Pitfall 2 + Pitfall 3):
    //   - syncID: per-table Set<UUID> dedup. First occurrence keeps its value; any row whose
    //     syncID is already seen gets a fresh UUID(). First run (all share the constant default)
    //     → all but one reassigned. Re-run after a mid-stage throw (all distinct) → no-op.
    //   - updatedAt: backfilled idempotently from an immutable source field (createdAt /
    //     modifiedAt), so re-running yields the same value. Expense is NEVER touched — it has
    //     carried a real updatedAt since V4.
    //   - Explicit try context.save() at the end — REQUIRED; migration context does NOT
    //     auto-commit (Pitfall 3).
    static let v9ToV10 = MigrationStage.custom(
        fromVersion: SchemaV9.self,
        toVersion: SchemaV10.self,
        willMigrate: nil,
        didMigrate: { context in
            // 1. syncID backfill — defeat the constant-default footgun for all 11 syncable models.
            //    Idempotent per-row dedup (see backfillDistinctSyncIDs). DeletionLog is a new,
            //    empty table and is not SyncStamped — nothing to backfill there.
            try backfillDistinctSyncIDs(SchemaV10.Expense.self, syncID: \SchemaV10.Expense.syncID, in: context)
            try backfillDistinctSyncIDs(SchemaV10.Category.self, syncID: \SchemaV10.Category.syncID, in: context)
            try backfillDistinctSyncIDs(SchemaV10.Note.self, syncID: \SchemaV10.Note.syncID, in: context)
            try backfillDistinctSyncIDs(SchemaV10.NoteBlock.self, syncID: \SchemaV10.NoteBlock.syncID, in: context)
            try backfillDistinctSyncIDs(SchemaV10.Account.self, syncID: \SchemaV10.Account.syncID, in: context)
            try backfillDistinctSyncIDs(SchemaV10.Asset.self, syncID: \SchemaV10.Asset.syncID, in: context)
            try backfillDistinctSyncIDs(SchemaV10.NetWorthSnapshot.self, syncID: \SchemaV10.NetWorthSnapshot.syncID, in: context)
            try backfillDistinctSyncIDs(SchemaV10.SIP.self, syncID: \SchemaV10.SIP.syncID, in: context)
            try backfillDistinctSyncIDs(SchemaV10.SIPAmountChange.self, syncID: \SchemaV10.SIPAmountChange.syncID, in: context)
            try backfillDistinctSyncIDs(SchemaV10.Contribution.self, syncID: \SchemaV10.Contribution.syncID, in: context)
            try backfillDistinctSyncIDs(SchemaV10.RoutineCompletion.self, syncID: \SchemaV10.RoutineCompletion.syncID, in: context)

            // 2. updatedAt backfill — idempotent by construction (source fields never change).
            //    Expense: DO NOT touch — it has a real updatedAt since V4 (the constant default on
            //    the new-field expression does NOT overwrite the existing column value on migrate).
            //    Note: updatedAt = modifiedAt. NoteBlock: updatedAt = owning note's modifiedAt
            //    (Date() fallback only for orphan blocks). All others: updatedAt = createdAt.
            for note in try context.fetch(FetchDescriptor<SchemaV10.Note>()) {
                note.updatedAt = note.modifiedAt
            }
            for block in try context.fetch(FetchDescriptor<SchemaV10.NoteBlock>()) {
                block.updatedAt = block.note?.modifiedAt ?? Date()
            }
            for category in try context.fetch(FetchDescriptor<SchemaV10.Category>()) {
                category.updatedAt = category.createdAt
            }
            for account in try context.fetch(FetchDescriptor<SchemaV10.Account>()) {
                account.updatedAt = account.createdAt
            }
            for asset in try context.fetch(FetchDescriptor<SchemaV10.Asset>()) {
                asset.updatedAt = asset.createdAt
            }
            for snapshot in try context.fetch(FetchDescriptor<SchemaV10.NetWorthSnapshot>()) {
                snapshot.updatedAt = snapshot.createdAt
            }
            for sip in try context.fetch(FetchDescriptor<SchemaV10.SIP>()) {
                sip.updatedAt = sip.createdAt
            }
            for change in try context.fetch(FetchDescriptor<SchemaV10.SIPAmountChange>()) {
                change.updatedAt = change.createdAt
            }
            for contribution in try context.fetch(FetchDescriptor<SchemaV10.Contribution>()) {
                contribution.updatedAt = contribution.createdAt
            }
            for completion in try context.fetch(FetchDescriptor<SchemaV10.RoutineCompletion>()) {
                completion.updatedAt = completion.createdAt
            }

            // 3. Explicit save — REQUIRED; migration context does NOT auto-commit (Pitfall 3).
            try context.save()
        }
    )

    // V11 adds the two kitchen @Models (PantryItem, ShoppingListItem — KTCH-01/KTCH-03,
    // Phase 20) and changes NOTHING about the 12 classes copied forward from V10: not one
    // field, default, or @Relationship. Purely additive.
    // .custom over .lightweight: FB13812722 workaround preserved for all stages.
    //
    // didMigrate is nil BY DESIGN — and this is the interesting part, because v9ToV10 needed a
    // non-nil one. That backfill existed to defeat the SwiftData constant-default footgun: a
    // `UUID()`/`Date()` default expression added to an EXISTING model via additive migration is
    // evaluated once, so every already-persisted row would share one syncID. V11 adds no fields
    // to any existing model — its only additions are two brand-new tables with zero existing
    // rows — so there is literally nothing to backfill. Every kitchen row's syncID/updatedAt is
    // assigned at `init` time on a live device (KTCH-04: syncable from birth).
    static let v10ToV11 = MigrationStage.custom(
        fromVersion: SchemaV10.self,
        toVersion: SchemaV11.self,
        willMigrate: nil,
        didMigrate: nil   // PantryItem/ShoppingListItem are new EMPTY tables — nothing to backfill
    )

    // Note: inferAccountType(from:) is now the module-level free function in
    // MyHomeApp/Support/AccountBalance.swift — reused here by reference (D-03).
}

/// Reassigns a distinct `syncID` to every row of `type` whose syncID collides with an
/// earlier row's — insurance against the SwiftData constant-default footgun, where an
/// additively-added `UUID()` default is evaluated once and shared across all migrated rows,
/// which would make the merge engine treat unrelated records as one identity (SYNC-01).
///
/// The footgun does NOT reproduce on Xcode 26.5 / iOS 26 (verified in Phase 18 by disabling this
/// backfill: SchemaV10MigrationTests.distinctSyncIDsAcrossAllRows still passed, so SwiftData
/// assigned per-row UUIDs). This is kept as a guard for OS versions and device migration paths
/// we cannot exercise in tests; on a passing path it is a no-op beyond one fetch per table,
/// once. Note that the tests therefore do NOT fail if this is removed.
///
/// Idempotent: a table whose syncIDs are already all-distinct is left untouched, so a re-run
/// after a mid-stage throw is a no-op.
///
/// Takes the syncID key path rather than constraining to `SyncStamped` (Phase 20, 20-01):
/// `SyncStamped` conformance always points at the CURRENT schema version (SchemaV11 today), but
/// this helper operates on the frozen SchemaV10 types inside the v9ToV10 stage. Binding it to the
/// protocol would re-break this stage on every future schema bump; the key path is version-agnostic.
private func backfillDistinctSyncIDs<T: PersistentModel>(
    _ type: T.Type,
    syncID syncIDPath: ReferenceWritableKeyPath<T, UUID>,
    in context: ModelContext
) throws {
    let rows = try context.fetch(FetchDescriptor<T>())
    var seen = Set<UUID>()
    for row in rows {
        if seen.contains(row[keyPath: syncIDPath]) {
            row[keyPath: syncIDPath] = UUID()   // duplicate (constant default) → fresh distinct identity
        }
        seen.insert(row[keyPath: syncIDPath])
    }
}
