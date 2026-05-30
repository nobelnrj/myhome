import SwiftUI
import SwiftData
import UserNotifications

// MARK: - ReminderTarget

/// Protocol-like enum for the two possible reminder targets (note-level or block-level).
/// This lets `ReminderEditView` operate on either without duplicating code.
enum ReminderTarget {
    case note(Note)
    case block(NoteBlock)

    var reminderEnabled: Bool {
        get {
            switch self {
            case .note(let n): return n.reminderEnabled
            case .block(let b): return b.reminderEnabled
            }
        }
        nonmutating set {
            switch self {
            case .note(let n): n.reminderEnabled = newValue
            case .block(let b): b.reminderEnabled = newValue
            }
        }
    }

    var reminderDate: Date? {
        get {
            switch self {
            case .note(let n): return n.reminderDate
            case .block(let b): return b.reminderDate
            }
        }
        nonmutating set {
            switch self {
            case .note(let n): n.reminderDate = newValue
            case .block(let b): b.reminderDate = newValue
            }
        }
    }

    var reminderIsAllDay: Bool {
        get {
            switch self {
            case .note(let n): return n.reminderIsAllDay
            case .block(let b): return b.reminderIsAllDay
            }
        }
        nonmutating set {
            switch self {
            case .note(let n): n.reminderIsAllDay = newValue
            case .block(let b): b.reminderIsAllDay = newValue
            }
        }
    }

    var reminderRecurrenceData: Data? {
        get {
            switch self {
            case .note(let n): return n.reminderRecurrenceData
            case .block(let b): return b.reminderRecurrenceData
            }
        }
        nonmutating set {
            switch self {
            case .note(let n): n.reminderRecurrenceData = newValue
            case .block(let b): b.reminderRecurrenceData = newValue
            }
        }
    }

    var reminderEndRuleData: Data? {
        get {
            switch self {
            case .note(let n): return n.reminderEndRuleData
            case .block(let b): return b.reminderEndRuleData
            }
        }
        nonmutating set {
            switch self {
            case .note(let n): n.reminderEndRuleData = newValue
            case .block(let b): b.reminderEndRuleData = newValue
            }
        }
    }

    var reminderLeadMinutes: Int {
        get {
            switch self {
            case .note(let n): return n.reminderLeadMinutes
            case .block(let b): return b.reminderLeadMinutes
            }
        }
        nonmutating set {
            switch self {
            case .note(let n): n.reminderLeadMinutes = newValue
            case .block(let b): b.reminderLeadMinutes = newValue
            }
        }
    }

    /// Stable identifier for notification scheduling (the owning model's UUID).
    var reminderID: UUID {
        switch self {
        case .note(let n): return n.id
        case .block(let b): return b.id
        }
    }

    /// Display title for the notification banner.
    var displayTitle: String {
        switch self {
        case .note(let n): return n.title.isEmpty ? "Reminder" : n.title
        case .block(let b): return b.text.isEmpty ? "Reminder" : b.text
        }
    }

    /// Owning note (needed to set isPinned for yearly auto-pin).
    var owningNote: Note? {
        switch self {
        case .note(let n): return n
        case .block(let b): return b.note
        }
    }
}

// MARK: - ReminderEditView

/// Sheet for setting/editing a reminder on a Note or NoteBlock (D3-02).
///
/// Presents from EditNoteView's note-level toolbar and per-block context menu.
/// Single-sheet discipline: uses @Environment(\.dismiss) — no nested sheets.
///
/// Features (NOT-07..10):
/// - All-day toggle (switches DatePicker between .date and .date+.hourAndMinute)
/// - Date (+ time if timed) via disclosure-row pattern (EditExpenseView §145-180)
/// - Lead-time stepper in minutes (clamped ≥ 0)
/// - Recurrence menu (None / Daily / Weekly+weekday picker / Monthly / Yearly)
/// - End-rule picker (Never / On Date / After N, N clamped ≥ 1)
/// - Pre-checked "Pin to top" toggle when recurrence == yearly (D3-09)
/// - In-context auth request on first-ever reminder (D3-12); denied → Settings hint
/// - "Remove Reminder" with confirmationDialog (UI-SPEC §4)
/// - Reschedule on save: cancel-then-rebuild (Open Q2 + Pitfall 3 — save context after schedule)
///
/// Security: T-03-13 (clamp inputs), T-03-14 (deterministic IDs), T-03-16 (no logging).
struct ReminderEditView: View {

