# Requirements — v1.3.1 UX Polish

**Milestone goal:** A fast interim polish pass — make the app feel more premium (floating nav bar), de-crowd the Overview (remove duplicated spend charts), and make every expense editable wherever it appears. Local-only, no schema change, no new dependencies.

**Constraints:** iOS 17+, Swift 6.2 / SwiftUI / SwiftData, SchemaV11 (no schema change), local-only, zero new dependencies. Continues phase numbering from v1.3 (Phase 23+).

## v1.3.1 Requirements

### Navigation

- [ ] **NAV-01**: Replace the native tab bar with a custom floating nav bar — the five destinations remain, presented as a floating, neumorphic bar detached from the screen edge for a premium feel; existing `-startTab N` debug indices continue to work. (#33)

  > Context: v1.2 attempted this as DS-03 and reverted to the native bar (a native `TabView` bar could not be styled/glow). This re-attempts it as a genuine custom floating bar over a plain `TabView` selection, accepting that the custom bar owns its own styling.

### Overview declutter

- [ ] **OVF-04**: Remove the duplicated Overview content — "Where it's going" (spend donut) and "By category" render the same spend-by-category data, and the budget section overlaps it further. Consolidate to a single spend-by-category presentation on the Overview and reduce chart crowding, without losing tap-to-filter-into-Activity or the account × date-range filter shipped in v1.3 (OVF-01..03). (#34)

### Editing

- [ ] **EDIT-01**: Make every expense row tap-to-edit wherever it appears — Budget-screen filtered expense lists, Analytics/category drill-downs, and any other list of expenses open the existing expense edit sheet on tap (parity with the main Activity list). No new edit UI; reuse the existing editor. (#35)

## Future Requirements

Deferred to v1.4 Finance & AI Depth (tracked in GitHub, nobelnrj/myhome):
- Security debt: Face ID review fixes (#31), auto-sync paired-device allowlist (#43)
- Finance depth: bill reminders (#27), recurring-transaction detection (#28), data exports (#29), account scope pill in Expenses (#44)
- Smarter AI: grounded Overview insight / follow-ups / trend narratives (#30)

## Out of Scope (this milestone)

- **Any schema or data-model change** — v1.3.1 is pure presentation/interaction polish on SchemaV11.
- **New charts or analytics** — OVF-04 removes/consolidates existing content; it does not add new visualizations.
- **New expense-editing capabilities** — EDIT-01 only widens where the *existing* edit sheet is reachable; it adds no new fields or flows.
- **Finance/AI/security work** — belongs to v1.4.

## Traceability

<!-- Filled by roadmap: REQ-ID → Phase. -->

| REQ-ID | Phase |
|--------|-------|
| NAV-01 | — |
| OVF-04 | — |
| EDIT-01 | — |

---
*Created: 2026-07-22 — v1.3.1 UX Polish milestone.*
