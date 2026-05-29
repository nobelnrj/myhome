import SwiftUI

/// Root navigation container.
/// Plan 03 will replace this placeholder with ExpenseListView
/// once the @Model schema (plan 02) is in place.
struct RootView: View {
    var body: some View {
        NavigationStack {
            ContentView()
        }
    }
}

private struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "house")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            Text("My Home")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Expense tracker coming soon.")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("My Home")
    }
}
