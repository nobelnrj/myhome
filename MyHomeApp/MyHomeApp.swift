import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks
import UIKit

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

    /// SYNC-04: foreground-only P2P auto-sync orchestrator. Injected with the production
    /// MultipeerConnectivity transport; `deviceName` comes from UIDevice so the coordinator
    /// itself never touches UIKit. Started/stopped by scenePhase below.
    @State private var syncCoordinator = SyncCoordinator(
        transport: MultipeerSyncTransport(),
        deviceName: UIDevice.current.name
    )

    /// scenePhase for scheduling background refresh on app-backgrounding.
    @Environment(\.scenePhase) private var scenePhase

    /// D-01: user-selected appearance (System/Light/Dark), persisted in plain UserDefaults.
    /// Shares the "appearanceTheme" key with the Settings Appearance row so flipping the row
    /// re-resolves the root scheme live. D-02: a missing/garbage value resolves to `.system`
    /// (follow the device) via the optional-init fallback below — no migration, no opt-in gate.
    @AppStorage("appearanceTheme") private var appearanceThemeRaw = AppearanceTheme.system.rawValue

    /// SYNC-03: a received `.myhomesnap` file URL awaiting the confirm-merge sheet. Set ONLY by
    /// the `.onOpenURL` handler when the incoming URL is a snapshot document — never populated
    /// for Google OAuth callback URLs (those are filtered by the pathExtension guard) so the
    /// import sheet never hijacks the OAuth flow.
    @State private var pendingImportURL: IdentifiableURL?

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            RootView(gmailSyncController: gmailSyncController)
                // D-01: root scheme is AppStorage-driven (System/Light/Dark) — supersedes the
                // former forced-dark DS-05 pin. Garbage/missing key → .system (D-02).
                .preferredColorScheme((AppearanceTheme(rawValue: appearanceThemeRaw) ?? .system).colorScheme)
                .environment(syncCoordinator)
                .onAppear {
                    setupNotifications()
                    // One-time repair for stores that accumulated duplicate ingested expenses
                    // from overlapping pre-guard sync runs (doubled Overview totals). No-op once
                    // the store is clean, so it is safe to run on every launch.
                    DuplicateExpenseCleanup.run(in: container.mainContext)
                    // SYNC-04: wire auto-sync to the production store and start discovery.
                    // App launches foregrounded; the scenePhase .active branch does not reliably
                    // fire for the initial transition on all iOS versions, so start here.
                    syncCoordinator.setContext(container.mainContext)
                    syncCoordinator.start()
                    #if DEBUG
                    seedSampleDataIfRequested()
                    #endif
                }
                // SYNC-03: route an opened `.myhomesnap` (AirDrop accept, Files "open in", or
                // any onOpenURL delivery) into the confirm-merge sheet. The guard filters on the
                // file extension so Google OAuth callback URLs (and any future custom scheme) fall
                // straight through untouched — only snapshot documents are claimed.
                .onOpenURL { url in
                    guard url.pathExtension.lowercased() == "myhomesnap" else { return }
                    pendingImportURL = IdentifiableURL(url: url)
                }
                // Nothing touches the store here: the sheet decodes-then-confirms and only merges
                // when the user explicitly taps Merge (T-18-11).
                .sheet(item: $pendingImportURL) { item in
                    SnapshotImportSheet(fileURL: item.url)
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
        // Schedule background refresh when app goes to background (ING-04) and drive the
        // foreground-only P2P sync lifecycle (SYNC-04). MC sessions die in the background
        // anyway; a clean teardown avoids zombie sessions. `.inactive` is deliberately a
        // no-op so share sheets and the Face ID overlay never kill an in-flight sync.
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                scheduleBackgroundRefresh()
                syncCoordinator.stop()
            case .active:
                syncCoordinator.start()   // guarded idempotent
            default:
                break                     // .inactive → untouched
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
        // The two trailing 1–2%-share spends exercise the donut's tiny-segment path
        // (rounded caps must not overlap — the NeuDonutRing min-span fix).
        // (category index, amount, days ago). The tiny spends stay within the last few
        // days so they land in the CURRENT month — the donut is month-scoped.
        // Phase 21 (OVF-01): two sample accounts so the Overview account filter is visually
        // verifiable in the simulator. Seeded expenses are attributed alternately to these two;
        // the income row is left unassigned so the "Unassigned" filter row also has something to
        // show. Guarded by the same -seedSampleData flag + SAMPLE idempotence check above.
        let hdfc = Account(name: "SAMPLE HDFC", typeRaw: "credit_card")
        hdfc.colorHex = "#2563EB"
        hdfc.symbolName = "creditcard"
        hdfc.last4 = "42"
        hdfc.sortOrder = 0
        ctx.insert(hdfc)
        let icici = Account(name: "SAMPLE ICICI Credit", typeRaw: "credit_card")
        icici.colorHex = "#C2410C"
        icici.symbolName = "creditcard"
        icici.last4 = "18"
        icici.sortOrder = 1
        ctx.insert(icici)
        let sampleAccountIDs = [hdfc.id, icici.id]

        let spends: [(Int, Decimal, Int)] = [(0, 14200, 1), (1, 9300, 4), (2, 5100, 7), (3, 3800, 10),
                                             (0, 2600, 13), (1, 1900, 16), (4, 430, 2), (5, 210, 3)]
        for (i, (catIndex, amount, daysAgo)) in spends.enumerated() {
            guard catIndex < cats.count else { continue }
            let day = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            let e = Expense(amount: amount, date: day, note: "SAMPLE")
            e.categories = [cats[catIndex]]
            // Attribute alternately so filtering to one account halves the visible spend (OVF-01).
            e.accountID = sampleAccountIDs[i % sampleAccountIDs.count]
            ctx.insert(e)
        }
        // Income (negative amount, uncategorised) so the two-tone orb shows green + red.
        // Left UNASSIGNED (accountID == nil) so the "Unassigned" filter row has a figure.
        let income = Expense(amount: Decimal(-14000), date: cal.date(byAdding: .day, value: -2, to: now) ?? now, note: "SAMPLE")
        ctx.insert(income)

        // Assets + snapshot history so the Overview net-worth card (donut + trend) renders.
        let mf = Asset()
        mf.name = "SAMPLE Index Fund"
        mf.assetClassRaw = "mutual_fund"
        mf.units = 1200
        mf.currentNAV = Decimal(155)
        mf.navAsOfDate = now
        ctx.insert(mf)
        let stock = Asset()
        stock.name = "SAMPLE Stock"
        stock.assetClassRaw = "stock"
        stock.units = 90
        stock.currentNAV = Decimal(640)
        stock.navAsOfDate = now
        ctx.insert(stock)
        for dayOffset in stride(from: 35, through: 0, by: -1) {
            let snap = NetWorthSnapshot()
            snap.date = cal.startOfDay(for: cal.date(byAdding: .day, value: -dayOffset, to: now) ?? now)
            let wobble = Decimal(dayOffset % 7) * 2800 - Decimal(dayOffset) * 950
            snap.mfValue = 186_000 - wobble
            snap.stockValue = 57_600 + wobble / 2
            snap.totalNetWorth = snap.mfValue + snap.stockValue
            ctx.insert(snap)
        }
        seedSamplePantry(ctx)
        seedSampleShoppingExtras(ctx)

        try? ctx.save()
    }

    /// Seeds a pantry covering all three stock states (in stock / LOW / OUT) so the Kitchen
    /// screenshots show the badges without any UI interaction. Idempotent: skipped once any
    /// PantryItem exists.
    @MainActor
    private func seedSamplePantry(_ ctx: ModelContext) {
        let existingPantry = (try? ctx.fetch(FetchDescriptor<PantryItem>())) ?? []
        guard existingPantry.isEmpty else { return }

        // (name, quantity, unit, lowStockThreshold, restockQuantity)
        let items: [(String, Double, String, Double, Double)] = [
            ("Sona Masoori rice", 5, "kg",   1, 5),
            ("Atta",              4, "kg",   1, 5),
            ("Milk",              1, "L",    1, 3),   // LOW (at threshold)
            ("Eggs",              2, "pcs",  4, 12),  // LOW (below threshold)
            ("Filter coffee",     0, "pack", 1, 2),   // OUT
            ("Dishwash liquid",   3, "btl",  1, 1)
        ]
        for (name, qty, unit, threshold, restock) in items {
            ctx.insert(PantryItem(
                name: name, quantity: qty, unit: unit,
                lowStockThreshold: threshold, restockQuantity: restock
            ))
        }
    }

    /// Seeds two MANUAL shopping extras (one unchecked, one checked) so the Shopping segment
    /// screenshots show both the plain and struck-through row styling. The RESTOCK section needs
    /// no seed — it is derived from the pantry above. Idempotent: skipped once any row exists.
    @MainActor
    private func seedSampleShoppingExtras(_ ctx: ModelContext) {
        let existing = (try? ctx.fetch(FetchDescriptor<ShoppingListItem>())) ?? []
        guard existing.isEmpty else { return }

        ctx.insert(ShoppingListItem(name: "Aluminium foil"))
        ctx.insert(ShoppingListItem(name: "Paper napkins", quantity: 2, unit: "pack"))
        let bought = ShoppingListItem(name: "Batteries", quantity: 4, unit: "pcs")
        bought.isChecked = true
        bought.checkedAt = Date()
        ctx.insert(bought)
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
