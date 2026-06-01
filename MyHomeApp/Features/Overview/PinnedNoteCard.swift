import SwiftUI
import SwiftData

/// Overview Card 3: Pinned note preview with deep-link to Notes tab (OVR-03).
///
/// Dumb/value-driven: consumes a pre-resolved `note: Note?` from the parent's
/// `OverviewAggregation.pinnedOrChecklistNote` result. No @Query.
///
/// `isFallbackChecklist` is `true` when the note came from the checklist fallback
/// (not a pinned note) — controls the Row A chip icon and foreground color.
///
/// Threat mitigations:
/// - T-04-06: Note title and block text rendered via plain `Text(...)` ONLY.
///   Never use AttributedString with markdown to prevent link injection.
/// - T-04-07: Deep-link is a plain integer @Binding assignment; no URL parsing.
///
/// Accessibility:
/// - `.accessibilityElement(children: .combine)` on the card.
/// - "Open note" button has explicit `.accessibilityLabel`.
struct PinnedNoteCard: View {

    let note: Note?
    let isFallbackChecklist: Bool
    @Binding var selectedTab: Int
    @Binding var deepLinkNoteID: UUID?

    // MARK: - Helpers

    /// Returns the first non-empty block text from the note for the preview row.
    /// Prefix checkbox blocks with "☐ " (unchecked) or "☑ " (checked).
    private func firstBlockPreview(_ note: Note) -> String? {
        guard let blocks = note.blocks else { return nil }
        let sorted = blocks.sorted { $0.order < $1.order }
        for block in sorted {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if block.kindRaw == "checkbox" {
                return (block.isChecked ? "☑ " : "☐ ") + text
            }
            return text
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row A — Card title + chip
            HStack {
                Text("Pinned Note")
                    .font(.title2)
                    .bold()
                Spacer()
                if isFallbackChecklist {
                    Image(systemName: "checklist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }

            if let note = note {
                // Row B — Note title (plain Text — T-04-06)
                Text(note.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Row C — First block preview (plain Text — T-04-06)
                if let preview = firstBlockPreview(note) {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Row D — "Open note" deep-link button
                HStack {
                    Spacer()
                    Button("Open note") {
                        deepLinkNoteID = note.id
                        selectedTab = 3
                    }
                    .font(.subheadline)
                    .tint(.accentColor)
                    .accessibilityLabel("Open \(note.title) in Notes tab")
                }
            } else {
                // Empty state — no pinned note and no checklist note
                Text("Pin a note to see it here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    Spacer()
                    Button("Go to Notes") {
                        selectedTab = 3
                    }
                    .font(.subheadline)
                    .tint(.accentColor)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview("Empty state") {
    @Previewable @State var tab = 0
    @Previewable @State var noteID: UUID? = nil
    PinnedNoteCard(
        note: nil,
        isFallbackChecklist: false,
        selectedTab: $tab,
        deepLinkNoteID: $noteID
    )
    .padding()
}
