import SwiftUI
import SwiftData

/// The Kitchen surface — `Pantry | Shopping` segmented host (KTCH-01, KTCH-02, KTCH-03).
///
/// PUSHED destination from Overview (see `20-03-PLAN.md`): the native TabView already holds the
/// iOS maximum of 5 tabs before a "More" spillover appears, and Assets/Analytics set the exact
/// precedent. So this view does NOT own a NavigationStack — Overview's stack hosts it, and the
/// existing `-startTab` indices 0–4 stay byte-identical.
///
/// Layout matches `20-REF-pantry.png` / `20-REF-shopping.png`: a neumorphic segmented control
/// directly under the inline title (the Shopping segment carries an accent count pill when
/// something needs buying), then the segment's own content.
///
/// 20-04 lifted the pantry content into `PantryListView` unchanged — a move, not a rewrite.
struct KitchenView: View {

    enum KitchenSegment: Int, CaseIterable {
        case pantry
        case shopping

        var label: String {
            switch self {
            case .pantry: return "Pantry"
            case .shopping: return "Shopping"
            }
        }
    }

    @Query(sort: \PantryItem.name) private var pantry: [PantryItem]
    @Query private var extras: [ShoppingListItem]

    @State private var segment: KitchenSegment = .pantry
    @State private var showAddSheet = false

    /// Badge on the Shopping segment: everything still to buy — derived restock rows plus
    /// unchecked manual extras.
    private var shoppingCount: Int {
        KitchenLogic.deriveShoppingItems(from: pantry).count + extras.filter { !$0.isChecked }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            segmentedHeader

            switch segment {
            case .pantry:
                PantryListView(showAddSheet: $showAddSheet)
            case .shopping:
                ShoppingListView()
            }
        }
        .background(DesignTokens.bgCanvas)
        .navigationTitle("Kitchen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if segment == .pantry {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add pantry item")
                }
            }
        }
        #if DEBUG
        // Screenshot-verify hook: simctl cannot tap the picker, so `-kitchenTab 1` opens the
        // Shopping segment directly (mirrors the existing `-startTab` hook style).
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-kitchenTab"), i + 1 < args.count,
               let raw = Int(args[i + 1]), let requested = KitchenSegment(rawValue: raw) {
                segment = requested
            }
        }
        #endif
    }

    // MARK: - Segmented header

    @ViewBuilder
    private var segmentedHeader: some View {
        HStack(spacing: 4) {
            ForEach(KitchenSegment.allCases, id: \.self) { item in
                Button {
                    guard segment != item else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { segment = item }
                    Haptics.selection()
                } label: {
                    HStack(spacing: 8) {
                        Text(item.label)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(segment == item ? DesignTokens.accentText : DesignTokens.label2)
                        if item == .shopping, shoppingCount > 0 {
                            Text("\(shoppingCount)")
                                .font(.system(size: 13, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(DesignTokens.bgCanvas)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(DesignTokens.orange))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if segment == item {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(DesignTokens.bgCanvas)
                                .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 3)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    item == .shopping && shoppingCount > 0
                        ? "Shopping, \(shoppingCount) items to buy"
                        : item.label
                )
                .accessibilityAddTraits(segment == item ? [.isSelected] : [])
            }
        }
        .padding(4)
        .neuSurface(.recessed, radius: 20, padding: nil)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - Pantry segment

/// The pantry inventory list (KTCH-01, KTCH-02) — unchanged 20-03 content, lifted out of
/// `KitchenView` so the segmented host stays thin.
///
/// "RUNNING LOW" (out first, then low) above "STOCKED", each a single raised `.neuSurface` card of
/// Divider-separated rows with a right-aligned count on the section header.
struct PantryListView: View {

    @Binding var showAddSheet: Bool

    @Query(sort: \PantryItem.name) private var pantry: [PantryItem]

    @State private var editingItem: PantryItem?

    private var lowOrOut: [PantryItem] {
        KitchenLogic.deriveShoppingItems(from: pantry)
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
