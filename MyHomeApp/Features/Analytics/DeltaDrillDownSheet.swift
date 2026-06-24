import SwiftUI
import SwiftData

// MARK: - DeltaDrillDownSheet

/// Per-category current-vs-prior spend drill-down sheet (ANL-06).
///
/// Presented as a `.sheet` when the user taps the delta chip in `AnalyticsView`.
/// Each row shows:
///   - Category name
///   - Current period spend
///   - Prior period spend (keyed lookup via `summary.priorCategorySpend`)
///   - A non-interactive `DeltaChip` showing the per-category change
///
/// Rows are sorted DESCENDING by absolute per-category delta (biggest movers first).
struct DeltaDrillDownSheet: View {

    // MARK: - Inputs

    /// The pre-aggregated summary for the currently-selected range.
    let summary: SpendSummary

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Computed rows

    private struct DrillRow: Identifiable {
        let id: PersistentIdentifier
        let name: String
        let current: Decimal
        let prior: Decimal
        var delta: Decimal { current - prior }
    }

    private var rows: [DrillRow] {
        summary.categoryBreakdown
            .map { item in
                let prior = summary.priorCategorySpend[item.id] ?? .zero
                return DrillRow(
                    id: item.id,
                    name: item.name,
                    current: item.spentDecimal,
                    prior: prior
                )
            }
            // Sort descending by absolute delta — biggest movers first (15-RESEARCH line 442)
            .sorted { abs($0.delta) > abs($1.delta) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if rows.isEmpty {
                        Text("No category spend for this period.")
                            .foregroundStyle(DesignTokens.label2)
                            .font(.subheadline)
                            .padding(.top, 32)
                    } else {
                        ForEach(rows) { row in
                            rowView(row)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.bgCanvas)
            .navigationTitle("Spending Change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DesignTokens.accent)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Row view

    @ViewBuilder
    private func rowView(_ row: DrillRow) -> some View {
        VStack(spacing: 8) {
            // Category name row
            HStack {
                Text(row.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.label)
                Spacer()
                // Non-interactive per-category delta chip
                DeltaChip(delta: row.delta, priorTotal: row.prior, onTap: {})
            }

            // Current vs prior amounts
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This period")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.label2)
                    Text(row.current.formattedINRWhole())
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.label)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Prior period")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.label2)
                    Text(row.prior.formattedINRWhole())
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.label2)
                }
            }
        }
        .padding(14)
        .neuSurface(.recessed)
    }
}
