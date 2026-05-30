import SwiftUI
import SwiftData

// MARK: - CalendarView

/// Custom month-grid calendar for the Notes Calendar segment (D3-17).
///
/// SwiftUI has no built-in calendar component — this implements a `LazyVGrid`-based
/// month grid with per-day reminder counts (from CalendarAggregator) and a tapped-day
/// agenda sheet with x/y completion progress (D3-16: derived live, stores nothing).
///
/// Month navigation: prev/next arrows + formattedAsMonthYear title (Date+Display.swift).
/// Day cell: day number + dot badge when count > 0.
/// Tapped day: agenda list of reminders due that day + DayProgress.
///
/// Satisfies: SC-R4(a) (calendar per-day counts), SC-R4(b) (tapped-day agenda/progress), NOT-09.
struct CalendarView: View {

    // MARK: - Data source (all notes for aggregation)

    @Query private var notes: [Note]

    // MARK: - State

    /// Current viewed month, tracked as a Date (first of month in device timezone).
    @State private var viewedMonthStart: Date = {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }()

    /// The date the user tapped on (nil = no day selected).
    @State private var selectedDay: Date? = nil

    // MARK: - Calendar helpers

    private var deviceCal: Calendar {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        return cal
    }

    /// All day-cells to render for the viewed month grid (including leading padding from
    /// the start-of-week to the 1st of the month, and trailing padding to complete the row).
    private var gridDays: [Date?] {
        let cal = deviceCal
        // Days in the viewed month
        guard let range = cal.range(of: .day, in: .month, for: viewedMonthStart) else {
            return []
        }
        let firstWeekday = cal.component(.weekday, from: viewedMonthStart) // 1=Sun..7=Sat
        // Leading nil padding to align day-1 with its correct column
        let leadingNils = firstWeekday - cal.firstWeekday  // positive in Sun-start calendars
        let adjusted = ((leadingNils % 7) + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: adjusted)
        for day in range {
            if let date = cal.date(byAdding: .day, value: day - 1, to: viewedMonthStart) {
                result.append(date)
            }
        }
        // Trailing nils to complete the last row (grid of 7 columns)
        let remainder = result.count % 7
        if remainder != 0 {
            result += Array(repeating: nil, count: 7 - remainder)
        }
        return result
    }

    /// Per-day reminder counts (derived live from CalendarAggregator).
    private var dayCounts: [Date: Int] {
        CalendarAggregator.perDayCounts(for: notes)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            weekdayHeader
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            monthGrid
                .padding(.horizontal, 8)

            Spacer()
        }
        .sheet(item: Binding(
            get: { selectedDay.map { SelectedDay(date: $0) } },
            set: { val in selectedDay = val?.date }
        )) { item in
            DayAgendaView(day: item.date, notes: notes)
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            Button {
                stepMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Previous month")

            Spacer()

            Text(viewedMonthStart.formattedAsMonthYear())
                .font(.headline)
                .accessibilityLabel("Viewing \(viewedMonthStart.formattedAsMonthYear())")

            Spacer()

            Button {
                stepMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Next month")
        }
    }

    // MARK: - Weekday Header Row

    private var weekdayHeader: some View {
        let cal = deviceCal
        // Short weekday names starting from calendar's firstWeekday
        let symbols = cal.shortWeekdaySymbols
        let start = cal.firstWeekday - 1  // 0-based index
        let ordered = Array(symbols[start...]) + Array(symbols[..<start])

        return LazyVGrid(columns: gridColumns, spacing: 0) {
            ForEach(ordered, id: \.self) { name in
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Month Grid

    private var monthGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 4) {
            ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                if let day = day {
                    dayCell(day)
                } else {
                    Color.clear
                        .frame(height: 48)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let cal = deviceCal
        let isToday = cal.isDateInToday(day)
        let count = dayCounts[cal.startOfDay(for: day)] ?? 0
        let isSelected = selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false

        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 2) {
                Text(day.formattedAsCalendarDay())
                    .font(.body)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                    )

                // Dot badge when there are reminders
                if count > 0 {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                } else {
                    Color.clear.frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.formattedAsCalendarDay()), \(count) \(count == 1 ? "reminder" : "reminders")")
    }

    // MARK: - Grid layout

    private let gridColumns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    // MARK: - Month navigation

    private func stepMonth(by value: Int) {
        var cal = deviceCal
        cal.timeZone = TimeZone.current
        if let next = cal.date(byAdding: .month, value: value, to: viewedMonthStart) {
            viewedMonthStart = next
        }
    }
}

// MARK: - SelectedDay (Identifiable wrapper for sheet binding)

private struct SelectedDay: Identifiable {
    let id = UUID()
    let date: Date
}

// MARK: - DayAgendaView

/// Agenda sheet showing all reminders due on a specific day with completion progress.
///
/// Opened when the user taps a day cell in CalendarView.
/// Progress from CalendarAggregator.progress(for:notes:) — derived live (D3-16).
struct DayAgendaView: View {

    let day: Date
    let notes: [Note]

    @Environment(\.dismiss) private var dismiss

    private var progress: DayProgress {
        CalendarAggregator.progress(for: day, notes: notes)
    }

    /// All reminders (note + block level) due on this day.
    private var remindersOnDay: [ReminderItem] {
        var items: [ReminderItem] = []
        let cal = Calendar.current
        for note in notes {
            if note.reminderEnabled,
               let date = note.reminderDate,
               cal.isDate(date, inSameDayAs: day) {
                items.append(ReminderItem(
                    id: note.id,
                    title: note.title.isEmpty ? "Untitled Note" : note.title,
                    date: date,
                    isAllDay: note.reminderIsAllDay,
                    isChecked: (note.blocks ?? []).allSatisfy { $0.isChecked } && !(note.blocks ?? []).isEmpty
                ))
            }
            for block in note.blocks ?? [] {
                if block.reminderEnabled,
                   let date = block.reminderDate,
                   cal.isDate(date, inSameDayAs: day) {
                    items.append(ReminderItem(
                        id: block.id,
                        title: block.text.isEmpty ? "(Checklist item)" : block.text,
                        date: date,
                        isAllDay: block.reminderIsAllDay,
                        isChecked: block.isChecked
                    ))
                }
            }
        }
        return items.sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if remindersOnDay.isEmpty {
                    ContentUnavailableView(
                        "No Reminders",
                        systemImage: "calendar",
                        description: Text("No reminders scheduled for this day.")
                    )
                } else {
                    List {
                        // Progress header
                        if progress.total > 0 {
                            Section {
                                HStack {
                                    Text("Progress")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(progress.done) of \(progress.total) complete")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: progress.fraction)
                                    .tint(.accentColor)
                            }
                        }

                        // Reminder items
                        Section {
                            ForEach(remindersOnDay) { item in
                                HStack(spacing: 12) {
                                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.isChecked ? .secondary : Color.accentColor)
                                        .font(.body)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.body)
                                            .strikethrough(item.isChecked)
                                            .foregroundStyle(item.isChecked ? .secondary : .primary)

                                        Text(item.date.formattedAsReminderDate(isAllDay: item.isAllDay))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                                .accessibilityLabel("\(item.title), \(item.isChecked ? "complete" : "pending")")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(day.formattedAsReminderDate(isAllDay: true))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - ReminderItem (view model for DayAgendaView)

private struct ReminderItem: Identifiable {
    let id: UUID
    let title: String
    let date: Date
    let isAllDay: Bool
    let isChecked: Bool
}
