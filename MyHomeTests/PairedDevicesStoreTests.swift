import Foundation
import Testing
@testable import MyHome

/// SYNC-06 — unit tests for the local-only paired-devices allowlist. Each test injects a
/// fresh `UserDefaults(suiteName:)` and clears its domain, so state never leaks between
/// tests or into `.standard`. `@MainActor` because `PairedDevicesStore` is main-actor-bound.
@MainActor
@Suite struct PairedDevicesStoreTests {

    /// A clean, isolated UserDefaults for one test.
    private func freshDefaults(_ suite: String) -> UserDefaults {
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func device(_ id: String, name: String = "Phone") -> PairedDevice {
        PairedDevice(installID: id, friendlyName: name, pairedAt: Date(timeIntervalSince1970: 1_000))
    }

    // MARK: - Codable round-trip

    @Test func pairedDeviceRoundTripsAllFields() throws {
        let original = PairedDevice(installID: "iid-1", friendlyName: "Reo's iPhone",
                                    pairedAt: Date(timeIntervalSince1970: 42))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PairedDevice.self, from: data)
        #expect(decoded == original)
        #expect(decoded.installID == "iid-1")
        #expect(decoded.friendlyName == "Reo's iPhone")
        #expect(decoded.pairedAt == Date(timeIntervalSince1970: 42))
    }

    // MARK: - Fresh store

    @Test func freshStoreIsEmpty() {
        let store = PairedDevicesStore(defaults: freshDefaults("PDS.fresh"))
        #expect(store.devices.isEmpty)
        #expect(store.allowlist.isEmpty)
    }

    // MARK: - add / upsert

    @Test func addInsertsAndAppearsInAllowlist() {
        let store = PairedDevicesStore(defaults: freshDefaults("PDS.add"))
        store.add(device("iid-1"))
        #expect(store.isPaired("iid-1"))
        #expect(store.allowlist == ["iid-1"])
    }

    @Test func addUpsertsByInstallIDNotDuplicate() {
        let store = PairedDevicesStore(defaults: freshDefaults("PDS.upsert"))
        store.add(device("iid-1", name: "Old Name"))
        store.add(device("iid-1", name: "New Name"))
        // One row, not two — upsert by installID.
        #expect(store.devices.count == 1)
        #expect(store.devices.first?.friendlyName == "New Name")
        #expect(store.allowlist == ["iid-1"])
    }

    @Test func addDistinctIDsAccumulate() {
        let store = PairedDevicesStore(defaults: freshDefaults("PDS.two"))
        store.add(device("iid-1"))
        store.add(device("iid-2"))
        #expect(store.devices.count == 2)
        #expect(store.allowlist == ["iid-1", "iid-2"])
    }

    // MARK: - remove

    @Test func removeDropsRowAndIsPairedBecomesFalse() {
        let store = PairedDevicesStore(defaults: freshDefaults("PDS.remove"))
        store.add(device("iid-1"))
        store.add(device("iid-2"))
        store.remove(installID: "iid-1")
        #expect(store.isPaired("iid-1") == false)
        #expect(store.isPaired("iid-2") == true)
        #expect(store.allowlist == ["iid-2"])
    }

    @Test func removedDeviceLeavesAllowlist() {
        let store = PairedDevicesStore(defaults: freshDefaults("PDS.removeAll"))
        store.add(device("iid-1"))
        store.remove(installID: "iid-1")
        #expect(store.allowlist.isEmpty)
    }

    // MARK: - Persistence across re-instantiation

    @Test func persistenceSurvivesReinstantiation() {
        let defaults = freshDefaults("PDS.persist")
        let first = PairedDevicesStore(defaults: defaults)
        first.add(device("iid-1", name: "Persisted"))
        // A brand-new instance reading the SAME defaults sees the row.
        let second = PairedDevicesStore(defaults: defaults)
        #expect(second.isPaired("iid-1"))
        #expect(second.devices.first?.friendlyName == "Persisted")
        #expect(second.allowlist == ["iid-1"])
    }

    @Test func removalPersistsAcrossReinstantiation() {
        let defaults = freshDefaults("PDS.persistRemove")
        let first = PairedDevicesStore(defaults: defaults)
        first.add(device("iid-1"))
        first.remove(installID: "iid-1")
        let second = PairedDevicesStore(defaults: defaults)
        #expect(second.isPaired("iid-1") == false)
        #expect(second.allowlist.isEmpty)
    }
}