    // MARK: - Init

    /// The target (note or block) being edited. Passed by value so the view works
    /// with both Note and NoteBlock without SwiftData @Bindable coupling.
    let target: ReminderTarget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // MARK: - Local state (mirrors model fields for this sheet)

    @State private var isAllDay: Bool = false
    @State private var reminderDate: Date = Date().addingTimeInterval(3600) // 1 hour from now
    @State private var leadMinutes: Int = 0   // 0 = no advance alert
    @State private var recurrenceType: RecurrenceType = .none
    @State private var selectedWeekdays: Set<Int> = []  // 1=Sun..7=Sat
    @State private var endRuleType: EndRuleType = .never
    @State private var endDate: Date = Date().addingTimeInterval(86400 * 7) // 1 week out
    @State private var afterCount: Int = 1
    @State private var pinToTop: Bool = true   // pre-checked for yearly (D3-09)

    // UI state
    @State private var showDatePicker: Bool = false
    @State private var showEndDatePicker: Bool = false
    @State private var showRemoveConfirmation: Bool = false
    @State private var permissionDenied: Bool = false
    @State private var isSaving: Bool = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // All-day toggle
                allDaySection

                // Date (and time if timed) — disclosure-row pattern
                dateSection

                // Lead-time stepper
                leadTimeSection

                // Recurrence
                recurrenceSection

                // End rule (only when recurrence != .none)
                if recurrenceType != .none {
                    endRuleSection
                }

                // Yearly auto-pin toggle (D3-09)
                if recurrenceType == .yearly {
                    yearlyPinSection
                }

