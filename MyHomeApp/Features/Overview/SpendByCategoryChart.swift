import SwiftUI
import Charts
import SwiftData

// MARK: - CategorySpendItem

/// Pre-aggregated value type for the spend-by-category BarMark chart (EXP-10).
///
/// `spent` is `Double` (not `Decimal`) because Swift Charts requires `Plottable` conformance.
/// The Decimal→Double conversion happens at the aggregation boundary (caller's body),
/// never inside the Chart DSL (Pitfall B guard).
struct CategorySpendItem: Identifiable {
    /// Stable identity for SwiftUI diffing — the category's persistentModelID.
    let id: PersistentIdentifier
    /// Category display name.
    let name: String
    /// Total spend converted from Decimal at the caller's aggregation boundary.
    /// Used ONLY as the Chart plot value (Plottable requires Double).
    let spent: Double
    /// Original Decimal spend, carried alongside `spent` so display strings format from
    /// the exact value — never reconstruct `Decimal(spent)` from the lossy Double (WR-03,
    /// Pitfall B: no float drift in displayed money).
    let spentDecimal: Decimal
}

// MARK: - SpendByCategoryChart

/// Card showing a horizontal BarMark chart ranking categories by current-month spend (EXP-10).
///
/// Accepts pre-aggregated `[CategorySpendItem]` sorted descending by `spent` — the parent
/// (OverviewView) owns the sort; this view is display-only.
///
/// Pitfall A guard: `categoryItems` is a pre-computed value array, not a raw `@Query` result.
/// Pitfall B guard: `CategorySpendItem.spent` is `Double`; no `Decimal` enters the Chart DSL.
struct SpendByCategoryChart: View {

    /// Pre-aggregated, descending-sorted category spend items. Pass an empty array to show
    /// the empty state.
    let categoryItems: [CategorySpendItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row A — Card title
            Text("Spend by Category")
                .font(.title2)
                .foregroundStyle(DesignTokens.label)

            // Row B — Chart or empty state
            if categoryItems.isEmpty {
                // D4-07 empty state
                Text("No spend yet this month.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.label2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 80)
            } else {
                Chart(categoryItems) { item in
                    BarMark(
                        x: .value("Amount", item.spent),
                        y: .value("Category", item.name)
                    )
                    .foregroundStyle(DesignTokens.accent)
                    .annotation(position: .trailing) {
                        Text(item.spentDecimal.formattedINRCompact())
                            .font(.caption)
                            .foregroundStyle(DesignTokens.label2)
                    }
                    .accessibilityLabel("\(item.name), \(item.spentDecimal.formattedINR())")
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel()
                            .font(.caption)
                    }
                }
                .frame(height: 220)
                .chartScrollableAxes(.vertical)
                .accessibilityLabel("Spend by category chart")
            }
        }
        .neuSurface(.raised)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

private struct CategoryChartPreviewHelper: View {
    @Query private var categories: [Category]

    var body: some View {
        let items = categories.prefix(8).enumerated().map { index, cat in
            let amount = (8 - index) * 2000 + 500
            return CategorySpendItem(
                id: cat.persistentModelID,
                name: cat.name ?? "Category \(index + 1)",
                spent: Double(amount),
                spentDecimal: Decimal(amount)
            )
        }
        SpendByCategoryChart(categoryItems: items)
            .padding()
    }
}

#Preview("Populated") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Category.self, Expense.self, configurations: config)
    let names = ["Groceries", "Dining", "Fuel", "Utilities", "Health", "Entertainment", "Shopping", "Other"]
    for (i, name) in names.enumerated() {
        let cat = Category(name: name, symbolName: nil, sortOrder: i)
        container.mainContext.insert(cat)
    }
    return CategoryChartPreviewHelper()
        .modelContainer(container)
}

#Preview("Empty") {
    SpendByCategoryChart(categoryItems: [])
        .padding()
}
