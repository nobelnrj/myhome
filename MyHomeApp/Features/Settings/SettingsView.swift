import SwiftUI

/// Settings tab (tag 4) — Face ID toggle, Manage Categories sheet, Budgets deep-link, About footer.
///
/// Restyled to the `MyHome.html` design: a profile header card plus colored `IconTile` glyphs on
/// each row. **All behavior is unchanged** — the Face-ID-gated toggle binding, the full Gmail
/// connect/sync/sign-out logic, Manage Categories sheet, and Budgets deep-link are identical to
/// before; only the row presentation changed.
///
/// Security:
/// - Face ID Lock toggle uses a custom Binding that calls auth-gated enableLock()/disableLock().
///   The toggle never flips the flag without authentication success (T-05-03, D5-07a/b, SEC-01).
struct SettingsView: View {

    @Binding var selectedTab: Int
    let lockController: LockController
    let gmailSyncController: GmailSyncController

    @State private var showManageCategories = false
    @State private var showSignOutConfirmation = false

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

                // MARK: Gmail Section

                Section("Gmail") {
                    if !gmailSyncController.isConnected {
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

                        // Surface sign-in errors while still disconnected (otherwise the
                        // error case below — nested in the connected branch — never renders).
                        if case let .error(msg) = gmailSyncController.syncStatus {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(msg)
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                                Button("Try again", action: {
                                    Task { await gmailSyncController.signIn() }
                                })
                                .font(.subheadline)
                            }
                        }
                    } else {
                        if let email = gmailSyncController.connectedEmail {
                            HStack {
                                rowLabel("Gmail", symbol: "envelope", color: Color(.systemRed))
                                Spacer()
                                Text(email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        HStack {
                            Text("Last synced")
                            Spacer()
                            if let lastSynced = gmailSyncController.lastSyncedAt {
                                Text(lastSynced.relativeToNow)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Never")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if gmailSyncController.syncStatus == .syncing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Syncing…")
                                    .font(.subheadline)
                                Spacer()
                            }
                        } else {
                            Button("Sync now") {
                                Task { await gmailSyncController.sync() }
                            }
                            .disabled(gmailSyncController.syncStatus == .syncing)
                        }

                        if gmailSyncController.syncStatus == .tokenExpired {
                            Button("Reconnect Gmail", action: {
                                Task { await gmailSyncController.signIn() }
                            })
                            .foregroundStyle(.orange)
                        }

                        if case let .error(msg) = gmailSyncController.syncStatus {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(msg)
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                                Button("Try again", action: {
                                    Task { await gmailSyncController.sync() }
                                })
                                .font(.subheadline)
                            }
                        }

                        Button("Sign out", action: {
                            showSignOutConfirmation = true
                        })
                        .foregroundStyle(.red)
                    }
                }
                .confirmationDialog("Sign out of Gmail?", isPresented: $showSignOutConfirmation) {
                    Button("Sign out", role: .destructive) {
                        Task { await gmailSyncController.signOut() }
                    }
                    Button("Cancel", role: .cancel) { }
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

                // MARK: About Section (footer — no header)

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
                Text(gmailSyncController.connectedEmail ?? "MyHome")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(gmailSyncController.isConnected ? "Gmail connected" : "Not connected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

    /// A standard settings row label: colored `IconTile` + title. Wrapping existing buttons /
    /// toggles in this keeps their behavior unchanged while matching the design.
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
