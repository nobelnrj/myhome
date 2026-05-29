import SwiftData

/// SchemaMigrationPlan for MyHome.
///
/// v1 is the initial schema. v2 adds the Category model and the Expense ↔ Category
/// relationship. Never remove or reorder existing schema versions from this list.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]          // append SchemaV2 — never remove SchemaV1
    }

    static var stages: [MigrationStage] {
        [v1ToV2]
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
}
