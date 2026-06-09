---
phase: 08-stabilization
reviewed: 2026-06-09T00:00:00Z
depth: standard
files_reviewed: 10
files_reviewed_list:
  - MyHomeApp/Features/Budgets/ManageCategoriesView.swift
  - MyHomeApp/Features/Gmail/GmailSyncController.swift
  - MyHomeApp/Features/Notes/CalendarView.swift
  - MyHomeApp/Features/Notes/RoutineResetService.swift
  - MyHomeApp/Persistence/Schema/SchemaV5.swift
  - MyHomeApp/RootView.swift
  - MyHomeApp/Support/CalendarAggregator.swift
  - MyHomeTests/CalendarAggregationTests.swift
  - MyHomeTests/CategoryCRUDTests.swift
  - MyHomeTests/GmailSyncControllerTests.swift
findings:
  critical: 1
  warning: 6
  info: 5
  total: 12
status: issues_found
---

# Phase 8: Code Review Report

**Reviewed:** 2026-06-09
**Depth:** standard
**Files Reviewed:** 10
**Status:** issues_found

## Summary

Reviewed the Phase 8 stabilization changes targeting four live SwiftData crashes
(STAB-01..04). The tombstone guards in `CalendarAggregator` / `DayAgendaView` are
correctly applied, the Gmail sync `PersistentIdentifier` re-resolution + single-batched-save
pattern is sound, and the category insertion contract (`min(sortOrder)-1`) is right and
test-locked.

However the review surfaced one BLOCKER (an integer underflow / collision in the
category sortOrder contract that the STAB-03 fix does not actually guard against), plus
several correctness and robustness warnings concentrated in `GmailSyncController` (a
genuinely confusing double-negation that is the kind of footgun the phase set out to
eliminate, redundant un-idempotent-looking backfill, fragile string-matching auth-error
detection, and a known-stale `existingExpenses` dedup snapshot within a single sync run).

## Critical Issues

### CR-01: Category sortOrder collision when a category is deleted then re-added

**File:** `MyHomeApp/Features/Budgets/ManageCategoriesView.swift:193`
**Issue:** The STAB-03 "prepend at top" contract computes
`nextSortOrder = (all.map(\.sortOrder).min() ?? 0) - 1`. This is correct only if the
minimum monotonically decreases. It does not. `deleteCategory` (line 243) removes a row
without renumbering survivors, and there is no lower-bound floor. Concretely:

1. Seeded categories occupy `0..13`. Add "A" → `-1`. Add "B" → `-2`.
2. Delete "B" (the current minimum). The minimum is now `-1`.
3. Add "C" → `min = -1`, so `-1 - 1 = -2`. Fine.

But the more damaging path: because `sortOrder` is a plain `Int` with **no uniqueness
constraint** (SchemaV5 forbids `@Attribute(.unique)`), two categories can legitimately end
up sharing the same `sortOrder`. After repeated add/delete churn the "top" slot is not
guaranteed unique, and `@Query(sort: \Category.sortOrder)` then orders the tied rows by an
**undefined secondary key** — meaning the just-added category can render in an arbitrary
position, not the top. The STAB-03 test (`newCategoryPrependsAtTop`) only exercises the
pristine seed path (monotonic 0..13) and never deletes, so it cannot catch this. The
acceptance contract ("new category always at top") is therefore not actually guaranteed by
the implementation. There is additionally an unbounded-underflow concern over the app's
lifetime, though collision/tie-break is the practical defect.

**Fix:** Make the ordering deterministic and collision-free. Either add a stable secondary
sort key, or renumber on insert so the new row is strictly less than every survivor and ties
are impossible:
```swift
// Option A: stable tie-break so equal sortOrder never produces arbitrary order
@Query(sort: [SortDescriptor(\Category.sortOrder), SortDescriptor(\Category.createdAt, order: .reverse)])
private var categories: [Category]

// Option B: renumber survivors on insert (top = 0, push everyone down)
let all = try context.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder)]))
for (i, c) in all.enumerated() { c.sortOrder = i + 1 }
let category = Category(name: trimmed, symbolName: "tag", sortOrder: 0)
```

## Warnings

### WR-01: Confusing double-negation in deferred-backfill guard

