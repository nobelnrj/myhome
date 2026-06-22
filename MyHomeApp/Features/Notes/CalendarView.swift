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
        .background(DesignTokens.bgCanvas)
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
                    .foregroundStyle(DesignTokens.label2)
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
                    .foregroundStyle(isToday ? DesignTokens.accent : DesignTokens.label)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isSelected ? DesignTokens.accent.opacity(0.15) : Color.clear)
                    )

                // Dot badge when there are reminders
                if count > 0 {
                    Circle()
                        .fill(DesignTokens.accent)
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

// MARK: - AgendaReminderItem (live-model wrapper for DayAgendaView)

/// Display model for a single agenda row.
///
/// All display properties are computed from the live `ReminderTarget` reference types
/// (ReminderTarget is defined in ReminderEditView.swift and is module-internal).
/// Mutations to the Note/NoteBlock propagate back to CalendarView's @Query and cause
/// DayProgress to recompute live — no detached snapshot involved.
private struct AgendaReminderItem: Identifiable {
    let id: UUID
    let target: ReminderTarget
    let date: Date

    init(target: ReminderTarget, date: Date) {
        switch target {
        case .note(let note): self.id = note.id
        case .block(let block): self.id = block.id
        }
        self.target = target
        self.date = date
    }

    var title: String {
        switch target {
        case .note(let note):   return note.title.isEmpty ? "Untitled Note" : note.title
        case .block(let block): return block.text.isEmpty ? "(Checklist item)" : block.text
        }
    }

    var isAllDay: Bool {
        switch target {
        case .note(let note):   return note.reminderIsAllDay
        case .block(let block): return block.reminderIsAllDay
        }
    }

    var isChecked: Bool {
        switch target {
        case .note(let note):
            let blocks = note.blocks ?? []
            guard !blocks.isEmpty else { return false }
            return blocks.allSatisfy { $0.isChecked }
        case .block(let block):
            return block.isChecked
        }
    }
}

// MARK: - DayAgendaView

/// Agenda sheet showing all reminders due on a specific day with completion progress.
///
/// Opened when the user taps a day cell in CalendarView.
/// Progress from CalendarAggregator.progress(for:notes:) — derived live (D3-16).
///
/// Completion: each row's checkbox is a Button bound to the live Note/NoteBlock via
/// ReminderTarget. Tapping toggles the model and saves context (CLAUDE.md: explicit save).
/// Completing cancels pending notifications (mirrors NotificationActionDelegate.handleComplete).
struct DayAgendaView: View {

    let day: Date
    let notes: [Note]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// State for navigating to a tapped routine note via sheet (D-01).
    @State private var editingRoutineNote: Note? = nil

    private var progress: DayProgress {
        CalendarAggregator.progress(for: day, notes: notes)
    }

    /// All routine notes — surfaced on every day (D-01/D-03).
    ///
    /// STAB-01: guard against tombstoned @Model objects (same pattern as remindersOnDay).
    /// Routines appear on EVERY day, driven only by isDailyRoutine flag — NOT by any reminder.
    private var routineNotes: [Note] {
        notes.filter { note in
            guard note.modelContext != nil else { return false }  // STAB-01: skip tombstoned notes
            return note.isDailyRoutine
        }
        .sorted { $0.title < $1.title }  // alphabetical within section
    }

    /// All reminders (note + block level) due on this day, bound to live model targets.
    ///
    /// STAB-01: Both loops guard against tombstoned @Model objects using the established
    /// `modelContext != nil` idiom (mirrors EditNoteView.swift:332). A Note or NoteBlock
    /// can be deleted (tombstoned) from another view while this sheet is open; accessing any
    /// stored property on a tombstoned object causes a SwiftData fault / EXC_BAD_ACCESS crash.
    private var remindersOnDay: [AgendaReminderItem] {
        var items: [AgendaReminderItem] = []
        let cal = Calendar.current
        for note in notes {
            guard note.modelContext != nil else { continue }  // STAB-01: skip tombstoned notes
            if note.reminderEnabled,
               let date = note.reminderDate,
               cal.isDate(date, inSameDayAs: day) {
                items.append(AgendaReminderItem(
                    target: ReminderTarget.note(note),
                    date: date
                ))
            }
            for block in note.blocks ?? [] {
                guard block.modelContext != nil else { continue }  // STAB-01: skip tombstoned blocks
                if block.reminderEnabled,
                   let date = block.reminderDate,
                   cal.isDate(date, inSameDayAs: day) {
                    items.append(AgendaReminderItem(
                        target: ReminderTarget.block(block),
                        date: date
                    ))
                }
            }
        }
        return items.sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if remindersOnDay.isEmpty && routineNotes.isEmpty {
                    ContentUnavailableView(
                        "Nothing Scheduled",
                        systemImage: "calendar",
                        description: Text("No routines or reminders for this day.")
                    )
                } else {
                    List {
                        // Section 1: Daily Routines (D-01 — always first, every day)
                        if !routineNotes.isEmpty {
                            Section("Daily Routines") {
                                ForEach(routineNotes) { note in
                                    RoutineAgendaRow(note: note, onTap: { editingRoutineNote = note })
                                        .listRowBackground(DesignTokens.surfaceRaised)
                                }
                            }
                        }

                        // Progress header — recomputed live from model via `progress`
                        if progress.total > 0 {
                            Section {
                                HStack {
                                    Text("Progress")
                                        .font(.subheadline)
                                        .foregroundStyle(DesignTokens.label2)
                                    Spacer()
                                    Text("\(progress.done) of \(progress.total) complete")
                                        .font(.subheadline)
                                        .foregroundStyle(DesignTokens.label2)
                                }
                                ProgressView(value: progress.fraction)
                                    .tint(DesignTokens.accent)
                            }
                            .listRowBackground(DesignTokens.surfaceRaised)
                        }

                        // Reminder items with actionable checkboxes
                        if !remindersOnDay.isEmpty {
                            Section {
                                ForEach(remindersOnDay) { item in
                                    HStack(spacing: 12) {
                                        // Actionable checkbox (>=44pt target) bound to live model
                                        Button {
                                            toggleCompletion(item)
                                        } label: {
                                            Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(item.isChecked ? DesignTokens.accent : DesignTokens.label3)
                                                .font(.body)
                                                .frame(minWidth: 44, minHeight: 44)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(item.isChecked ? "Mark incomplete" : "Mark complete")

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(.body)
                                                .strikethrough(item.isChecked)
                                                .foregroundStyle(item.isChecked ? DesignTokens.label3 : DesignTokens.label)

                                            Text(item.date.formattedAsReminderDate(isAllDay: item.isAllDay))
                                                .font(.caption)
                                                .foregroundStyle(DesignTokens.label2)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                    .listRowBackground(DesignTokens.surfaceRaised)
                                    .accessibilityLabel("\(item.title), \(item.isChecked ? "complete" : "pending")")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(DesignTokens.bgCanvas)
                }
            }
            .navigationTitle(day.formattedAsReminderDate(isAllDay: true))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingRoutineNote) { note in
                EditNoteView(note: note)
            }
        }
    }

    // MARK: - Completion toggle (bound to live model)

    /// Toggles completion on the live Note/NoteBlock and persists.
    ///
    /// Mirrors NotificationActionDelegate.handleComplete semantics:
    /// - BLOCK target: toggle isChecked; when completing, cancel pending alerts + set reminderEnabled = false.
    ///   When unchecking, only clear isChecked (no auto-reschedule — that is the editor's job).
    /// - NOTE target WITH blocks: set all blocks to the new checked state; when completing,
    ///   cancel note-level alerts + set reminderEnabled = false.
    /// - NOTE target WITHOUT blocks: completing sets reminderEnabled = false + cancels alerts
    ///   (item drops from pending list). Unchecking only clears reminderEnabled state.
    ///
    /// Security: T-03-16 — no note/block body text in logs.
    private func toggleCompletion(_ item: AgendaReminderItem) {
        switch item.target {

        case .block(let block):
            guard block.modelContext != nil else { return }  // STAB-01: defensive guard
            let newChecked = !block.isChecked
            block.isChecked = newChecked
            if newChecked {
                // Cancel pending alerts and disable the reminder (mirrors D3-04)
                cancelBlockReminder(block)
            }

        case .note(let note):
            guard note.modelContext != nil else { return }  // STAB-01: defensive guard
            let blocks = note.blocks ?? []
            if !blocks.isEmpty {
                // Determine new state: if all are already checked, uncheck all; else check all
                let allChecked = blocks.allSatisfy { $0.isChecked }
                let newChecked = !allChecked
                for block in blocks {
                    block.isChecked = newChecked
                }
                if newChecked {
                    cancelNoteReminder(note)
                }
            } else {
                // No blocks: completion is one-directional (WR-04). Completing cancels + disables
                // the reminder so it leaves the agenda. There is no re-enable path here — a
                // transiently-visible disabled item must not resurrect a reminder with no pending
                // notifications (mirrors NotificationActionDelegate.handleComplete).
                if note.reminderEnabled {
                    cancelNoteReminder(note)
                }
            }
        }

        // Explicit save (CLAUDE.md: no implicit autosave reliance)
        try? context.save()
    }

    /// Cancels pending notifications for a block-level reminder and clears reminderEnabled.
    private func cancelBlockReminder(_ block: NoteBlock) {
        let leadCount = block.reminderLeadMinutes > 0 ? 1 : 0
        var weekdays: [Int] = []
        if let data = block.reminderRecurrenceData,
           let rec = try? JSONDecoder().decode(ReminderRecurrence.self, from: data) {
            weekdays = rec.weekdays ?? []
        }
        NotificationScheduler(center: SystemNotificationCenter())
            .cancel(reminderID: block.id, leadCount: leadCount, weekdays: weekdays)
        block.reminderEnabled = false
    }

    /// Cancels pending notifications for a note-level reminder and clears reminderEnabled.
    private func cancelNoteReminder(_ note: Note) {
        let leadCount = note.reminderLeadMinutes > 0 ? 1 : 0
        var weekdays: [Int] = []
        if let data = note.reminderRecurrenceData,
           let rec = try? JSONDecoder().decode(ReminderRecurrence.self, from: data) {
            weekdays = rec.weekdays ?? []
        }
        NotificationScheduler(center: SystemNotificationCenter())
            .cancel(reminderID: note.id, leadCount: leadCount, weekdays: weekdays)
        note.reminderEnabled = false
    }
}

// MARK: - RoutineAgendaRow

/// A single row in the DayAgendaView "Daily Routines" section (D-01, D-03, D-06).
///
/// Mirrors AgendaReminderItem row structure. Displays completion state and provides
/// check-time completion recording via fetch-before-insert idempotency (T-12-07).
///
/// Security: all strings use plain Text(...) — no AttributedString (T-12-10).
private struct RoutineAgendaRow: View {
    var note: Note
    var onTap: () -> Void

    @Environment(\.modelContext) private var context

    // @Query for today's completion records for this note (Pitfall 4: captured in init).
    @Query private var todayCompletions: [RoutineCompletion]

    init(note: Note, onTap: @escaping () -> Void) {
        self.note = note
        self.onTap = onTap
        var istCal = Calendar(identifier: .gregorian)
        istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let dayKey = istCal.startOfDay(for: Date())
        let noteID = note.id
        self._todayCompletions = Query(
            filter: #Predicate<RoutineCompletion> { $0.noteID == noteID && $0.dayKey == dayKey }
        )
    }

    /// True when the routine is complete for today.
    ///
    /// - Checklist routines: all checkbox blocks are checked.
    /// - Text-only routines: a RoutineCompletion record exists for today's IST dayKey.
    private var isCompleteToday: Bool {
        let checkboxBlocks = (note.blocks ?? []).filter { $0.kindRaw == "checkbox" }
        if !checkboxBlocks.isEmpty {
            return checkboxBlocks.allSatisfy(\.isChecked)
        }
        // Text-only: determined by RoutineCompletion record from @Query
        return !todayCompletions.isEmpty
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                toggleAllBlocks()
            } label: {
                Image(systemName: isCompleteToday ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCompleteToday ? DesignTokens.accent : DesignTokens.label3)
                    .font(.body)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCompleteToday ? "Routine complete" : "Mark routine complete")

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.body)
                    .strikethrough(isCompleteToday)
                    .foregroundStyle(isCompleteToday ? DesignTokens.label3 : DesignTokens.label)

                // Status subtitle
                if let time = note.routineDailyReminderTime {
                    Text("Daily at \(time.formatted(.dateTime.hour().minute()))")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.label2)
                } else {
                    Text("Daily routine")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.label2)
                }

                // "Done today" inline button for text-only routines (D-06)
                let checkboxBlocks = (note.blocks ?? []).filter { $0.kindRaw == "checkbox" }
                if checkboxBlocks.isEmpty && !isCompleteToday {
                    Button("Done today") {
                        recordCompletion()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
        .padding(.vertical, 2)
    }

    /// Toggles all checkbox blocks and records a completion at check-time (D-06, T-12-07).
    ///
    /// Mirrors recordTodayCompletion() from EditNoteView — fetch-before-insert idempotency.
    private func toggleAllBlocks() {
        let checkboxBlocks = (note.blocks ?? []).filter { $0.kindRaw == "checkbox" }
        if !checkboxBlocks.isEmpty {
            let newChecked = !checkboxBlocks.allSatisfy(\.isChecked)
            for block in checkboxBlocks { block.isChecked = newChecked }
            if newChecked { recordCompletion() }
        } else {
            // Text-only routine: tap on indicator records completion
            if !isCompleteToday { recordCompletion() }
        }
        try? context.save()  // mirrors DayAgendaView.toggleCompletion line 451
    }

    /// Writes or upserts a RoutineCompletion for today's IST dayKey (fetch-before-insert).
    ///
    /// Mirrors recordTodayCompletion() pattern from EditNoteView (12-03) and PATTERNS.md.
    private func recordCompletion() {
        var istCal = Calendar(identifier: .gregorian)
        istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let dayKey = istCal.startOfDay(for: Date())
        let noteID = note.id
        let descriptor = FetchDescriptor<RoutineCompletion>(
            predicate: #Predicate { $0.noteID == noteID && $0.dayKey == dayKey }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.completedAt = Date()
        } else {
            context.insert(RoutineCompletion(noteID: noteID, dayKey: dayKey))
        }
        try? context.save()  // explicit save (CLAUDE.md)
    }
}
