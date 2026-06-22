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
            // Row A — Card title
            Text("Spend Over Time")
                .font(.title2)
                .foregroundStyle(DesignTokens.label)

            // Row B — Range segmented control (always visible, even in empty state)
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
                    // WHOOP-style trend bars: rounded, color-coded, gradient fill.
                    BarMark(
                        x: .value("Date", point.date),
                        y: .value("Spend", point.spent)
                    )
                    .cornerRadius(4)
                    .foregroundStyle(DesignTokens.accent.gradient)
                    .accessibilityLabel("\(point.dateLabel), \(point.spentDecimal.formattedINR())")
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisGridLine()
                        AxisValueLabel(format: xAxisDateFormat(for: selectedRange))
                            .font(.caption)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text(Decimal(d).formattedINRCompact())
                                    .font(.caption)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .accessibilityLabel("Spend over time chart, \(selectedRange.label) view")
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
