import SwiftUI

/// Notes tab root view — List | Calendar segmented host (D3-17).
///
/// Owns its NavigationStack. The segmented control switches between:
///   - `NotesListView` (shipped in plan 03-05)
///   - `CalendarView` (LazyVGrid month grid — 03-06)
///
/// `deepLinkNoteID`: injected by RootView when a notification banner tap arrives
/// (kOpenNoteNotification). Forces the view to the List segment and forwards the
/// UUID to NotesListView, which opens the matching EditNoteView sheet.
///
/// Satisfies: NOT-01..06 (note keeper), D3-17 (segmented tab root).
struct NotesHomeView: View {

    // MARK: - Deep-link

    @Binding var deepLinkNoteID: UUID?

    // MARK: - Init

    /// Default constant binding keeps existing previews and callers that don't
    /// inject a deep-link binding (e.g. previews) compiling unchanged.
    init(deepLinkNoteID: Binding<UUID?> = .constant(nil)) {
        self._deepLinkNoteID = deepLinkNoteID
    }

    // MARK: - Segment state

    private enum NoteSegment: Int, CaseIterable {
        case list
        case calendar

        var label: String {
            switch self {
            case .list: return "List"
            case .calendar: return "Calendar"
            }
        }
    }

    @State private var selectedSegment: NoteSegment = .list

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control header
                segmentedHeader

                // Content area — switch on segment
                switch selectedSegment {
                case .list:
                    NotesListView(deepLinkNoteID: $deepLinkNoteID)
                case .calendar:
                    // 03-06: CalendarView — LazyVGrid month grid with per-day counts + agenda
                    CalendarView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
        }
        // When a deep-link arrives, switch to the list segment so NotesListView is active
        .onChange(of: deepLinkNoteID) { _, newID in
            if newID != nil {
                selectedSegment = .list
            }
        }
    }

    // MARK: - Segmented Header

    private var segmentedHeader: some View {
        Picker("View", selection: $selectedSegment) {
            ForEach(NoteSegment.allCases, id: \.self) { segment in
                Text(segment.label).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}
