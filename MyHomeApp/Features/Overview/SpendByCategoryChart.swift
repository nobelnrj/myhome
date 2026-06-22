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
    /// Category accent color (CategoryStyle.color) — bars match the donut legend so the two
    /// charts read as one palette instead of a flat single-hue bar list.
    var color: Color = DesignTokens.accent
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

    /// Top categories shown as track-backed bars (no inner scroll).
    private var topItems: [CategorySpendItem] { Array(categoryItems.prefix(6)) }
    /// Largest spend in the visible set — bars are scaled relative to this.
    private var maxSpent: Double { max(topItems.first?.spent ?? 0, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Row A — Card title
            Text("Spend by Category")
                .font(.title2)
                .foregroundStyle(DesignTokens.label)

            // Row B — Track-backed bar list (WHOOP-style) or empty state
            if categoryItems.isEmpty {
                // D4-07 empty state
                Text("No spend yet this month.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.label2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 80)
            } else {
                VStack(spacing: 13) {
                    ForEach(topItems) { item in
                        categoryBar(item)
                    }
                }
            }
        }
        .neuSurface(.raised)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Spend by category")
    }

    // MARK: - Track-backed bar row

    @ViewBuilder
    private func categoryBar(_ item: CategorySpendItem) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(item.name)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.label)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(item.spentDecimal.formattedINRWords())
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignTokens.label2)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DesignTokens.fillRecessed2)
                    Capsule()
                        .fill(item.color.gradient)
                        .frame(width: max(6, CGFloat(item.spent / maxSpent) * geo.size.width))
                }
            }
            .frame(height: 9)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.spentDecimal.formattedINR())")
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
