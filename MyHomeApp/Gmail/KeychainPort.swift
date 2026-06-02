import Foundation

// MARK: - KeychainPort

/// Protocol seam that abstracts Keychain operations required by GmailSyncController.
/// Injecting this protocol lets unit tests run without touching the OS Keychain
/// (SpyKeychainStore in MyHomeTests).
///
/// NOTE: This protocol is defined here for the production conformer.
/// The test double (SpyKeychainStore) in MyHomeTests/Support/SpyKeychainStore.swift also conforms.
/// SpyKeychainStore.swift declares `@testable import MyHome` — the protocol must be public.
///
/// SEC-03: Gmail OAuth refresh token stored in Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly.
/// D6-23: Wrap Security.framework behind a port/protocol (mirrors NotificationCenterPort).
public protocol KeychainPort: Sendable {
    /// Saves a string value to the Keychain for the given key.
    /// Overwrites any existing value for the same key.
    /// - Parameters:
    ///   - value: The string to store
    ///   - key: The Keychain item identifier
    /// - Throws: `KeychainError` if the save fails
    func save(_ value: String, forKey key: String) throws

    /// Loads a string value from the Keychain for the given key.
    /// - Parameter key: The Keychain item identifier
    /// - Returns: The stored string, or `nil` if no item exists for this key
    /// - Throws: `KeychainError` if the load fails for reasons other than item-not-found
    func load(forKey key: String) throws -> String?

    /// Deletes the Keychain item for the given key.
    /// No-ops if the key does not exist.
    /// - Parameter key: The Keychain item identifier
    /// - Throws: `KeychainError` if the delete fails
    func delete(forKey key: String) throws
}

// MARK: - KeychainError

/// Errors surfaced by Keychain operations.
///
/// D6-20: Keychain error → "Couldn't save your Gmail credentials. Please try again."
public enum KeychainError: Error, Sendable {
    /// No item was found for the requested key.
    case itemNotFound
    /// An item already exists for this key (should not occur; save() overwrites via delete+add).
    case duplicateItem
    /// The data stored could not be decoded as a UTF-8 string.
    case unexpectedData
    /// An unexpected OSStatus code was returned by the Security framework.
    case unexpectedStatus(OSStatus)
}
