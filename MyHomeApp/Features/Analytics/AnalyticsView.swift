import SwiftUI
import SwiftData
import Charts

// MARK: - AnalyticsView

/// Full-screen Analytics view pushed from Overview via .navigationDestination (ANL-01).
///
/// Owns the Week/Month/Year range selection (@State selectedRange). The `SpendSummary` is
/// computed at the TOP of `body` (no-stale-data rule — 15-RESEARCH line 459):
/// changing `selectedRange` re-renders `body`, re-running `AnalyticsAggregator.summarize`
/// so headline, trend chart, and category bars update atomically (ANL-02).
///
/// The caller (OverviewMonthContent) passes the full 2-year-wide expense array and all
/// categories so the aggregator can compute prior-period deltas (Pitfall 2 / ANL-02).
///
/// Charts receive ONLY pre-aggregated value types from SpendSummary — never raw expenses
/// enter any Chart DSL (Pitfall A / T-15-05).
struct AnalyticsView: View {

    // MARK: - Inputs

    /// All expenses spanning both current and prior periods (2-year-wide query from caller).
    let expenses: [Expense]
    /// All categories — for name + color resolution in the aggregator.
    let categories: [Category]

    // MARK: - Range state (ANL-02)

    /// Selected time range. Changing this triggers a body re-render → summarize re-runs.
    @State private var selectedRange: SpendRange = .month

    // MARK: - Body

    var body: some View {
        // NO-STALE-DATA RULE: summarize at the very top of body, outside any nested
        // LazyVStack/Group, so SwiftUI dependency tracking always re-computes on selectedRange
        // change (15-RESEARCH line 459 / ANL-02).
        let summary = AnalyticsAggregator.summarize(
            expenses: expenses,
            categories: categories,
            range: selectedRange
        )

        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 16) {

                // 1. Range picker (ANL-02)
                Picker("Range", selection: $selectedRange) {
                    ForEach(SpendRange.allCases, id: \.self) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)

                // 2. Headline card
                headlineCard(summary: summary)

                // 3. Trend chart (ANL-03) — receives pre-aggregated buckets only (Pitfall A)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Spending Trend")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.label2)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                    AnalyticsTrendChart(buckets: summary.trendBuckets)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }
                .neuSurface(.raised)

                // 4. By-category breakdown (ANL-04)
                // INSERTION POINT: AnalyticsCategoryBars — mounted in Task 2
                // AnalyticsCategoryBars(items: summary.categoryBreakdown)
                //   is mounted below in Task 2 inside a .neuSurface(.raised) section.

                // 5. Delta chips insertion point (Phase 15-03 — deferred)
                // DeltaChip(summary: summary) goes here in 15-03.
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(DesignTokens.bgCanvas)
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func headlineCard(summary: SpendSummary) -> some View {
        VStack(spacing: 6) {
            // Caption row
            HStack {
                Text("SPENT")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignTokens.label2)
                    .kerning(1.2)
                Spacer()
                Text(rangeCaption(for: selectedRange))
                    .font(.caption)
                    .foregroundStyle(DesignTokens.label2)
            }

            // Hero number — solid .bold .default (NOT thin ultraLight-rounded per v1.2 hero rule)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(summary.totalSpend.formattedINRWords())
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.label)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding(20)
        .neuSurface(.floating)
    }

    private func rangeCaption(for range: SpendRange) -> String {
        switch range {
        case .week:  return "Last 7 days"
        case .month: return currentMonthName()
        case .year:  return String(Calendar.current.component(.year, from: Date()))
        }
    }

    private func currentMonthName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date())
    }
}
