import Foundation
import UserNotifications
import SwiftData
import SwiftUI

// MARK: - Notification Category + Action IDs

/// UNNotificationCategory identifier for note/block reminders.
let kReminderCategoryID = "com.myhome.reminder"

// kReconcileCategoryID is declared in SIPAccrualService.swift (= "com.myhome.sip.reconcile").
// It is used here for category registration and deep-link routing (D-06).

/// Complete action: checks the target checklist row and cancels future alerts.
let kCompleteActionID   = "com.myhome.reminder.complete"

/// Snooze action: reschedules the notification ~1 hour from now.
let kSnoozeActionID     = "com.myhome.reminder.snooze"

// MARK: - Notification identifier parsing

/// Parses a notification identifier into its component parts.
///
/// Identifier scheme (from NotificationScheduler):
///   "<uuid>-main"           — main fire
///   "<uuid>-lead-<index>"   — lead-time alert
///   "<uuid>-weekday-<N>"    — weekly-weekday fire
///
/// This helper extracts the UUID prefix so the delegate can look up the owning model.
///
/// WR-07: Prefer reading the UUID from userInfo (noteID/blockID) which is already stamped;
/// use identifier parsing only as fallback.
func reminderIDFromUserInfo(_ userInfo: [AnyHashable: Any]) -> UUID? {
    // Prefer blockID if present (block-level reminder), else noteID (note-level)
    if let blockIDString = userInfo["blockID"] as? String,
       let blockID = UUID(uuidString: blockIDString) {
        return blockID
    }
    if let noteIDString = userInfo["noteID"] as? String,
       let noteID = UUID(uuidString: noteIDString) {
        return noteID
    }
    return nil
}

/// Parses the reminder UUID from a notification identifier string.
///
/// WR-07: This is a fallback only — prefer `reminderIDFromUserInfo` when userInfo is available.
/// Reconstructs the UUID from the first 5 hyphen-split components (UUID is 8-4-4-4-12 = 5 groups).
func reminderIDFromNotificationIdentifier(_ identifier: String) -> UUID? {
    // Split on "-" and try to reconstruct UUID from first 5 components (UUID has 5 parts)
    let parts = identifier.split(separator: "-")
    // UUID string: 8-4-4-4-12 chars = 5 groups
    if parts.count >= 5 {
        let uuidString = parts.prefix(5).joined(separator: "-")
        return UUID(uuidString: uuidString)
    }
    return nil
}

// MARK: - Category registration

/// Registers the actionable UNNotificationCategory for reminders at app launch.
///
/// Idempotent — safe to call on every launch.
/// Must be called before the app finishes launching for action delivery to work.
///
/// Actions:
/// - Complete: foreground-less, checks the row + cancels future alerts (D3-04)
/// - Snooze:   foreground-less, reschedules ~1h (NotificationScheduler)
func registerReminderNotificationCategory() {
    let completeAction = UNNotificationAction(
        identifier: kCompleteActionID,
        title: "Complete",
        options: []   // background: no need to foreground the app
    )
    let snoozeAction = UNNotificationAction(
        identifier: kSnoozeActionID,
        title: "Snooze",
        options: []
    )
    let category = UNNotificationCategory(
        identifier: kReminderCategoryID,
        actions: [completeAction, snoozeAction],
        intentIdentifiers: [],
        options: [.customDismissAction]
    )
    // D-06 / T-115-04: Appended to the SAME categories array — one single registration call
    // so the reminder category is not clobbered (a second call would replace the first).
    let reconcileCategory = UNNotificationCategory(
        identifier: kReconcileCategoryID,
        actions: [],
        intentIdentifiers: [],
        options: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([category, reconcileCategory])
}

// MARK: - NotificationActions content builder

/// Builds a `UNMutableNotificationContent` for a reminder with the correct category
/// and user-info payload for deep-linking.
///
/// The `noteID` parameter is the UUID of the owning Note (for note-level and block-level
/// reminders — the delegate always navigates to the note, optionally to the block row).
///
/// T-03-14: deterministic reminder identifiers map to specific note/row id.
/// T-03-16: no note body text in notification content.
func makeReminderContent(title: String, noteID: UUID, blockID: UUID? = nil) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = title
    content.sound = .default
    content.categoryIdentifier = kReminderCategoryID
    // Deep-link payload: note + optional block UUID
    var userInfo: [String: String] = ["noteID": noteID.uuidString]
    if let bid = blockID { userInfo["blockID"] = bid.uuidString }
    content.userInfo = userInfo
    return content
}

// MARK: - MainActor-isolated container holder (CR-04)

