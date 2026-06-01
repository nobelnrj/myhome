# Phase 5: Face ID Gate & Settings - Context

**Gathered:** 2026-06-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver two things that make the household's financial data feel trusted before any
external data flows in (Phase 6+):

1. **A biometric app-lock gate** — Face ID with automatic device-passcode fallback,
   intercepting app open, toggleable in Settings.
2. **A 5th "Settings" tab** — the household's admin home: the lock toggle, a
   category-management entry, a link to the Budgets screen, and an About/version
   footer.

**In scope (SEC-01, SEC-02, SET-01, SET-02, SET-03):**
- **SEC-01 / SET-01** — Toggle a Face ID lock on/off in Settings; when on, the app
  requires authentication to open.
- **SEC-02** — Fall back to device passcode via `LAPolicy.deviceOwnerAuthentication`;
  handle every `LAError` case explicitly **without ever locking the user out**.
- **SET-02** — Manage categories (add, rename, delete) from Settings.
- **SET-03** — Per-category monthly budgets are manageable "from Settings" — satisfied
  via a thin Settings→Budgets-tab link (see D5-08 deviation); budget-editing logic
  itself stays on the Budgets screen.

**Out of scope (later phases / not this phase):**
- **Gmail token in Keychain (SEC-03), Gmail sign-out/reconnect (SET-04), last-synced
  timestamp + "Sync now" (SET-05)** — these are **Phase 6**, not Phase 5. No Gmail
  anything in this phase (a clean Settings structure is left for P6 to slot into).
- Bank-email ingestion / parsers / Review Inbox (Phase 7).
- Cross-device sync / CloudKit sharing — post-v1; schema already CloudKit-ready,
  untouched here.
- Per-note / per-record encryption — the app-level Face ID gate covers the trust need
  (explicitly out of scope per REQUIREMENTS.md).
- A custom in-app PIN/passcode — we use the **device** passcode via the LocalAuthentication
  system prompt only; no app-specific passcode is created or stored.

**Schema constraint:** Phase 5 introduces **no new `@Model` types and no schema
migration.** The lock-enabled flag is a `UserDefaults` preference, not persisted model
state. Category/budget management reuses the existing `Category` model and views.

</domain>

<decisions>
## Implementation Decisions

### Lock trigger & re-lock (discussed)
- **D5-01:** The gate authenticates on **cold launch AND on return from background
  after a ~3-minute grace period** — not on every foreground. Quick app-switches
  (e.g., copy an OTP) within the grace window do **not** re-prompt; longer absences
  re-lock. Track the backgrounding timestamp; compare elapsed time on
  `scenePhase`/foreground transition. *Discretion:* exact grace constant (start at
  180s) and the scene-phase wiring are the planner's call, provided the two triggers
  (cold launch + post-grace foreground) hold.
- **D5-02:** **Locked / inactive UI = privacy blur overlay + dedicated unlock screen.**
  Whenever the app is inactive/backgrounded, obscure content with a privacy overlay so
  the app-switcher snapshot leaks nothing. When locked, show a dedicated unlock screen
  (app icon + a visible **"Unlock" button**) — never a blank or auto-only gate. The
  unlock screen is what the user sees until authentication succeeds.

### Authentication policy & LAError handling — SEC-02 (discussed)
- **D5-03:** Use **`LAPolicy.deviceOwnerAuthentication`** (Face ID first, then the
  system passcode fallback within the same OS prompt). Do **not** build a custom
  passcode path — this is exactly the policy SEC-02 names.
- **D5-04 (no biometry, passcode exists):** On `.biometryNotAvailable` /
  `.biometryNotEnrolled`, `deviceOwnerAuthentication` automatically falls through to
  the device passcode. Treat this as a normal passcode-only lock — the app stays
  protected, just without Face ID. No special UI beyond what the system shows.
- **D5-05 (NO device passcode at all):** When the device has no passcode (so the policy
  cannot evaluate) **and the lock is enabled**: **hard block with a reachable escape.**
  Content stays hidden (no normal entry), but the unlock screen displays guidance —
  *"Set a device passcode in iOS Settings to unlock this app, then return."* On the
  next foreground, **re-evaluate**: once a passcode exists, authentication proceeds.
  **No reinstall, no data loss.** This is the literal reconciliation of SEC-02's
  "never lock the user out" with a passcode-less device.
