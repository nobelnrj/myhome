import SwiftUI
import SwiftData

/// Holdings CRUD list under Settings > Assets (D-05, ASSET-01, ASSET-02).
///
/// Mirrors `AccountsListView` file-for-file.
/// Pull-to-refresh triggers `amfiNavService.forceRefresh()` + `npsNavService.forceRefresh()` (D-06).
/// Each row shows IconTile (class), name, "class · N units", current value, and StalenessView.
/// Swipe-delete calls `context.delete` + `context.save()` (CR-01).
///
/// Threat mitigations:
/// - T-11-10: All names rendered via plain `Text(...)` — never AttributedString(markdown:).
/// - T-11-SC: No third-party packages used.
struct AssetsListView: View {

    @Environment(\.modelContext) private var context

    /// Holdings sorted newest-first.
    @Query(sort: \Asset.createdAt, order: .reverse) private var allAssets: [Asset]

    /// AMFINavService injected by RootView (Plan 02).
    @Environment(AMFINavService.self) private var amfiNavService

    /// NPSNavService injected by RootView (Plan 11.1-04) — pull-to-refresh must
    /// refresh NPS NAVs too, otherwise NPS holdings only update on the IST-gated
    /// foreground pass with no manual override.
    @Environment(NPSNavService.self) private var npsNavService

    // MARK: - State

    @State private var showAddSheet = false
    @State private var assetToDelete: Asset? = nil
    @State private var showDeleteConfirmation = false

    // MARK: - Body

    var body: some View {
        Group {
            if allAssets.isEmpty {
                ContentUnavailableView(
                    "No Holdings Yet",
                    systemImage: "chart.bar",
                    description: Text("Tap + to add your first holding.")
                )
            } else {
                List {
                    ForEach(allAssets) { asset in
                        NavigationLink(destination: AssetDetailView(asset: asset)) {
                            holdingRow(asset)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                assetToDelete = asset
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    amfiNavService.forceRefresh()
                    npsNavService.forceRefresh()
                }
            }
        }
        .navigationTitle("Assets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Holding")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            EditAssetView(asset: nil)
        }
        .confirmationDialog(
            "Delete Holding?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Holding", role: .destructive) {
                if let a = assetToDelete { deleteAsset(a) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This holding will be permanently removed. This cannot be undone.")
        }
    }

    // MARK: - Holding Row

    @ViewBuilder
    private func holdingRow(_ asset: Asset) -> some View {
        let units = asset.units ?? 0
        let nav = asset.currentNAV
        let currentValue: Decimal? = nav != nil ? units * nav! : nil

        HStack(spacing: 16) {
            IconTile(
                symbol: assetSymbol(asset.assetClassRaw),
                color: assetColor(asset.assetClassRaw),
                size: 30
            )
            VStack(alignment: .leading, spacing: 0) {
                Text(asset.name ?? "—")  // T-11-10: plain Text — never AttributedString(markdown:)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(assetClassLabel(asset.assetClassRaw)) · \(formattedUnits(units)) units")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let value = currentValue {
                    Text(value.formattedINRWhole())
                        .font(.body)
                        .foregroundStyle(.primary)
                } else {
                    Text("—")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                StalenessView(navAsOfDate: asset.navAsOfDate)
            }
        }
        .frame(minHeight: 44)
    }

    // MARK: - Helpers

    private func assetSymbol(_ classRaw: String?) -> String {
        switch classRaw {
        case "mutual_fund": return "chart.bar.fill"
        case "stock":       return "chart.line.uptrend.xyaxis"
        case "nps":         return "umbrella.fill"
        default:            return "chart.bar.fill"
        }
    }

    private func assetColor(_ classRaw: String?) -> Color {
        switch classRaw {
        case "mutual_fund": return Color(.systemBlue)
        case "stock":       return Color(.systemGreen)
        case "nps":         return Color(.systemOrange)
        default:            return Color(.systemBlue)
        }
    }

    private func assetClassLabel(_ classRaw: String?) -> String {
        switch classRaw {
        case "mutual_fund": return "Mutual Fund"
        case "stock":       return "Stock"
        case "nps":         return "NPS"
        default:            return "Mutual Fund"
        }
    }

    private func formattedUnits(_ units: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        return formatter.string(from: units as NSDecimalNumber) ?? "\(units)"
    }

    // MARK: - CRUD Actions

    private func deleteAsset(_ asset: Asset) {
        context.delete(asset)
        do {
            try context.save()  // CR-01: explicit save
        } catch {
            assertionFailure("Failed to delete asset: \(error)")
        }
    }
}