/// Holds the ModelContainer on the MainActor so the delegate can access it
/// without @unchecked Sendable data-race hazards.
@MainActor
final class MainActorContainerHolder {
    var container: ModelContainer?
}

// MARK: - NotificationActionDelegate

/// `UNUserNotificationCenterDelegate` — handles foreground display, action responses,
/// and notification taps (deep-link into EditNoteView for the relevant note/row).
///
/// Registered at app launch in `MyHomeApp.swift`.
///
/// Action handling:
/// - Complete: check the target row + cancel its future advance alerts (D3-04).
/// - Snooze:   reschedule ~1h from now via NotificationScheduler.
/// - Tap (default): deep-link to the note (post a Notification to navigate).
///
/// Security: T-03-14 (identifier → note UUID mapping), T-03-16 (no body in logs).
///
/// CR-04: SwiftData mutations run on MainActor via mainContext — no @unchecked Sendable hazard.
final class NotificationActionDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {

    /// CR-04: Container stored in a @MainActor-isolated holder to eliminate the
    /// @unchecked Sendable data-race. All SwiftData work happens on mainContext.
    let containerHolder = MainActorContainerHolder()

    /// Convenience accessor for callers setting the container at launch (MyHomeApp.swift).
    @MainActor
    var modelContainer: ModelContainer? {
        get { containerHolder.container }
        set { containerHolder.container = newValue }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notification banners even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Handles action button taps and notification banner taps (deep-link).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let identifier = response.notification.request.identifier

        switch response.actionIdentifier {

        case kCompleteActionID:
            handleComplete(identifier: identifier, userInfo: userInfo)

        case kSnoozeActionID:
            handleSnooze(identifier: identifier, userInfo: userInfo)

        default:
            // D-06: SIP reconcile banner tap — deep-link into ReconcileView for the holding
            let categoryID = response.notification.request.content.categoryIdentifier
            if categoryID == kReconcileCategoryID {
                handleReconcileDeepLink(userInfo: userInfo)
            } else {
                // Default: note/row deep-link
                handleDeepLink(userInfo: userInfo)
            }
        }

        completionHandler()
    }

    // MARK: - Complete action (D3-04)

