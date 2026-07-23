import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// Settings tab (tag 4) — Face ID toggle, Manage Categories sheet, Budgets deep-link, About footer.
///
/// Gmail Section (multi-account, D-MA-05, 260603-lvt):
/// - When no accounts are connected: shows "Connect Gmail" button + authorizing/error states.
/// - When one or more accounts are connected: renders one row per account (email + last-synced
///   + per-account Reconnect/Disconnect). Below the list: "Add account" + overall "Sync now".
/// - BGAppRefreshTask still drives gmailSyncController.sync() (the multi-account loop) unchanged.
///
/// Security:
/// - Face ID Lock toggle uses a custom Binding that calls auth-gated enableLock()/disableLock().
///   The toggle never flips the flag without authentication success (T-05-03, D5-07a/b, SEC-01).
struct SettingsView: View {

    @Binding var selectedTab: Int
    let lockController: LockController
    let gmailSyncController: GmailSyncController
    let transferScanService: TransferScanService

    @Environment(\.modelContext) private var modelContext
    /// SYNC-05: the P2P auto-sync coordinator (injected in MyHomeApp) — drives the Sync row's
    /// glanceable last-synced text and the Sync destination screen.
    @Environment(SyncCoordinator.self) private var syncCoordinator

    @State private var showManageCategories = false
    /// True while an enable/disable auth task is in flight — prevents toggle flicker (WR-01).
    @State private var isTogglingLock = false
    /// DEBUG screenshot-verify hook: `-openSync` pushes the Sync screen on launch (a navigation
    /// push, unreachable via -startTab) — mirrors OverviewView's `-openAnalytics` convention.
    @State private var navigateToSync = false
    @State private var showSignOutAllConfirmation = false
    @State private var pendingDisconnectEmail: String? = nil

    // MARK: Sync snapshot (SYNC-03)
    /// The exported `.myhomesnap` temp file to share (drives the share sheet). Nil when idle.
    @State private var exportShareURL: IdentifiableURL? = nil
    /// Drives the Files picker for choosing a snapshot to import.
    @State private var showSnapshotImporter = false
    /// The snapshot file the user picked to import (drives the confirm-merge sheet).
    @State private var importPickedURL: IdentifiableURL? = nil
    /// Export failure message (plain alert).
    @State private var exportErrorMessage: String? = nil
    @State private var accountReviewPending: Bool =
        UserDefaults.standard.bool(forKey: "accountReviewPending")

    /// All accounts — used only to confirm auto-created accounts actually exist before
    /// showing the review badge, so a stale `accountReviewPending` flag never shows a badge
    /// that leads to an empty review sheet.
    @Query private var accounts: [Account]
    private var hasAutoCreatedAccounts: Bool { accounts.contains { $0.sourceLabel != nil } }

