import Foundation
import Security

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

// MARK: - SystemKeychainStore

/// Production conformer that wraps Security.framework Keychain APIs.
///
/// This is the only type in the Gmail subsystem that touches the OS Keychain.
/// All unit tests inject SpyKeychainStore instead.
///
/// SEC-03 / D6-05: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly — prevents
/// backup/restore exfiltration (T-06-04-KEYCHAIN); ThisDeviceOnly also prevents
/// the item appearing on another device via iCloud Keychain.
///
/// Save uses add-then-update (upsert): try SecItemAdd first; on errSecDuplicateItem
/// update via SecItemUpdate WITHOUT kSecReturnData in the update query (Security
/// framework anti-pattern: including kSecReturnData in an update query causes
/// errSecParam on some OS versions).
public struct SystemKeychainStore: KeychainPort, @unchecked Sendable {

    private let service: String

    public init(service: String = "com.reojacob.myhome.gmail") {
        self.service = service
    }

    public func save(_ value: String, forKey key: String) throws {
        let data = Data(value.utf8)
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // Item exists — update value only; do NOT include kSecReturnData in update query
            let searchQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key,
            ]
            let attributes: [CFString: Any] = [kSecValueData: data]
            let updateStatus = SecItemUpdate(searchQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if addStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    public func load(forKey key: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return value
    }

    public func delete(forKey key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        // Tolerant of item-not-found (idempotent delete)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
