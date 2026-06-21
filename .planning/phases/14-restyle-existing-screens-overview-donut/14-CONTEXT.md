# Phase 14: Restyle Existing Screens + Overview Donut - Context

**Gathered:** 2026-06-21
**Status:** Ready for UI design contract
**Source:** Conversational decisions (post Phase-13 deploy review)

<domain>
## Phase Boundary

Phase 14 is the **first visible restyle** of the v1.2 redesign. Phase 13 built the design-system
components (`DesignTokens`, `NeuSurface`, `RollingMoneyText`, `NeuTabBar`) but applied them to **zero**
screens — all 67 feature view files still use stock system styling (`Color(.secondarySystemBackground)`,
`.accentColor` = system blue). Phase 14 bolts the existing **Neomorphism** design system onto every
screen and adds the Overview spend donut.

Delivers: all 9 screen groups restyled to charcoal neumorphic surfaces + canary-yellow accent +
luminous category palette; the "Where it's going" spend donut on Overview with tap-to-filter into Activity.
</domain>

<decisions>
## Locked Decisions (from this conversation — do NOT re-ask)

- **SKIN = Neomorphism, NOT Liquid Glass.** The design handoff ships 6 interchangeable skins. The user's
  reference screenshots are the default *Liquid Glass* skin, but `DesignTokens.swift` was translated from
  the *neuro* (Neomorphism) branch. After a side-by-side comparison (`design/skin-comparison.html`), the
  user explicitly chose **Neomorphism**. KEEP the existing `DesignTokens`/`NeuSurface` as-is. Do NOT rework
  toward translucent glass / `backdropFilter` / iOS 26 `glassEffect`. Opaque charcoal surfaces with dual
  soft shadow are the target material.
- **Tab bar = native iOS, restyled colors only.** The DS-03 floating capsule `NeuTabBar` was REVERTED to
  the native `TabView` tab bar (commit 92e3e61). Do NOT rebuild a custom/floating tab bar. Phase 14 restyles
  the native bar's accent/tint only. `NeuTabBar.swift` is orphaned — delete it during Phase 14 (needs the 4
  manual pbxproj edits, see [[xcodeproj-explicit-file-refs]]).
- **Dark-mode-only retained** (DS-05, single `.preferredColorScheme(.dark)` at app root). Keep.
- **Migrate `CardStyle` → `.neuSurface(.raised)`.** `CardStyle.swift` is a deprecation shim marked
  "removed in Phase 14". Replace every `.cardStyle()` call site and delete the shim.
- **Hero rupee figures use `RollingMoneyText`** (e.g. net-cash-flow total, donut center, budget left-to-spend).
- **Match the reference layout/content structure** (not material): Overview gets a "NET CASH FLOW" hero card
  (income/spent split), the "4 expenses to review" card, the Analytics push affordance, and the donut.
  Category icons use the luminous category palette (`DesignTokens.cat*`).
</decisions>

<canonical_refs>
## Canonical References

- **Reference mockup (structure & layout source of truth):**
  `design/design_handoff_myhome_neumorphic/src/*.jsx` — `home.jsx`, `expenses.jsx`, `budgets.jsx`,
  `notes.jsx`, `settings.jsx`, `analytics.jsx`. Render the **neuro** skin mentally, not the default liquid.
- **Design tokens (the contract for all values):** `MyHomeApp/DesignSystem/DesignTokens.swift`
- **Surface modifier:** `MyHomeApp/DesignSystem/NeuSurface.swift` (`.neuSurface(.raised/.floating/.recessed)`)
- **Rolling money:** `MyHomeApp/DesignSystem/RollingMoneyText.swift`
- **Visual comparison artifact:** `design/skin-comparison.html` (liquid vs neuro, for the record)
- ROADMAP Phase 14 success criteria + requirements SKIN-01…09, OVR-05, OVR-06.
</canonical_refs>

<specifics>
## Specifics

- **9 screen groups to restyle:** Overview, Activity/Expenses, Budgets, Notes/calendar/agenda, Settings,
  Accounts, Assets/Net-worth, Transfer Inbox, Gmail Review Inbox. No stock `Color(.secondarySystemBackground)`
  or other system color may remain visible anywhere.
- **Donut ("Where it's going" — OVR-05/06):** current month top-4 spend categories + "Others" roll-up;
  rolling total in center via `RollingMoneyText`; **exclude confirmed self-transfer expenses** from all
  segment totals; tapping a segment navigates to Activity pre-filtered to that category; all segments fully
  visible inside the card (no clipping at card edges); colors = neumorphic category palette.
- **No regressions:** expense/account/asset/note CRUD, Gmail sync, self-transfer confirm, Face ID gate,
  and navigation deep-links (incl. `kOpenNoteNotification` → Notes tab) must behave identically to v1.1.
- **pbxproj discipline:** every new `.swift` file needs the 4 manual pbxproj edits (no synchronized groups).
</specifics>

<deferred>
## Deferred / Out of Scope

- Liquid Glass skin (explicitly rejected for v1.2).
- Floating/custom tab bar (reverted; native only).
- The dedicated Analytics screen (Phase 15) and AI Insight card (Phase 16) — Phase 14 only adds the
  push affordance to reach Analytics, not the screen itself.
</deferred>

<scope_fence>
## Scope Fence

IN: restyling existing screens to the neuro design system; the Overview donut + tap-to-filter; CardStyle
removal; native tab bar restyle; `NeuTabBar.swift` deletion.

OUT: new screens (Analytics/AI), schema changes, new data sources, the Liquid Glass material, any custom
tab bar.
</scope_fence>
