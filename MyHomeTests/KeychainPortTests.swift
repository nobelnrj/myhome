import Testing
import Foundation
@testable import MyHome

// Requirements: SEC-03 (refresh token Keychain round-trip via spy)
// Threat ref: T-6-TOKEN (token persistence integrity)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/KeychainPortTests
// Plan 06-01 — GREEN from Task 1: SpyKeychainStore is already wired; these pass after spies exist.
// Note: These tests verify the SPY interface (save/load/delete round-trip).
// The real SystemKeychainStore implementation (plan 04) is separately tested via device UAT-6-07.

/// KeychainPortTests — round-trip unit tests for SpyKeychainStore.
///
/// SEC-03: Refresh token stored in Keychain (via spy in unit tests; real Keychain on device).
/// These tests verify protocol conformance and in-memory behavior of the test double.
struct KeychainPortTests {

    // MARK: - SEC-03: Save → load round-trip

    @Test("saveThenLoadReturnsValue: SpyKeychainStore save then load returns the stored value — SEC-03")
    func saveThenLoadReturnsValue() throws {
        let spy = SpyKeychainStore()
        try spy.save("my-refresh-token", forKey: "refresh_token")
        let loaded = try spy.load(forKey: "refresh_token")
        #expect(loaded == "my-refresh-token", "load() after save() must return the stored value — SEC-03")
    }

    // MARK: - SEC-03: Delete → load returns nil

    @Test("deleteThenLoadReturnsNil: SpyKeychainStore delete then load returns nil — SEC-03")
    func deleteThenLoadReturnsNil() throws {
        let spy = SpyKeychainStore()
        try spy.save("my-refresh-token", forKey: "refresh_token")
        try spy.delete(forKey: "refresh_token")
        let loaded = try spy.load(forKey: "refresh_token")
        #expect(loaded == nil, "load() after delete() must return nil — SEC-03")
    }

    // MARK: - SEC-03: Overwrite (save twice) returns latest value

    @Test("overwriteReturnsLatestValue: SpyKeychainStore save twice overwrites and load returns latest — SEC-03")
    func overwriteReturnsLatestValue() throws {
        let spy = SpyKeychainStore()
        try spy.save("old-refresh-token", forKey: "refresh_token")
        try spy.save("new-refresh-token", forKey: "refresh_token")
        let loaded = try spy.load(forKey: "refresh_token")
        #expect(loaded == "new-refresh-token", "load() after two save() calls must return the latest value — SEC-03")
    }

    // MARK: - SEC-03: Load of unknown key returns nil

    @Test("loadUnknownKeyReturnsNil: SpyKeychainStore load of unknown key returns nil without error — SEC-03")
    func loadUnknownKeyReturnsNil() throws {
        let spy = SpyKeychainStore()
        let loaded = try spy.load(forKey: "nonexistent_key")
        #expect(loaded == nil, "load() for unknown key must return nil (not throw) — SEC-03")
    }

    // MARK: - SEC-03: Delete of unknown key does not throw

    @Test("deleteUnknownKeyDoesNotThrow: SpyKeychainStore delete of unknown key is a no-op — SEC-03")
    func deleteUnknownKeyDoesNotThrow() throws {
        let spy = SpyKeychainStore()
        // Should not throw
        try spy.delete(forKey: "nonexistent_key")
        // If we reach here, no throw occurred
        #expect(Bool(true), "delete() for unknown key must not throw — SEC-03")
    }
}
