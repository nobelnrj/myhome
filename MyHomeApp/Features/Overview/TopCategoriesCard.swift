import SwiftUI
import SwiftData

/// Overview Card 2: Top 3 categories by current-month spend (OVR-02).
///
/// Dumb/value-driven: consumes pre-sorted `top3` array from the parent's
/// `OverviewAggregation.topCategories` result. No @Query.
///
/// Empty state (D4-07): `top3.isEmpty` → "No spend yet this month." centered in card.
///
/// Row height: `.frame(minHeight: 44)` on each row for Apple HIG touch target compliance.
/// No dividers between rows — VStack spacing provides visual separation per UI-SPEC.
///
/// Accessibility: `.accessibilityElement(children: .combine)` on the card.
/// Each row marked `.accessibilityAddTraits(.isStaticText)` — no action in v1.
struct TopCategoriesCard: View {

    /// Pre-sorted top-3 categories by descending spend (length 0–3).
    let top3: [(category: Category, spent: Decimal)]

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Row A — Card title
            Text("Top Categories")
                .font(.title2)
                .bold()
                .foregroundStyle(DesignTokens.label)

            if top3.isEmpty {
                // Empty state — no spend this month
                Text("No spend yet this month.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.label2)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // Rows B–D — one row per ranked category
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(top3.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 12) {
                            // Rank label
                            Text("#\(index + 1)")
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.label2)
                                .frame(width: 20, alignment: .leading)

                            // SF Symbol icon
                            if let symbol = item.category.symbolName {
                                Image(systemName: symbol)
                                    .font(.body)
                                    .foregroundStyle(DesignTokens.label2)
                                    .frame(width: 28, height: 28)
                                    .accessibilityHidden(true)
                            } else {
                                // Fallback spacer when no symbol is set
                                Color.clear
                                    .frame(width: 28, height: 28)
                            }

                            // Category name
                            Text(item.category.name ?? "")
                                .font(.body)
                                .foregroundStyle(DesignTokens.label)
                                .lineLimit(1)

                            Spacer()

                            // ₹ amount (full formattedINR per UI-SPEC)
                            Text(item.spent.formattedINR())
                                .font(.body)
                                .foregroundStyle(DesignTokens.label)
                        }
                        .frame(minHeight: 44)
                        .accessibilityAddTraits(.isStaticText)
                    }
                }
            }
        }
        .neuSurface(.raised)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview("3 categories") {
    // Build preview fixtures without SwiftData container
    // (Category requires a live context — use a simple mock approach via a container)
    Text("TopCategoriesCard — needs live preview context")
        .font(.subheadline)
        .padding()
}

#Preview("Empty state") {
    TopCategoriesCard(top3: [])
        .padding()
}
