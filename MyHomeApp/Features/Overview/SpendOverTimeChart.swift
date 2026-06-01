import SwiftUI
import Charts
import SwiftData

// MARK: - SpendOverTimeChart

/// Card showing a LineMark + AreaMark trend chart with a Week/Month/Year segmented control (EXP-11).
///
/// Accepts `monthExpenses: [Expense]` from the parent — the aggregator computes its own
/// date windows from `Date()` (current day), so the expense array need not be bounded
/// to a single month when `.week` or `.year` range is selected.
///
/// Pitfall A guard: `bucketedData` is computed in `body` before the Chart DSL is entered;
///   the raw `[Expense]` array never enters `Chart {}` directly.
/// Pitfall B guard: `SpendBucket.spent` is `Double` (converted at aggregation boundary);
///   no `Decimal` enters any `.value(...)` call.
struct SpendOverTimeChart: View {

    /// Pre-fetched expense array from the parent view's `@Query`.
    /// The aggregator computes its own date windows internally.
    let monthExpenses: [Expense]

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
            expenses: monthExpenses,
            range: selectedRange
        )
        let hasSpend = bucketedData.contains { $0.spent > 0 }

        VStack(alignment: .leading, spacing: 12) {
            // Row A — Card title
            Text("Spend Over Time")
                .font(.title2)

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
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 80)
            } else {
                Chart(bucketedData) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Spend", point.spent)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.15))

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Spend", point.spent)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .symbol(.circle)
                    .symbolSize(30)
                    .accessibilityLabel("\(point.dateLabel), \(Decimal(point.spent).formattedINR())")
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
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

private struct OverTimeChartPreviewHelper: View {
    @Query private var expenses: [Expense]

    var body: some View {
        SpendOverTimeChart(monthExpenses: expenses)
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
    SpendOverTimeChart(monthExpenses: [])
        .padding()
}
