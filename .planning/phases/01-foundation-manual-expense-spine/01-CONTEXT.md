# Phase 1: Foundation & Manual Expense Spine - Context

**Gathered:** 2026-05-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Stand up the project and prove a CloudKit-ready SwiftData spine through one real
end-to-end feature: **manual expense add → edit → delete → list**. This phase
locks every one-way-door decision on day one (bundle / CloudKit container /
App Group IDs, `PrivacyInfo.xcprivacy`, the 8 CloudKit-readiness model rules,
`VersionedSchema` + `SchemaMigrationPlan` scaffolding, Swift Testing harness with
an in-memory `ModelContainer`).

**In scope:** FND-01..07, EXP-01, EXP-02, EXP-03 — the Xcode project, the
`Expense` `@Model`, manual CRUD UI reaching a list, en-IN currency formatting,
UTC date storage, privacy manifest, versioned-schema scaffolding, test harness.

**Out of scope (later phases):** category management + picker, tags, budgets,
month grouping (Phase 2); notes (Phase 3); overview + charts (Phase 4); Face ID +
Settings (Phase 5); Gmail OAuth + ingestion + merchant normalization + refund
detection logic (Phases 6–7). The schema must accommodate these additively — no
breaking migration when they arrive.

</domain>

<decisions>
## Implementation Decisions

### Amount & Date Entry (discussed)
- **D-01:** Transaction date **defaults to now and is editable** via a date
  picker. The ≤4-tap fast path requires no date interaction; backdating is a
  deliberate extra action.
- **D-02:** Date is stored as a **full UTC timestamp** (date + time-of-day),
  displayed in the user's local time. Rationale: future-proofs intra-day
  ordering and aligns with timestamped bank emails arriving in Phase 7 — avoids
  a date-only → timestamp schema change later.
- **D-03:** **Negative amounts are allowed in manual entry from v1.** The keypad
  and validation accept negative ₹ values (user can record a refund/reversal
  manually). Stored as `Decimal`.
- **D-04:** Amount uses a **standard decimal keypad, paise optional** — whole
  rupees (₹500) are valid, paise allowed when needed (₹499.50). Stored as
  `Decimal`; displayed with 2 decimal places using `Locale(identifier: "en_IN")`
  (₹1,00,000.00 grouping). NOT cents-style auto-decimal entry.

### Expense Schema — v1 fields (Claude's discretion)
- **D-05:** The `Expense` `@Model` for v1 carries: `id: UUID` (primary key),
  `amount: Decimal` (defaulted, signed), `currencyCode: String` (defaulted
  `"INR"` — multi-currency-ready per PROJECT.md, single-currency UI),
  `date: Date` (UTC timestamp, defaulted to now), `note: String?` (optional
  free-form memo / payee text for manual entries), `createdAt: Date`,
  `updatedAt: Date`. All fields optional-or-defaulted, no `@Attribute(.unique)`,
  money as `Decimal`, dates UTC — per the 8 CloudKit-readiness rules (FND-03).
- **D-06:** A dedicated normalized **merchant field is NOT added in Phase 1** —
  it arrives with ingestion (Phase 7). The optional `note` field covers
  manual-entry payee text for now. (Additive: Phase 7 can add `merchant` /
  `rawEmailBody` / `parserID` fields without breaking existing rows.)

### Category in the Phase 1 Flow (Claude's discretion)
- **D-07:** The **category picker is deferred to Phase 2.** Phase 1's add flow is
  `open → amount keypad → (optional date/note) → save`, which already satisfies
  the ≤4-tap criterion (open → type amount → save = 3 taps). This deviates from
  ROADMAP Phase 1 success-criterion #1's literal "amount → category → save"
  wording: the category step lands in Phase 2 with EXP-04/05, where the full
  India-tuned list + custom-category CRUD exists. Manual CRUD + list is the true
  vertical slice that proves the spine.
