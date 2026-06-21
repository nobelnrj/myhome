import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks

@main
struct MyHomeApp: App {
    /// Production ModelContainer — App Group store URL + AppMigrationPlan.
    /// Created once at app startup; crashes with a diagnostic message if the store
    /// cannot be opened (schema corruption or migration failure).
    let container: ModelContainer = {
        do {
            return try ModelContainer.appContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    /// Notification action delegate — retained for the lifetime of the app.
    @State private var notificationDelegate = NotificationActionDelegate()

    /// Gmail sync controller — moved from RootView to MyHomeApp so the BGTask handler
    /// can capture it (RESEARCH Open Question 2, 07-PATTERNS.md §MyHomeApp.swift).
    @State private var gmailSyncController = GmailSyncController()

    /// scenePhase for scheduling background refresh on app-backgrounding.
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            RootView(gmailSyncController: gmailSyncController)
                .preferredColorScheme(.dark)   // DS-05: neumorphic dark-mode-only; applied once at root
                .onAppear {
                    setupNotifications()
                }
        }
        .modelContainer(container)
        // ING-04: BGAppRefreshTask — best-effort background email ingestion.
        // "Sync now" stays the reliable path. This is a bonus (do not imply reliability in UI).
        //
        // T-07-13: The handler is registered here (before end of launch) to match the
        // Info.plist identifier com.reojacob.myhome.emailrefresh. Both must exist or the
        // app crashes on launch (Apple requirement: every permitted identifier has a handler).
        .backgroundTask(.appRefresh("com.reojacob.myhome.emailrefresh")) {
            // T-07-12: Reschedule FIRST inside the handler — otherwise it never fires again.
            scheduleBackgroundRefresh()

            // T-07-11: sync() runs the proactive-refresh block before any fetch — token
            // mitigations from 06-SECURITY.md are preserved unchanged in sync().

            // T-07-12: Background handler has a 30s budget. Keep it fast:
            // list→skip-dismissed→getRaw→parse→triage, no retries.
            //
            // RESEARCH Pitfall 5: GmailSyncController is @MainActor — must hop to MainActor
            // before calling any @MainActor method from a background context.
            await MainActor.run {
                // RESEARCH Open Question 3: the background process cannot reuse the app's
                // container (it may not be loaded). Create a FRESH ModelContainer+ModelContext
                // via the Phase 1 factory so ingested expenses are written to the same store.
                if let freshContainer = try? ModelContainer.appContainer() {
                    gmailSyncController.setContext(freshContainer.mainContext)
                }
                Task {
                    await gmailSyncController.sync()
                }
            }
        }
        // Schedule background refresh when app goes to background (ING-04).
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                scheduleBackgroundRefresh()
            }
        }
    }

    // MARK: - BGAppRefreshTask scheduling

    /// Submits a BGAppRefreshTaskRequest to schedule the next background email refresh.
    ///
    /// earliestBeginDate: 1 hour from now (iOS may delay; "best-effort" qualifier applies).
    /// Idempotent: submitting a new request replaces any pending request with the same identifier.
    /// nonisolated: BGTaskScheduler.shared.submit is safe to call from any context.
    nonisolated private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.reojacob.myhome.emailrefresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600) // 1 hour
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Notification setup (idempotent — safe to call on every launch)

    @MainActor
    private func setupNotifications() {
        // Register Complete/Snooze actionable category
        registerReminderNotificationCategory()

        // Inject the model container so the delegate can create fetch contexts
        notificationDelegate.modelContainer = container

        // Set the delegate (idempotent per UNUserNotificationCenter contract)
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }
}
