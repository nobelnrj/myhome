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

    @State private var showManageCategories = false

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
