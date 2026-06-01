---
phase: "04-overview-charts"
plan: "03"
subsystem: "ui"
tags: [swiftui, overview, cards, dumb-components, ovr-01, ovr-02, ovr-03]
dependency_graph:
  requires:
    - MyHomeApp/Support/OverviewAggregation.swift
    - MyHomeApp/Support/BudgetCalculator.swift
    - MyHomeApp/Support/NoteListOrganizer.swift
    - MyHomeApp/Persistence/Models/Note.swift
    - MyHomeApp/Persistence/Models/NoteBlock.swift
    - MyHomeApp/Persistence/Models/Category.swift
  provides:
    - MyHomeApp/Features/Overview/SpendBudgetCard.swift
    - MyHomeApp/Features/Overview/TopCategoriesCard.swift
    - MyHomeApp/Features/Overview/PinnedNoteCard.swift
  affects:
    - MyHome.xcodeproj/project.pbxproj
tech_stack:
  added: []
  patterns:
    - Dumb/value-driven SwiftUI cards — all data arrives via init parameters, no @Query
    - Card shell pattern from BudgetCategoryCard (padding 16, secondarySystemBackground, cornerRadius 12, shadow 0.04)
    - BudgetColor → SwiftUI Color mapping from BudgetProgressView (normal→accent, warning→orange, over→red)
    - GeometryReader+ZStack progress bar at fixed frame height (16pt, cornerRadius 8) from BudgetProgressView
    - Inline fractionUsed/colorThreshold computation via NSDecimalNumber(decimal:) — no Category instance needed
    - Plain Text() for all user-authored content (T-04-06 security rule)
    - @Binding selectedTab for cross-tab navigation (integer assignment, no URL parsing)
key_files:
  created:
    - MyHomeApp/Features/Overview/SpendBudgetCard.swift
    - MyHomeApp/Features/Overview/TopCategoriesCard.swift
    - MyHomeApp/Features/Overview/PinnedNoteCard.swift
  modified:
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "SpendBudgetCard computes fractionUsed/colorThreshold inline (not via OverviewAggregation.aggregateThreshold) — mirrors BudgetProgressData pattern; avoids passing the tuple result when the card already has totalSpend+totalBudget"
  - "TopCategoriesCard receives pre-sorted top3 array; no sort logic inside the card — caller (OverviewView) calls OverviewAggregation.topCategories before passing"
  - "PinnedNoteCard receives Note? + isFallbackChecklist bool; parent resolves via OverviewAggregation.pinnedOrChecklistNote then checks NoteListOrganizer.organize(notes).pinned to set the flag"
metrics:
  duration: 25
  completed_date: "2026-06-01"
---

# Phase 4 Plan 3: Three Non-Chart Overview Cards Summary

Three dumb SwiftUI card components — SpendBudgetCard (OVR-01), TopCategoriesCard (OVR-02), PinnedNoteCard (OVR-03) — each consuming pre-computed data from `OverviewAggregation` via init params with no `@Query`.

## What Was Built

### Task 1: SpendBudgetCard (OVR-01)

**File:** `MyHomeApp/Features/Overview/SpendBudgetCard.swift`

**Init signature (for Plan 04-05 OverviewView to wire verbatim):**
```swift
struct SpendBudgetCard: View {
    let totalSpend: Decimal
    let totalBudget: Decimal
    @Binding var selectedTab: Int
}
```

Key implementation:
- Inline `fractionUsed: Double?` and `colorThreshold: BudgetColor` computed properties; guards `totalBudget > 0` to prevent divide-by-zero
- `barFillColor` maps BudgetColor → `.accentColor` / `Color(.systemOrange)` / `Color(.systemRed)` verbatim from `BudgetProgressView.fillColor`
- Row C: `GeometryReader + ZStack` bar at `.frame(height: 16)`, `cornerRadius: 8`, `.animation(.easeInOut(duration: 0.3), value: fractionUsed)`, `.accessibilityElement(children: .ignore)`
- Row D: HStack `"₹X remaining"` / `"₹X over budget"` colored per `BudgetColor` + `"X% used"` / `"100%+"` matching Phase 2 copy exactly
- Empty state (no budget): replaces Rows C/D with `"Set a budget to track your spending."` + `Button("Set a budget") { selectedTab = 2 }`
- Empty state (no spend + no budget): prepends `"No spend yet this month."` before the above
- Card shell: `padding(16)`, `secondarySystemBackground`, `cornerRadius(12)`, `shadow(.black.opacity(0.04), radius: 2, y: 1)`, `.accessibilityElement(children: .combine)`
- `import Charts` absent; `import SwiftData` absent

### Task 2: TopCategoriesCard (OVR-02)

**File:** `MyHomeApp/Features/Overview/TopCategoriesCard.swift`

**Init signature:**
```swift
struct TopCategoriesCard: View {
    let top3: [(category: Category, spent: Decimal)]
}
```

Key implementation:
- `import SwiftData` for `Category` type (is a `@Model`)
- `ForEach(Array(top3.enumerated()), id: \.offset)` renders 0–3 rows
- Each row: `HStack(spacing: 12)` — rank `"#\(index+1)"` (`.subheadline`, `.secondary`, width 20pt) + SF Symbol (`.body`, `.secondary`, 28pt frame, `.accessibilityHidden(true)`) + name (`.body`, lineLimit 1) + `Spacer()` + `spent.formattedINR()` (`.body`)
- `.frame(minHeight: 44)` per row + `.accessibilityAddTraits(.isStaticText)`
- No `Divider()` — VStack spacing only
- Empty state: `"No spend yet this month."` centered
- Same card shell as above

