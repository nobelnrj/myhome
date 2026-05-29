import SwiftData
import Foundation

extension ModelContainer {
    /// Creates the app's production ModelContainer, wired to the App Group store URL.
    ///
    /// Store path: group.com.reojacob.myhome / MyHome.store
    /// CloudKit: .none for v1 (local-only); flip to
    ///   .private("iCloud.com.reojacob.myhome") post-paid-developer-upgrade.
    ///
    /// App Group fallback (RESEARCH Open Question 1, Pitfall 5):
    /// On a free Apple Developer account the App Group entitlement may not provision
    /// reliably. If containerURL returns nil, we fall back to .applicationSupportDirectory.
    /// The store file is at the same relative path in both cases so migration is a file copy.
    /// TODO: migrate to App Group URL when paid account active (group.com.reojacob.myhome).
    static func appContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)

        // Resolve the App Group container URL; fall back to Application Support if unavailable.
        let storeURL: URL
        if let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.reojacob.myhome") {
            storeURL = groupURL.appendingPathComponent("MyHome.store")
        } else {
            // TODO: migrate to App Group URL when paid account active
            let supportURL = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
            storeURL = supportURL.appendingPathComponent("MyHome.store")
        }

        let config = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none  // flip to .private("iCloud.com.reojacob.myhome") post-upgrade
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
    }
}
