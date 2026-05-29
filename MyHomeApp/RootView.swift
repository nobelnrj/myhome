import SwiftUI

/// Root navigation host.
/// Wires to ExpenseListView which owns its own NavigationStack.
struct RootView: View {
    var body: some View {
        ExpenseListView()
    }
}
