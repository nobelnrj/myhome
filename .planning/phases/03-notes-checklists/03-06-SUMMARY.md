---
phase: 03-notes-checklists
plan: "06"
subsystem: ui
tags: [swiftui, usernotifications, lazyvgrid, deep-link, reminder, recurrence, calendar]

# Dependency graph
requires:
  - phase: 03-03
    provides: NotificationScheduler + NotificationCenterPort (schedule/cancel/buildRequests)
  - phase: 03-04
    provides: CalendarAggregator (per-day counts + day completion progress)
  - phase: 03-05
    provides: EditNoteView reminder hooks + NotesHomeView calendar segment placeholder

provides:
  - ReminderEditView: full reminder picker (all-day/timed, lead-time, recurrence, end rule, yearly auto-pin)
  - CalendarView: LazyVGrid month grid + per-day counts + tapped-day agenda with completion progress
  - NotificationActions: Complete/Snooze category registration + UNUserNotificationCenterDelegate
  - Live local notifications: categoryIdentifier+userInfo stamped in NotificationScheduler.makeRequest
  - Deep-link wiring: RootView tab-selection binding + NotesListView kOpenNoteNotification observer
  - Calendar day-agenda checkboxes: live Button bindings with completion + notification-cancel

affects: [04-overview-charts, phase-05-settings]

# Tech tracking
tech-stack:
  added: [UserNotifications (Complete/Snooze UNNotificationAction), UNUserNotificationCenterDelegate]
  patterns:
    - Cancel-then-rebuild for reminder reschedule (avoids orphan accumulation)
    - categoryIdentifier stamped at makeRequest time so OS delivers action buttons
    - noteID/blockID threaded through ReminderInfo.userInfo for deep-link routing
    - TabView driven by @State selection binding in RootView for programmatic navigation
    - AgendaReminderItem/ReminderTarget struct wrappers for live model binding in day agenda

key-files:
  created:
    - MyHomeApp/Features/Notes/ReminderEditView.swift
    - MyHomeApp/Support/NotificationActions.swift
    - MyHomeApp/Features/Notes/CalendarView.swift
  modified:
    - MyHomeApp/Features/Notes/EditNoteView.swift
    - MyHomeApp/Features/Notes/NotesHomeView.swift
    - MyHomeApp/MyHomeApp.swift
    - MyHomeApp/Support/NotificationScheduler.swift
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "categoryIdentifier must be stamped on UNMutableNotificationRequest at make-time (not at schedule-time) — iOS silently drops actions if category is absent from the request"
  - "Deep-link routes through a single kOpenNoteNotification NSNotification so any view-hierarchy depth can respond without a custom environment key"
  - "TabView selection held as @State in RootView and passed as Binding so NotesListView can programmatically switch tabs on deep-link"
  - "Calendar day-agenda rows use AgendaReminderItem/ReminderTarget wrappers binding directly to Note/NoteBlock so completion state is live — a detached snapshot would silently be stale"
  - "Snooze reschedules ~1h via NotificationScheduler without modifying the stored reminder date, so the model stays clean"

patterns-established:
  - "NotificationActions pattern: register UNNotificationCategory at app launch via idempotent seed-hook; delegate set once on UNUserNotificationCenter"
  - "Cancel-then-rebuild: always cancel by existing identifier set before scheduling new requests (prevents phantom accumulation below the 64-cap)"
  - "Live agenda binding: never snapshot model data into a separate struct for UI that needs to reflect completion — bind the @Model directly"

requirements-completed: [NOT-07, NOT-08, NOT-09, NOT-10]

# Metrics
duration: multi-session
completed: 2026-05-31
---

# Phase 03 Plan 06: Reminders Hub + Live Notifications Summary

**ReminderEditView with full recurrence/end-rule/yearly-pin, LazyVGrid Calendar with live completion progress, and actionable local notifications (Complete/Snooze/deep-link) wired end-to-end through UNUserNotificationCenterDelegate — human UAT passed on iPhone 17 simulator.**

## Performance