- **D5-06 (recoverable failures):** On `.userCancel`, `.authenticationFailed`,
  `.systemCancel`, `.appCancel`, `.userFallback`, `.biometryLockout` — **stay on the
  unlock screen with a visible Retry/Unlock button**; the user can always re-trigger
  auth. For `.biometryLockout`, add text guiding the user to use the passcode. Never an
  inescapable loop, never a dead end. Every `LAError` case from SEC-02 must be handled
  explicitly (`.biometryNotAvailable`, `.biometryNotEnrolled`, `.biometryLockout`,
  `.userFallback`, `.userCancel`, `.appCancel`, `.systemCancel`).

### Toggle behavior — SEC-01 / SET-01 (discussed)
- **D5-07a (enable):** Turning the lock **ON triggers an auth prompt; the lock only
  enables on success.** Proves biometrics/passcode work before the user relies on them.
- **D5-07b (disable):** Turning the lock **OFF requires authentication first** — stops
  someone with an already-unlocked phone from quietly disabling the gate.
- **D5-07c (storage):** The lock-enabled boolean is stored in **App Group
  `UserDefaults`** (the suite the app already uses), **not Keychain** — it's a
  preference, not a secret. Keychain is reserved for the Gmail refresh token in P6
  (SEC-03).

### Settings shell & management placement — SET-02 / SET-03 (discussed)
- **D5-08 (budget placement — DEVIATION):** **Budget editing stays on the Budgets
  screen** (Budget cards → existing `EditBudgetSheet`). Settings does **not** host
  budget-editing UI. To satisfy SET-03 / ROADMAP SC#3's literal *"manage per-category
  monthly budgets **from Settings**"* wording, Settings includes a **thin "Budgets"
  row that deep-links/switches to the Budgets tab (tag 2)** — no budget UI is
  duplicated in Settings. *Rationale (user):* "Budget is a bigger screen and should
  have its own screen; don't pollute Settings." **Action for downstream:** flag that
  ROADMAP Phase 5 SC#3 wording should be relaxed at phase transition to reflect that
  budget management is reached *via* Settings (link), not hosted *in* Settings.
- **D5-09 (category management — mirror):** Settings hosts a **category-management
  entry that reuses the existing `ManageCategoriesView`** (add/rename/delete). This
  **mirrors** — does not replace — the existing "Manage Categories" entry on the
  Budgets tab; the same view is presented from both places (no duplication). User
  framing: *"Settings should have a button that allows the user to add/manage
  categories. That's it."*
- **D5-10 (shell content):** Settings is **minimal** — Face ID lock toggle, the
  category-management entry (D5-09), the Budgets link (D5-08), and a small
  **About / app-version footer**. **No** Gmail placeholder, **no** disabled "coming
  soon" rows — leave a clean List structure that Phase 6 slots its Gmail section into.

### Navigation / tab wiring
- **D5-11:** Settings becomes **tab tag 4** (the 5th tab — D4-01: exactly the iOS
  limit, no "More" overflow). Add it to `RootView`'s `TabView` after Notes (tag 3).
  The Budgets deep-link (D5-08) sets the existing `selectedTab` binding to **2** — so
  Settings needs access to that binding (mirror how `OverviewView` already takes
  `selectedTab: Binding<Int>`).

### Claude's Discretion (planner / UI-SPEC)
- **D5-12:** Left to researcher/planner/UI-SPEC using standard SwiftUI +
  LocalAuthentication + SwiftData conventions:
  - The **Settings tab icon + label** (e.g., `gearshape` / "Settings") — pick one
    consistent with the existing SF Symbol tab style.
  - The **exact grace-period constant** (start 180s) and the **scene-phase / lifecycle
    seam** where the gate hooks in (App vs RootView; `@Environment(\.scenePhase)` vs a
    small `@Observable` lock controller). Prefer a **testable seam** so `LAContext`
    can be faked in unit tests (mirror the `NotificationCenterPort`/`SpyCenter` pattern
    from Phase 3 — wrap `LAContext` behind a protocol port so LAError paths are unit-
    testable without a device). TDD default applies to the pure lock-state logic
    (grace-elapsed math, error→action mapping).
  - Whether the category entry is presented as a **sheet** (matches today's Budgets-tab
    `ManageCategoriesView` presentation) or a `NavigationLink` push — keep it
    consistent with the rest of Settings.
  - Exact copy for the unlock screen, the no-passcode guidance (D5-05), and the
    `.biometryLockout` hint (owned by the UI-SPEC).
  - About/version footer content (app name + version/build string).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirement & roadmap sources
