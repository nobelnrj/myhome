import Testing
@testable import MyHome

// ---------------------------------------------------------------------------
// SpyKeychainStore — in-memory KeychainPort test double.
//
// KeychainPort is defined in MyHomeApp/Gmail/KeychainPort.swift
// (production file, plan 06-01). This file provides the test double only.
//
// Mirrors SpyCenter.swift exactly in structure and naming conventions.
// ---------------------------------------------------------------------------

/// In-memory spy that operates on a dictionary so unit tests can exercise
/// every Keychain path without touching the OS Security framework.
public final class SpyKeychainStore: KeychainPort, @unchecked Sendable {

    // MARK: - In-memory store

    private var store: [String: String] = [:]

    // MARK: - Settable stubs

    /// When non-nil, save() throws this error instead of writing to the store.
    public var shouldThrowOnSave: Error? = nil

    /// When non-nil, load() throws this error instead of reading from the store.
    public var shouldThrowOnLoad: Error? = nil

    /// When non-nil, delete() throws this error instead of removing from the store.
    public var shouldThrowOnDelete: Error? = nil

    public init() {}

    // MARK: - KeychainPort

    public func save(_ value: String, forKey key: String) throws {
        if let error = shouldThrowOnSave { throw error }
        store[key] = value
    }

    public func load(forKey key: String) throws -> String? {
        if let error = shouldThrowOnLoad { throw error }
        return store[key]
    }

    public func delete(forKey key: String) throws {
        if let error = shouldThrowOnDelete { throw error }
        store.removeValue(forKey: key)
    }

    // MARK: - Reset

    /// Clears the in-memory store and resets all error stubs to nil.
    /// Useful between tests if the same SpyKeychainStore is reused.
    public func reset() {
        store = [:]
        shouldThrowOnSave = nil
        shouldThrowOnLoad = nil
        shouldThrowOnDelete = nil
    }

    // MARK: - Test helpers

    /// Returns the raw store dictionary — useful for asserting keychain contents in tests.
    public var allKeys: Set<String> { Set(store.keys) }
}
