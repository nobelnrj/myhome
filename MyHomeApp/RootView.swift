import SwiftUI
import SwiftData

/// Root TabView host (D2-10, D3-17, D4-01, D5-11).
///
/// Phase 5 additions:
/// - @State lockController = LockController() — owns the Face ID gate state (@Observable, D5-11)
/// - scenePhase observation drives blur + grace-period re-lock (D5-02, D5-01)
/// - Privacy blur (.blur radius 20) applied to TabView on inactive/background (T-05-04)
/// - UnlockView overlay when lockController.isLocked && lockController.lockEnabled (T-05-01)
/// - Settings tab (tag 4, gearshape icon — D5-11, D5-12)
///
/// Phase 7 additions:
/// - gmailSyncController moved to MyHomeApp, passed in here (BGTask needs it — Open Question 2)
/// - reviewBadgeCount @State drives Expenses tab .badge (D7-04)
/// - .onAppear injects modelContext into gmailSyncController for foreground sync persistence
///
/// Phase 4 tabs (4-tab bar — D4-01):
/// 0. Home — OverviewView (dashboard, default launch tab).      tag: 0
/// 1. Expenses — ExpenseListView (owns its NavigationStack).    tag: 1
/// 2. Budgets — BudgetsView (owns its NavigationStack).         tag: 2
/// 3. Notes — NotesHomeView (segmented List|Calendar host).     tag: 3
/// 4. Settings — SettingsView (Face ID toggle, categories, about). tag: 4
///
/// The `selectedTab` binding allows programmatic tab switching, e.g. on a
/// notification deep-link (kOpenNoteNotification → switch to Notes tab, open note).
///
/// No shared NavigationPath — each tab owns its navigation independently.
struct RootView: View {

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: Int = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-startTab"), i + 1 < args.count, let t = Int(args[i + 1]) { return t }
        #endif
        return 0
    }()
    @State private var deepLinkNoteID: UUID? = nil
    /// OVR-06: Category filter deep-link from Overview donut tap → pre-filters Activity tab.
    /// Set by SpendDonutCard's onCategoryTap closure; cleared by ExpenseListView on appear.
    @State private var activityCategoryFilter: UUID? = nil
    /// CR-03: Thread blockID deep-link through the view hierarchy so EditNoteView can
    /// scroll to and highlight the target block row when a block-level reminder is tapped.
    @State private var deepLinkBlockID: UUID? = nil
    /// D-06: SIP reconcile notification tap — holds the resolved Asset to present ReconcileView.
    /// Set by the kOpenReconcileNotification observer; cleared on sheet dismiss.
    @State private var deepLinkReconcileSIPID: UUID? = nil
    /// Face ID gate state — @Observable owned via @State, never @StateObject (PITFALLS.md Pitfall 10)
    @State private var lockController = LockController()
    @State private var routineResetService = RoutineResetService()
    /// Transfer scan service — owned by RootView, injected into both GmailSyncController (post-sync)
    /// and SettingsView (on-demand "Scan for Transfers" action). Mirrors RoutineResetService pattern.
    @State private var transferScanService = TransferScanService()
    /// AMFI NAV auto-refresh service (D-06, ASSET-03) — fetches NAVAll.txt once per IST day.
    /// Shared with descendant asset views via .environment so the picker and pull-to-refresh work.
    @State private var amfiNavService = AMFINavService()
    /// Net-worth snapshot service (D-08, ASSET-08) — upserts one NetWorthSnapshot per IST day.
    @State private var netWorthSnapshotService = NetWorthSnapshotService()
    /// NPS NAV auto-refresh service (D-01, ASSET-09) — fetches npsnav.in/api/latest-min once per IST day.
    /// Shared via .environment so NPSSchemePickerView and EditAssetView can read schemeList.
    @State private var npsNavService = NPSNavService()
    /// SIP accrual engine (D-04, D-07, ASSET-09) — prices elapsed installments and writes Contribution rows.
    @State private var sipAccrualService = SIPAccrualService()

    /// Gmail sync controller — owned by MyHomeApp, passed in here (Phase 7: BGTask ownership).
    let gmailSyncController: GmailSyncController

    /// Review-inbox badge count — updated by ExpenseListView via @Binding (D7-04).
    @State private var reviewBadgeCount: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView(selectedTab: $selectedTab, deepLinkNoteID: $deepLinkNoteID, activityCategoryFilter: $activityCategoryFilter)
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(0)
            ExpenseListView(reviewBadgeCount: $reviewBadgeCount, deepLinkCategoryFilter: $activityCategoryFilter)
                .tabItem {
                    Label("Expenses", systemImage: "list.bullet")
                }
                .badge(reviewBadgeCount)
                .tag(1)
            BudgetsView()
                .tabItem {
                    Label("Budgets", systemImage: "chart.bar")
                }
                .tag(2)
            NotesHomeView(deepLinkNoteID: $deepLinkNoteID, deepLinkBlockID: $deepLinkBlockID)
                .tabItem {
                    Label("Notes", systemImage: "note.text")
                }
                .tag(3)
            SettingsView(selectedTab: $selectedTab, lockController: lockController, gmailSyncController: gmailSyncController, transferScanService: transferScanService)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(4)        }
        .tint(DesignTokens.accent)   // D-02: canary yellow selected-tab tint (#FFD60A)
        .onChange(of: selectedTab) { _, _ in Haptics.selection() }
        .onAppear {
            // Inject the SwiftData context into the sync controller so sync() can persist
            // ingested expenses. Called here (not in init) so the @Environment is populated.
            gmailSyncController.setContext(modelContext)
            // Inject context into routine reset service (same pattern — D-07, STAB-04)
            routineResetService.modelContext = modelContext
            // Inject context into transfer scan service; wire into gmail sync for post-sync detection (D-08)
            transferScanService.modelContext = modelContext
            gmailSyncController.transferScanService = transferScanService
            // Phase 11: inject context into AMFI NAV service + net-worth snapshot service (D-06, D-08)
            amfiNavService.modelContext = modelContext
            netWorthSnapshotService.modelContext = modelContext
            // Phase 11.1: inject context into NPS NAV service + SIP accrual service (D-01, D-04)
            npsNavService.modelContext = modelContext
            sipAccrualService.modelContext = modelContext
        }
        // Deep-link observer: notification banner tap → switch to Notes tab + open note
        .onReceive(NotificationCenter.default.publisher(for: kOpenNoteNotification)) { notification in
            if let noteID = notification.userInfo?["noteID"] as? UUID {
                deepLinkNoteID = noteID
                // CR-03: forward block target when present
                deepLinkBlockID = notification.userInfo?["blockID"] as? UUID
                selectedTab = 3
            }
        }
        // D-06: SIP reconcile deep-link observer — present ReconcileView for the SIP's holding.
        // Mirrors kOpenNoteNotification pattern: read userInfo, store UUID, sheet presentation resolves.
        .onReceive(NotificationCenter.default.publisher(for: kOpenReconcileNotification)) { notification in
            if let sipID = notification.userInfo?["sipID"] as? UUID {
                deepLinkReconcileSIPID = sipID
            }
        }
        // D-06: Present ReconcileView when the user taps a SIP reconcile notification.
        // Resolves sipID → SIP → Asset via FetchDescriptor using the @Environment modelContext.
        .sheet(isPresented: Binding(
            get: { deepLinkReconcileSIPID != nil },
            set: { if !$0 { deepLinkReconcileSIPID = nil } }
        )) {
            if let sipID = deepLinkReconcileSIPID {
                reconcileSheetView(for: sipID)
            }
        }
        // Privacy blur: active on inactive + background so app-switcher snapshot is obscured (T-05-04, D5-02)
        .blur(radius: lockController.isBlurred ? 20 : 0)
        .animation(.easeInOut(duration: 0.2), value: lockController.isBlurred)
        // UnlockView overlay: shown when locked + lock enabled (T-05-01, D5-02)
        .overlay {
            if lockController.isLocked && lockController.lockEnabled {
                UnlockView(lockController: lockController)
                    .transition(.opacity)
            }
        }
        // Scene phase observation: drives blur, grace-period re-lock, and auto-authenticate on foreground
         .onChange(of: scenePhase) { _, newPhase in
             lockController.scenePhaseChanged(newPhase)
             gmailSyncController.scenePhaseChanged(newPhase)
             if newPhase == .active {
                 routineResetService.resetIfNeeded()   // synchronous — no Task needed (D-07)
                 // Phase 11: daily NAV refresh + net-worth snapshot upsert (D-06, D-08)
                 amfiNavService.refreshIfNeeded()      // IST gate; URLSession inside Task {}
                 // Phase 11.1: NPS NAV refresh + SIP accrual (D-01, D-04, D-07)
                 // Order is mandatory (D-02): accrueIfNeeded BEFORE upsertIfNeeded so the
                 // same-cycle net-worth snapshot includes the just-accrued units.
                 npsNavService.refreshIfNeeded()       // IST gate; URLSession inside Task {}
                 sipAccrualService.accrueIfNeeded()    // no IST gate; Task-wrapped
                 netWorthSnapshotService.upsertIfNeeded() // IST gate; compute/save inside Task {}
             }
             // Auto-trigger auth on foreground when locked (banking-app feel — D5-02, D5-01)
             // Pitfall: never call async directly in onChange; always wrap in Task
             if newPhase == .active && lockController.isLocked && lockController.lockEnabled {
                 Task { await lockController.authenticate() }
             }
         }
        // Phase 11: pass amfiNavService into the environment so AssetsListView, AMFISchemePickerView,
        // and any descendant can call refreshIfNeeded() / read schemeList (D-02, D-06).
        .environment(amfiNavService)
        // Phase 11.1: NPSSchemePickerView and EditAssetView read npsNavService from environment.
        // SIPAccrualService does NOT need environment injection — only RootView drives it.
        .environment(npsNavService)
    }

    // MARK: - Reconcile deep-link sheet (D-06)

    /// Resolves a sipID UUID to its owning Asset and returns a ReconcileView sheet.
    ///
    /// Uses a FetchDescriptor on the @Environment modelContext — the same context already
    /// present in RootView for other services. Resolves SIP.assetID → Asset.
    /// If the SIP or Asset cannot be found (deleted, corrupted) the sheet is dismissed silently.
    @ViewBuilder
    private func reconcileSheetView(for sipID: UUID) -> some View {
        // Resolve sipID → SIP → Asset synchronously from the main context.
        // Both models are small; FetchDescriptor with fetchLimit=1 is safe on MainActor.
        if let sip = fetchSIP(id: sipID),
           let asset = fetchAsset(id: sip.assetID) {
            ReconcileView(asset: asset)
        } else {
            // SIP or Asset not found — dismiss immediately with an empty view
            EmptyView()
                .onAppear { deepLinkReconcileSIPID = nil }
        }
    }

    private func fetchSIP(id: UUID) -> SIP? {
        var descriptor = FetchDescriptor<SIP>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchAsset(id: UUID) -> Asset? {
        var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
