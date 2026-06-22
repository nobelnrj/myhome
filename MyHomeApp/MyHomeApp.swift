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
                    #if DEBUG
                    seedSampleDataIfRequested()
                    #endif
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

    #if DEBUG
    // MARK: - Sample data seeder (DEBUG only, launch-arg gated — for visual verification)

    /// Seeds budgets + a month of expenses + income when launched with `-seedSampleData`.
    /// Never runs in release builds and only when the flag is explicitly passed.
    @MainActor
    private func seedSampleDataIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seedSampleData") else { return }
        let ctx = container.mainContext
        let cats = (try? ctx.fetch(FetchDescriptor<Category>())) ?? []
        guard cats.count >= 4 else { return }

        // Idempotent-ish: if a sample-tagged expense already exists, skip.
        let existing = (try? ctx.fetch(FetchDescriptor<Expense>())) ?? []
        if existing.contains(where: { $0.note == "SAMPLE" }) { return }

        let cal = Calendar.current
        let now = Date()
        // Budgets on the first four categories.
        let budgets: [Decimal] = [18000, 12000, 8000, 6000]
        for (i, c) in cats.prefix(4).enumerated() { c.monthlyBudget = budgets[i] }

        // Spend across categories this month (positive = spend). Spends-only so totalSpend
        // stays clean-positive for the demo (uncategorised negatives would net it down).
        let spends: [(Int, Decimal)] = [(0, 14200), (1, 9300), (2, 5100), (3, 3800), (0, 2600), (1, 1900)]
        for (idx, (catIndex, amount)) in spends.enumerated() {
            let day = cal.date(byAdding: .day, value: -(idx * 3 + 1), to: now) ?? now
            let e = Expense(amount: amount, date: day, note: "SAMPLE")
            e.categories = [cats[catIndex]]
            ctx.insert(e)
        }
        try? ctx.save()
    }
    #endif

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
