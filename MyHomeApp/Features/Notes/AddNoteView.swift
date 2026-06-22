import SwiftUI
import SwiftData

/// Sheet for creating a new note.
///
/// Creates a Note with the required title, then calls `onCreated` with the new note and dismisses.
/// The caller (NotesListView) receives the note via `onCreated` and presents EditNoteView AFTER
/// this sheet fully dismisses — parent-coordinated sequential sheets (no nested sheets).
///
/// Untitled notes are discarded on dismiss (D3-03, T-03-10) — guarded by the disabled Add Note button.
///
/// Implementation: Task 2 (TDD, plan 03-05). Bug fix: 03-05 nested-sheet anti-pattern.
struct AddNoteView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""

    /// Called with the newly-created Note just before this sheet dismisses.
    /// NotesListView holds the note and presents EditNoteView via onDismiss handoff.
    var onCreated: (Note) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // T-03-10 plain TextField — never TextEditor/AttributedString (Pitfall 1)
                    TextField("Note title", text: $title)
                        .font(.headline)
                        .accessibilityLabel("Note title")
                }
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Note") {
                        createNote()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .tint(DesignTokens.accent)
                }
            }
        }
    }

    // MARK: - Actions

    private func createNote() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let note = Note(title: trimmed)
        context.insert(note)
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save new note: \(error)")
        }
        // Hand off the note to the parent, then dismiss.
        // NotesListView will present EditNoteView after this sheet fully dismisses.
        onCreated(note)
        dismiss()
    }
}
