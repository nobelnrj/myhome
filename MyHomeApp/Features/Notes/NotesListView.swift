import SwiftUI
import SwiftData

/// Sectioned, searchable Notes list.
///
/// Sections (D3-08, NOT-03/04): Daily Routine → Pinned → Other (most-recent-first within each).
/// Search (NOT-06): in-memory via NoteSearchFilter (Assumption A2 — avoids #Predicate reach into
/// NoteBlock.text; per Open Question 3 in RESEARCH, block-text search via #Predicate is not
/// feasible in SwiftData 1.x without relationship joins — in-memory filter is correct).
///
/// Reads via @Query (sort: modifiedAt, order: .reverse); writes via modelContext (no repository).
/// Security: T-03-08 (in-memory filter), T-03-11/12 (explicit save + no content in logs).
struct NotesListView: View {

    @Query(sort: \Note.modifiedAt, order: .reverse) private var notes: [Note]
    @Environment(\.modelContext) private var context

    @State private var showingAddSheet: Bool = false
    @State private var editingNote: Note? = nil
    @State private var searchText: String = ""

    // MARK: - Computed

    /// Notes after applying search filter, then partitioned into sections.
    private var sections: NoteListSections {
        let filtered = NoteSearchFilter.filter(notes, query: searchText)
        return NoteListOrganizer.organize(filtered)
    }

    // MARK: - Body

    var body: some View {
        Group {
            if notes.isEmpty {
                ContentUnavailableView(
                    "No Notes Yet",
                    systemImage: "note.text",
                    description: Text("Tap + to capture your first note or checklist.")
                )
            } else {
                notesList
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
                .tint(.accentColor)
                .accessibilityLabel("Add Note")
            }
        }
        .searchable(text: $searchText, prompt: "Search notes")
        .sheet(isPresented: $showingAddSheet) {
            AddNoteView()
        }
        .sheet(item: $editingNote) { note in
            EditNoteView(note: note)
        }
    }

    // MARK: - Notes List

    @ViewBuilder
    private var notesList: some View {
        List {
            let s = sections

            // Daily Routine section
            if !s.dailyRoutine.isEmpty {
                Section {
                    ForEach(s.dailyRoutine) { note in
                        NoteRow(note: note)
                            .contentShape(Rectangle())
                            .onTapGesture { editingNote = note }
                    }
                    .onDelete { offsets in
                        deleteNotes(s.dailyRoutine, at: offsets)
                    }
                } header: {
                    Text("Daily Routine")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.top, 24)
                }
            }

            // Pinned section
            if !s.pinned.isEmpty {
                Section {
                    ForEach(s.pinned) { note in
                        NoteRow(note: note)
                            .contentShape(Rectangle())
                            .onTapGesture { editingNote = note }
                    }
                    .onDelete { offsets in
                        deleteNotes(s.pinned, at: offsets)
                    }
                } header: {
                    Text("Pinned")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.top, 24)
                }
            }

            // Other section
            if !s.other.isEmpty {
                Section {
                    ForEach(s.other) { note in
                        NoteRow(note: note)
                            .contentShape(Rectangle())
                            .onTapGesture { editingNote = note }
                    }
                    .onDelete { offsets in
                        deleteNotes(s.other, at: offsets)
                    }
                } header: {
                    if !s.dailyRoutine.isEmpty || !s.pinned.isEmpty {
                        Text("Other Notes")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .padding(.top, 24)
                    }
                }
            }

            // Empty search results
            if !searchText.isEmpty && s.dailyRoutine.isEmpty && s.pinned.isEmpty && s.other.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Actions

    private func deleteNotes(_ sectionNotes: [Note], at offsets: IndexSet) {
        for index in offsets {
            context.delete(sectionNotes[index])
        }
        // CR-01: persist the delete explicitly
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save after deleting note: \(error)")
            print("Failed to save after deleting note: \(error)")
        }
    }
}