**File:** `MyHomeApp/Features/Gmail/GmailSyncController.swift:211-215`
**Issue:** The guard reads
`!defaults.bool(forKey: GmailAccountStore.migrationDoneKey) == false`. Swift's `!` binds
tighter than `==`, so this is `(!flag) == false`, i.e. `flag == true` ("migration is done").
The comment says exactly that, so the parse happens to match intent — but this is precisely
the unreadable footgun a stabilization phase should remove, and a future edit can silently
invert it. Worse, `runMigrationIfNeeded()` runs immediately above (line 208) and, when
migration was needed, already calls `backfillSourceAccount` with the non-nil context; then
this block runs `backfillSourceAccount` again unconditionally on the same context. It is
idempotent (only touches `sourceAccount == nil` rows) so not a data bug, but it is a
redundant full `FetchDescriptor<Expense>` fetch + scan on every `setContext`.
**Fix:** Replace with a plain boolean and skip the redundant call:
```swift
let migrationDone = defaults.bool(forKey: GmailAccountStore.migrationDoneKey)
if migrationDone, let firstAccount = store.accounts.first {
    store.backfillSourceAccount(email: firstAccount.email, modelContext: context)
}
```
(And only run it when `runMigrationIfNeeded` did NOT already backfill, to avoid the double scan.)

### WR-02: Stale `existingExpenses` snapshot makes intra-run dedup unreliable

**File:** `MyHomeApp/Features/Gmail/GmailSyncController.swift:458-503` (and 616-649 in legacy path)
**Issue:** `existingExpenses` is fetched once before the message loop and used both for the
`accountMessageIDs` skip-set and for `DedupChecker.findDuplicate`. Because the single
`ctx.save()` is deferred to after the loop (the correct D-04 fix), newly inserted expenses
within this same run are never added back into `existingExpenses` or `accountMessageIDs`. If
the same `messageID` (or a content-duplicate) appears twice in one `messageIDs` page — e.g. a
reversal + original, or Gmail returning the same id — both rows are inserted, defeating the
idempotency guard for the duration of the run.
**Fix:** Track inserted ids/expenses in a local mutable set/array and consult it inside the loop:
```swift
var seenThisRun = accountMessageIDs
...
if seenThisRun.contains(messageID) { continue }
...
seenThisRun.insert(messageID)
```

### WR-03: Auth-error classification by `localizedDescription` string matching is fragile

**File:** `MyHomeApp/Features/Gmail/GmailSyncController.swift:411-414, 549-552, 692-698`
**Issue:** Recoverable-vs-fatal auth handling keys off
`error.localizedDescription.lowercased().contains("invalid_grant" / "401" / "unauthorized")`.
`localizedDescription` is locale-dependent and not a stable API contract — under a non-English
locale, or if the underlying port wraps the HTTP status differently, an expired/revoked token
will silently fail to set `needsReconnect`/`.tokenExpired`, leaving the account stuck in a
generic error with no Reconnect CTA (regressing ING-16). This is the same class of
brittleness STAB aims to remove.
**Fix:** Surface a typed error from the auth/fetch ports (e.g. `GmailAuthError.invalidGrant`,
`.unauthorized`) and switch on the case rather than string-matching the localized message.

### WR-04: `onDelete` swipe bypasses the delete confirmation actually deleting nothing visible-but-unconfirmed... and uses a stale index

