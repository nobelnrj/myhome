import SwiftData

/// SchemaMigrationPlan with a single version and no migration stages.
///
/// v1 is the first and only schema version. When Phase 2 adds Category,
/// append SchemaV2.self to `schemas` and a MigrationStage to `stages`.
/// Never remove or reorder existing schema versions from this list.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    /// No stages — v1 is the initial version (D-08: forward-compat from day one).
    /// Phase 2 will add: .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self) { ... }
    static var stages: [MigrationStage] { [] }
}
