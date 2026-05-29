import Testing
@testable import MyHome

/// Wave 0 stub — intentionally failing (red).
/// The seed store (MyHomeV1Seed.store) is created in plan 04 after the v1 schema ships.
@MainActor
struct MigrationTests {

    @Test("v1 store loads successfully under AppMigrationPlan")
    func v1StoreMigratesCleanly() throws {
        // Seed store not yet created — this plan only ships in plan 04.
        // Issue.record marks the test as a known issue (red) rather than a failure.
        Issue.record("seed store not yet created — plan 04")
    }
}