- **D-08:** **No breaking migration when categories arrive.** The Phase 1 schema
  must be forward-compatible so Phase 2 adds the `Category` `@Model` + the
  `Expense ↔ Category` relationship *additively* (optional, inverse-declared
  relationship per the CloudKit-readiness rules). The researcher/planner choose
  the exact SwiftData mechanism (declare the optional relationship now vs. add it
  in Phase 2's `VersionedSchema` v2) — the binding constraint is: **Phase 2 is a
  lightweight, non-destructive schema migration, never a rewrite.**

### One-Way-Door Identifiers (Claude's discretion — CONFIRM BEFORE BUILD)
- **D-09:** Proposed immutable identifiers (FND-02), derived from the owner
  (Reo Jacob / nobelreojacob@gmail.com). **These are permanent — the user should
  confirm or override before the project is created:**
  - Bundle ID: `com.reojacob.myhome`
  - CloudKit container: `iCloud.com.reojacob.myhome`
  - App Group: `group.com.reojacob.myhome`
  - Minimum deployment target: **iOS 17.0**
  These ship in Phase 1 and are never changed. CloudKit is wired as
  container-ready even though v1 runs local-only.

### Claude's Discretion
The following are explicitly left to the researcher/planner using standard
SwiftData/SwiftUI conventions: project structure & file layout, the exact
in-memory test fixture pattern, en-IN `NumberFormatter`/`FormatStyle` choice,
SwiftData `ModelContainer` wiring, and the visual layout of the add/edit/list
screens (the latter is owned by the upcoming UI-SPEC). Schema-field naming may be
refined by research as long as the CloudKit-readiness rules (D-05) hold.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project charter & scope
- `.planning/PROJECT.md` — constraints, key decisions, sharing/sync architecture, INR/CloudKit-ready stance
- `.planning/REQUIREMENTS.md` — FND-01..07, EXP-01..03 (v1 requirement text + acceptance intent)
- `.planning/ROADMAP.md` §"Phase 1" — goal, success criteria, requirement mapping; §"Phase 2" for the additive-migration boundary

### Domain research (load-bearing for this phase)
- `.planning/research/STACK.md` — Swift 6.2 / SwiftUI / SwiftData / iOS 17+ stack rationale
- `.planning/research/ARCHITECTURE.md` — CloudKit-ready schema discipline, the 8 `@Model` rules, VersionedSchema scaffolding
- `.planning/research/PITFALLS.md` — SwiftData + CloudKit readiness landmines (no `.unique`, optional/defaulted fields, no stored enums, Decimal money, UTC dates, required-reason API privacy manifest)
- `.planning/research/SUMMARY.md` — the manual-entry-before-ingestion sequencing decision and overall phasing rationale

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — greenfield. No Swift/Xcode files exist yet; repo currently holds only `.planning/`.

### Established Patterns
- None in-repo. The binding patterns are the CloudKit-readiness rules and stack choices documented in `.planning/research/ARCHITECTURE.md` and `PITFALLS.md`.

### Integration Points
- This phase establishes the integration surface (the `ModelContainer`, the `Expense` model, the app entry point) that every later phase builds on.

</code_context>

<specifics>
## Specific Ideas

- en-IN money rendering is explicit: ₹1,00,000.00 (lakh grouping), not ₹100,000.00 — see FND-07.
- The ≤4-tap add flow is a hard UX target (EXP-01); Phase 1 hits it without a category step.
- The schema is the durable asset — treat the 8 CloudKit-readiness rules as non-negotiable even though v1 is local-only.

</specifics>

<deferred>
## Deferred Ideas

- **Category picker + India-tuned list + custom category CRUD** → Phase 2 (EXP-04/05). Phase 1 leaves the schema forward-compatible (D-08).
- **Normalized merchant field, raw email body, parserID/parserVersion** → Phase 7 ingestion (additive schema fields).
- **Multi-currency display / FX** → out of scope (schema carries `currencyCode`, UI stays INR-only).
- **Tags, budgets, month grouping** → Phase 2.

</deferred>

---

*Phase: 1-Foundation & Manual Expense Spine*
*Context gathered: 2026-05-29*
