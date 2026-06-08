# Pitfalls Research

**Domain:** SwiftData / SwiftUI iOS app — adding Accounts, Assets & Household Polish (v1.1) to a shipped app
**Researched:** 2026-06-08
**Confidence:** HIGH (based on direct codebase inspection + Apple Developer Forums + official SwiftData documentation patterns)

---

## Critical Pitfalls

### Pitfall 1 (CRASH — HIGHEST PRIORITY): SwiftData ModelContext Threading / Actor Isolation Violation

**What goes wrong:**
The app crashes with `EXC_BAD_ACCESS` or a fatal `"Context missing for op"` error during sync or when the Notes screen is opened. The crash happens because a `ModelContext` — or a `@Model` instance fetched from one context — is accessed from a different actor or thread than where it was created. In Swift 6 strict-concurrency mode every `@MainActor`-isolated type is enforced at compile time, but the underlying SwiftData runtime does NOT protect you from passing model instances across context boundaries at runtime.

**Why it happens (root-cause checklist — apply in order):**

1. **Context-without-model access during sync:** `GmailSyncController.syncAccount()` calls `ctx.fetch(FetchDescriptor<Expense>())` and `ctx.insert(expense)` from within `async` tasks. The `modelContext` property is `var modelContext: ModelContext? = nil` injected externally. If `setContext()` races with a background `Task { await sync() }` that starts before the context is assigned, `modelContext` is nil and the sync silently builds an empty `existingExpenses` array — but if a concurrent path on a different actor already holds model references, the fetch on the new context returns stale or duplicate objects.

2. **`@Model` instance passed across actor boundaries:** SwiftData `@Model` classes are NOT `Sendable`. A `Category` or `Expense` fetched in one `ModelContext` (even the main-actor one) CANNOT be safely read from a detached `Task` or background `Task {}` block. The current `syncAccount()` builds `categoriesByName: [String: Category]` from the main-context then uses those `Category` references deep inside a `for messageID in messageIDs` loop that runs across `await fetch.getRawMessage(...)` suspension points. Each `await` is a potential actor hop — and on any hop where the executor switches context (e.g. a URLSession callback), accessing those `Category` instances is a threading violation. iOS 17 is lenient about this; iOS 18 / Swift 6 strict mode may trap.

3. **`NoteBlock` accessed after cascade-delete:** `Note` has `@Relationship(deleteRule: .cascade, ...)`. When the user deletes a `Note` from `NotesListView` while `CalendarView`'s `DayAgendaView` sheet is open, the `AgendaReminderItem.target` holds a live `.block(NoteBlock)` reference. The cascade delete fires, the `NoteBlock` is removed from the store, but the `AgendaReminderItem` struct still points to it. The next `body` render accesses `block.isChecked` → EXC_BAD_ACCESS. This is the most likely cause of "crashes when notes is opened."

4. **`@Query` binding to deleted model during animation:** SwiftUI's `ForEach` in `NotesListView` (and agenda lists) can try to re-render a just-deleted row during the SwiftUI diffing/animation pass. SwiftData does not nil-out the reference synchronously; the view body reads a tombstoned object. Fix: always call `try? context.save()` immediately after `context.delete(note)` before yielding.

5. **`ctx.save()` inside a tight loop (sync pipeline):** `syncAccount()` calls `try ctx.save()` inside `for messageID in messageIDs`. Each `save()` synchronously flushes to disk on the calling actor. If `messageIDs` has 50 items and the context is the main-actor context, this blocks the main thread for up to ~200ms per save, which can trigger watchdog if the app is coming to foreground at the same time. The correct pattern is to batch inserts and call `save()` once after the loop.

6. **`ModelContainer` creation at app launch vs. async migration:** If `SchemaV6` (Accounts entity) migration is non-trivial and the app creates the `ModelContainer` synchronously in `@main App.init`, any migration error throws during app startup — which crashes before the catch block in the entry point can do anything useful. The project already uses `.custom` stages (good), but the `didMigrate` closures are `nil`. Adding an `Account` entity with a relationship to `Expense` will require a non-nil `didMigrate` to backfill — if that closure throws or is skipped, the container is in an inconsistent state.

7. **`scenePhaseChanged` racing with `sync()`:** `LockController` uses `@MainActor` correctly. However `GmailSyncController.scenePhaseChanged(.active)` can set `syncStatus = .tokenExpired` concurrently with an in-flight `sync()` task that is mid-await. Both run on `@MainActor` so they are serialized — but if `scenePhaseChanged` fires between the `syncStatus = .syncing` line and the first `await syncAccount()` call, it will clobber `.syncing` with `.tokenExpired`, and the UI shows a misleading reconnect CTA while sync is actually running fine.