- **Duration:** multi-session
- **Started:** 2026-05-30
- **Completed:** 2026-05-31
- **Tasks:** 3 (Tasks 1-2 auto, Task 3 human UAT checkpoint)
- **Files modified:** 8

## Accomplishments

- Full reminder editing sheet: all-day/timed toggle, date+time picker, lead-time stepper, recurrence menu (none/daily/weekly-with-weekday-picker/monthly/yearly), end rule (never/on-date/after-N), yearly-only pre-checked "Pin to top" toggle; wired into EditNoteView for note-level and per-block reminders
- LazyVGrid Calendar segment in Notes tab: month grid with per-day reminder counts/dots from CalendarAggregator, tapped-day agenda with x/y completion progress, empty state; replaces the 03-05 placeholder
- Complete/Snooze actionable notifications: UNNotificationCategory registered at launch; UNUserNotificationCenterDelegate Complete action checks the target row and cancels future advance alerts; Snooze reschedules ~1h; tap deep-links into the correct note/row
- Human UAT passed (iPhone 17, Xcode 26.5): in-context permission prompt, timed banner fires, Complete checks row + cancels future, Snooze re-fires ~1h, deep-link opens correct note, calendar per-day counts + tapped-day agenda completable with live progress

## Task Commits

Each task was committed atomically:

1. **Task 1: ReminderEditView + EditNoteView hooks** — `8a3494a` (feat)
2. **Task 2: CalendarView + NotificationActions + app wiring** — `06ae800` (feat)
3. **Task 3: Manual UAT — Human approved** (no files modified)

**Post-UAT fix commits:**
- `fa24d87` — fix: stamp categoryIdentifier+userInfo on notification requests
- `1c32d91` — fix: wire RootView tab-selection binding + NotesListView deep-link observer
- `8583ecf` — fix: bind calendar day-agenda checkboxes to live model

## Files Created/Modified

- `MyHomeApp/Features/Notes/ReminderEditView.swift` — All-day/timed picker, lead-time stepper, recurrence menu (incl. weekday picker), end-rule picker, yearly auto-pin toggle; encodes reminder*Data fields, calls cancel-then-rebuild on NotificationScheduler, saves context
- `MyHomeApp/Support/NotificationActions.swift` — Registers Complete/Snooze UNNotificationCategory; UNUserNotificationCenterDelegate handles Complete (check row + cancel future), Snooze (~1h reschedule), and tap (deep-link via kOpenNoteNotification)
- `MyHomeApp/Features/Notes/CalendarView.swift` — LazyVGrid month grid with prev/next nav, per-day counts/dots from CalendarAggregator, tapped-day agenda with live AgendaReminderItem binding and x/y progress
- `MyHomeApp/Features/Notes/EditNoteView.swift` — Presents ReminderEditView sheet from note-level and per-block hooks; checkbox tap now cancels that row's pending reminders
- `MyHomeApp/Features/Notes/NotesHomeView.swift` — Calendar segment wired to CalendarView (replaces 03-05 placeholder)
- `MyHomeApp/MyHomeApp.swift` — Registers notification category + sets UNUserNotificationCenterDelegate at launch
- `MyHomeApp/Support/NotificationScheduler.swift` — makeRequest stamps categoryIdentifier + userInfo (noteID, blockID) on every UNMutableNotificationRequest
- `MyHome.xcodeproj/project.pbxproj` — Added ReminderEditView.swift, NotificationActions.swift, CalendarView.swift to MyHome app target

## Decisions Made