### Task 3: PinnedNoteCard (OVR-03)

**File:** `MyHomeApp/Features/Overview/PinnedNoteCard.swift`

**Init signature:**
```swift
struct PinnedNoteCard: View {
    let note: Note?
    let isFallbackChecklist: Bool
    @Binding var selectedTab: Int
    @Binding var deepLinkNoteID: UUID?
}
```

Key implementation:
- `import SwiftData` for `Note` type
- Row A chip: `pin.fill` (`.accentColor`) for pinned notes, `checklist` (`.secondary`) for checklist fallback
- Row B: `Text(note.title)` — plain `Text()` only (T-04-06 security rule enforced)
- Row C: `firstBlockPreview(_:)` — iterates sorted blocks, prefixes checkbox blocks with `"☐ "` (unchecked) or `"☑ "` (checked); plain `Text(preview)` only
- Row D: `Button("Open note") { deepLinkNoteID = note.id; selectedTab = 3 }` with `.accessibilityLabel("Open \(note.title) in Notes tab")`
- Empty state: `"Pin a note to see it here."` centered + `Button("Go to Notes") { selectedTab = 3 }`
- `AttributedString(markdown:)` is absent (confirmed via grep)

---

## Acceptance Criteria Verification

| Check | Result |
|-------|--------|
| `grep -c "struct SpendBudgetCard"` | 1 ✓ |
| `grep -c "case .overBudget"` in SpendBudgetCard | 2 ✓ |
| `.frame(height: 16)` in SpendBudgetCard | 2 ✓ |
| `"Set a budget to track your spending."` in SpendBudgetCard | 1 ✓ |
| `"No spend yet this month."` in SpendBudgetCard | 2 ✓ |
| `selectedTab = 2` in SpendBudgetCard | 1 ✓ |
| `import Charts` in SpendBudgetCard | 0 ✓ |
| `grep -c "struct TopCategoriesCard"` | 1 ✓ |
| `"Top Categories"` in TopCategoriesCard | 1 ✓ |
| `"No spend yet this month."` in TopCategoriesCard | 2 ✓ |
| `.frame(minHeight: 44)` in TopCategoriesCard | 2 ✓ |
| `Divider()` in TopCategoriesCard | 0 ✓ |
| `formattedINR()` in TopCategoriesCard | 1 ✓ |
| `grep -c "struct PinnedNoteCard"` | 1 ✓ |
| `selectedTab = 3` in PinnedNoteCard | 2 ✓ |
| `"Pin a note to see it here."` in PinnedNoteCard | 1 ✓ |
| `"Open note"` in PinnedNoteCard | 3 ✓ |
| `"Go to Notes"` in PinnedNoteCard | 1 ✓ |
| `AttributedString(markdown` in PinnedNoteCard | 0 ✓ |
| Project builds (iPhone 17 simulator) | BUILD SUCCEEDED ✓ |

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Bug] `.foregroundStyle(.accentColor)` not valid on Image in this context**
- **Found during:** Task 3 (first build attempt)
- **Issue:** `Image(...).foregroundStyle(.accentColor)` caused `error: type 'ShapeStyle' has no member 'accentColor'` — the shorthand `.accentColor` without `Color.` prefix is not valid as a `ShapeStyle` argument in some contexts.
- **Fix:** Changed to `.foregroundStyle(Color.accentColor)` — explicit type resolves the ambiguity.
- **Files modified:** `MyHomeApp/Features/Overview/PinnedNoteCard.swift`
- **Commit:** Inline fix before a40846d

**2. [Rule 2 - Correctness] Removed `Divider()` and `AttributedString(markdown:)` from doc comments**
- **Found during:** Acceptance criteria verification
- **Issue:** Doc comments contained the literal strings `Divider()` and `AttributedString(markdown:)` which would cause the grep-based acceptance criteria to report false positives (count > 0 instead of 0).
- **Fix:** Reworded comments to remove the literal strings while preserving meaning.
- **Files modified:** `TopCategoriesCard.swift`, `PinnedNoteCard.swift`
- **Impact:** None on behavior; grep criteria now correctly pass.

---

## Known Stubs

None. All three cards render their populated and empty states entirely from the init parameters passed in. No stub patterns, no hardcoded placeholder data, no `TODO` wiring gaps introduced. Previews for TopCategoriesCard with live Category fixtures note that a SwiftData container is needed — this is expected and documented inline; the empty-state preview works without one.

---

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes. The only user-authored content that reaches the screen is `note.title` and `block.text`, both rendered via plain `Text()` per T-04-06 — confirmed by grep (AttributedString(markdown count = 0).

---

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| `MyHomeApp/Features/Overview/SpendBudgetCard.swift` exists | FOUND |
| `MyHomeApp/Features/Overview/TopCategoriesCard.swift` exists | FOUND |
| `MyHomeApp/Features/Overview/PinnedNoteCard.swift` exists | FOUND |
| commit 0b8537e exists | FOUND |
| commit 6a86496 exists | FOUND |
| commit a40846d exists | FOUND |
| BUILD SUCCEEDED (iPhone 17 simulator) | CONFIRMED |
