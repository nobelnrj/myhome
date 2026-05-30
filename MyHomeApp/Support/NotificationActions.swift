import Foundation
import UserNotifications
import SwiftData
import SwiftUI

// MARK: - Notification Category + Action IDs

/// UNNotificationCategory identifier for note/block reminders.
let kReminderCategoryID = "com.myhome.reminder"

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
    UNUserNotificationCenter.current().setNotificationCategories([category])
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
final class NotificationActionDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {

    /// Shared model container for background context (injected at app launch).
    /// Access is safe: written once on main actor at launch, read from callbacks on delegate queue.
    var modelContainer: ModelContainer?

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
            // Notification tap — deep-link to note/row
            handleDeepLink(userInfo: userInfo)
        }

        completionHandler()
    }

    // MARK: - Complete action (D3-04)

    private func handleComplete(identifier: String, userInfo: [AnyHashable: Any]) {
        guard let container = modelContainer else { return }

        // Parse the target reminder ID from the notification identifier
        guard let reminderID = reminderIDFromNotificationIdentifier(identifier) else { return }

        // Run on a background context to avoid blocking the main actor
        Task {
            let context = ModelContext(container)
            // Look for a matching NoteBlock first (block-level reminder)
            let blockDescriptor = FetchDescriptor<NoteBlock>()
            if let blocks = try? context.fetch(blockDescriptor) {
                if let block = blocks.first(where: { $0.id == reminderID }) {
                    // Check the block
                    block.isChecked = true
                    // Cancel future advance alerts (D3-04)
                    let leadCount = block.reminderLeadMinutes > 0 ? 1 : 0
                    var weekdays: [Int] = []
                    if let data = block.reminderRecurrenceData,
                       let rec = try? JSONDecoder().decode(ReminderRecurrence.self, from: data) {
                        weekdays = rec.weekdays ?? []
                    }
                    NotificationScheduler(center: SystemNotificationCenter())
                        .cancel(reminderID: block.id, leadCount: leadCount, weekdays: weekdays)
                    block.reminderEnabled = false
                    try? context.save()
                    return
                }
            }
            // Fall back to note-level reminder
            let noteDescriptor = FetchDescriptor<Note>()
            if let notes = try? context.fetch(noteDescriptor) {
                if let note = notes.first(where: { $0.id == reminderID }) {
                    // Cancel the note-level reminder
                    let leadCount = note.reminderLeadMinutes > 0 ? 1 : 0
                    var weekdays: [Int] = []
                    if let data = note.reminderRecurrenceData,
                       let rec = try? JSONDecoder().decode(ReminderRecurrence.self, from: data) {
                        weekdays = rec.weekdays ?? []
                    }
                    NotificationScheduler(center: SystemNotificationCenter())
                        .cancel(reminderID: note.id, leadCount: leadCount, weekdays: weekdays)
                    note.reminderEnabled = false
                    try? context.save()
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
        content.userInfo = userInfo as? [String: String] ?? [:]

        // Re-fire ~1 hour from now
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let snoozeIdentifier = "\(identifier)-snooze-\(Int(Date().timeIntervalSince1970))"
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
            let blockIDString = userInfo["blockID"] as? String
            let blockID = blockIDString.flatMap { UUID(uuidString: $0) }
            NotificationCenter.default.post(
                name: kOpenNoteNotification,
                object: nil,
                userInfo: [
                    "noteID": noteID,
                    "blockID": blockID as Any
                ]
            )
        }
    }
}

// MARK: - Deep-link notification name

/// Posted by NotificationActionDelegate when the user taps a reminder banner.
/// Payload: `["noteID": UUID, "blockID": UUID?]`
/// Observed by the Notes UI layer to navigate to the correct note/row.
let kOpenNoteNotification = Notification.Name("com.myhome.openNote")
