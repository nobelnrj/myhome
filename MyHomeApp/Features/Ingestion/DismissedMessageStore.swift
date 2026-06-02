import Foundation

// MARK: - DismissedMessageStore

/// Lightweight persistence for Gmail message IDs that the user has swiped-to-discard (D7-07).
///
/// **Storage:** App Group UserDefaults — the same store as GmailSyncController's metadata.
/// A `Set<String>` of message IDs is persisted as `[String]` (UserDefaults round-trip).
/// No SwiftData model needed — dismissed IDs are opaque tokens with no relationship to
/// expenses and require no CloudKit sync or querying (RESEARCH §Dismissed Message-ID Tracking).
///
/// **Threat T-07-05:** Accepted — dismissed IDs are non-security state. Worst case is a
/// dismissed email re-surfacing in the Review Inbox; no data or security impact.
///
/// Mirrors the UserDefaults accessor pattern from `GmailSyncController.swift` (lines 43-62):
///   `UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard`
public struct DismissedMessageStore {

    /// UserDefaults key for the dismissed message-ID set.
    private static let key = "gmail_dismissed_message_ids"

    /// App Group UserDefaults — shared between app, extensions, and BGTask (D7-07).
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
    }

    // MARK: - Public API

    /// Returns true if the given Gmail message ID has been dismissed by the user.
    ///
    /// - Parameter messageID: The Gmail API message ID string.
    /// - Returns: `true` if the ID is in the dismissed set.
    public static func isDismissed(_ messageID: String) -> Bool {
        dismissed().contains(messageID)
    }

    /// Persists `messageID` as dismissed so it never re-surfaces on future syncs.
    ///
    /// Idempotent — calling `dismiss` on an already-dismissed ID is a no-op.
    ///
    /// - Parameter messageID: The Gmail API message ID to dismiss.
    public static func dismiss(_ messageID: String) {
        var set = dismissed()
        set.insert(messageID)
        defaults.set(Array(set), forKey: key)
    }

    // MARK: - Internal

    /// Reads the current dismissed set from UserDefaults.
    ///
    /// `internal` (not private) so unit tests can inspect the set directly.
    static func dismissed() -> Set<String> {
        let array = defaults.stringArray(forKey: key) ?? []
        return Set(array)
    }
}
