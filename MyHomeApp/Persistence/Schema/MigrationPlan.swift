import SwiftData
import Foundation

/// SchemaMigrationPlan for MyHome.
///
/// v1 is the initial schema. v2 adds the Category model and the Expense ↔ Category
/// relationship. v3 adds Note + NoteBlock (additive superset; never remove or reorder
/// existing schema versions from this list).
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self, SchemaV7.self, SchemaV8.self, SchemaV9.self]   // append V9 — never remove V1–V8
    }

    static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3, v3ToV4, v4ToV5, v5ToV6, v6ToV7, v7ToV8, v8ToV9]   // append v8ToV9
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

    // Note: inferAccountType(from:) is now the module-level free function in
    // MyHomeApp/Support/AccountBalance.swift — reused here by reference (D-03).
}
