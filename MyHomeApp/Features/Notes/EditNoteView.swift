import SwiftUI
import SwiftData

// MARK: - Debouncer

/// Isolated debounce unit for auto-save — testable without the view (NOT-05).
///
/// Usage: call `schedule { action }` after each edit. The action fires only after
/// `delay` seconds of silence (rapid calls coalesce into a single trailing execution).
///
/// Implementation detail: uses `Task` + `try await Task.sleep` to avoid Combine/Timer
/// (@Observable / @State only discipline — PATTERNS.md Shared Patterns).
@MainActor
final class Debouncer {
    private var task: Task<Void, Never>?
    let delay: TimeInterval

    init(delay: TimeInterval = 0.5) {
        self.delay = delay
    }

    func schedule(action: @MainActor @escaping () -> Void) {
        task?.cancel()
        task = Task { [delay] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                action()
            } catch {
                // Task cancelled (new edit arrived) — do nothing.
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

// MARK: - EditNoteView

/// Full-screen block editor for a note (title + interleaved text/checkbox blocks).
///
/// Auto-save: debounced ~500ms via `Debouncer` (NOT-05, T-03-10).
/// No save button (UI-SPEC §5).
/// Discard-on-empty-title: if title is empty on dismiss, the note is deleted (D3-03, T-03-10).
/// Plain TextField only — never TextEditor/AttributedString (Pitfall 1).
/// 03-06 HOOK: "Set Reminder" entry points are marked with REMINDER_HOOK comments.
///
/// Security: T-03-11 (error copy shown to user), T-03-12 (no body content in logs).
/// Phase 12: Routine section (D-10), daily reminder (D-04/D-05), completion recording (D-06),
///           compact streak + RoutineDetailView link (D-09), drag-to-reorder (D-11).
struct EditNoteView: View {

    @Bindable var note: Note
    /// CR-03: when arriving via a block-level reminder deep-link, the row to scroll to + highlight.
    var targetBlockID: UUID? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// CR-03: transient highlight for the deep-linked block row (cleared after a beat).
    @State private var focusedBlockID: UUID? = nil

    @State private var isDirty: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var saveError: Bool = false
    /// WR-09: set once the note is deleted/discarded so an in-flight debounced save that
    /// resolves afterward becomes a no-op instead of saving a deleted/half-applied context.
    @State private var noteRemoved: Bool = false

    // Debouncer for auto-save (isolated so AutoSaveTests can verify directly — NOT-05)
    @State private var debouncer = Debouncer(delay: 0.5)

    // 03-06: Reminder sheet state
    @State private var showNoteReminder: Bool = false
    @State private var reminderBlock: NoteBlock? = nil   // nil = note-level, non-nil = block-level

    // Phase 12: drag-to-reorder edit mode (D-11)
    @State private var editMode: EditMode = .inactive

    // Phase 12: notification permission denied alert (T-12-06)
    @State private var showNotificationDeniedAlert: Bool = false

    // Phase 12: @Query for completions — predicate captured in init (Pitfall 4)
    @Query private var completions: [RoutineCompletion]

    // MARK: - Init

    init(note: Note, targetBlockID: UUID? = nil) {
        self.note = note
        self.targetBlockID = targetBlockID
        // Pitfall 4: capture note.id into a local before the predicate
        let noteID = note.id
        self._completions = Query(
            filter: #Predicate<RoutineCompletion> { $0.noteID == noteID },
            sort: [SortDescriptor(\.dayKey, order: .reverse)]
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Title field (required — D3-03)
                        titleField
                            .padding(.top, 16)

                        // Block list (interleaved text + checkbox blocks)
                        blockList

                        // Add block buttons
                        addBlockButtons
                            .padding(.bottom, 16)

                        // Phase 12: Routine section (D-10) — always visible so user can opt in
                        routineSection
                    }
                    .padding(.horizontal, 16)
                }
                // CR-03: scroll to + briefly highlight the deep-linked block row.
                .onAppear { focusDeepLinkedBlock(using: proxy) }
            }
            .navigationTitle(note.title.isEmpty ? "New Note" : note.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        debouncer.cancel()
                        flushSave()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete note")
                }
                // 03-06: Note-level "Set Reminder" toolbar button
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        reminderBlock = nil
                        showNoteReminder = true
                    } label: {
                        Image(systemName: note.reminderEnabled ? "bell.fill" : "bell")
                    }
                    .accessibilityLabel(note.reminderEnabled ? "Edit reminder" : "Set reminder")
                }
                // Phase 12: drag-to-reorder toggle (D-11)
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Reorder items")
                }
            }
            .confirmationDialog(
                "Delete Note?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Note", role: .destructive) {
                    deleteNote()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this note? This cannot be undone.")
            }
            .alert("Couldn't save note. Please try again.", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            }
            // Phase 12: notification permission denied alert (T-12-06 / UI-SPEC Error States)
            .alert("Couldn't schedule reminder", isPresented: $showNotificationDeniedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Enable notifications in Settings > MyHome.")
            }
            // 03-06: Reminder edit sheet — single sheet per parent-coordinated handoff discipline
            .sheet(isPresented: $showNoteReminder) {
                if let block = reminderBlock {
                    ReminderEditView(target: .block(block))
                } else {
                    ReminderEditView(target: .note(note))
                }
            }
        }
        .onDisappear {
            debouncer.cancel()
            handleDismiss()
        }
    }

    // MARK: - Title Field

    private var titleField: some View {
        // Plain TextField — never TextEditor/AttributedString (Pitfall 1, T-03-12)
        TextField("Title", text: $note.title)
            .font(.title2)
            .fontWeight(.semibold)
            .onChange(of: note.title) { _, _ in
                markDirty()
            }
            .accessibilityLabel("Note title")
    }

    // MARK: - Block List

    @ViewBuilder
    private var blockList: some View {
        let blocks = blocksForDisplay
        if blocks.isEmpty {
            Text("Tap below to add a note or checklist item.")
                .font(.body)
                .foregroundStyle(.secondary)
        } else if editMode.isEditing {
            // Phase 12: nested List required for .onMove (Open Question #2 resolved)
            // Wrap in a List only when in edit mode; keep ScrollView+VStack path when not editing.
            List {
                ForEach(blocks) { block in
                    blockRow(block)
                }
                .onMove { source, destination in
                    reorderBlocks(from: source, to: destination)
                }
            }
            .environment(\.editMode, $editMode)
            .frame(height: CGFloat(blocks.count) * 52)
            .listStyle(.plain)
        } else {
            ForEach(blocks) { block in
                blockRow(block)
            }
        }
    }

    @ViewBuilder
    private func blockRow(_ block: NoteBlock) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if block.kindRaw == "checkbox" {
                // Checkbox toggle button (≥44pt target)
                Button {
                    toggleCheck(block)
                } label: {
                    Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                        .font(.body)
                        .foregroundStyle(block.isChecked ? Color.secondary : Color.accentColor)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(block.isChecked ? "Uncheck item" : "Check item")
            }

            // Plain TextField — never TextEditor (Pitfall 1)
            TextField(
                block.kindRaw == "checkbox" ? "Checklist item" : "Note text",
                text: Binding(
                    get: { block.text },
                    set: { newValue in
                        block.text = newValue
                        markDirty()
                    }
                ),
                axis: .vertical
            )
            .font(.body)
            .foregroundStyle(block.isChecked ? Color.secondary.opacity(0.6) : .primary)
            .strikethrough(block.isChecked)
            .opacity(block.isChecked ? 0.6 : 1.0)
            .lineLimit(1...10)
            // 03-06: per-block "Set Reminder" context menu
            .contextMenu {
                Button {
                    reminderBlock = block
                    showNoteReminder = true
                } label: {
                    Label(
                        block.reminderEnabled ? "Edit Reminder" : "Set Reminder",
                        systemImage: block.reminderEnabled ? "bell.fill" : "bell"
                    )
                }
                if block.reminderEnabled {
                    Button(role: .destructive) {
                        cancelBlockReminder(block)
                    } label: {
                        Label("Remove Reminder", systemImage: "bell.slash")
                    }
                }
            }
        }
        .padding(.vertical, 4)
        // CR-03: stable id for ScrollViewReader + transient highlight on deep-link arrival.
        .id(block.id)
        .listRowBackground(Color.clear)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(focusedBlockID == block.id ? Color.accentColor.opacity(0.15) : Color.clear)
        )
    }

    // MARK: - Deep-link focus

    /// CR-03: scrolls to the deep-linked block and pulses a highlight so the user sees which row
    /// the reminder belonged to. No-op when not arriving from a block-level deep-link.
    private func focusDeepLinkedBlock(using proxy: ScrollViewProxy) {
        guard let targetBlockID else { return }
        // Defer one runloop so the rows exist before scrolling.
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(targetBlockID, anchor: .center) }
            focusedBlockID = targetBlockID
        }
        // Fade the highlight out after a short beat.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { focusedBlockID = nil }
        }
    }

    // MARK: - Add Block Buttons

    private var addBlockButtons: some View {
        HStack(spacing: 16) {
            Button {
                addBlock(kind: "text")
            } label: {
                Label("Add Text", systemImage: "text.cursor")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Add text block")
            .frame(minHeight: 44)

            Button {
                addBlock(kind: "checkbox")
            } label: {
                Label("Add Item", systemImage: "checkmark.square")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Add checklist item")
            .frame(minHeight: 44)

            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Routine Section (Phase 12 — D-10/D-04/D-06/D-09)

    /// Routine section — always visible so users can opt any note into a daily routine.
    /// GroupBox("Routine") per UI-SPEC Surface 1.
    /// Security: T-12-10 — all strings via plain Text(...), never AttributedString.
    @ViewBuilder
    private var routineSection: some View {
        GroupBox("Routine") {
            VStack(alignment: .leading, spacing: 12) {
                // D-10: Toggle to mark note as a daily routine
                Toggle("Daily Routine", isOn: $note.isDailyRoutine)
                    .onChange(of: note.isDailyRoutine) { _, isOn in
                        if !isOn {
                            note.routineDailyReminderTime = nil
                        }
                        // T-12-06: always cancel first, then re-schedule if on+time set
                        RoutineNotificationService().cancel(noteID: note.id)
                        if isOn, let time = note.routineDailyReminderTime {
                            Task {
                                await RoutineNotificationService().schedule(
                                    noteID: note.id,
                                    title: note.title,
                                    time: time
                                )
                            }
                        }
                        markDirty()
                    }

                if note.isDailyRoutine {
                    // D-04: Daily Reminder enable toggle — derived from routineDailyReminderTime != nil
                    Toggle("Daily Reminder", isOn: Binding(
                        get: { note.routineDailyReminderTime != nil },
                        set: { enabled in
                            if enabled {
                                // Default fire time: 07:00 IST (D-04)
                                note.routineDailyReminderTime = Calendar.current.date(
                                    bySettingHour: 7, minute: 0, second: 0, of: Date()
                                )
                            } else {
                                note.routineDailyReminderTime = nil
                                RoutineNotificationService().cancel(noteID: note.id)
                            }
                            markDirty()
                        }
                    ))

                    // D-04: Time picker — visible only when reminder is enabled
                    if note.routineDailyReminderTime != nil {
                        DatePicker(
                            "Time",
                            selection: Binding(
                                get: { note.routineDailyReminderTime! },
                                set: { newTime in
                                    note.routineDailyReminderTime = newTime
                                    // D-05: cancel-then-add on time change
                                    RoutineNotificationService().cancel(noteID: note.id)
                                    Task {
                                        await RoutineNotificationService().schedule(
                                            noteID: note.id,
                                            title: note.title,
                                            time: newTime
                                        )
                                    }
                                    markDirty()
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }

                    // D-06: "Done today" button — shown ONLY for text-only routines (no checkbox blocks)
                    if (note.blocks ?? []).filter({ $0.kindRaw == "checkbox" }).isEmpty {
                        Button("Done today") {
                            recordTodayCompletion()
                            markDirty()
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                    }

                    // D-09: Compact streak + NavigationLink to full history
                    HStack {
                        // T-12-10: plain Text — no AttributedString
                        Text("🔥 \(currentStreak) day streak")
                            .font(.subheadline)
                        Spacer()
                        NavigationLink("Routine History") {
                            RoutineDetailView(note: note)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Streak Computed Property (Phase 12 — D-09)

    /// Current streak count — uses StreakCalculator with IST calendar (mirrors RoutineResetService).
    private var currentStreak: Int {
        var istCal = Calendar(identifier: .gregorian)
        istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return StreakCalculator.compute(
            for: note.id,
            completions: completions,
            today: Date(),
            calendar: istCal
        ).currentStreak
    }

    // MARK: - Computed

    /// Blocks sorted: open items first, checked items last (open-above-checked per UI-SPEC §5).
    private var sortedBlocks: [NoteBlock] {
        let all = note.blocks ?? []
        let sorted = all.sorted { $0.order < $1.order }
        let open = sorted.filter { !$0.isChecked }
        let checked = sorted.filter { $0.isChecked }
        return open + checked
    }

    /// Phase 12 (D-11): switch between raw-order (for drag reorder) and display-sorted blocks.
    private var blocksForDisplay: [NoteBlock] {
        editMode.isEditing
            ? (note.blocks ?? []).sorted { $0.order < $1.order }   // raw order for reorder drag
            : sortedBlocks                                            // open-above-checked (existing)
    }

    // MARK: - Auto-Save

    private func markDirty() {
        isDirty = true
        note.modifiedAt = Date()
        // Debounced auto-save: fires ~500ms after last edit (NOT-05)
        debouncer.schedule { [self] in
            saveIfDirty()
        }
    }

    private func saveIfDirty() {
        guard isDirty else { return }
        performSave()
    }

    private func flushSave() {
        guard isDirty else { return }
        performSave()
    }

    private func performSave() {
        // WR-09: never save once the note has been deleted/discarded (a debounced save may
        // resolve after delete on the same run loop).
        guard !noteRemoved, note.modelContext != nil else { return }
        // T-03-12: no note body content in error strings
        do {
            try context.save()
            isDirty = false
        } catch {
            // T-03-11: surface error copy to user, assert in debug
            assertionFailure("Failed to save note: \(error)")
            saveError = true
        }
    }

    // MARK: - Dismiss Handler

    private func handleDismiss() {
        let trimmed = note.title.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            // T-03-10: discard-on-empty-title (D3-03)
            noteRemoved = true   // WR-09: block any in-flight debounced save
            context.delete(note)
            do {
                try context.save()
            } catch {
                assertionFailure("Failed to discard untitled note: \(error)")
            }
        } else if isDirty {
            performSave()
        }
    }

    // MARK: - Actions

    private func addBlock(kind: String) {
        let existingBlocks = note.blocks ?? []
        let maxOrder = existingBlocks.map { $0.order }.max() ?? -1
        let block = NoteBlock(kindRaw: kind, text: "", order: maxOrder + 1)
        block.note = note
        context.insert(block)
        if note.blocks == nil { note.blocks = [] }
        note.blocks?.append(block)
        markDirty()
    }

    private func toggleCheck(_ block: NoteBlock) {
        block.isChecked.toggle()
        // 03-06: when a row is checked, cancel its future reminder/advance alerts (D3-04)
        if block.isChecked && block.reminderEnabled {
            cancelBlockReminder(block)
        }
        // Phase 12 (D-06): if this is a routine note and a block was just checked,
        // verify all boxes are checked and record a completion at check-time.
        if note.isDailyRoutine && block.isChecked {
            checkAndRecordCompletion()
        }
        markDirty()
    }

    /// Phase 12 (D-06): guard all checkbox blocks are checked, then record today's completion.
    private func checkAndRecordCompletion() {
        let checkboxBlocks = (note.blocks ?? []).filter { $0.kindRaw == "checkbox" }
        guard !checkboxBlocks.isEmpty else { return }
        guard checkboxBlocks.allSatisfy(\.isChecked) else { return }
        recordTodayCompletion()
    }

    /// Phase 12 (D-06/D-08): fetch-before-insert idempotent completion record.
    ///
    /// Writes/upserts a RoutineCompletion keyed by (noteID, IST-dayKey).
    /// Called at check-time (before RoutineResetService can wipe isChecked) — T-12-07.
    /// No .unique constraint used — CloudKit rule 2; dedup is in app code.
    private func recordTodayCompletion() {
        // IST day key — mirrors RoutineResetService.swift lines 26-29
        var istCal = Calendar(identifier: .gregorian)
        istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let dayKey = istCal.startOfDay(for: Date())
        let noteID = note.id
        // Fetch-before-insert for idempotency (no .unique — CloudKit rule 2)
        let descriptor = FetchDescriptor<RoutineCompletion>(
            predicate: #Predicate { $0.noteID == noteID && $0.dayKey == dayKey }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.completedAt = Date()
        } else {
            let completion = RoutineCompletion(noteID: noteID, dayKey: dayKey)
            context.insert(completion)
        }
        // Save is handled by the calling markDirty() path (debounced auto-save)
    }

    /// Phase 12 (D-11): re-index NoteBlock.order after drag-to-reorder.
    private func reorderBlocks(from source: IndexSet, to destination: Int) {
        var ordered = (note.blocks ?? []).sorted { $0.order < $1.order }
        ordered.move(fromOffsets: source, toOffset: destination)
        for (idx, block) in ordered.enumerated() {
            block.order = idx   // re-index: 0, 1, 2, ...
        }
        markDirty()
    }

    /// Cancels all pending notifications for a block-level reminder and clears the model fields.
    private func cancelBlockReminder(_ block: NoteBlock) {
        let leadCount = block.reminderLeadMinutes > 0 ? 1 : 0
        var weekdays: [Int] = []
        if let data = block.reminderRecurrenceData,
           let rec = try? JSONDecoder().decode(ReminderRecurrence.self, from: data) {
            weekdays = rec.weekdays ?? []
        }
        let scheduler = NotificationScheduler(center: SystemNotificationCenter())
        scheduler.cancel(reminderID: block.id, leadCount: leadCount, weekdays: weekdays)

        block.reminderEnabled = false
        block.reminderDate = nil
        block.reminderIsAllDay = false
        block.reminderRecurrenceData = nil
        block.reminderEndRuleData = nil
        block.reminderLeadMinutes = 0
        markDirty()
    }

    private func deleteNote() {
        debouncer.cancel()
        noteRemoved = true   // WR-09: block any in-flight debounced save
        // T-12-06: cancel routine notification before deleting (no orphaned notifications)
        RoutineNotificationService().cancel(noteID: note.id)
        context.delete(note)
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to delete note: \(error)")
        }
        dismiss()
    }
}
