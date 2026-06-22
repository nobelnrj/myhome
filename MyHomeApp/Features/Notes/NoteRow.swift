import SwiftUI
import SwiftData

/// A single row in the Notes list — neumorphic card (SKIN-04).
///
/// Shows: title (16pt semibold), pin icon (orange when pinned), reminder badge,
/// and a preview of checked/unchecked blocks.
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
                // Title — 16pt semibold (UI-SPEC Screen 4)
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignTokens.label)
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
                        .font(.system(size: 16))
                        .foregroundStyle(note.isPinned ? DesignTokens.orange : DesignTokens.label3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(note.isPinned ? "Unpin note" : "Pin note")

                // Reminder badge — design-style pill
                let reminderCount = reminderBlockCount
                if reminderCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                        Text(reminderBadgeText(count: reminderCount))
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(DesignTokens.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(DesignTokens.accent.opacity(0.12), in: Capsule())
                    .accessibilityLabel("\(reminderCount) reminder\(reminderCount == 1 ? "" : "s")")
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .neuSurface(.raised, isInteractive: true)
        .contentShape(Rectangle())
    }

    // MARK: - Block Preview

    @ViewBuilder
    private func blockPreview(_ block: NoteBlock) -> some View {
        if block.kindRaw == "checkbox" {
            HStack(spacing: 6) {
                // Unchecked: label3; checked: accent (UI-SPEC Screen 4)
                Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                    .font(.caption)
                    .foregroundStyle(block.isChecked ? DesignTokens.accent : DesignTokens.label3)
                // Done text: label3 + strikethrough (UI-SPEC Screen 4)
                Text(block.text.isEmpty ? " " : block.text)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.label3)
                    .strikethrough(block.isChecked)
                    .opacity(block.isChecked ? 0.6 : 1.0)
                    .lineLimit(1)
            }
            .accessibilityLabel("\(block.isChecked ? "Checked" : "Unchecked"): \(block.text)")
        } else {
            // Preview body: 14pt label2 (UI-SPEC Screen 4)
            Text(block.text.isEmpty ? " " : block.text)
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.label2)
                .lineLimit(1)
        }
    }

    // MARK: - Computed

    /// Blocks sorted: open items first, checked items last (open-above-checked).
    private var sortedBlocks: [NoteBlock] {
        let all = note.blocks ?? []
        let sorted = all.sorted { a, b in
            if a.order != b.order { return a.order < b.order }
            return false
        }
        let open = sorted.filter { !$0.isChecked }
        let checked = sorted.filter { $0.isChecked }
        return open + checked
    }

    /// Pill text: the note-level reminder's short date when present, else the reminder count.
    private func reminderBadgeText(count: Int) -> String {
        if note.reminderEnabled, let date = note.reminderDate {
            return date.formattedAsReminderBadge()
        }
        return "\(count)"
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
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save pin toggle: \(error)")
        }
    }
}
