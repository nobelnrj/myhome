import Foundation

// MARK: - UnparsedMessageStore

/// Persistent retry queue for bank emails that matched a bank sender (`canHandle` == true)
/// but no parser template (`parse` == nil) during a sync (07-08).
///
/// Previously such mails were dropped silently: by the time a parser gained the missing
/// template, the incremental sync window (`newer_than:<days-since-last-sync>d`) had moved
/// past them and they were unrecoverable. Queued IDs are retried on every sync until they
/// parse, are dismissed, or are evicted by the per-account cap.
///
/// **Storage:** injected UserDefaults (App Group in production, isolated suites in tests) —
/// one `[account email: [message ID]]` dictionary. Insertion order is preserved so the cap
/// evicts the oldest entries first. Mirrors `DismissedMessageStore`'s "IDs are opaque,
/// non-security state" rationale (T-07-05).
public struct UnparsedMessageStore {

    /// UserDefaults key for the account → queued-message-IDs dictionary.
    private static let storageKey = "gmail_unparsed_message_ids_v1"

    /// Upper bound per account; oldest IDs are evicted first. Generous relative to real
    /// alert volume while bounding UserDefaults growth if a bank changes every template at once.
    static let maxPerAccount = 300

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Queued message IDs for an account, oldest first.
    public func ids(for account: String) -> [String] {
        queues()[normalise(account)] ?? []
    }

    /// Appends `messageID` to the account's queue. Idempotent — an already-queued ID is
    /// left in place. Evicts the oldest entries beyond `maxPerAccount`.
    public func record(_ messageID: String, account: String) {
        var all = queues()
        let key = normalise(account)
        var queue = all[key] ?? []
        guard !queue.contains(messageID) else { return }
        queue.append(messageID)
        if queue.count > Self.maxPerAccount {
            queue.removeFirst(queue.count - Self.maxPerAccount)
        }
        all[key] = queue
        save(all)
    }

    /// Removes `messageID` from the account's queue (no-op when absent).
    public func remove(_ messageID: String, account: String) {
        var all = queues()
        let key = normalise(account)
        guard var queue = all[key], let idx = queue.firstIndex(of: messageID) else { return }
        queue.remove(at: idx)
        all[key] = queue.isEmpty ? nil : queue
        save(all)
    }

    /// Drops the whole queue for an account (sign-out).
    public func removeAll(for account: String) {
        var all = queues()
        guard all.removeValue(forKey: normalise(account)) != nil else { return }
        save(all)
    }

    // MARK: - Internal

    /// Account keys are lowercased emails, matching GmailAccountStore's identity rule (D-MA-01).
    private func normalise(_ account: String) -> String { account.lowercased() }

    private func queues() -> [String: [String]] {
        defaults.dictionary(forKey: Self.storageKey) as? [String: [String]] ?? [:]
    }

    private func save(_ queues: [String: [String]]) {
        if queues.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else {
            defaults.set(queues, forKey: Self.storageKey)
        }
    }
}
