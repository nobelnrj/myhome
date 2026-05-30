---
status: draft
phase: 03
name: notes-checklists
design_system: manual (SwiftUI, iOS 17+, no shadcn)
---

# UI Design Contract — Phase 03: Notes & Checklists

## 1. Spacing

- **Base scale:** 8-point (4, 8, 16, 24, 32, 48, 64)
- **List row vertical padding:** 12px (to match iOS grouped lists)
- **Touch targets:** Minimum 44x44pt for all actionable icons (checkbox, pin, add, reminder)
- **Block spacing:** 16pt between note blocks (paragraphs, checklist rows)
- **Section spacing:** 24pt between "Daily Routine", "Pinned", and "Other Notes" sections

## 2. Typography

- **Font sizes:**
  - Body: 16pt (primary note text, checklist rows)
  - Secondary: 14pt (dates, reminder meta, empty/error states)
  - Headline: 20pt (note titles, section headers)
  - Large Title: 28pt (Calendar month label)
- **Font weights:**
  - Regular (400): body, checklist, meta
  - Semibold (600): note titles, section headers, CTA buttons
- **Line heights:**
  - Body: 1.5
  - Headings: 1.2
- **Checklist checked rows:** Strikethrough + 60% opacity

## 3. Color

- **Dominant surface (60%):** System background (white/ultra-thin material)
- **Secondary (30%):** Grouped list backgrounds, calendar grid, card surfaces (systemGroupedBackground)
- **Accent (10%):** System blue (`accentColor`) — reserved for:
  - Primary CTA ("Add Note", "Save", "Set Reminder")
  - Pin icon (active state)
  - Reminder action buttons (Complete, Snooze)
  - Calendar day with reminders (dot/accent)
- **Destructive:** System red — only for "Delete Note" and "Remove Reminder" actions

## 4. Copywriting

- **Primary CTA label:** "Add Note"
- **Empty state copy:**  
  - List: "No Notes Yet"  
    Description: "Tap + to capture your first note or checklist."
  - Calendar: "No Reminders"  
    Description: "Scheduled reminders will appear here."
- **Error state copy:**  
  - "Couldn't save note. Please try again."
  - "Notification permission denied. Enable in Settings to receive reminders."
- **Destructive actions:**
  - "Delete Note" (confirmation: "Are you sure you want to delete this note? This cannot be undone.")
  - "Remove Reminder" (confirmation: "Remove this reminder from the note?")
- **Reminder action labels:**  
  - "Complete" (marks checklist row as done, cancels future reminders)
  - "Snooze" (refires in 1 hour)

## 5. Visual & Interaction Patterns

- **Note model:** Block list (ordered text paragraphs and checklist rows)
- **Checklist:** Checking a row moves it below open items, applies strikethrough + dim
- **Pinning:** Manual toggle; yearly reminders suggest auto-pin (toggle pre-checked)
- **Reminders:** Attach to note or any block; all-day or timed; recurrence (none/daily/weekly-with-weekdays/monthly/yearly); end rules (never/on date/after N)
- **Notifications:** Request permission on first use; actionable (Complete/Snooze); tap deep-links to note/block
- **Calendar:** Segmented control (List | Calendar) in Notes tab; month grid with per-day reminder counts; tap day → agenda with completion progress
- **Search:** `.searchable` covers note title + all block text
- **Auto-save:** Debounced 500ms after edit, no explicit save button
- **Untitled note:** Discarded on dismiss

## 6. Accessibility

- All touch targets ≥44x44pt
- Dynamic Type supported (use `.font(.body)`, `.font(.headline)` etc.)
- VoiceOver: All actionable elements (checkbox, pin, reminder) have descriptive labels
- Sufficient color contrast (system colors)

## 7. Registry

- **Tool:** none (manual SwiftUI, no shadcn, no third-party blocks)

## 8. Integration Points

- **TabView:** Add "Notes" tab in `RootView.swift` (segmented List/Calendar inside)
- **Schema:** Additive `SchemaV3` (do not mutate V1/V2); follow CloudKit rules
- **Notification scheduling:** Isolated service, unit-testable, pure scheduling logic
- **Date formatting:** Extend `Date+Display.swift` for reminder/calendar labels
- **Empty state:** Use `ContentUnavailableView` pattern from Expenses

---

## References

- All requirements and decisions sourced from:
  - `.planning/REQUIREMENTS.md` (NOT-01..06, expanded per context)
  - `.planning/phases/03-notes-checklists/03-CONTEXT.md` (D3-01..D3-19, phase boundary, specifics)
  - `.planning/ROADMAP.md` (Phase 3, context, and success criteria)
  - Existing code: `ExpenseListView.swift`, `Date+Display.swift`, `RootView.swift`

---
