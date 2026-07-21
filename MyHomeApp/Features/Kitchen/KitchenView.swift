import SwiftUI
import SwiftData

/// The Kitchen surface — pantry inventory (KTCH-01, KTCH-02).
///
/// PUSHED destination from Overview (see `20-03-PLAN.md`): the native TabView already holds the
/// iOS maximum of 5 tabs before a "More" spillover appears, and Assets/Analytics set the exact
/// precedent. So this view does NOT own a NavigationStack — Overview's stack hosts it, and the
/// existing `-startTab` indices 0–4 stay byte-identical.
///
/// Layout matches `20-REF-pantry.png`: "RUNNING LOW" (out first, then low) above "STOCKED", each
/// a single raised `.neuSurface` card of Divider-separated rows, with a right-aligned count on the
/// section header.
///
/// 20-04 lifts this pantry content into a `Pantry | Shopping` segmented host; keeping the content
/// in a private subview here makes that a move, not a rewrite.
struct KitchenView: View {

    @Query(sort: \PantryItem.name) private var pantry: [PantryItem]

    @State private var showAddSheet = false
    @State private var editingItem: PantryItem?

    private var lowOrOut: [PantryItem] {
        pantry
            .filter { KitchenLogic.stockStatus(for: $0) != .inStock }
            .sorted { a, b in
                let sa = KitchenLogic.stockStatus(for: a)
                let sb = KitchenLogic.stockStatus(for: b)
                if sa != sb { return sa == .out }        // out of stock first
                return (a.name ?? "") < (b.name ?? "")
            }
    }

    private var stocked: [PantryItem] {
        pantry.filter { KitchenLogic.stockStatus(for: $0) == .inStock }
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: DesignTokens.spacing16) {
                if pantry.isEmpty {
                    emptyState
                        .entrance(0)
                } else {
                    if !lowOrOut.isEmpty {
                        sectionHeader("Running low", count: lowOrOut.count)
                        itemCard(lowOrOut)
                            .entrance(0)
                    }
                    if !stocked.isEmpty {
                        sectionHeader("Stocked", count: stocked.count)
                        itemCard(stocked)
                            .entrance(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(DesignTokens.bgCanvas)
        .navigationTitle("Kitchen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add pantry item")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            EditPantryItemView(item: nil)
        }
        .sheet(item: $editingItem) { item in
            EditPantryItemView(item: item)
        }
        #if DEBUG
        // Screenshot-verify hook: `-editFirstPantryItem` opens the edit sheet on the first row
        // (the sheet is otherwise only reachable by tapping, which simctl cannot do).
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-editFirstPantryItem") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    editingItem = lowOrOut.first ?? pantry.first
                }
            }
        }
        #endif
    }

    // MARK: - Pieces

    @ViewBuilder
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).eyebrow()
            Spacer()
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.label3)
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, -8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) items")
    }

    @ViewBuilder
    private func itemCard(_ items: [PantryItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                PantryItemRow(item: item) { editingItem = item }
                if index < items.count - 1 {
                    Divider().padding(.leading, 64)
                }
            }
        }
        .neuSurface(.raised, padding: nil)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "basket")
                .font(.system(size: 30))
                .foregroundStyle(DesignTokens.accentText)
                .frame(width: 62, height: 62)
                .background(DesignTokens.fillRecessed, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("Your pantry is empty")
                .font(.headline)
                .foregroundStyle(DesignTokens.label)
            Text("Add your staples — anything that runs low will show up here and on the shopping list.")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.label2)
                .multilineTextAlignment(.center)
            Button("Add an item") { showAddSheet = true }
                .buttonStyle(NeuSecondaryButtonStyle(
                    expands: false, fontSize: 15, verticalPadding: 12, horizontalPadding: 24
                ))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .neuSurface(.floating, padding: 24)
        .padding(.top, 24)
    }
}