**File:** `MyHomeApp/Features/Budgets/ManageCategoriesView.swift:35-40`
**Issue:** `onDelete` captures `categories[index]` into `categoryToDelete` and shows the
confirmation dialog — good. But `offsets` is an `IndexSet` that can contain more than one
index (multi-row delete), and only `offsets.first` is honored, so a multi-select delete
silently drops the rest. More importantly, the index is read against the `categories` array
at gesture time but the actual delete happens later from the dialog against the captured
object reference, which is fine — however if the `@Query` array mutates between the swipe and
the confirmation (e.g. a concurrent Gmail sync inserts/changes nothing here, but a rename
reorders via sortOrder), no crash occurs because the object ref is captured, yet the user may
confirm deletion of a row that has since scrolled. Low likelihood but worth guarding.
**Fix:** Iterate all offsets, or disable multi-delete; capture is already by-reference so keep that:
```swift
.onDelete { offsets in
    guard let index = offsets.first else { return }
    categoryToDelete = categories[index]
    showDeleteConfirmation = true
}
```
(At minimum add the `guard ... else { return }` so an empty `IndexSet` can't crash on `.first!`-style assumptions, and document that multi-delete is intentionally unsupported.)

### WR-05: `setContext` injects a possibly-nil-equivalent context and runs migration on the main actor unconditionally

**File:** `MyHomeApp/Features/Gmail/GmailSyncController.swift:205-216`, `MyHomeApp/RootView.swift:82-86`
**Issue:** `RootView.onAppear` calls `gmailSyncController.setContext(modelContext)` every time
the view appears (tab switches, re-appears after sheet dismissal can re-fire `onAppear` in
some navigation configurations). Each call re-runs `runMigrationIfNeeded()` and the
deferred-backfill block, doing a full `FetchDescriptor<Expense>` scan on the main actor. After
the first run the migration guard short-circuits cheaply, but the WR-01 backfill block still
fetches all expenses every time `onAppear` fires. On a large expense table this is main-thread
work on every appearance.
**Fix:** Guard `setContext` so the migration/backfill path runs at most once:
```swift
func setContext(_ context: ModelContext) {
    self.modelContext = context
    guard !didRunStartupMigration else { return }
    didRunStartupMigration = true
    runMigrationIfNeeded()
    ...
}
```

### WR-06: `weekdayHeader` array slicing assumes a non-empty, full-length symbol array

**File:** `MyHomeApp/Features/Notes/CalendarView.swift:137-139`
**Issue:** `let start = cal.firstWeekday - 1; let ordered = Array(symbols[start...]) + Array(symbols[..<start])`.
This is safe for the standard Gregorian calendar (`firstWeekday` ∈ 1...7, `shortWeekdaySymbols`
has 7 entries), but it is an unchecked slice indexed by a `Calendar`-derived value. A
non-Gregorian or misconfigured calendar where `firstWeekday` falls outside `1...symbols.count`
would trap at runtime. Given the app pins `Calendar.current`, the risk is low, but the slice is
unguarded.
**Fix:** Clamp `start` defensively: `let start = max(0, min(cal.firstWeekday - 1, symbols.count - 1))`.

## Info

### IN-01: SchemaV5 `Category.init` default `sortOrder: 0` is a documented footgun left live

**File:** `MyHomeApp/Persistence/Schema/SchemaV5.swift:55-61`
**Issue:** The default `sortOrder: Int = 0` is acknowledged in a long comment as a footgun
that drops new categories into the seeded `0..13` band. The comment chooses not to fix it to
preserve SchemaV5 identity. That is a reasonable schema-immutability call, but it means the
correctness of every call site depends on an unenforced convention (see CR-01). Consider a
non-schema factory helper (`Category.makeTopOfList(in:)`) that centralizes the `min-1` logic so
individual call sites cannot regress.

### IN-02: `RoutineResetService` is a logging no-op scaffold

**File:** `MyHomeApp/Features/Notes/RoutineResetService.swift:16-26`
**Issue:** `resetIfNeeded()` computes `todayIST` and only `print`s. It runs on every
`scenePhase == .active` (RootView:111). The forced-unwrap `TimeZone(identifier: "Asia/Kolkata")!`
is safe (a real tz id) and the work is trivial, so this is acceptable as a Phase 9 scaffold —
flagged only so the dangling `print` is removed before ship and not mistaken for live logic.
**Fix:** Keep, but ensure the `print` is gated behind a debug flag or removed in Phase 9.

### IN-03: `syncAccount` email-mismatch branch can clobber an in-memory token with nil

**File:** `MyHomeApp/Features/Gmail/GmailSyncController.swift:444-450`
**Issue:** When `confirmedEmail != email`, it does
`accessTokenMap[confirmedEmail] = accessTokenMap[email]`. If `accessTokenMap[email]` is nil
(token only passed as a parameter, never stored in the map — which is the common path), this
assigns `nil`, leaving `confirmedEmail` with no in-memory token even though `accessToken` (the
param) is valid for this run. Functionally harmless this run (the param is used directly) but
the map ends up inconsistent for the next sync.
**Fix:** `accessTokenMap[confirmedEmail] = accessToken` (use the known-valid parameter).

### IN-04: Duplicate ~90-line ingestion body across `syncAccount` and `legacySingleAccountSync`

**File:** `MyHomeApp/Features/Gmail/GmailSyncController.swift:488-545` vs `635-691`
**Issue:** The message-processing loop (fetch raw → header extract → parser select → confidence
→ dedup → build Expense → re-resolve category by PersistentIdentifier → insert) is duplicated
almost verbatim between the multi-account and legacy paths. The D-04 category-resolution fix had
to be applied in two places; the next change risks fixing only one. This is a maintenance hazard
directly adjacent to the bug class this phase fixed.
**Fix:** Extract a private `ingest(messageIDs:accessToken:email:dedupSet:) async throws` helper
called by both paths.

### IN-05: STAB-02 tests assert category presence but not identity / count

**File:** `MyHomeTests/GmailSyncControllerTests.swift:426-430`
**Issue:** `syncResolvesCategoryByPersistentIDAcrossAwait` asserts
`expenses.first?.categories.isEmpty == false` but never asserts the resolved category is the
specific "Dining" instance, nor that exactly one category is linked. A regression that linked the
wrong category (e.g. off-by-one in the name map) would pass. Tighten:
```swift
#expect(expenses.first?.categories.first?.name == "Dining")
#expect(expenses.first?.categories.count == 1)
```
Also note `makeContainerStab02` includes `Note.self, NoteBlock.self` which are unused for these
tests (harmless, minor).

---

_Reviewed: 2026-06-09_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
