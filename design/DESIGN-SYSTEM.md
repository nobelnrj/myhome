# MyHome — Design System (current baseline)

> Snapshot of the app's actual visual language as of Phase 7 (2026-06-03).
> **Two uses:** (1) paste into **Claude Design** as brand guidelines so its mockups match the real app; (2) the reference for translating any mockup back into SwiftUI.

## TL;DR — the system is "iOS native"
The app deliberately leans on Apple's system design. There is **no custom color palette and no custom fonts** — it uses SwiftUI semantic colors and the system (San Francisco) type scale. Keep new designs in this idiom unless we consciously decide to brand harder.

## Color
| Token | Value | Used for |
|---|---|---|
| Accent | **iOS system default (blue)** — `AccentColor.colorset` is empty | Primary actions, links, selection, tab selection |
| `.primary` | System label | Main text |
| `.secondary` | System secondary label | Subtitles, metadata, captions (most common: 63 uses) |
| `.tertiary` | System tertiary label | Faint/disabled text |
| `.red` | System red | Destructive / negative (e.g. overspend, reversals) |
| `.orange` | System orange | Warnings / attention |
| `.white`, `.clear` | — | Backgrounds / overlays |

Automatically supports light & dark mode because everything is semantic. **Do not introduce hard-coded hex colors** — pick a semantic role or add a named colorset.

## Typography (system text styles — Dynamic Type safe)
`largeTitle` · `title2` · `headline` · `body` · `subheadline` (most used) · `caption` · `caption2`
- No custom font files. Stays legible at all accessibility text sizes.

## Spacing & layout
- **4-point grid.** Observed stack spacings: 0, 2, 4, 6, 8, 12, 16, 32.
- Default screen padding: **16**.
- Standard SwiftUI components: `List`, `NavigationStack`, `.sheet`, `tabItem`, `Form`.

## Navigation — 5 tabs
1. **Home** (`Overview/OverviewView`)
2. **Expenses** (`Expenses/ExpenseListView`) — Phase 7 adds the Review Inbox here
3. **Budgets** (`Budgets/BudgetsView`)
4. **Notes** (`Notes/NotesHomeView`)
5. **Settings** (`Settings/SettingsView`) — Gmail connect / "Connected as"

## Key screens (for feedback targeting)
- Expenses: `ExpenseListView`, `AddExpenseView`, `EditExpenseView`, `ExpenseRow`, `DecimalKeypadView`, `CategoryPickerView`
- Budgets: `BudgetsView`, `BudgetProgressView`, `ManageCategoriesView`, `FilteredExpenseListView`
- Notes/Reminders: `NotesHomeView`, `NotesListView`, `CalendarView`, `AddNoteView`, `ReminderEditView`
- Overview: `OverviewView`
- Settings: `SettingsView`, `UnlockView` (Face ID gate)

## Constraints to respect in any redesign
- iPhone 17 / iOS 26, Xcode 26.5, SwiftUI, module `MyHome`.
- Face ID lock gates sensitive content (`UnlockView` / LockController).
- iOS 26 **Liquid Glass** material is available if we want a modern glass treatment.

## Handoff note
Claude Design outputs HTML/web prototypes, **not SwiftUI**. Treat its mockups as a *visual target*; iOS specifics (nav bars, lists, sheets, glass) get rebuilt natively and verified in the iPhone 17 simulator.