- `.planning/ROADMAP.md` §"Phase 5: Face ID Gate & Settings" — goal, success criteria
  (3 items), requirement set SEC-01/02 + SET-01/02/03, UI hint: yes. **Note SC#3
  wording deviation per D5-08.**
- `.planning/REQUIREMENTS.md` — SEC-01 (line ~22), SEC-02 (line ~23, the full LAError
  list), SET-01/02/03 (lines ~81–83). Authoritative requirement text. **SEC-03 /
  SET-04 / SET-05 are Phase 6 — do not implement here.**

### Project charter & scope
- `.planning/PROJECT.md` — Security constraint ("Face ID app lock required (financial
  data)"; "Gmail OAuth tokens in Keychain"; "no analytics/telemetry/third-party SDKs");
  Key Decision "Face ID required to open app … toggleable in settings for paranoia
  override"; iOS 17+ Swift 6.2 / SwiftUI / SwiftData stack; "performance is not a
  constraint — do not over-engineer."

### Domain research (load-bearing)
- `.planning/research/STACK.md` — Swift 6.2 / SwiftUI / SwiftData / iOS 17+ stack
  (LocalAuthentication availability).
- `.planning/research/PITFALLS.md` — SwiftData/SwiftUI landmines: `@Observable` /
  `@Bindable` / `@State` ONLY (never `@StateObject` / `@ObservedObject` / `@Published`);
  no system keyboard (custom keypad pattern). The lock controller, if any, must follow
  the `@Observable` rule.
- `.planning/research/ARCHITECTURE.md` — schema discipline (confirms Phase 5 is
  no-new-model / no-migration); App Group store conventions.

### Prior phase context (binding patterns)
- `.planning/phases/02-categories-tags-budgets/02-CONTEXT.md` — **D2-11 (management
  inline on Budgets; Phase 5 relocates/mirrors into Settings)**, the `Category` model
  + `monthlyBudget` decisions, "no repository layer / `@Query` + `modelContext`"
  pattern, CR-01 explicit-save pattern for financial writes.
- `.planning/phases/04-overview-charts/04-CONTEXT.md` — **D4-01 (5-tab limit, no "More"
  menu; Settings is the 5th tab)**, the `selectedTab` binding pattern that
  `OverviewView` already uses for programmatic tab switching (template for the D5-08
  Budgets deep-link).
- `.planning/phases/03-notes-checklists/03-CONTEXT.md` — the
  `NotificationCenterPort` / `SpyCenter` **protocol-port test seam** — mirror this
  shape to wrap `LAContext` for unit-testable LAError paths (D5-12).

### Source the phase builds on (read before implementing)
- `MyHomeApp/MyHomeApp.swift` — `@main App` / `WindowGroup` / `scenePhase` host;
  the lock gate hooks in around `RootView` (gate overlay + scene-phase observation).
- `MyHomeApp/RootView.swift` — the `TabView` host. **Add Settings as tag 4** after
  Notes (tag 3); thread the `selectedTab` binding into Settings for the D5-08 Budgets
  deep-link (currently tags: Home 0, Expenses 1, Budgets 2, Notes 3).
- `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` — **reused verbatim** as the
  Settings category-management entry (D5-09); add/rename/delete with lookup-before-
  insert, `.nullify` delete, CR-01 explicit save already implemented.
- `MyHomeApp/Features/Budgets/BudgetsView.swift` — owns the existing "Manage
  Categories" toolbar button + month pager + budget cards; the **Budgets deep-link
  target** (tag 2). Budget editing stays here (D5-08).
- `MyHomeApp/Features/Budgets/EditBudgetSheet.swift` — the existing per-category
  budget editor, reached from Budget cards; **unchanged**, stays on the Budgets screen.
