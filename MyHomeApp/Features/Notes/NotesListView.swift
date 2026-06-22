import SwiftUI
import SwiftData

/// Sectioned, searchable Notes list.
///
/// Sections (D3-08, NOT-03/04): Daily Routine → Pinned → Other (most-recent-first within each).
/// Search (NOT-06): in-memory via NoteSearchFilter (Assumption A2 — avoids #Predicate reach into
/// NoteBlock.text; per Open Question 3 in RESEARCH, block-text search via #Predicate is not
/// feasible in SwiftData 1.x without relationship joins — in-memory filter is correct).
///
/// `deepLinkNoteID`: injected by NotesHomeView when a notification deep-link arrives.
/// When non-nil the view looks up the matching Note and sets `editingNote` to open it
/// via the existing `.sheet(item: $editingNote)`. Resets `deepLinkNoteID` to nil after
/// consuming it. Single-sheet discipline preserved — no nested sheets added (03-05).
///
/// Reads via @Query (sort: modifiedAt, order: .reverse); writes via modelContext (no repository).
/// Security: T-03-08 (in-memory filter), T-03-11/12 (explicit save + no content in logs),
///           T-03-14 (deep-link maps deterministic UUID → correct note only).
struct NotesListView: View {

    // MARK: - Deep-link

    @Binding var deepLinkNoteID: UUID?
    /// CR-03: Target block row for block-level reminder deep-links.
    @Binding var deepLinkBlockID: UUID?

    // MARK: - Init

    /// Default constant binding keeps previews and existing callers that omit
    /// the deep-link param compiling unchanged.
    init(deepLinkNoteID: Binding<UUID?> = .constant(nil), deepLinkBlockID: Binding<UUID?> = .constant(nil)) {
        self._deepLinkNoteID = deepLinkNoteID
        self._deepLinkBlockID = deepLinkBlockID
    }

    @Query(sort: \Note.modifiedAt, order: .reverse) private var notes: [Note]
    @Environment(\.modelContext) private var context

    @State private var showingAddSheet: Bool = false
    @State private var editingNote: Note? = nil
    @State private var noteToEditAfterAdd: Note? = nil
    @State private var searchText: String = ""
    /// CR-03: Block row to focus when opening a note via block-level deep-link.
    @State private var deepLinkTargetBlockID: UUID? = nil

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
                .tint(DesignTokens.accent)
                .accessibilityLabel("Add Note")
            }
        }
        .searchable(text: $searchText, prompt: "Search notes")
        // Parent-coordinated sequential sheets: AddNoteView dismisses first, then
        // onDismiss hands the created note to EditNoteView. Only one sheet is ever
        // presented at a time — no nested-sheet anti-pattern (bug fix 03-05).
        .sheet(isPresented: $showingAddSheet, onDismiss: {
            if let n = noteToEditAfterAdd {
                noteToEditAfterAdd = nil
                editingNote = n
            }
        }) {
            AddNoteView(onCreated: { noteToEditAfterAdd = $0 })
        }
        .sheet(item: $editingNote) { note in
            // CR-03: Pass target block ID for row focus when arriving via block-level deep-link.
            EditNoteView(note: note, targetBlockID: deepLinkTargetBlockID)
                .onDisappear { deepLinkTargetBlockID = nil }
        }
        // Deep-link: when a noteID arrives, locate the matching Note and open its editor.
        // Reuses the existing editingNote sheet — no nested sheet (03-05 single-sheet rule).
        .onChange(of: deepLinkNoteID) { _, newID in
            guard let id = newID else { return }
            if let match = notes.first(where: { $0.id == id }) {
                editingNote = match
            }
            deepLinkNoteID = nil
        }
        // CR-03: Block-level deep-link — capture target block and open the owning note.
        .onChange(of: deepLinkBlockID) { _, newBlockID in
            guard let blockID = newBlockID else { return }
            // Find the note that owns this block (broken into explicit steps so the
            // type-checker does not time out on the nested optional-collection closures).
            var owningNote: Note?
            for note in notes {
                let blocks: [NoteBlock] = note.blocks ?? []
                if blocks.contains(where: { $0.id == blockID }) {
                    owningNote = note
                    break
                }
            }
            if let note = owningNote {
                deepLinkTargetBlockID = blockID
                editingNote = note
            }
            deepLinkBlockID = nil
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
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture { editingNote = note }
                    }
                    .onDelete { offsets in
                        deleteNotes(s.dailyRoutine, at: offsets)
                    }
                } header: {
                    Text("Daily Routine")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignTokens.label2)
                        .textCase(.uppercase)
                        .padding(.top, 24)
                }
            }

            // Pinned section
            if !s.pinned.isEmpty {
                Section {
                    ForEach(s.pinned) { note in
                        NoteRow(note: note)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture { editingNote = note }
                    }
                    .onDelete { offsets in
                        deleteNotes(s.pinned, at: offsets)
                    }
                } header: {
                    Text("Pinned")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignTokens.label2)
                        .textCase(.uppercase)
                        .padding(.top, 24)
                }
            }

            // Other section
            if !s.other.isEmpty {
                Section {
                    ForEach(s.other) { note in
                        NoteRow(note: note)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture { editingNote = note }
                    }
                    .onDelete { offsets in
                        deleteNotes(s.other, at: offsets)
                    }
                } header: {
                    if !s.dailyRoutine.isEmpty || !s.pinned.isEmpty {
                        Text("All Notes")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DesignTokens.label2)
                            .textCase(.uppercase)
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
        .scrollContentBackground(.hidden)
        .background(DesignTokens.bgCanvas)
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
