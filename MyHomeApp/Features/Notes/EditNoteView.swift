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
struct EditNoteView: View {

    @Bindable var note: Note
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var isDirty: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var saveError: Bool = false

    // Debouncer for auto-save (isolated so AutoSaveTests can verify directly — NOT-05)
    @State private var debouncer = Debouncer(delay: 0.5)

    // MARK: - Body

    var body: some View {
        NavigationStack {
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
                }
                .padding(.horizontal, 16)
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
                // 03-06 HOOK: "Set Reminder" toolbar button goes here
                // ToolbarItem(placement: .primaryAction) { ... }
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
        let blocks = sortedBlocks
        if blocks.isEmpty {
            Text("Tap below to add a note or checklist item.")
                .font(.body)
                .foregroundStyle(.secondary)
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
            // 03-06 HOOK: per-block "Set Reminder" context menu goes here
            // .contextMenu { ... }
        }
        .padding(.vertical, 4)
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

    // MARK: - Computed

    /// Blocks sorted: open items first, checked items last (open-above-checked per UI-SPEC §5).
    private var sortedBlocks: [NoteBlock] {
        let all = note.blocks ?? []
        let sorted = all.sorted { $0.order < $1.order }
        let open = sorted.filter { !$0.isChecked }
        let checked = sorted.filter { $0.isChecked }
        return open + checked
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
        // 03-06 HOOK: when isChecked becomes true, cancel future reminder for this block
        // NotificationScheduler.cancel(for: block, center: notificationCenter)
        markDirty()
    }

    private func deleteNote() {
        debouncer.cancel()
        context.delete(note)
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to delete note: \(error)")
        }
        dismiss()
    }
}