- **categoryIdentifier stamped at makeRequest time:** iOS only shows Complete/Snooze action buttons if the request itself carries the category identifier. The fix was to stamp it in `NotificationScheduler.makeRequest` rather than at the call site, so every scheduling path is covered automatically.
- **kOpenNoteNotification via NotificationCenter:** Deep-link routing uses a single named NSNotification posted by the delegate, received in NotesListView, which programmatically navigates to the correct note. This avoids threading a navigation path through the environment.
- **RootView @State tab selection:** TabView selection lifted to RootView as @State and passed as Binding so NotesListView can switch the tab when a deep-link arrives from any context.
- **AgendaReminderItem/ReminderTarget for live agenda:** Calendar day-agenda rows bind directly to Note/NoteBlock via wrapper structs rather than using a snapshot copy, ensuring completion state and notification cancellation are always live.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Notification actions (Complete/Snooze) not appearing on delivered banners**
- **Found during:** Task 3 (Manual UAT)
- **Issue:** Scheduled notifications were missing `categoryIdentifier` and `userInfo` payload — the OS therefore did not attach the registered Complete/Snooze action buttons, and there was no noteID/blockID for deep-link routing
- **Fix:** Modified `NotificationScheduler.makeRequest` to stamp `categoryIdentifier = NotificationActions.categoryID` and `userInfo = ["noteID": ..., "blockID": ...]` (threading noteID/blockID through ReminderInfo) on every UNMutableNotificationRequest it produces
- **Files modified:** `MyHomeApp/Support/NotificationScheduler.swift`, `MyHomeApp/Persistence/Models/ReminderValueTypes.swift` (ReminderInfo userInfo fields)
- **Verification:** Re-ran UAT — Complete/Snooze buttons appeared on delivered notification banner
- **Committed in:** `fa24d87`

**2. [Rule 1 - Bug] Deep-link tap opened app but did not navigate to the note**
- **Found during:** Task 3 (Manual UAT)
- **Issue:** `kOpenNoteNotification` was posted by the delegate but no observer was registered; additionally, TabView had no selection binding so programmatic tab switching was impossible
- **Fix:** Added `@State var selectedTab` in RootView with Binding passed to TabView; added `onReceive(kOpenNoteNotification)` observer in NotesListView that switches tab + pushes the target note onto the NavigationStack
- **Files modified:** `MyHomeApp/MyHomeApp.swift` (RootView tab-selection state), `MyHomeApp/Features/Notes/NotesHomeView.swift` (deep-link observer in NotesListView)
- **Verification:** Re-ran UAT — tapping delivered banner navigated directly to the correct note
- **Committed in:** `1c32d91`

**3. [Rule 1 - Bug] Calendar day-agenda checkboxes were non-interactive (static Image + detached snapshot)**
- **Found during:** Task 3 (Manual UAT)
- **Issue:** The day-agenda rows rendered a static `Image(systemName:)` for the checkbox and used a detached copy of reminder data — tapping had no effect and progress did not update
- **Fix:** Replaced the static Image with an actionable Button; introduced `AgendaReminderItem` / `ReminderTarget` wrapper structs that hold a reference to the live Note/NoteBlock `@Model`; on tap, calls the same `handleComplete` path (checks the row, cancels pending notifications); `DayProgress` recomputes live from the model
- **Files modified:** `MyHomeApp/Features/Notes/CalendarView.swift`
- **Verification:** Re-ran UAT — tapping agenda checkboxes checks the row and live progress updates
- **Committed in:** `8583ecf`

---

**Total deviations:** 3 auto-fixed (all Rule 1 — bugs found during manual UAT)
**Impact on plan:** All three fixes were required for the plan's success criteria (Complete action, deep-link, calendar completable with live progress). No scope creep.

## Issues Encountered

Three OS-owned behaviors could only be verified by the human UAT checkpoint (Task 3), which is why they were not caught earlier:
1. Category identifier absence is invisible at build time — the notification simply delivers without action buttons.
2. Deep-link wiring gap was only observable by tapping an actual banner.
3. Static calendar checkbox was only observable by interacting with the agenda view.

All three were caught and fixed within the UAT session before approval.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 3 is complete: the full Notes + Reminders hub is live (NOT-01..10, SC-R1..R5 all satisfied).
- Phase 4 (Overview & Charts) can proceed: it depends on Phase 2 (complete) and Phase 3 (now complete). It will consume the pinned-note surface and per-category spend data.
- No blockers from Phase 3 carried forward.

---
*Phase: 03-notes-checklists*
*Completed: 2026-05-31*
