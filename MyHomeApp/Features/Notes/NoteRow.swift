import SwiftUI
import SwiftData

/// A single row in the Notes list.
///
/// Shows: title (headline 20pt), pin icon (accent when pinned, tap toggles isPinned),
/// reminder badge, and a preview of checked/unchecked blocks.
///
/// Accessibility: pin button and checkbox controls have descriptive labels (UI-SPEC §6).
/// Security: T-03-12 — no note content is logged in this view.
struct NoteRow: View {

    @Bindable var note: Note
    @Environment(\.modelContext) private var context

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Title + block preview
            VStack(alignment: .leading, spacing: 4) {
                // Title — headline 20pt semibold (UI-SPEC §2)
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Block preview (first 3 blocks at most)
                let blocks = sortedBlocks
                if !blocks.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(blocks.prefix(3)) { block in
                            blockPreview(block)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right-side column: pin + reminder badge
            VStack(alignment: .trailing, spacing: 4) {
                // Pin toggle button (≥44pt target via padding)
                Button {
                    togglePin()
                } label: {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin")
                        .font(.subheadline)
                        .foregroundStyle(note.isPinned ? Color.accentColor : Color.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(note.isPinned ? "Unpin note" : "Pin note")

                // Reminder badge — count of blocks + note-level reminders
                let reminderCount = reminderBlockCount
                if reminderCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        Text("\(reminderCount)")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                    .accessibilityLabel("\(reminderCount) reminder\(reminderCount == 1 ? "" : "s")")
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Block Preview

    @ViewBuilder
    private func blockPreview(_ block: NoteBlock) -> some View {
        if block.kindRaw == "checkbox" {
            HStack(spacing: 6) {
                Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                    .font(.caption)
                    .foregroundStyle(block.isChecked ? Color.secondary : Color.primary)
                // Checked rows: strikethrough + 60% opacity (UI-SPEC §2 + §5)
                Text(block.text.isEmpty ? " " : block.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .strikethrough(block.isChecked)
                    .opacity(block.isChecked ? 0.6 : 1.0)
                    .lineLimit(1)
            }
            .accessibilityLabel("\(block.isChecked ? "Checked" : "Unchecked"): \(block.text)")
        } else {
            Text(block.text.isEmpty ? " " : block.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Computed

    /// Blocks sorted: open items first, checked items last (open-above-checked).
    private var sortedBlocks: [NoteBlock] {
        let all = note.blocks ?? []
        let sorted = all.sorted { a, b in
            // Primary sort: order field
            if a.order != b.order { return a.order < b.order }
            return false
        }
        // Checked items sink to bottom
        let open = sorted.filter { !$0.isChecked }
        let checked = sorted.filter { $0.isChecked }
        return open + checked
    }

    /// Count of reminder-enabled blocks + note-level reminder.
    private var reminderBlockCount: Int {
        let blockReminders = (note.blocks ?? []).filter { $0.reminderEnabled }.count
        let noteReminder = note.reminderEnabled ? 1 : 0
        return blockReminders + noteReminder
    }

    // MARK: - Actions

    private func togglePin() {
        note.isPinned.toggle()
        note.modifiedAt = Date()
        // Explicit save (CR-01)
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save pin toggle: \(error)")
        }
    }
}