**How to avoid:**

- **Immediate fix for crash #3 (highest probability):** In `DayAgendaView`, guard every model property access with a `modelContext != nil` check or use `item.target`'s `isDeleted` / `persistentModelID` before accessing fields. The existing code in `CalendarView.swift` accesses `note.blocks ?? []` and then immediately iterates `block.isChecked` with no deletion guard.
- **Fix crash #5 (sync loop):** Move `ctx.insert(expense)` outside the loop; accumulate a `[Expense]` array and insert all at once, then call `save()` once after the loop.
- **Fix cross-actor Category references:** Capture only `[String: UUID]` (PersistentIdentifier-safe) from the main context before the `for messageID` loop; re-fetch the `Category` by ID inside the same context at point of use, or capture the name string instead of the live model reference.
- **For `SchemaV6`:** Always provide a non-nil `didMigrate` closure when adding a new entity with a back-relationship to an existing entity. Test migration on a device with an existing v5 store before shipping.

**Warning signs:**
- Crash logs pointing to `NoteBlock.isChecked` or `Note.blocks` getter
- `EXC_BAD_ACCESS` in `PersistentModel._$observationRegistrar`
- `"Context missing for op"` in console during sync
- Notes screen crashes only after a note with reminders was recently deleted
- Sync never completes when notes screen is open simultaneously (context contention)

**Phase to address:** Phase 1 — Stabilization (must be first; app reliability is the gating condition for all other phases)

---

### Pitfall 2 (CRASH): Daily Routine Completion Stored as Mutable Bool on a Recurring Model

