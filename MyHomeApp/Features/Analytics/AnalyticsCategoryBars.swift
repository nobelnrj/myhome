import SwiftUI

// MARK: - AnalyticsCategoryBars

/// By-category spending breakdown for the Analytics screen (ANL-04).
///
/// Accepts pre-aggregated `[CategorySpendItem]` already sorted descending by spend
/// (from `SpendSummary.categoryBreakdown`). Shows ALL categories for the range — no top-N
/// truncation (success criterion 4 / ANL-04).
///
/// Renders track-backed horizontal bars mirroring `SpendByCategoryChart`, using the
/// neumorphic category palette (`item.color`) from `CategoryStyle.color(for:)`.
///
/// PITFALL A GUARD: this view never receives raw expenses; only pre-aggregated items.
/// PITFALL B GUARD: amounts display from `item.spentDecimal` (Decimal), never from `item.spent` (Double).
struct AnalyticsCategoryBars: View {

    // MARK: - Input

    /// Pre-aggregated category spend items, sorted descending by spend. Pass the entire
    /// `SpendSummary.categoryBreakdown` — ANL-04 requires all categories (no truncation).
    let items: [CategorySpendItem]

    // MARK: - Computed

    /// Largest spend value; bars scale relative to this. Guarded against zero (safe division).
    private var maxSpent: Double { max(items.first?.spent ?? 0, 1) }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section label
            Text("By Category")
                .font(.headline)
                .foregroundStyle(DesignTokens.label2)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if items.isEmpty {
                // Empty state — calm, no crash (ANL-04 edge case)
                Text("No spend this range.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.label2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 16)
            } else {
                // ALL categories — no prefix/truncation (ANL-04 success criterion 4)
                VStack(spacing: 13) {
                    ForEach(items) { item in
                        categoryBar(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
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
                // Display from Decimal (Pitfall B guard — no float drift)
                Text(item.spentDecimal.formattedINRWhole())
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignTokens.label2)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track (recessed background)
                    Capsule().fill(DesignTokens.fillRecessed2)
                    // Fill capsule proportional to item.spent / maxSpent (maxSpent > 0 guarded)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [item.color.opacity(0.7), item.color],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: max(6, CGFloat(item.spent / maxSpent) * geo.size.width))
                        .neonGlow(item.color, radius: 7)
                }
            }
            .frame(height: 9)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.spentDecimal.formattedINR())")
    }
}
