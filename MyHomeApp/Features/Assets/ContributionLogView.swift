import SwiftUI
import SwiftData

/// Read-only per-holding contribution timeline.
///
/// Shows each accrual installment with the NAV used, units added, and whether it is
/// an estimate or a reconciled entry (isEstimate flag — D-05).
///
/// Mirrors `EditAssetView` List structure + plain Text display convention (T-11-10).
/// Predicate-filtered @Query init approach mirrors other list views in the project.
///
/// Threat mitigations:
/// - T-115-05: All contribution + units display via plain `Text()` — never AttributedString(markdown:).
struct ContributionLogView: View {

    var asset: Asset

    @Query private var contributions: [Contribution]

    init(asset: Asset) {
        self.asset = asset
        let id = asset.id
        _contributions = Query(
            filter: #Predicate<Contribution> { $0.assetID == id },
            sort: \Contribution.date,
            order: .reverse
        )
    }

    // MARK: - Body

    var body: some View {
        Group {
            if contributions.isEmpty {
                ContentUnavailableView(
                    "No Contributions",
                    systemImage: "tray",
                    description: Text("Contributions appear here after the SIP accrual engine has run.")
                )
            } else {
                List {
                    ForEach(contributions) { contribution in
                        contributionRow(contribution)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Contributions")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Row

    @ViewBuilder
    private func contributionRow(_ contribution: Contribution) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(contribution.date, style: .date)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                estimateBadge(isEstimate: contribution.isEstimate)
            }
            .frame(minHeight: 44)

            HStack {
                Text("Amount")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(contribution.amount.formattedINRWhole())   // T-11-10: plain Text
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Units added")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedUnits(contribution.unitsAdded))  // T-11-10: plain Text
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("NAV used")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(contribution.navUsed.formattedINR())       // T-11-10: plain Text
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Estimate / Reconciled badge

    @ViewBuilder
    private func estimateBadge(isEstimate: Bool) -> some View {
        if isEstimate {
            Label("Estimate", systemImage: "chart.line.uptrend.xyaxis.circle")
                .font(.caption)
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
        } else {
            Label("Reconciled", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        }
    }

    // MARK: - Formatting

    private func formattedUnits(_ units: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        return formatter.string(from: units as NSDecimalNumber) ?? "\(units)"
    }
}
