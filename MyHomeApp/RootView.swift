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

    @State private var selectedTab: Int = 0
    @State private var deepLinkNoteID: UUID? = nil
    /// CR-03: Thread blockID deep-link through the view hierarchy so EditNoteView can
    /// scroll to and highlight the target block row when a block-level reminder is tapped.
    @State private var deepLinkBlockID: UUID? = nil
    /// Face ID gate state — @Observable owned via @State, never @StateObject (PITFALLS.md Pitfall 10)
    @State private var lockController = LockController()
    @State private var routineResetService = RoutineResetService()

    /// Gmail sync controller — owned by MyHomeApp, passed in here (Phase 7: BGTask ownership).
    let gmailSyncController: GmailSyncController

    /// Review-inbox badge count — updated by ExpenseListView via @Binding (D7-04).
    @State private var reviewBadgeCount: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView(selectedTab: $selectedTab, deepLinkNoteID: $deepLinkNoteID)
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(0)

            ExpenseListView(reviewBadgeCount: $reviewBadgeCount)
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

            SettingsView(selectedTab: $selectedTab, lockController: lockController, gmailSyncController: gmailSyncController)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(4)
        }
        .onAppear {
            // Inject the SwiftData context into the sync controller so sync() can persist
            // ingested expenses. Called here (not in init) so the @Environment is populated.
            gmailSyncController.setContext(modelContext)
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
             }
             // Auto-trigger auth on foreground when locked (banking-app feel — D5-02, D5-01)
             // Pitfall: never call async directly in onChange; always wrap in Task
             if newPhase == .active && lockController.isLocked && lockController.lockEnabled {
                 Task { await lockController.authenticate() }
             }
         }
    }
}