    private func handleComplete(identifier: String, userInfo: [AnyHashable: Any]) {
        // Resolve target UUIDs to Sendable locals BEFORE crossing into the @MainActor Task.
        // `userInfo` is [AnyHashable: Any] (non-Sendable) so it must not be captured by the
        // actor-isolated closure (Swift 6 data-race diagnostic).
        // WR-07: prefer userInfo (noteID/blockID); fall back to identifier parsing.
        // WR-06: blockID presence tells us the target kind so we don't guess.
        let blockID = (userInfo["blockID"] as? String).flatMap(UUID.init(uuidString:))
        let noteID = (userInfo["noteID"] as? String).flatMap(UUID.init(uuidString:))
        let fallbackID = reminderIDFromNotificationIdentifier(identifier)

        // CR-04: All SwiftData work on MainActor using mainContext.
        Task { @MainActor in
            guard let container = containerHolder.container else { return }
            let context = container.mainContext

            if blockID != nil, let reminderID = blockID ?? fallbackID {
                // Block-level reminder — predicate fetch (WR-06)
                var blockDescriptor = FetchDescriptor<NoteBlock>(
                    predicate: #Predicate { $0.id == reminderID }
                )
                blockDescriptor.fetchLimit = 1
                if let blocks = try? context.fetch(blockDescriptor),
                   let block = blocks.first {
                    block.isChecked = true
                    let leadCount = block.reminderLeadMinutes > 0 ? 1 : 0
                    var weekdays: [Int] = []
                    if let data = block.reminderRecurrenceData,
                       let rec = try? JSONDecoder().decode(ReminderRecurrence.self, from: data) {
                        weekdays = rec.weekdays ?? []
                    }
                    NotificationScheduler(center: SystemNotificationCenter())
                        .cancel(reminderID: block.id, leadCount: leadCount, weekdays: weekdays)
                    block.reminderEnabled = false
                    do {
                        try context.save()
                    } catch {
                        assertionFailure("NotificationActionDelegate: failed to save after completing block: \(error)")
                    }
                    return
                }
            }

            // Note-level reminder — predicate fetch by noteID (WR-06)
            if let reminderID = noteID ?? fallbackID {
                var noteDescriptor = FetchDescriptor<Note>(
                    predicate: #Predicate { $0.id == reminderID }
                )
                noteDescriptor.fetchLimit = 1
                if let notes = try? context.fetch(noteDescriptor),
                   let note = notes.first {
                    let leadCount = note.reminderLeadMinutes > 0 ? 1 : 0
                    var weekdays: [Int] = []
                    if let data = note.reminderRecurrenceData,
                       let rec = try? JSONDecoder().decode(ReminderRecurrence.self, from: data) {
                        weekdays = rec.weekdays ?? []
                    }
                    NotificationScheduler(center: SystemNotificationCenter())
                        .cancel(reminderID: note.id, leadCount: leadCount, weekdays: weekdays)
                    note.reminderEnabled = false
                    do {
                        try context.save()
                    } catch {
                        assertionFailure("NotificationActionDelegate: failed to save after completing note: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Snooze action (~1h)

    private func handleSnooze(identifier: String, userInfo: [AnyHashable: Any]) {
        let content = UNMutableNotificationContent()
        // Preserve original title from the triggering notification
        content.title = (userInfo["originalTitle"] as? String) ?? "Reminder"
        content.sound = .default
        content.categoryIdentifier = kReminderCategoryID

        // CR-02: Rebuild payload by iterating userInfo and copying String→String pairs.
        // Direct `as? [String:String]` cast on [AnyHashable:Any] always fails at runtime —
        // the keys are AnyHashable, not String, even when the underlying values are strings.
        var preserved: [String: String] = [:]
        for (k, v) in userInfo {
            if let ks = k as? String, let vs = v as? String {
                preserved[ks] = vs
            }
        }
        content.userInfo = preserved

        // CR-02: Reuse the deterministic "<reminderID>-main" identifier for the snoozed copy
        // so the existing cancel path (NotificationScheduler.cancel) can clear it when the
        // reminder is later cancelled. Derive the main identifier from the original identifier.
        let snoozeIdentifier: String
        if let reminderID = reminderIDFromNotificationIdentifier(identifier) {
            // Reuse deterministic main identifier so cancel() removes the snoozed copy
            snoozeIdentifier = "\(reminderID)-main"
        } else {
            // Fallback: unique identifier (not cancellable by scheduler, but avoids collision)
            snoozeIdentifier = "\(identifier)-snooze-\(Int(Date().timeIntervalSince1970))"
        }

        // Re-fire ~1 hour from now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let request = UNNotificationRequest(
            identifier: snoozeIdentifier,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - Deep-link (tap on banner)

    private func handleDeepLink(userInfo: [AnyHashable: Any]) {
        // Post a notification that RootView / NotesHomeView can observe to navigate
        // to the relevant note. The UI layer subscribes to kOpenNoteNotification.
        if let noteIDString = userInfo["noteID"] as? String,
           let noteID = UUID(uuidString: noteIDString) {
            var payload: [String: Any] = ["noteID": noteID]
            // CR-03: Only include blockID when non-nil — avoid boxing Optional(nil) as Any.
            // RootView and NotesListView now thread blockID through to EditNoteView for row focus.
            if let blockIDString = userInfo["blockID"] as? String,
               let blockID = UUID(uuidString: blockIDString) {
                payload["blockID"] = blockID
            }
            NotificationCenter.default.post(
                name: kOpenNoteNotification,
                object: nil,
                userInfo: payload
            )
        }
    }

    // MARK: - Reconcile deep-link (D-06)

    /// Handles a tap on the monthly SIP reconcile notification.
    ///
    /// Reads `userInfo["sipID"]` as a UUID (T-115-03: guard-parsed, never force-unwrapped)
    /// and posts `kOpenReconcileNotification` so RootView can present ReconcileView for
    /// the corresponding holding.
    private func handleReconcileDeepLink(userInfo: [AnyHashable: Any]) {
        // T-115-03: parse via UUID(uuidString:) with guard — nil/garbage userInfo → no post, no presentation
        guard let sipIDString = userInfo["sipID"] as? String,
              let sipID = UUID(uuidString: sipIDString) else {
            return
        }
        NotificationCenter.default.post(
            name: kOpenReconcileNotification,
            object: nil,
            userInfo: ["sipID": sipID]
        )
    }
}

// MARK: - Deep-link notification names

/// Posted by NotificationActionDelegate when the user taps a reminder banner.
/// Payload: `["noteID": UUID, "blockID": UUID?]`
/// Observed by the Notes UI layer to navigate to the correct note/row.
let kOpenNoteNotification = Notification.Name("com.myhome.openNote")

/// Posted by NotificationActionDelegate when the user taps a SIP reconcile banner (D-06).
/// Payload: `["sipID": UUID]`
/// Observed by RootView to present ReconcileView for the SIP's holding.
let kOpenReconcileNotification = Notification.Name("com.myhome.openReconcile")