**What goes wrong:**
`NoteBlock.isChecked: Bool = false` is the single source of truth for completion state. For a daily-routine checklist (e.g. "Morning exercises"), `isChecked` is checked at 8 AM, becomes `true`, then the user expects it to reset to `false` the next morning. There is no mechanism for this — the bool persists forever. The reported bug "daily routine should reset completed state when the day ends" is exactly this: either the developer tries to roll over by mutating `isChecked` at app launch (wrong: misses the reset if app isn't opened at midnight) or the UI shows yesterday's completed state as today's state.

**Why it happens:**
The v1.0 data model uses a single `isChecked` bool because in v1.0 no recurring items needed daily rollover. Adding a "daily routine" concept on top of this model without a schema change produces stale completion: the bool stays `true` after day N and the UI shows all items already checked on day N+1.

**How to avoid:**
Two correct approaches — choose one:

1. **Date-keyed completion (recommended for v1.1):** Add a `lastCheckedDate: Date? = nil` field to `NoteBlock` in `SchemaV6`. The "is complete for today" computed property becomes `Calendar.current.isDateInToday(lastCheckedDate ?? .distantPast)`. Toggling sets `lastCheckedDate = Date()`. No daily job needed — the staleness clears automatically at the day boundary.

2. **Separate completion log entity:** Add `NoteBlockCompletion(blockID: UUID, completedOn: Date)` and query for today's completions. Heavier schema change; better for per-day history. Overkill for v1.1.

**Do NOT use:**
- App-launch-time rollover (`isChecked = false` on every cold start): misses the reset if the app is not opened. Also corrupts in-progress sessions (user checks items, backgrounds app, re-opens same session — reset fires mid-session).
- Timer-based midnight reset: timezone boundary is midnight in `TimeZone.current`, not UTC. If `reminderDate` is stored UTC (it is in this app) but the reset timer uses `Date()` at UTC midnight, the reset fires at 5:30 AM IST, which is wrong. Day boundary must always be derived from `Calendar.current` (device locale) not from a UTC interval.

**Warning signs:**
- `AgendaReminderItem.isChecked` returns `true` for blocks not touched today
- The daily reminder fires at the right time but the checklist shows yesterday's state
- `block.isChecked` toggled to `true` in June, still `true` in July

**Phase to address:** Phase 1 — Stabilization (this is a known bug; the data model fix must land before the daily-routine calendar reminder feature in a later phase, because the feature depends on correct per-day state)

---

### Pitfall 3 (BUG): Category Sort Order — New Category Appended to Bottom

**What goes wrong:**
`ManageCategoriesView` inserts new categories with `sortOrder: 0` (the default). Because existing categories already have `sortOrder` values from `0` onward (seeded categories use `sortOrder: 0, 1, 2...`), a new custom category with `sortOrder: 0` sorts to the top of the list only if the fetch is ordered ascending — but it appears at the bottom because the insert does not bump `sortOrder` to `max(existing) + 1`. The reported bug is "Add category attaches to bottom not top."

**Why it happens:**
The `Category` model has `var sortOrder: Int = 0`. The add-category flow (wherever `ctx.insert(Category(...))` is called) does not compute `max(existingSortOrders) + 1` before insert. The fetch descriptor likely uses `SortDescriptor(\Category.sortOrder, order: .forward)` — so the new category lands after all existing ones (all of which have `sortOrder >= 0`), giving "appended to bottom" behavior.

**How to avoid:**
Before inserting, fetch all categories, compute `let nextOrder = (categories.map(\.sortOrder).max() ?? -1) + 1`, pass to `Category(name:, symbolName:, sortOrder: nextOrder)`. Or if you want new categories at the top: set `nextOrder = 0` and increment all existing categories' `sortOrder` by 1 first (heavier; not recommended). Simplest: insert at top by setting `sortOrder = -1` and re-normalizing sort orders lazily.

**Warning signs:**
- New custom categories appear after "Other" at the bottom of the category picker
- `sortOrder` of new category is 0 while existing categories have higher values

**Phase to address:** Phase 1 — Stabilization (trivial one-line fix; unblock it first so testers aren't confused)

---

### Pitfall 4: SchemaV6 Migration — String sourceAccount to Account Entity Without Data Loss

**What goes wrong:**
v1.1 adds an `Account` entity. The natural design is to replace `Expense.sourceAccount: String?` (the Gmail email address used as an account identifier in V5) with `Expense.account: Account?` (a real relationship). If this is done naively with a `@Attribute(originalName: "sourceAccount")` rename, the migration will delete all string data and leave `account` nil on every existing expense. Thousands of expenses lose their account attribution silently.

**Why it happens:**
SwiftData lightweight migration can rename a property but cannot transform a `String?` to an `@Model` relationship. A custom `didMigrate` closure is required to: (1) fetch all `Account` entities, build a `[String: Account]` lookup by email/name, (2) fetch all `Expense` entities that have a populated legacy `sourceAccount` string, (3) match each to the corresponding `Account` and set the relationship. If `didMigrate` is `nil` (as it has been for all previous stages), this step silently never runs.

**How to avoid:**
- In `SchemaV6`, keep `sourceAccount: String?` as a carry-forward field **alongside** the new `account: Account?` relationship. Do not remove `sourceAccount` in V6.
- In the `v5ToV6` migration stage's `didMigrate:` closure: for each distinct `sourceAccount` string value, find or create the matching `Account` entity and assign it to `expense.account`.
- Only in `SchemaV7` (or a later pass) drop `sourceAccount: String?` once all expenses have been migrated.
- Always test the migration by copying a real `default.store` from the simulator to a test target and running the migration under XCTest before shipping.

**Warning signs:**
- All existing expenses show `nil` account after update
- Console logs: `"Fatal error: Expected only Arrays for Relationships"` during migration
- `Account` entity count is correct but `expense.account` is nil on old rows

**Phase to address:** Phase 2 — Accounts Management (the migration stage must be written and tested before the feature is shipped; never skip the `didMigrate` closure)

---

### Pitfall 5: Self-Transfer Detection False Positives

**What goes wrong:**
Auto-flagging debit/credit pairs from different accounts as "self-transfers" incorrectly hides real spend. Common false-positive scenarios:

- A refund from a merchant (credit to Account A) matches a prior purchase debit within the time/amount window.
- A cash withdrawal (debit Account A) followed by a cash deposit (credit Account B) — this IS a transfer but the "confirmation" step is skipped or auto-approved.
- Split payments: a ₹5,000 debit to one account and a ₹5,000 credit on a credit card statement that is actually an EMI payment, not a transfer.
- Two purchases of the same round amount (e.g. two ₹500 grocery runs) flagged as a transfer pair.

**Why it happens:**
Naive matching on `(amount, date window)` alone produces too many false positives because round amounts and same-day transactions are common. The "pair" concept assumes every credit matching a debit is a transfer — but credits can be refunds, salary credits, or interest.

**How to avoid:**
- Never auto-exclude transfers. The PROJECT.md requirement is explicit: "auto-detect + confirm, never silent exclusion." Every detected pair must surface in a confirm step.
- Match on `(amount ± tolerance, date within N hours)` AND require BOTH accounts to be known `Account` entities (prevents matching against external merchants).
- Add a `isLikelyTransfer: Bool` flag on `Expense` (SchemaV6) that is user-settable. Once the user confirms or denies, persist the decision; do not re-flag on next sync.
- Partial match edge case: if debit is ₹10,100 (bank fee included) and credit is ₹10,000, the pair should NOT match. Use a tight tolerance (< ₹5 or < 0.1%).
- Refund vs. transfer: credits on a DEBIT account with `ingestionStateRaw == "autoSaved"` are likely refunds, not transfer targets. Credits on a SAVINGS account are more likely transfers. Use `sourceLabel` (e.g. "HDFC Savings") to differentiate.

**Warning signs:**
- Salary credit flagged as transfer pair with a same-amount expense
- Review Inbox showing "possible transfer" on every ₹500 transaction
- Net worth calculation drops because transfers were double-counted as expenses

**Phase to address:** Phase 3 — Self-Transfer Detection (comes after Accounts are stable; detection quality depends on Account entity existing)

---

### Pitfall 6: Asset Tracker — Unofficial NSE/BSE Price Endpoints Breaking

**What goes wrong:**
India stock price fetching from unofficial NSE/Yahoo Finance endpoints (e.g. `https://query1.finance.yahoo.com/v8/finance/chart/RELIANCE.NS`) breaks silently with no error to the user. NSE's own website blocks direct API calls from iOS apps with User-Agent filtering. The app shows stale prices (last fetched value) as if they were live, misleading the user into thinking their net worth is current.

**Why it happens:**
NSE's unofficial endpoints add `X-Requested-With` and session-cookie requirements that change without notice. Yahoo Finance has broken its free API multiple times. The free `mfapi.in` and `mfdata.in` for AMFI MF NAVs are community-maintained services with no SLA — they can be down for hours. The official AMFI NAV file (`http://portal.amfiindia.com/spages/NAV0.txt`) is the only truly reliable source, but it is a flat text file with a pipe-delimited format that requires parsing and is only updated once daily after market close (not intraday).

**How to avoid:**
- **AMFI NAV (mutual funds):** Use the official AMFI file directly, never a third-party wrapper for the production path. Parse the pipe-delimited format. It updates once daily at ~6:30 PM IST — display the "as-of date" from the file, not `Date()`.
- **Stocks (NSE/BSE):** Treat as best-effort only. Never block the UI waiting for a stock price fetch. If the fetch fails or returns a non-200, keep the last known price with a visible "as-of date" and a stale indicator. Manual override must always be available.
- **NPS:** NPS tier-I/II NAVs are published by the Pension Fund Regulatory and Development Authority (PFRDA) — not available via any free machine-readable API. Use manual override only for NPS.
- **Price staleness display:** Every asset price shown must carry an "as-of date" label. Do NOT show a price without its date. "Net worth as of [date]" must be the summary headline.
- **No blocking network on main thread:** All price fetch calls must use `async`/`await` in a background task (or a `ModelActor`), never `URLSession.shared.data(from:)` inline in a SwiftUI view body or `@MainActor` context.

**Warning signs:**
- Stock fetch returns HTTP 403 or empty JSON with no user-visible error
- NAV for the same scheme differs between `mfapi.in` and the official AMFI file
- Net worth summary shows today's date but prices are from 3 days ago (weekend/holiday gap)

**Phase to address:** Phase 4 — Asset Tracker (design the manual-override path first; treat all external APIs as optional enhancements)

---

### Pitfall 7: Asset Tracker — Decimal vs Double Precision for NAV / Units

**What goes wrong:**
Mutual fund NAVs have up to 4 decimal places (e.g. ₹145.3721). Units held can be fractional (e.g. 34.721 units). If either value is stored as `Double`, IEEE 754 rounding errors accumulate: `34.721 * 145.3721` in `Double` gives a slightly wrong number that, when displayed as ₹INR, shows ₹0.01 rounding artifacts. At portfolio scale (20+ funds), these compound into a noticeable error in "Total Net Worth."

**Why it happens:**
The app already enforces `Decimal` for expense amounts (Pitfall 17 in the SchemaV4 header comment). The trap is that when adding the Asset entity, a developer unfamiliar with the existing convention reaches for `Double` because NAV and units "feel like" floating-point values (they are not currency themselves). Swift's `Decimal` type handles this correctly.

**How to avoid:**
- `AssetHolding.units: Decimal` — never `Double`
- `AssetHolding.nav: Decimal` — never `Double`
- `AssetHolding.currentValue: Decimal` computed as `units * nav` using `Decimal` arithmetic
- AMFI NAV file values are strings like `"145.3721"` — parse with `Decimal(string: navString)`, not `Double(navString)`
- When calling the AMFI API, decode the NAV field as `String` in the `Codable` struct, then convert to `Decimal`

**Warning signs:**
- Net worth total shows a value ending in .99 or .01 that doesn't match manual calculation
- `Double(navString)` in parser code

**Phase to address:** Phase 4 — Asset Tracker (enforce from schema definition; harder to fix later)

---

### Pitfall 8: Asset Tracker — Stale Price Presented as Live / Holiday Gaps

**What goes wrong:**
AMFI NAV is not published on market holidays, weekends, or days when trading is suspended. If the app fetches the AMFI file on a Saturday, it gets Friday's NAV — but displays it without context. The user opens the app on Monday before the new NAV is published and sees Friday's price with no date label. They assume it's live, make a decision, and it's wrong.

**Why it happens:**
Naive implementation: fetch NAV → store value → display value. The `navFetchedAt: Date` field is omitted from the schema, or is present but not shown in the UI.

**How to avoid:**
- `AssetHolding.navDate: Date?` — the date of the NAV, parsed from the AMFI file header ("Scheme NAV as on DD-MMM-YYYY"), not the fetch date.
- Display rule: if `navDate` is today (IST), show price with no stale badge. If `navDate` is yesterday (IST), show "as of yesterday." If `navDate` is 2+ days ago, show an amber stale badge.
- IST day boundary: use `TimeZone(identifier: "Asia/Kolkata")!` calendar for all "is this today's NAV" comparisons. UTC midnight is 6:30 AM IST — a naive UTC comparison will show Saturday's NAV as "today's" all of Saturday even though the market closed Friday.

**Warning signs:**
- `navDate` stored as `Date()` (fetch time) instead of parsed from file header
- Portfolio value shown without any date context
- Stale badge never appears even when market is closed

**Phase to address:** Phase 4 — Asset Tracker

---

### Pitfall 9: Notes Daily-Routine Calendar Reminder — Notification Explosion

**What goes wrong:**
Adding a "daily reminder" to a note/checklist block that has `ReminderRecurrence.daily` and `ReminderEndRule.never` correctly produces a single repeating `UNCalendarNotificationTrigger(repeats: true)` (the existing `repeatingRequests` path in `NotificationScheduler`). BUT if the daily routine feature is implemented as "schedule a new reminder each morning" (i.e., calling `schedule()` once per day in the BGAppRefreshTask), each call adds a NEW repeating trigger on top of the existing one. After 64 days, the 64-notification cap is hit and all subsequent reminders are silently dropped.

**Why it happens:**
BGAppRefreshTask is the natural hook for daily operations. A developer unfamiliar with the existing `NotificationScheduler` pattern might call `schedule(info)` for every active daily routine note on every background refresh, not realizing the existing `cancel(reminderID:…) + re-schedule` pattern is required for idempotency.

**How to avoid:**
- Never call `schedule()` without first calling `cancel(reminderID:…)` for the same reminder ID. The cancel-then-reschedule pattern is idempotent.
- For the "daily routine calendar reminder" feature, the correct path is: when the user enables the calendar integration on a note, call `NotificationScheduler.schedule(info)` once with `recurrence: .daily, endRule: .never`. Do NOT re-schedule in BGAppRefreshTask.
- The BGAppRefreshTask should only trigger re-scheduling if the `reminderEnabled` state has been toggled, the date has changed, or `pendingCount()` is unexpectedly 0 (indicating notifications were cleared by the OS).

**Warning signs:**
- `pendingCount()` approaches 64 unexpectedly
- Daily reminder fires multiple times per day at slightly different times
- Notification budget exhaustion causes other reminders to silently stop firing

**Phase to address:** Phase 5 — Notes Enhancement (needs explicit test that `schedule()` is idempotent; add a unit test that calls `schedule()` N times and asserts `pendingCount() == 1`)

---

### Pitfall 10: Timezone / Day-Boundary Bugs in Routines and Asset Dates

**What goes wrong:**
Two distinct day-boundary bugs:

(a) **Routine completion rollover at wrong time:** `Calendar.current` respects the device's time zone. But `Date()` stored to `lastCheckedDate` (if added in SchemaV6) is UTC. Comparing `Calendar.current.isDateInToday(lastCheckedDate)` is correct IF the calendar's time zone matches. However if `Calendar.current` is re-created as `Calendar(identifier: .gregorian)` anywhere without explicitly setting `timeZone = TimeZone.current`, it defaults to UTC. For IST (UTC+5:30), "today" UTC ends at 5:30 PM IST — so a habit marked complete at 6 PM IST would appear as "not yet done today" in a UTC calendar.

(b) **Asset NAV date display wrong by one day:** AMFI file header format is `"DD-MMM-YYYY"`. Parsing with `DateFormatter` using `en_US_POSIX` locale and no timezone set (defaults to UTC) stores the date at midnight UTC. Displaying with a device-timezone formatter then shows it as the previous day for any user in UTC+ timezones (India is UTC+5:30, so midnight UTC = 5:30 AM IST = still the same calendar day, but only barely — if AMFI updates at 6:30 PM IST = 1:00 PM UTC, the `navDate` is correct IST but UTC midnight is still the prior calendar day).

**How to avoid:**
- Always use `Calendar.current` with `cal.timeZone = TimeZone.current` explicitly set (see `CalendarView.deviceCal` — this pattern is already correct in the existing code; carry it to all new date comparisons).
- For AMFI date parsing: parse the `DD-MMM-YYYY` string into a `Date` using a `DateFormatter` with `timeZone = TimeZone(identifier: "Asia/Kolkata")` and `locale = Locale(identifier: "en_US_POSIX")`. Store as UTC `Date` (as the app does for all dates). Display using `Calendar.current` (device timezone) for "is this today/yesterday" checks.
- The existing `NotificationScheduler.deviceCalendar()` pattern (explicit `cal.timeZone = TimeZone.current`) must be used wherever day boundaries matter.

**Warning signs:**
- Routine checklist resets at 5:30 PM IST instead of midnight
- AMFI NAV date shown as yesterday when fetched in the evening
- Unit tests pass on a UTC machine but fail when run with `TZ=Asia/Kolkata`

**Phase to address:** Phase 1 — Stabilization (for the routine reset bug) and Phase 4 — Asset Tracker (for NAV date parsing)

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `ctx.save()` inside the fetch/parse loop | Prevents data loss if crash mid-sync | Blocks main thread ~200ms × N emails; can trigger watchdog | Never — batch and save once |
| `modelContext` as optional `var` injected post-init | Enables test-without-container patterns | `nil` context silently no-ops inserts; no crash, silent data loss | Acceptable only if every insert site explicitly guards `if let ctx = modelContext` |
| `try? ctx.fetch(...)` swallowing errors | No crash on fetch failure | Silently returns empty array; dedup fails; duplicate expenses ingested | Never for dedup-critical fetch; always propagate or log |
| Keep `sourceAccount: String?` in V6 alongside new `Account` relationship | Avoids a destructive migration | Two sources of truth; risk of them diverging | Acceptable in V6 as a migration scaffold; must be removed in V7 |
| Single `isChecked: Bool` for recurring completion | No schema change needed | Wrong completion state across day boundaries for daily routines | Never for recurring items — requires per-day state |
| NSE/Yahoo unofficial stock price endpoint | Free, no signup | Can break without notice; no SLA; may add rate-limit headers | Acceptable as best-effort only if UI shows "as-of date" and gracefully degrades |
| AMFI community wrapper (mfapi.in) | JSON is cleaner than raw NAV0.txt | Third-party dependency with no SLA; Netlify free tier | Acceptable as a fallback; official AMFI file must be the primary |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| AMFI NAV0.txt | Parse NAV as `Double` | Parse as `String`, convert to `Decimal(string:)` |
| AMFI NAV0.txt | Use `Date()` as the NAV date | Parse `"DD-MMM-YYYY"` header with IST timezone formatter |
| AMFI NAV0.txt | Fetch on main thread synchronously | `URLSession.shared.data(from:)` in a `Task { }` off the main actor |
| NSE stock quote | Assume HTTP 200 = valid data | NSE can return 200 with an error JSON body; always decode and check `"status"` field |
| NSE stock quote | No User-Agent header | NSE web endpoints require a browser-like User-Agent; add it or requests return 403 |
| Gmail sync | Pass `Category` @Model across `await` suspension | Capture `[String: PersistentIdentifier]` before the loop; re-fetch inside same context after each await |
| Gmail sync | `ctx.save()` in loop | Accumulate `[Expense]`; `ctx.insert()` all; `try ctx.save()` once after loop |
| UNUserNotification | Call `schedule()` in BGAppRefreshTask for existing recurring reminders | Only schedule on first enable; cancel+reschedule only when config changes |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `ctx.fetch(FetchDescriptor<Expense>())` with no predicate in sync loop | 500ms freeze during sync with 1000+ expenses | Add predicate for recent expenses or use in-memory dedup set built once | ~500 expenses |
| `@Query` all expenses in Overview/Budget views with no date filter | Overview loads slowly as expense history grows | Add date predicate (current month) to `@Query` or compute aggregates lazily | ~5000 expenses |
| Asset price fetch blocking main actor | UI freeze for 2–5 seconds on net-worth screen open | All price fetch in `Task { }` off the main actor; never `await` inside `@MainActor` computed property | Every launch on slow connection |
| Large `rawEmailBody: String?` in `Expense` loaded in list queries | List scroll jitter as blobs are faulted in | Add `#Predicate` or `FetchDescriptor.propertiesToFetch` to exclude `rawEmailBody` from list queries | ~100 expenses with raw email body |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Storing asset quantities (units, NAV) in `UserDefaults` | Readable without Face ID lock | Store in SwiftData (covered by the app-level Face ID gate) |
| Logging `sourceAccount` email in sync error messages | Email address in crash logs / console | Use hashed/truncated form in logs; never full email |
| NSE/AMFI fetch over HTTP (not HTTPS) | MITM attack on price data | Always HTTPS; AMFI file is served over HTTP — force HTTPS redirect or validate response |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Showing "Net Worth: ₹X" without a date | User trusts stale value as live | Always show "as of [date]" in every net-worth headline |
| Self-transfer auto-excluded without confirmation | Real spend hidden from budget; user loses trust in accuracy | Auto-detect + confirm flow — requirement explicitly stated in PROJECT.md |
| Routine completion reset at midnight wakes no one | User sees reset state in the morning but didn't trigger it | Reset must be lazy (date-keyed), not active (event-based) — no notification needed for reset |
| Asset tracker showing portfolio value without a "last updated" badge | User makes financial decisions on stale data | Amber stale badge when `navDate` is more than 1 trading day old |
| Transfer confirmation buried in Review Inbox | User never sees it; transfers stay as expenses indefinitely | Give transfers a distinct top-of-inbox section (separate from low-confidence parses) |

---

## "Looks Done But Isn't" Checklist

- [ ] **Sync pipeline:** `ctx.save()` moved outside the message loop — verify no per-message save
- [ ] **Notes crash:** `AgendaReminderItem` and `DayAgendaView` guard against `isDeleted` before accessing `block.isChecked` or `note.blocks`
- [ ] **Routine completion:** `lastCheckedDate` field added to `NoteBlock` in SchemaV6 and `isCheckedToday` computed property uses `Calendar.current` with explicit `timeZone = TimeZone.current`
- [ ] **SchemaV6 migration:** `v5ToV6` stage has a non-nil `didMigrate` closure that backfills `expense.account` from `expense.sourceAccount` string values
- [ ] **Asset NAV parsing:** NAV value decoded as `String` then converted to `Decimal(string:)`, never `Double`
- [ ] **Asset NAV date:** parsed with `TimeZone(identifier: "Asia/Kolkata")` formatter; displayed as IST calendar date
- [ ] **Self-transfer detection:** all flagged pairs go through confirm step — no silent exclusion path exists
- [ ] **Notification scheduling:** `schedule(info)` in daily-routine feature is called only on enable/edit, not on every BGAppRefreshTask run
- [ ] **Category insert:** new category `sortOrder` = `max(existing) + 1`, not 0
- [ ] **Stock price fetch:** UI never blocks waiting for NSE response; stale fallback shown if fetch fails or times out in < 3 seconds

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| SwiftData crash (deleted-model access) | LOW | Add `isDeleted` guard in view; run on device to confirm crash stops |
| Migration data loss (sourceAccount → Account) | HIGH | Restore from last iCloud backup; write a recovery migration that reads sourceAccount string and re-links |
| Notification explosion (cap hit) | MEDIUM | Call `UNUserNotificationCenter.current().removeAllPendingNotificationRequests()` + reschedule all active reminders |
| NSE endpoint broken | LOW | Show stale price with date badge; prompt user to enter manually |
| AMFI community API down | LOW | Fall back to official AMFI NAV0.txt direct fetch |
| Routine completion stuck (isChecked never resets) | MEDIUM | SchemaV6 migration: set `lastCheckedDate = nil` on all blocks where `isChecked == true` and `note` has daily recurrence |
| Self-transfer false positives hiding spend | MEDIUM | Provide a "mark as expense (not transfer)" action in the confirm flow; re-include in budget calculations |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| SwiftData crash — deleted model access, cross-actor Category | Phase 1 — Stabilization | Run Notes with concurrent sync + delete a note with open agenda sheet; no crash |
| ctx.save() in sync loop blocking main thread | Phase 1 — Stabilization | Sync with 20+ emails; main thread time profiler shows no >50ms spike per message |
| Routine completion stale bool | Phase 1 — Stabilization | Mark checklist items complete, background app 24h+ (or mock date), reopen — items show as incomplete |
| Category sort order at insert | Phase 1 — Stabilization | Add a category → it appears at top of list |
| SchemaV6 migration + Account backfill | Phase 2 — Accounts Management | Unit test migrating a v5 fixture store to v6; all expenses with sourceAccount get account relationship |
| Self-transfer false positives | Phase 3 — Self-Transfer Detection | Integration test with known transfer + known refund pair; refund must not be flagged |
| Asset NAV as Decimal | Phase 4 — Asset Tracker | Unit test: `Decimal(string: "145.3721")! * Decimal(string: "34.721")!` matches expected value |
| Asset stale price display | Phase 4 — Asset Tracker | Set device clock to Saturday; fetch AMFI → "as of Friday" stale badge visible |
| Asset timezone day boundary | Phase 4 — Asset Tracker | Unit test with IST timezone calendar comparison for NAV date parsing |
| Notification explosion in daily routine | Phase 5 — Notes Enhancement | Call `schedule()` 10 times for same reminder; assert `pendingCount() == 1` |
| Timezone bug in routine rollover | Phase 1 — Stabilization | Unit test: `isCheckedToday` with `lastCheckedDate` = yesterday 11:59 PM IST + IST calendar returns false |

---

## Sources

- [SwiftData EXC_BAD_ACCESS forum thread — Apple Developer Forums](https://forums.developer.apple.com/forums/thread/745424)
- [SwiftData crashes when trying to access a deleted object — delasign.com](https://www.delasign.com/blog/swiftdata-crashes-when-trying-to-access-a-deleted-object/)
- [SwiftData: Solving Fatal Errors and EXC_BAD_ACCESS While Handling Entities on Different Threads — simplykyra.com](https://www.simplykyra.com/blog/swiftdata-solving-fatal-errors-and-exc_bad_access-while-handling-entities-on-different-threads/)
- [Concurrent Programming in SwiftData — fatbobman.com](https://fatbobman.com/en/posts/concurret-programming-in-swiftdata/)
- [SwiftData Context missing for op — Apple Developer Forums](https://developer.apple.com/forums/thread/757820?page=2)
- [All the ways SwiftData's ModelContainer can Error on Creation — scottdriggers.com](https://scottdriggers.com/blog/swiftdata-modelcontainer-creation-crash/)
- [SwiftData migration crashes when working with relationships — HackingWithSwift forums](https://www.hackingwithswift.com/forums/swift/swiftdata-migration-crashes-when-working-with-relationships/29374)
- [SwiftData fetch from Background Thread — Medium](https://medium.com/@sebasf8/swiftdata-fetch-from-background-thread-c8d9fdcbfbbe)
- [MFapi.in — Free India Mutual Fund API](https://www.mfapi.in/)
- [Official AMFI India NAV data](https://www.amfiindia.com/research-information)
- [Don't rely on BGAppRefreshTask for your app's business logic — mertbulan.com](https://mertbulan.com/programming/dont-rely-on-bgapprefreshtask-for-your-apps-business-logic)
- Direct codebase inspection: `GmailSyncController.swift`, `CalendarView.swift`, `SchemaV4.swift`, `SchemaV5.swift`, `NotificationScheduler.swift`, `MigrationPlan.swift`

---
*Pitfalls research for: SwiftData/SwiftUI iOS app — v1.1 Accounts, Assets & Household Polish*
*Researched: 2026-06-08*
