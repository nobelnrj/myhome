import SwiftUI
import SwiftData

/// Sheet for creating a new note.
///
/// Creates a Note with the required title; immediately presents the block editor (EditNoteView).
/// Untitled notes are discarded on dismiss (D3-03, T-03-10).
///
/// Implementation: Task 2 (TDD, plan 03-05).
struct AddNoteView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var createdNote: Note? = nil
    @State private var showEditor: Bool = false

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
                    .tint(.accentColor)
                }
            }
            .sheet(isPresented: $showEditor, onDismiss: { dismiss() }) {
                if let note = createdNote {
                    EditNoteView(note: note)
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
        createdNote = note
        showEditor = true
    }
}
