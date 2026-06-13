import Foundation
import UserNotifications

// MARK: - RoutineNotificationService

/// Schedules a daily repeating local notification for a routine note.
///
/// Uses a direct `UNCalendarNotificationTrigger` (time-only, repeats daily) pattern,
/// mirroring `SIPAccrualService.scheduleReconcileReminder` — NOT `NotificationScheduler.buildRequests`.
///
/// D-05 guarantee: exactly one pending notification request per routine note.
/// Cancel is synchronous; add is async. Cancel is always called BEFORE awaiting add.
/// Stable identifier: `"routine-daily-{noteID.uuidString}"` — distinct from the NotificationScheduler
/// reminder identifier scheme and from the SIP reconcile domain.
///
/// T-12-05: `userInfo` carries ONLY `noteID` and `isRoutineReminder` — no note body text.
struct RoutineNotificationService {

    private let center: any NotificationCenterPort

    init(center: any NotificationCenterPort = SystemNotificationCenter()) {
        self.center = center
    }

    // MARK: - Stable identifier

    /// Returns the stable pending-request identifier for a given routine note.
    ///
    /// Prefix `"routine-daily-"` is distinct from:
    /// - NotificationScheduler's `"{reminderID}-main"` / `"{reminderID}-weekday-*"` scheme
    /// - SIPAccrualService's `"sip-reconcile-{sipID}"` scheme
    static func identifier(for noteID: UUID) -> String {
        "routine-daily-\(noteID.uuidString)"
    }

    // MARK: - Schedule

    /// Cancel any existing pending request for this note, then schedule a new one.
    ///
    /// Uses time-only `DateComponents` `[.hour, .minute]` so the trigger fires every day
    /// at the user's chosen time — `repeats: true`. Cancel is synchronous (D-05 Pitfall 3);
    /// add is async. The cancel-then-add ordering is maintained: cancel runs synchronously
    /// BEFORE the await on center.add.
    ///
    /// - Parameters:
    ///   - noteID: The routine note's UUID — used to derive the stable identifier.
    ///   - title: The notification title (note title — user-authored, expected on lock screen).
    ///   - time: The daily fire time; only `.hour` and `.minute` components are used.
    func schedule(noteID: UUID, title: String, time: Date) async {
        // 1. Cancel synchronously FIRST (D-05 — Pitfall 3: cancel before async add)
        cancel(noteID: noteID)

        // 2. Build time-only DateComponents in device timezone.
        //    Only .hour and .minute — no date components — so the trigger repeats daily.
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        // 3. Build the notification content.
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Time for your daily routine"
        content.sound = .default
        // Enable the Complete action (mirrors kReminderCategoryID pattern — NotificationActions.swift line 9)
        content.categoryIdentifier = kReminderCategoryID
        // T-12-05: userInfo carries ONLY noteID + isRoutineReminder — no note body text.
        content.userInfo = ["noteID": noteID.uuidString, "isRoutineReminder": "true"]

        // 4. Create and add the request using the stable per-note identifier.
        let request = UNNotificationRequest(
            identifier: Self.identifier(for: noteID),
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    // MARK: - Cancel

    /// Synchronously removes the pending request for this note, if any.
    func cancel(noteID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: noteID)])
    }
}
