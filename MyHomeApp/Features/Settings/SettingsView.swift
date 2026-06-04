import SwiftUI

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

    @State private var showManageCategories = false
    @State private var showSignOutAllConfirmation = false
    @State private var pendingDisconnectEmail: String? = nil

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

                // MARK: Security Section

                Section("Security") {
                    Toggle(isOn: Binding(
                        get: { lockController.lockEnabled },
                        set: { newValue in
                            Task {
                                if newValue {
                                    await lockController.enableLock()
                                } else {
                                    await lockController.disableLock()
                                }
                            }
                        }
                    )) {
                        rowLabel("Face ID Lock", symbol: "faceid", color: Color(.systemGreen))
                    }
                }

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
                                rowLabel("Connect Gmail", symbol: "envelope", color: Color(.systemRed))
                            }
                        }

                        // Surface sign-in errors while disconnected
                        if case let .error(msg) = gmailSyncController.syncStatus {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(msg)
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
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
                                    .foregroundStyle(.red)
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
                            rowLabel("Add account", symbol: "plus.circle", color: Color(.systemBlue))
                        }
                        .disabled(gmailSyncController.syncStatus == .authorizing ||
                                  gmailSyncController.syncStatus == .syncing)

                        // Overall "Sync now" syncs all accounts
                        Button("Sync now") {
                            Task { await gmailSyncController.sync() }
                        }
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

                // MARK: Data Section

                Section("Data") {
                    Button {
                        showManageCategories = true
                    } label: {
                        rowLabel("Manage Categories", symbol: "square.grid.2x2", color: Color(.systemIndigo))
                    }

                    Button {
                        selectedTab = 2
                    } label: {
                        HStack {
                            rowLabel("Budgets", symbol: "chart.pie", color: .accentColor)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                // MARK: About Section (footer)

                Section {
                    HStack {
                        rowLabel("About MyHome", symbol: "house", color: .accentColor)
                        Spacer()
                        Text(versionString)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showManageCategories) {
            ManageCategoriesView()
        }
    }

    // MARK: - Per-account Row (D-MA-05)

    /// Renders one row per connected account: email + last-synced + Reconnect/Disconnect affordances.
    private func accountRow(_ account: GmailAccount) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "envelope.circle.fill")
                    .foregroundStyle(Color(.systemRed))
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let lastSynced = account.lastSyncedAt {
                        Text("Last synced \(lastSynced.relativeToNow)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never synced")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                        .foregroundStyle(.orange)
                    }
                    Button("Disconnect") {
                        pendingDisconnectEmail = account.email
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
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
                        colors: [.accentColor, .accentColor.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 56, height: 56)
                .overlay(
                    Group {
                        if let initial = avatarInitial {
                            Text(initial)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: "person.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
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
                        .foregroundStyle(.secondary)
                } else if accountCount == 1 {
                    Text("Gmail connected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(accountCount) Gmail accounts")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .cardStyle(cornerRadius: 14)
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
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Version String

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (Build \(build))"
    }
}
