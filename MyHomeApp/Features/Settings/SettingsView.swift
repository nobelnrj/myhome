import SwiftUI

/// Settings tab (tag 4) — Face ID toggle, Manage Categories sheet, Budgets deep-link, About footer.
///
/// Security:
/// - Face ID Lock toggle uses a custom Binding that calls auth-gated enableLock()/disableLock().
///   The toggle never flips the flag without authentication success (T-05-03, D5-07a/b, SEC-01).
///
/// Data:
/// - "Manage Categories" presents ManageCategoriesView as a .sheet (D5-09).
/// - "Budgets" switches to tab 2 via selectedTab binding (D5-08) — no budget UI duplicated here.
///
/// About footer: reads version/build from Bundle.main (D5-10, D5-12 discretion).
/// No Gmail placeholder rows (D5-10).
struct SettingsView: View {

    @Binding var selectedTab: Int
    let lockController: LockController
    let gmailSyncController: GmailSyncController

    @State private var showManageCategories = false
    @State private var showSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            List {

                // MARK: Security Section

                Section("Security") {
                    Toggle("Face ID Lock", isOn: Binding(
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
                    ))
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
                            Button("Connect Gmail") {
                                Task { await gmailSyncController.signIn() }
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
                            Text("Connected as: \(email)")
                                .font(.subheadline)
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
                    Button("Manage Categories") {
                        showManageCategories = true
                    }

                    Button {
                        selectedTab = 2
                    } label: {
                        HStack {
                            Text("Budgets")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                // MARK: About Section (footer — no header)

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MyHome")
                            .font(.subheadline)
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

    // MARK: - Version String

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (Build \(build))"
    }
}
