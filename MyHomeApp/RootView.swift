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
///
/// Phase 24 (NAV-01) — Custom Floating Nav Bar (rebuilt, no native bar):
/// - There is NO `TabView`. The five tab roots live in a plain `ZStack` and are switched by
///   the `selectedTab` state; `FloatingNavBar` (DesignSystem/FloatingNavBar.swift) is the ONLY
///   bar. Rebuilt this way because the previous approach kept a native `TabView` and tried to
///   HIDE its bar (`.toolbar(.hidden, for: .tabBar)` + frame-shrink hacks); the hidden native
///   bar kept leaking — a white band, then an empty native pill under the floating bar. A bar
///   that doesn't exist can't leak.
/// - Per-tab state preservation (matching native TabView semantics): each tab keeps its own
///   `NavigationStack`. A tab is instantiated LAZILY the first time it is selected and then kept
///   alive in the hierarchy forever (tracked in `activatedTabs`), toggled only by `.opacity` /
///   `.allowsHitTesting` / `.zIndex`. Because a tab is only added to the hierarchy on first
///   selection — never at launch for the other four — each tab's `.onAppear` / `.task`
///   side-effects (LockController, TransferScanService, Gmail/NAV refresh, routine reset, etc.)
///   fire exactly once, when that tab first becomes visible, exactly as a native `TabView` does.
/// - `-startTab N` seeds both `selectedTab` and `activatedTabs` (only that tab is pre-activated).
///   The note deep-link (`selectedTab = 3`) selects — and thereby activates — the Notes tab.
/// - Content clearance under the floating bar is reserved per-screen via `.floatingBarClearance()`
///   applied directly to each screen's own List/ScrollView. The container carries an explicit
///   `bgCanvas.ignoresSafeArea()` background so the screen background fills edge-to-edge and there
///   is never a white band regardless of how any individual tab insets its content.
struct RootView: View {

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    /// Resolves the launch tab from the `-startTab N` debug flag (default 0). Used to seed both
    /// `selectedTab` and the initially-activated tab so exactly one tab appears at launch.
    private static func initialTab() -> Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-startTab"), i + 1 < args.count, let t = Int(args[i + 1]), (0...4).contains(t) { return t }
        #endif
        return 0
    }

    @State private var selectedTab: Int = RootView.initialTab()

    /// Tabs that have been selected at least once and are therefore kept alive in the hierarchy.
    /// Seeded with only the launch tab so the other four never `.onAppear` (and never fire their
    /// services) until the user actually navigates to them — matching native TabView semantics.
    @State private var activatedTabs: Set<Int> = [RootView.initialTab()]
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

    /// SYNC-05: first-run bootstrap prompt. Set true in onAppear only for a fresh (effectively
    /// empty) install whose owner hasn't answered the prompt; presents SyncBootstrapView once.
    @State private var showBootstrapSheet = false

    var body: some View {
        // Phase 22 (ICON-02): `-iconGallery` swaps the whole root for the tile gallery, so
        // `simctl io booted screenshot` can capture all 17 pantry symbols deterministically —
        // simctl cannot navigate to Kitchen → Pantry. Mirrors the `-startTab` hook's style and,
        // like it, exists only in DEBUG (T-22-10).
        #if DEBUG
        if PantryIconGalleryView.isRequested {
            PantryIconGalleryView()
        } else {
            mainContent
        }
        #else
        mainContent
        #endif
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack(alignment: .bottom) {
            // Phase 24 fix (NAV-01): explicit full-bleed background BEHIND the tab content. Every
            // tab insets its content off the bottom edge (via floatingBarClearance); without this
            // the container's default (white) window background would show through as a band.
            DesignTokens.bgCanvas.ignoresSafeArea()

            // Custom tab container — no native TabView, so there is no native bar to leak. Each
            // tab is instantiated lazily on first selection (activatedTabs) and then kept alive,
            // switched only by opacity/hit-testing/zIndex so its NavigationStack state survives.
            ForEach(0..<5, id: \.self) { index in
                if activatedTabs.contains(index) {
                    tabRoot(for: index)
                        .opacity(selectedTab == index ? 1 : 0)
                        .allowsHitTesting(selectedTab == index)
                        .zIndex(selectedTab == index ? 1 : 0)
                }
            }

            FloatingNavBar(selectedTab: $selectedTab, reviewBadgeCount: reviewBadgeCount)
                // Above every tab's content so the bar is always tappable and on top.
                .zIndex(100)
        }
        .onChange(of: selectedTab) { _, newTab in
            // Activate (and thereby first-appear) the tab lazily on selection, then keep it alive.
            activatedTabs.insert(newTab)
            Haptics.selection()
        }
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
            // SYNC-05: offer the one-shot bootstrap sheet on a genuinely fresh install. The DEBUG
            // launch-arg suppression keeps the screenshot/UI-verify loops unblocked (release: false).
            if !BootstrapAdvisor.isSuppressedByLaunchArguments,
               BootstrapAdvisor.shouldOfferBootstrap(context: modelContext) {
                showBootstrapSheet = true
            }
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
        // SYNC-05: first-run bootstrap sheet. Presented once for a fresh install; SyncBootstrapView
        // persists the one-shot resolved flag on complete/later/swipe so it never re-appears.
        .sheet(isPresented: $showBootstrapSheet) {
            SyncBootstrapView(onResolved: { showBootstrapSheet = false })
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

    // MARK: - Tab roots (custom container — NAV-01)

    /// Returns the root view for a tab index. Order/destinations unchanged from the old TabView
    /// tags: 0 Home · 1 Expenses · 2 Budgets · 3 Notes · 4 Settings. Each root owns its own
    /// NavigationStack. Only ever built for an activated tab, so a tab's onAppear/.task fires the
    /// first time it is selected — never at launch for the unselected four.
    @ViewBuilder
    private func tabRoot(for index: Int) -> some View {
        switch index {
        case 0:
            OverviewView(selectedTab: $selectedTab, deepLinkNoteID: $deepLinkNoteID, activityCategoryFilter: $activityCategoryFilter)
        case 1:
            ExpenseListView(reviewBadgeCount: $reviewBadgeCount, deepLinkCategoryFilter: $activityCategoryFilter)
        case 2:
            BudgetsView()
        case 3:
            NotesHomeView(deepLinkNoteID: $deepLinkNoteID, deepLinkBlockID: $deepLinkBlockID)
        default:
            SettingsView(selectedTab: $selectedTab, lockController: lockController, gmailSyncController: gmailSyncController, transferScanService: transferScanService)
        }
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
