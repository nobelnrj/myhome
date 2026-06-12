import SwiftUI
import SwiftData

/// Per-holding detail view — current value, gain/loss, staleness, and field breakdown.
///
/// Mirrors `AccountDetailView`: header card (cardStyle()) + detail List (.insetGrouped) + toolbar Edit.
/// Reuses `AssetValuation` for all gain/loss math — never re-derives totalCost/percentGain.
///
/// Gain text always includes explicit "+"/"-" prefix (accessibility — color is not the only signal).
/// AMFI Scheme Code row appears only for mutual_fund holdings.
///
/// Threat mitigations:
/// - T-11-11: percentGain from AssetValuation returns nil when totalCost <= 0; UI shows "—".
/// - T-11-10: all names rendered via plain Text() — never AttributedString(markdown:).
struct AssetDetailView: View {

    var asset: Asset

    // MARK: - State

    @State private var showEditSheet = false

    // MARK: - Computed (reuses AssetValuation — no re-derived math)

    private var currentValue: Decimal {
        AssetValuation.currentValue(units: asset.units, currentNAV: asset.currentNAV)
    }

    private var totalCost: Decimal {
        AssetValuation.totalCost(units: asset.units, costBasisPerUnit: asset.costBasisPerUnit)
    }

    private var absoluteGain: Decimal {
        AssetValuation.absoluteGain(
            units: asset.units,
            costBasisPerUnit: asset.costBasisPerUnit,
            currentNAV: asset.currentNAV
        )
    }

    private var percentGain: Decimal? {
        AssetValuation.percentGain(
            units: asset.units,
            costBasisPerUnit: asset.costBasisPerUnit,
            currentNAV: asset.currentNAV
        )
    }

    private var gainColor: Color {
        if absoluteGain > 0 { return Color(.systemGreen) }
        if absoluteGain < 0 { return Color(.systemRed) }
        return .primary
    }

    private var assetClassLabel: String {
        switch asset.assetClassRaw {
        case "mutual_fund": return "Mutual Fund"
        case "stock":       return "Stock"
        case "nps":         return "NPS"
        default:            return "Holding"
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            // Header card pinned as first section (mirrors AccountDetailView.balanceCard pattern)
            Section {
                headerCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // Detail rows
            Section {
                detailRow("Units", value: formattedUnits(asset.units))
                detailRow("Cost per unit", value: asset.costBasisPerUnit?.formattedINR() ?? "—")
                detailRow("Total cost", value: totalCost.formattedINRWhole())
                detailRow(navLabel, value: asset.currentNAV?.formattedINR() ?? "—")
                gainLossRow
                if asset.assetClassRaw == "mutual_fund" {
                    detailRow("AMFI Scheme Code", value: asset.amfiSchemeCode ?? "—")
                }
            }

            // SIP history + reconcile (mirrors EditAssetView SIP section style)
            Section("SIP") {
                NavigationLink(destination: ContributionLogView(asset: asset)) {
                    Text("Contributions")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(minHeight: 44)
                }
                NavigationLink(destination: ReconcileView(asset: asset)) {
                    Text("Reconcile units")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(minHeight: 44)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(asset.name ?? "Holding")  // T-11-10: plain string access
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEditSheet = true }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditAssetView(asset: asset)
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(assetClassLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if asset.currentNAV != nil {
                Text(currentValue.formattedINRWhole())
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityValue(currentValue.formattedINRWhole())
            } else {
                Text("—")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(asset.name ?? "—")  // T-11-10: plain Text — no AttributedString
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                StalenessView(navAsOfDate: asset.navAsOfDate)
                if let navDate = asset.navAsOfDate {
                    Text("as of \(navDate.formatted(.dateTime.day().month(.abbreviated).year()))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("price not set")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Gain/Loss Row

    private var gainLossRow: some View {
        HStack {
            Text("Gain / Loss")
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    // Absolute gain with explicit +/- prefix (accessibility — color not only signal)
                    Text(formattedAbsoluteGain)
                        .font(.body)
                        .foregroundStyle(gainColor)
                    if let pct = percentGain {
                        Text("(\(formattedPercent(pct)))")
                            .font(.body)
                            .foregroundStyle(gainColor)
                    } else {
                        // T-11-11: zero cost basis — show "—" for %, never crash
                        Text("(—)")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(minHeight: 44)
    }

    // MARK: - Row Helpers

    @ViewBuilder
    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
    }

    private var navLabel: String {
        asset.assetClassRaw == "mutual_fund" ? "Current NAV" : "Current Price"
    }

    private var formattedAbsoluteGain: String {
        if absoluteGain > 0 {
            return "+\(absoluteGain.formattedINRWhole())"
        } else if absoluteGain < 0 {
            // formattedINRWhole() already adds "-" for negatives
            return absoluteGain.formattedINRWhole()
        } else {
            return absoluteGain.formattedINRWhole()
        }
    }

    private func formattedPercent(_ pct: Decimal) -> String {
        let sign = pct >= 0 ? "+" : ""
        let formatted = NSDecimalNumber(decimal: abs(pct)).doubleValue
        let pctStr = String(format: "%.2f", formatted)
        if pct >= 0 {
            return "+\(pctStr)%"
        } else {
            return "−\(pctStr)%"
        }
    }

    private func formattedUnits(_ units: Decimal?) -> String {
        guard let u = units else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        return formatter.string(from: u as NSDecimalNumber) ?? "\(u)"
    }
}