- `MyHomeApp/Persistence/ModelContainer+App.swift` — App Group store wiring; reference
  for the **App Group `UserDefaults` suite name** used to store the lock flag (D5-07c).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`ManageCategoriesView`** (`Features/Budgets/`) — full category add/rename/delete
  with uniqueness check + confirmation dialog + CR-01 save. **Reused as-is** for the
  Settings category entry (D5-09); no new category UI needed.
- **`EditBudgetSheet`** (`Features/Budgets/`) — per-category budget editor; stays on
  the Budgets screen (D5-08), not rebuilt in Settings.
- **`selectedTab` binding pattern** (`RootView` ↔ `OverviewView`) — existing
  programmatic-tab-switch mechanism; template for the Settings→Budgets deep-link.
- **`NotificationCenterPort` / `SpyCenter` seam** (`Support/`, Phase 3) — the
  protocol-port pattern to mirror for wrapping `LAContext` so LAError paths are
  unit-testable without a physical device.

### Established Patterns (binding)
- **Views talk to SwiftData directly** via `@Query` + `@Environment(\.modelContext)` —
  **no repository layer.** Category management already follows this.
- **State:** `@Observable` / `@State` / `@Bindable` only — never `@StateObject` /
  `@ObservedObject` / `@Published`. A lock controller, if introduced, must be
  `@Observable`.
- **CR-01:** financial/category writes call `context.save()` explicitly.
- **No new schema / migration** — Phase 5 adds zero `@Model` types.
- **App Group store** is the project's standardized persistence suite — the lock flag
  lives in the App Group `UserDefaults`, consistent with this.

### Integration Points
- **App lifecycle:** the gate intercepts at the `App`/`RootView` boundary, observing
  `scenePhase` for the background-timeout re-lock (D5-01) and presenting the
  blur+unlock overlay (D5-02).
- **`RootView` TabView:** Settings added as tag 4; `selectedTab` binding threaded in
  for the Budgets deep-link.
- **`LocalAuthentication`** is net-new to the project (`import LocalAuthentication`,
  `LAContext`, `LAPolicy.deviceOwnerAuthentication`) — first use; confirm iOS 17+
  availability in research (it's long-available, but verify the LAError enum surface).
- **App Group `UserDefaults`** — the lock-enabled flag's home; reuse the existing
  suite name from `ModelContainer+App.swift`.

</code_context>

<specifics>
## Specific Ideas

- The gate should feel like a **banking app**: locks on launch and after a few minutes
  in the background, but tolerates a quick switch-out to grab an OTP (the ~3-min grace).
- The unlock screen is a **real screen with an Unlock button** — never a blank gate or
  an auto-only prompt the user can get stuck behind.
- **"Never lock the user out"** is the load-bearing principle for SEC-02 — even the
  no-passcode hard block (D5-05) has a reachable, data-preserving escape.
- **Settings stays clean and minimal** — "don't pollute Settings." Budgets are a big
  screen and keep their own home; Settings just *links* there. Categories get a simple
  management button. About/version footer, nothing else.
- Enabling the lock should **prove it works** (auth-to-enable); disabling it should
  **require auth** so an intruder can't switch it off.

</specifics>

<deferred>
## Deferred Ideas

- **Gmail section in Settings** (connect, sign-out, last-synced, "Sync now") — **Phase 6**
  (SEC-03, SET-04, SET-05). Settings structure is intentionally left clean for it; no
  placeholder shipped now.
- **Custom in-app PIN / app-specific passcode** — out; we use the device passcode via
  `deviceOwnerAuthentication` only. Revisit only if device-passcode UX proves
  insufficient (not expected).
- **Per-record / per-note encryption** — out of charter (REQUIREMENTS.md); app-level
  gate covers the trust need.
- **Configurable grace-period UI** (user-tunable auto-lock timeout) — not in v1; a
  fixed ~3-min constant is enough for a two-user app. Revisit if real usage demands it.
- **Biometric re-auth for individual sensitive actions** (e.g., deleting all data) —
  not in scope; the app-open gate is the v1 boundary.

None of these block Phase 5; they stay out unless explicitly re-scoped.

</deferred>

---

*Phase: 5-Face ID Gate & Settings*
*Context gathered: 2026-06-02*