                // Remove reminder (if one exists)
                if target.reminderEnabled {
                    removeSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Set Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveReminder() }
                    }
                    .disabled(isSaving)
                    .tint(.accentColor)
                }
            }
            // Permission denied hint (D3-12)
            .alert(
                "Notifications Disabled",
                isPresented: $permissionDenied
            ) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Notification permission denied. Enable in Settings to receive reminders.")
            }
            // Remove reminder confirmation (UI-SPEC §4)
            .confirmationDialog(
                "Remove Reminder?",
                isPresented: $showRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove Reminder", role: .destructive) {
                    removeReminder()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The reminder and all its scheduled notifications will be removed.")
            }
        }
        .onAppear { loadFields() }
    }

    // MARK: - Sections

    private var allDaySection: some View {
        Section {
            Toggle("All Day", isOn: $isAllDay)
                .accessibilityLabel("All-day reminder")
        }
    }

    private var dateSection: some View {
        Section {
            // Disclosure row — tap to reveal/hide the DatePicker (EditExpenseView pattern)
            Button {
                showDatePicker.toggle()
            } label: {
                HStack {
                    Text("Date")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(reminderDate.formattedAsReminderDate(isAllDay: isAllDay))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Image(systemName: showDatePicker ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)

            if showDatePicker {
                DatePicker(
                    "Select date",
                    selection: $reminderDate,
                    // all-day → date only; timed → date + time (EditExpenseView §170-174)
                    displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
            }
        }
    }

    private var leadTimeSection: some View {
        Section(header: Text("Advance Alert")) {
            Stepper(
                leadMinutes == 0
                    ? "None"
                    : "\(leadMinutes) min before",
                value: $leadMinutes,
                in: 0...1440,
                step: 15
            )
            .accessibilityLabel("Advance alert minutes: \(leadMinutes)")
        }
    }

    private var recurrenceSection: some View {
        Section(header: Text("Repeat")) {
            Picker("Repeat", selection: $recurrenceType) {
                Text("None").tag(RecurrenceType.none)
                Text("Daily").tag(RecurrenceType.daily)
                Text("Weekly").tag(RecurrenceType.weekly)
                Text("Monthly").tag(RecurrenceType.monthly)
                Text("Yearly").tag(RecurrenceType.yearly)
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Recurrence frequency")

            // Weekday picker (only for weekly)
            if recurrenceType == .weekly {
                weekdayPicker
            }
        }
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("On days")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(weekdayData, id: \.int) { day in
                    let selected = selectedWeekdays.contains(day.int)
                    Button {
                        if selected {
                            selectedWeekdays.remove(day.int)
                        } else {
                            selectedWeekdays.insert(day.int)
                        }
                    } label: {
                        Text(day.short)
                            .font(.caption)
                            .fontWeight(selected ? .semibold : .regular)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(selected ? Color.accentColor : Color(.tertiarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(day.name), \(selected ? "selected" : "not selected")")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var endRuleSection: some View {
        Section(header: Text("End")) {
            Picker("Ends", selection: $endRuleType) {
                Text("Never").tag(EndRuleType.never)
                Text("On Date").tag(EndRuleType.onDate)
                Text("After").tag(EndRuleType.afterCount)
            }
            .pickerStyle(.menu)
            .accessibilityLabel("End rule")

            if endRuleType == .onDate {
                // Disclosure row for end date picker
                Button {
                    showEndDatePicker.toggle()
                } label: {
                    HStack {
                        Text("End Date")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(endDate.formattedAsReminderDate(isAllDay: true))
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        Image(systemName: showEndDatePicker ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)

                if showEndDatePicker {
                    DatePicker(
                        "End date",
                        selection: $endDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                }
            }

            if endRuleType == .afterCount {
                Stepper(
                    "\(afterCount) \(afterCount == 1 ? "time" : "times")",
                    value: $afterCount,
                    in: 1...365  // T-03-13: clamp N ≥ 1
                )
                .accessibilityLabel("Repeat \(afterCount) times")
            }
        }
    }

    private var yearlyPinSection: some View {
        Section {
            Toggle("Pin to top", isOn: $pinToTop)
                .accessibilityLabel("Pin note to top")
        } footer: {
            Text("Yearly reminders are pinned to the top of your notes.")
        }
    }

    private var removeSection: some View {
        Section {
            Button(role: .destructive) {
                showRemoveConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Text("Remove Reminder")
                    Spacer()
                }
            }
            .accessibilityLabel("Remove reminder")
        }
    }

    // MARK: - Load fields from model

    private func loadFields() {
        isAllDay = target.reminderIsAllDay
        reminderDate = target.reminderDate ?? Date().addingTimeInterval(3600)
        leadMinutes = max(0, target.reminderLeadMinutes)  // T-03-13: clamp ≥ 0

        if let data = target.reminderRecurrenceData,
           let rec = try? JSONDecoder().decode(ReminderRecurrence.self, from: data) {
            recurrenceType = rec.type
            if let days = rec.weekdays, !days.isEmpty {
                selectedWeekdays = Set(days)
            }
        }

        if let data = target.reminderEndRuleData,
           let rule = try? JSONDecoder().decode(ReminderEndRule.self, from: data) {
            endRuleType = rule.type
            if let d = rule.endDate { endDate = d }
            if let n = rule.occurrenceCount { afterCount = max(1, n) }  // T-03-13: clamp ≥ 1
        }

        // Default yearly pin from current isPinned state
        if let note = target.owningNote {
            pinToTop = note.isPinned
        }
    }

    // MARK: - Save

    private func saveReminder() async {
        isSaving = true
        defer { isSaving = false }

        let center = SystemNotificationCenter()

        // In-context permission request on first-ever reminder (D3-12)
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Permission request error — treat as denied
            await MainActor.run { permissionDenied = true }
            return
        }

        guard granted else {
            await MainActor.run { permissionDenied = true }
            return
        }

        // Build recurrence value type
        let weekdaysArray: [Int]? = (recurrenceType == .weekly && !selectedWeekdays.isEmpty)
            ? selectedWeekdays.sorted()
            : nil
        let recurrence = ReminderRecurrence(type: recurrenceType, weekdays: weekdaysArray)

        // Build end rule value type
        var endRule = ReminderEndRule(type: endRuleType)
        switch endRuleType {
        case .onDate: endRule.endDate = endDate
        case .afterCount: endRule.occurrenceCount = max(1, afterCount)  // T-03-13
        case .never: break
        }

        // Encode to Data? (rule 8 — no stored enums)
        guard let recurrenceData = try? JSONEncoder().encode(recurrence),
              let endRuleData = try? JSONEncoder().encode(endRule) else {
            return
        }

        // Cancel-then-rebuild: cancel old notifications before scheduling new ones (Open Q2)
        let oldRecurrence: ReminderRecurrence
        if let oldData = target.reminderRecurrenceData,
           let old = try? JSONDecoder().decode(ReminderRecurrence.self, from: oldData) {
            oldRecurrence = old
        } else {
            oldRecurrence = ReminderRecurrence()
        }
        let oldLeadCount = target.reminderLeadMinutes > 0 ? 1 : 0
        let oldWeekdays: [Int] = oldRecurrence.weekdays ?? []

        let scheduler = NotificationScheduler(center: center)
        scheduler.cancel(
            reminderID: target.reminderID,
            leadCount: oldLeadCount,
            weekdays: oldWeekdays
        )

        // Write reminder fields to the model
        target.reminderEnabled = true
        target.reminderDate = reminderDate
        target.reminderIsAllDay = isAllDay
        target.reminderRecurrenceData = recurrenceData
        target.reminderEndRuleData = endRuleData
        target.reminderLeadMinutes = max(0, leadMinutes)  // T-03-13

        // Yearly auto-pin (D3-09)
        if recurrenceType == .yearly, let note = target.owningNote {
            note.isPinned = pinToTop
        }

        // Schedule new notifications (Pitfall 3 — save context AFTER schedule)
        let info = ReminderInfo(
            id: target.reminderID,
            title: target.displayTitle,
            date: reminderDate,
            isAllDay: isAllDay,
            recurrence: recurrence,
            endRule: endRule,
            leadMinutes: leadMinutes > 0 ? [leadMinutes] : []  // T-03-13
        )
        do {
            try await scheduler.schedule(info)
        } catch {
            // Scheduling error is non-fatal — model is still saved (best effort)
        }

        // Pitfall 3: always save context after scheduling
        do {
            try context.save()
        } catch {
            // T-03-16: no note body in error — silent assertionFailure
            assertionFailure("ReminderEditView: failed to save context after scheduling")
        }

        await MainActor.run { dismiss() }
    }

    // MARK: - Remove

    private func removeReminder() {
        let scheduler = NotificationScheduler(center: SystemNotificationCenter())

        // Cancel all pending notifications for this reminder
        let leadCount = target.reminderLeadMinutes > 0 ? 1 : 0
        var weekdays: [Int] = []
        if let data = target.reminderRecurrenceData,
           let rec = try? JSONDecoder().decode(ReminderRecurrence.self, from: data) {
            weekdays = rec.weekdays ?? []
        }
        scheduler.cancel(reminderID: target.reminderID, leadCount: leadCount, weekdays: weekdays)

        // Clear model fields
        target.reminderEnabled = false
        target.reminderDate = nil
        target.reminderIsAllDay = false
        target.reminderRecurrenceData = nil
        target.reminderEndRuleData = nil
        target.reminderLeadMinutes = 0

        do {
            try context.save()
        } catch {
            assertionFailure("ReminderEditView: failed to save after removing reminder")
        }

        dismiss()
    }

    // MARK: - Weekday data

    private struct WeekdayInfo {
        let int: Int    // 1=Sun..7=Sat (Calendar convention)
        let short: String
        let name: String
    }

    private let weekdayData: [WeekdayInfo] = [
        WeekdayInfo(int: 1, short: "S", name: "Sunday"),
        WeekdayInfo(int: 2, short: "M", name: "Monday"),
        WeekdayInfo(int: 3, short: "T", name: "Tuesday"),
        WeekdayInfo(int: 4, short: "W", name: "Wednesday"),
        WeekdayInfo(int: 5, short: "T", name: "Thursday"),
        WeekdayInfo(int: 6, short: "F", name: "Friday"),
        WeekdayInfo(int: 7, short: "S", name: "Saturday"),
    ]
}
