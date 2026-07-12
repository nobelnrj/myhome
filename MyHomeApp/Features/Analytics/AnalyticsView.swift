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

    // MARK: - Sheet state (ANL-06)

    /// Controls presentation of the per-category delta drill-down sheet.
    @State private var showDeltaDrillDown = false

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
            LazyVStack(alignment: .leading, spacing: DesignTokens.spacing22) {

                // 1. Range picker (ANL-02) — recessed pill with a raised accent thumb (v2)
                NeuSegmentedControl(selection: $selectedRange)
                    .padding(.bottom, 2)

                // 2. Headline KPI (includes DeltaChip — ANL-05)
                headlineCard(summary: summary)

                // 3. Trend chart (ANL-03) — receives pre-aggregated buckets only (Pitfall A)
                AnalyticsTrendChart(buckets: summary.trendBuckets)
                    .neuSurface(.raised, padding: 14)

                // 4. By-category breakdown (ANL-04) — all categories, folded to 5 pill columns
                Text("By category")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DesignTokens.label)
                    .padding(.bottom, -10)
                AnalyticsCategoryBars(items: summary.categoryBreakdown)
                    .neuSurface(.raised)

                // 5. AI Insight card (AI-01/D-01/D-02):
                //    - #available(iOS 26, *) keeps this file compiling at iOS 17.0 target (Pitfall 1/2)
                //    - AIInsightCard does its own runtime availability check; returns EmptyView on
                //      any unavailable branch so pre-iOS-26 and AI-ineligible devices see nothing (SC-2)
                //    - summary is re-computed at top of body on every selectedRange change, so range
                //      switches flow through to the card's .task(id:) for re-generation (D-08)
                if #available(iOS 26, *) {
                    AIInsightCard(summary: summary)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(DesignTokens.bgCanvas)
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        // WR-01: sheet anchored at the ScrollView level, not on a LazyVStack child —
        // lazy containers can recycle child views and silently drop the presentation.
        .sheet(isPresented: $showDeltaDrillDown) {
            DeltaDrillDownSheet(summary: summary)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func headlineCard(summary: SpendSummary) -> some View {
        // v2 KPI block: TOTAL SPEND eyebrow / 40pt figure + delta chip / "vs last …" caption.
        // Sits directly on the canvas (no card) per the handoff.
        VStack(alignment: .leading, spacing: 5) {
            Text("TOTAL SPEND").eyebrow()

            HStack(alignment: .center, spacing: 10) {
                Text(summary.totalSpend.formattedINRWhole())
                    .font(.system(size: 40, weight: .semibold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.label)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                // ANL-05: delta chip with inverted color semantics; tap opens drill-down sheet (ANL-06)
                DeltaChip(delta: summary.delta, priorTotal: summary.priorTotalSpend) {
                    showDeltaDrillDown = true
                }
            }

            Text(priorCaption(for: selectedRange))
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.label3)
        }
        .padding(.horizontal, 4)
    }

    private func priorCaption(for range: SpendRange) -> String {
        switch range {
        case .week:  return "vs last week"
        case .month: return "vs last month"
        case .year:  return "vs last year"
        }
    }
}

// MARK: - NeuSegmentedControl

/// v2 segmented control: a recessed pill track with a raised `surfaceElevatedControl` thumb
/// under the active segment (accent text). The thumb slides with a soft spring.
private struct NeuSegmentedControl: View {
    @Binding var selection: SpendRange
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SpendRange.allCases, id: \.self) { range in
                Button {
                    Haptics.selection()
                    withAnimation(DesignTokens.springSoft) { selection = range }
                } label: {
                    Text(range.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selection == range ? DesignTokens.accentText : DesignTokens.label2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if selection == range {
                                Capsule()
                                    .fill(DesignTokens.surfaceElevatedControl)
                                    .overlay(
                                        Capsule().strokeBorder(
                                            LinearGradient(colors: [DesignTokens.segRimTop, DesignTokens.segRimBottom],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                                            lineWidth: 1
                                        )
                                    )
                                    .shadow(color: DesignTokens.neuHairlineDark, radius: 6, x: 3, y: 3)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule().fill(DesignTokens.fillRecessed3)
                .overlay(
                    Capsule().stroke(
                        LinearGradient(colors: [DesignTokens.neuHairlineDark, DesignTokens.segTrackRise],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                    .blur(radius: 0.5)
                    .clipShape(Capsule())
                )
        )
        .accessibilityElement(children: .contain)
    }
}