    var body: some View {
        NavigationStack {
            List {

                // MARK: Profile Header

                Section {
                    profileHeader
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                // MARK: Appearance Section (D-03)

                // Neumorphic System/Light/Dark segmented pill bound to the same
                // @AppStorage("appearanceTheme") key as the app root — flipping it re-themes
                // the app live. Placed near the top, above Security.
                Section("Appearance") {
                    AppearanceSegmentedRow()
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
                .listRowBackground(DesignTokens.surfaceRaised)

                // MARK: Security Section

                Section("Security") {
                    Toggle(isOn: Binding(
                        get: { lockController.lockEnabled },
                        set: { newValue in
                            guard !isTogglingLock else { return }
                            isTogglingLock = true
                            Task {
                                if newValue {
                                    await lockController.enableLock()
                                } else {
                                    await lockController.disableLock()
                                }
                                isTogglingLock = false
                            }
                        }
                    )) {
                        rowLabel("Face ID Lock", symbol: "faceid", color: DesignTokens.positive)
                    }
                    .tint(DesignTokens.accent)
                    .disabled(isTogglingLock)
                }
                .listRowBackground(DesignTokens.surfaceRaised)

                // MARK: Notifications Section

                Section("Notifications") {
                    rowLabel("Notifications", symbol: "bell", color: DesignTokens.negative)
                }
                .listRowBackground(DesignTokens.surfaceRaised)

                // MARK: Gmail Section (multi-account, D-MA-05)

                Section("Gmail") {
                    let accounts = gmailSyncController.store.accounts

                    if accounts.isEmpty {
                        // No accounts connected — show Connect button or authorizing state
                        if gmailSyncController.syncStatus == .authorizing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Connecting…")
                                    .font(.subheadline)
                                Spacer()
                            }
                        } else {
                            Button {
                                Task { await gmailSyncController.signIn() }
                            } label: {
                                rowLabel("Connect Gmail", symbol: "envelope", color: DesignTokens.negative)
                            }
                        }

                        // Surface sign-in errors while disconnected
                        if case let .error(msg) = gmailSyncController.syncStatus {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(msg)
                                    .font(.subheadline)
                                    .foregroundStyle(DesignTokens.negative)
                                Button("Try again") {
                                    Task { await gmailSyncController.signIn() }
                                }
                                .font(.subheadline)
                            }
                        }
                    } else {
                        // One or more accounts connected — per-account rows (D-MA-05)
                        ForEach(accounts, id: \.email) { account in
                            accountRow(account)
                        }

                        // Syncing indicator
                        if gmailSyncController.syncStatus == .syncing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Syncing…")
                                    .font(.subheadline)
                                Spacer()
                            }
                        }

                        // Global error display
                        if case let .error(msg) = gmailSyncController.syncStatus {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(msg)
                                    .font(.subheadline)
                                    .foregroundStyle(DesignTokens.negative)
                                Button("Try again") {
                                    Task { await gmailSyncController.sync() }
                                }
                                .font(.subheadline)
                            }
                        }

                        // Add account button (calls signIn — adds to existing, no clobber)
                        Button {
                            Task { await gmailSyncController.signIn() }
                        } label: {
                            rowLabel("Add account", symbol: "plus.circle", color: DesignTokens.accent)
                        }
                        .disabled(gmailSyncController.syncStatus == .authorizing ||
                                  gmailSyncController.syncStatus == .syncing)

                        // Overall "Sync now" syncs all accounts
                        Button("Sync now") {
                            Task { await gmailSyncController.sync() }
                        }
                        .foregroundStyle(DesignTokens.accentText)
                        .disabled(gmailSyncController.syncStatus == .syncing)
                    }
                }
                // Per-account disconnect confirmation dialog
                .confirmationDialog(
                    "Disconnect \(pendingDisconnectEmail ?? "account")?",
                    isPresented: Binding(
                        get: { pendingDisconnectEmail != nil },
                        set: { if !$0 { pendingDisconnectEmail = nil } }
                    )
                ) {
                    if let email = pendingDisconnectEmail {
                        Button("Disconnect", role: .destructive) {
                            gmailSyncController.signOut(email: email)
                            pendingDisconnectEmail = nil
                        }
                        Button("Cancel", role: .cancel) {
                            pendingDisconnectEmail = nil
                        }
                    }
                }
                .listRowBackground(DesignTokens.surfaceRaised)

                // MARK: Data Section

                Section("Data") {
                    // Scan for Transfers — on-demand transfer pair detection (D-08, XFER-01)
                    Button {
                        transferScanService.scan()
                    } label: {
                        HStack {
                            rowLabel("Scan for Transfers", symbol: "arrow.left.arrow.right", color: DesignTokens.catRent)
                            Spacer()
                            // First-run hint: surface when the initial full scan hasn't been done yet
                            if !UserDefaults.standard.bool(forKey: "transferScanFirstRunDone") {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(DesignTokens.orange)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .foregroundStyle(DesignTokens.label2)

                    // Accounts management row (D-06) with optional review badge (D-02)
                    NavigationLink(destination: AccountsListView()) {
                        HStack {
                            rowLabel("Accounts", symbol: "creditcard", color: DesignTokens.catSubscriptions)
                            Spacer()
                            // D-02: badge when review is pending AND auto-created accounts
                            // actually exist (guards against a stale flag — see hasAutoCreatedAccounts)
                            if accountReviewPending && hasAutoCreatedAccounts {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(DesignTokens.orange)
                                    .font(.subheadline)
                            }
                        }
                    }

                    // Assets holdings management (D-05, Phase 11)
                    NavigationLink(destination: AssetsListView()) {
                        rowLabel("Assets", symbol: "chart.bar", color: DesignTokens.catHealth)
                    }

                    Button {
                        showManageCategories = true
                    } label: {
                        rowLabel("Manage Categories", symbol: "square.grid.2x2", color: DesignTokens.catRent)
                    }

                    Button {
                        selectedTab = 2
                    } label: {
                        HStack {
                            rowLabel("Budgets", symbol: "chart.pie", color: DesignTokens.accent)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(DesignTokens.label3)
                        }
                    }
                    .foregroundStyle(DesignTokens.label2)

                    // MARK: P2P auto-sync surface (SYNC-05) — status + Sync Now
                    NavigationLink(destination: SyncStatusView()) {
                        HStack {
                            rowLabel("Sync", symbol: "arrow.triangle.2.circlepath", color: DesignTokens.catAuto)
                            Spacer()
                            // Glanceable last-synced so the state is legible without drilling in.
                            Text(SyncStatusPresentation.relativeLastSynced(syncCoordinator.statusStore.lastSyncedAt))
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.label3)
                        }
                    }

                    // MARK: Sync snapshot (SYNC-03) — export via share sheet / AirDrop
                    Button {
                        exportSnapshot()
                    } label: {
                        rowLabel("Export Sync Snapshot", symbol: "square.and.arrow.up", color: DesignTokens.positive)
                    }
                    .foregroundStyle(DesignTokens.label2)

                    // Import a `.myhomesnap` via the Files picker (AirDrop-open also routes here
                    // through onOpenURL). Feeds the same confirm-merge sheet.
                    Button {
                        showSnapshotImporter = true
                    } label: {
                        rowLabel("Import Snapshot…", symbol: "square.and.arrow.down", color: DesignTokens.accent)
                    }
                    .foregroundStyle(DesignTokens.label2)
                }
                .listRowBackground(DesignTokens.surfaceRaised)

                // MARK: Preferences Section

                Section("Preferences") {
                    rowLabel("Currency", symbol: "indianrupeesign.circle", color: DesignTokens.positive)
                    rowLabel("Budget period", symbol: "calendar", color: DesignTokens.orange)
                }
                .listRowBackground(DesignTokens.surfaceRaised)

                // MARK: About Section (footer)

                Section {
                    HStack {
                        rowLabel("About MyHome", symbol: "house", color: DesignTokens.accent)
                        Spacer()
                        Text(versionString)
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.label3)
                    }
                }
                .listRowBackground(DesignTokens.surfaceRaised)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DesignTokens.bgCanvas)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $navigateToSync) {
                SyncStatusView()
            }
            #if DEBUG
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-openSync") {
                    navigateToSync = true
                }
            }
            #endif
        }
        .sheet(isPresented: $showManageCategories) {
            ManageCategoriesView()
        }
        // SYNC-03: export share sheet (AirDrop / Save to Files) for the generated snapshot file.
        .sheet(item: $exportShareURL) { item in
            ActivityShareSheet(activityItems: [item.url])
        }
        // SYNC-03: confirm-merge sheet for a Files-picked snapshot.
        .sheet(item: $importPickedURL) { item in
            SnapshotImportSheet(fileURL: item.url)
        }
        // SYNC-03: Files picker filtered to the custom UTType.
        .fileImporter(
            isPresented: $showSnapshotImporter,
            allowedContentTypes: [.myHomeSnapshot],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first { importPickedURL = IdentifiableURL(url: url) }
            case let .failure(error):
                exportErrorMessage = error.localizedDescription
            }
        }
        .alert(
            "Export failed",
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    // MARK: - Sync snapshot export (SYNC-03)

    /// Export the full store to canonical `.myhomesnap` bytes, write a temp file, and present the
    /// share sheet (the user picks AirDrop / Save to Files there). Errors surface in a plain alert.
    private func exportSnapshot() {
        do {
            let data = try SnapshotExporter.exportData(context: modelContext, deviceName: UIDevice.current.name)
            let url = try SnapshotFile.writeTemporary(data: data, deviceName: UIDevice.current.name)
            exportShareURL = IdentifiableURL(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Per-account Row (D-MA-05)

    /// Renders one row per connected account: email + last-synced + Reconnect/Disconnect affordances.
    private func accountRow(_ account: GmailAccount) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "envelope.circle.fill")
                    .foregroundStyle(DesignTokens.negative)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let lastSynced = account.lastSyncedAt {
                        Text("Last synced \(lastSynced.relativeToNow)")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.label2)
                    } else {
                        Text("Never synced")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.label2)
                    }
                }
                Spacer()
                // Per-account actions
                VStack(alignment: .trailing, spacing: 4) {
                    if account.needsReconnect {
                        Button("Reconnect") {
                            Task { await gmailSyncController.signIn() }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.negative)
                    }
                    Button("Disconnect") {
                        pendingDisconnectEmail = account.email
                    }
                    .font(.caption)
                    .foregroundStyle(DesignTokens.negative)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [DesignTokens.accent, DesignTokens.accent.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 56, height: 56)
                .overlay(
                    Group {
                        if let initial = avatarInitial {
                            Text(initial)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(DesignTokens.accentOnYellow)
                        } else {
                            Image(systemName: "person.fill")
                                .font(.title2)
                                .foregroundStyle(DesignTokens.accentOnYellow)
                        }
                    }
                )
            VStack(alignment: .leading, spacing: 2) {
                // Show primary account email or "MyHome" if no accounts
                Text(gmailSyncController.connectedEmail ?? "MyHome")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                let accountCount = gmailSyncController.store.accounts.count
                if accountCount == 0 {
                    Text("Not connected")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.label2)
                } else if accountCount == 1 {
                    Text("Gmail connected")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.label2)
                } else {
                    Text("\(accountCount) Gmail accounts")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.label2)
                }
            }
            Spacer(minLength: 0)
        }
        .neuSurface(.raised, radius: 20)
    }

    private var avatarInitial: String? {
        guard let first = gmailSyncController.connectedEmail?.first else { return nil }
        return String(first).uppercased()
    }

    // MARK: - Row Label

    private func rowLabel(_ title: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color, size: 29)
            Text(title)
                .foregroundStyle(DesignTokens.label2)
        }
    }

    // MARK: - Version String

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (Build \(build))"
    }
}

