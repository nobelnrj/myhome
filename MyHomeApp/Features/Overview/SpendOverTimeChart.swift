import SwiftUI
import Charts
import SwiftData

// MARK: - SpendOverTimeChart

/// Card showing a LineMark + AreaMark trend chart with a Week/Month/Year segmented control (EXP-11).
///
/// Accepts `expenses: [Expense]` from the parent — the aggregator computes its own
/// date windows from `Date()` (current day), so the parent MUST supply data spanning the
/// widest range the chart can display (the current calendar year), NOT a month-bounded
/// array (CR-01). OverviewView feeds this from a year-scoped `@Query`.
///
/// Pitfall A guard: `bucketedData` is computed in `body` before the Chart DSL is entered;
///   the raw `[Expense]` array never enters `Chart {}` directly.
/// Pitfall B guard: `SpendBucket.spent` is `Double` (converted at aggregation boundary);
///   no `Decimal` enters any `.value(...)` call.
struct SpendOverTimeChart: View {

    /// Pre-fetched, year-scoped expense array from the parent view's `@Query`.
    /// The aggregator computes its own date windows internally (rolling week /
    /// current month / current calendar year), so this must span the calendar year.
    let expenses: [Expense]

    /// Currently selected time range (default: month). View-local state, not persisted.
    @State private var selectedRange: SpendRange = .month

    // MARK: - Helpers

    /// Returns a `Date.FormatStyle` for the X-axis labels based on the selected range.
    ///
    /// - Week: abbreviated weekday + day ("Mon 2")
    /// - Month: day-of-month number ("1", "2" … "31")
    /// - Year: abbreviated month name ("Jan", "Feb" … "Dec")
    private func xAxisDateFormat(for range: SpendRange) -> Date.FormatStyle {
        switch range {
        case .week:  return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day()
        case .year:  return .dateTime.month(.abbreviated)
        }
    }

    // MARK: - Body

    var body: some View {
        // Pitfall A: aggregate OUTSIDE the Chart DSL
        let bucketedData = SpendOverTimeAggregator.bucket(
            expenses: expenses,
            range: selectedRange
        )
        let hasSpend = bucketedData.contains { $0.spent > 0 }

        VStack(alignment: .leading, spacing: 12) {
            // Range segmented control (always visible, even in empty state). Card title
            // omitted — OverviewView's "Over Time" section header labels this card.
            Picker("Range", selection: $selectedRange) {
                Text(SpendRange.week.label).tag(SpendRange.week)
                Text(SpendRange.month.label).tag(SpendRange.month)
                Text(SpendRange.year.label).tag(SpendRange.year)
            }
            .pickerStyle(.segmented)

            // Row C — Chart or empty state
            if !hasSpend {
                // D4-07 empty state — Picker stays visible above (per UI-SPEC)
                Text("No spend yet for this period.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.label2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 80)
            } else {
                Chart(bucketedData) { point in
                    // v2 trend recipe (matches AnalyticsTrendChart): warm area fade under a
                    // smooth 3.5pt yellow→red gradient line.
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Spend", point.spent)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(
                        colors: [DesignTokens.chartAmber.opacity(0.26), .clear],
                        startPoint: .top, endPoint: .bottom))

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Spend", point.spent)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(LinearGradient(
                        colors: [DesignTokens.accent, DesignTokens.negative],
                        startPoint: .leading, endPoint: .trailing))
                    .accessibilityLabel("\(point.dateLabel), \(point.spentDecimal.formattedINR())")
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisGridLine()
                            .foregroundStyle(DesignTokens.chartGridline)
                        AxisValueLabel(format: xAxisDateFormat(for: selectedRange))
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.label3)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                            .foregroundStyle(DesignTokens.chartGridline)
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text(Decimal(d).formattedINRCompact())
                                    .font(.system(size: 11))
                                    .foregroundStyle(DesignTokens.label3)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .shadow(color: DesignTokens.chartAmber.opacity(0.30), radius: 5, y: 5)
                .accessibilityLabel("Spend over time chart, \(selectedRange.label) view")
                // D-12: force the chart palette luminous, then wrap it in a slate instrument
                // window in LIGHT ONLY. In dark this is a no-op (byte-identical, D-06): the chart
                // keeps sitting directly on the .raised card exactly as before. In light the amber
                // curve + gridlines glow inside a deep-slate window on the light card.
                .lightSlateInstrumentInset()
            }
        }
        .neuSurface(.raised)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

private struct OverTimeChartPreviewHelper: View {
    @Query private var expenses: [Expense]

    var body: some View {
        SpendOverTimeChart(expenses: expenses)
            .padding()
    }
}

#Preview("Populated — current month") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Expense.self, Category.self, configurations: config)

    let cal = Calendar.current
    let today = Date()
    // Insert 10 expenses spread over the last 10 days
    for offset in 0..<10 {
        if let day = cal.date(byAdding: .day, value: -offset, to: today) {
            let expense = Expense(amount: Decimal(Double.random(in: 500...5000)), date: day)
            container.mainContext.insert(expense)
        }
    }

    return OverTimeChartPreviewHelper()
        .modelContainer(container)
}

#Preview("Empty") {
    SpendOverTimeChart(expenses: [])
        .padding()
}
