import SwiftUI
import SwiftData
import UserNotifications

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

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear {
                    setupNotifications()
                }
        }
        .modelContainer(container)
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