// MARK: - Appearance Segmented Row (D-03)

/// Custom neumorphic 3-segment pill (System/Light/Dark) — NOT `Picker(.segmented)`.
///
/// Recessed track: a Capsule filled with `fillRecessed3`, a top shade band, and a dark→light
/// hairline stroke — the `EmbossedBar`/`VerticalPillGauge` well recipe. The active segment is a
/// raised Capsule with the `surfaceRaisedStrong` diagonal gradient + rim stroke (the
/// `NeuSecondaryButtonStyle` pill look), sliding between segments via `matchedGeometryEffect`
/// with `springBouncy`. Reduce Motion skips the slide (matches `EntranceModifier`'s guard).
///
/// Bound to `@AppStorage("appearanceTheme")` — the SAME key the app root reads — so a flip
/// re-themes the app live. The theme-flip transition itself is SwiftUI's default environment
/// change (no crossfade added here; Plan 07 evaluates jarring-ness on device).
private struct AppearanceSegmentedRow: View {
    @AppStorage("appearanceTheme") private var appearanceThemeRaw = AppearanceTheme.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var segmentNamespace

    private var selection: AppearanceTheme {
        AppearanceTheme(rawValue: appearanceThemeRaw) ?? .system
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppearanceTheme.allCases, id: \.self) { theme in
                segment(theme)
            }
        }
        .padding(4)
        .background(recessedTrack)
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance")
    }

    private func segment(_ theme: AppearanceTheme) -> some View {
        let isSelected = theme == selection
        return Text(theme.label)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isSelected ? DesignTokens.label : DesignTokens.label2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Capsule())
            .background {
                if isSelected {
                    activePill
                        .matchedGeometryEffect(id: "appearanceActiveSegment", in: segmentNamespace)
                }
            }
            .onTapGesture { select(theme) }
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func select(_ theme: AppearanceTheme) {
        guard theme != selection else { return }
        Haptics.selection()
        if reduceMotion {
            appearanceThemeRaw = theme.rawValue
        } else {
            withAnimation(DesignTokens.springBouncy) {
                appearanceThemeRaw = theme.rawValue
            }
        }
    }

    /// Recessed pill track — `fillRecessed3` well + top shade band + dark→light hairline
    /// (the `EmbossedBar` track recipe, NeuSurface.swift).
    private var recessedTrack: some View {
        Capsule()
            .fill(DesignTokens.fillRecessed3)
            .overlay(
                Capsule().fill(
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.35), location: 0),
                        .init(color: .clear, location: 0.55)
                    ], startPoint: .top, endPoint: .bottom)
                )
            )
            .overlay(
                Capsule().stroke(
                    LinearGradient(colors: [.black.opacity(0.55), .white.opacity(0.04)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            )
    }

    /// Raised active segment — `surfaceRaisedStrong` diagonal gradient + white/black rim
    /// (the `NeuSecondaryButtonStyle` pill look) with a soft depth shadow.
    private var activePill: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [DesignTokens.surfaceRaisedStrongTop,
                             DesignTokens.surfaceRaisedStrongBottom],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.07), Color.black.opacity(0.35)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
            .shadow(color: .black.opacity(0.25), radius: 4, x: 2, y: 2)
    }
}
