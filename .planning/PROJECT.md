# My Home

## Current State

**Shipped:** v1.3 Private Sync & Kitchen (2026-07-22) — see [milestones/v1.3-ROADMAP.md](milestones/v1.3-ROADMAP.md). Both phones now share household data privately for free — a transport-agnostic merge engine (syncID + last-writer-wins + tombstones) over AirDrop snapshots and automatic MultipeerConnectivity sync on home WiFi, with a first-run bootstrap and a trustworthy sync surface; no cloud, no $99 account, schema stays CloudKit-ready. Adds a first-class Kitchen (pantry stock, low-stock thresholds, auto-restocking shopping list) with on-device model-chosen pantry icons, and an account × date-range filter on the Overview — on top of the v1.2 neumorphic redesign, v1.1 finance hub, and v1.0 MVP.

## Current Milestone: v1.3.1 UX Polish (planning)

**Goal:** A fast interim polish pass — make the app feel more premium (floating nav bar), de-crowd the Overview (remove duplicated spend charts), and make every expense editable wherever it appears. Local-only, no schema change, no new dependencies.

**Target features:**
- **Floating nav bar (#33)** — replace the native tab bar with a custom floating nav bar for a premium feel. Re-attempts v1.2's reverted DS-03 as a true custom bar.
- **Overview declutter (#34)** — "Where it's going" donut and "By category" show the same data, and the budget section overlaps too; consolidate to a single spend-by-category view and de-crowd the dashboard.
- **Tap-to-edit expenses everywhere (#35)** — every expense row shown anywhere (Budget filtered list, Analytics drill-downs, category views) is tappable → opens the existing edit sheet.

## Following Milestone: v1.4 Finance & AI Depth (queued)

**Direction:** Deepen finance and AI, and pay down two shipping-feature security gaps first. Scope lives in the GitHub tracker (nobelnrj/myhome) until formalized via `/gsd-new-milestone`:
- **Security debt (first):** land the 4 un-merged Phase-05 Face ID review fixes (#31) and add a paired-device allowlist so auto-sync no longer trusts any LAN peer (#43).
- **Finance depth:** bill/subscription reminders (#27), recurring-transaction detection (#28), data exports (#29), and surfacing the account scope pill in Expenses too (#44).
- **Smarter AI:** better-grounded Overview insight / follow-ups / trend narratives (#30) — including fixing insight advice that miscounts investments as spend.

<details>
<summary>Previous milestone: v1.3 Private Sync & Kitchen (shipped 2026-07-22)</summary>

**Goal:** Let both phones share household data privately for free (no cloud, no $99 Apple Developer account), add a kitchen inventory + shopping list, and make the Overview filterable by account and date.

- Private P2P sync — transport-agnostic merge engine (syncID + LWW + tombstones); AirDrop snapshot exchange + automatic MultipeerConnectivity sync over home WiFi; first-run bootstrap; no cloud, schema stays CloudKit-ready (SchemaV9→V11).
- Kitchen inventory — pantry stock, per-item low-stock thresholds, auto-populated shopping list that restocks on check-off; a synced neumorphic surface.
- Pantry icon intelligence — on-device model (Apple FoundationModels) picks each item's icon from a closed category set, keyword table as offline fallback; never persisted or synced.
- Overview filtering — filter cash flow, spend donut, and totals by account subset combined with a custom date range.

Foreground-only P2P (no paid Push/CloudKit), free on-device transports only, zero new paid dependencies. 7-day provisioning expiry handled outside the app by `scripts/auto-deploy.sh`.

</details>

<details>
<summary>Earlier milestone: v1.2 Neumorphic Redesign (shipped 2026-07-13)</summary>

**Goal:** A full neumorphic (Soft UI) visual redesign of the entire app, plus the design handoff's net-new surfaces — making My Home look and feel like a polished, cohesive personal-finance product rather than a stock SwiftUI app.

- Neumorphic design system — tokens, `NeuSurface` dual-shadow modifiers, `RollingMoneyText`, accessibility infra.
- Restyle every screen — all nine screen groups to one consistent neumorphic look; zero regressions.
- "Where it's going" spend donut on Overview with tap-to-filter into Activity.
- Dedicated Analytics screen — time-range tabs, spending-trend area chart, by-category bars, inverted-color delta chips, single testable `AnalyticsAggregator`.
- AI Insight card — on-device Apple FoundationModels (iOS 26), two-layer availability gating, guided generation, numeric-integrity verification, streaming typewriter.
- Light mode support (added post-freeze, Phase 17) — full adaptive palette, reworked shadows, non-glow orb/rings, byte-identical dark rendering.

Local-only, zero new dependencies, iOS 17 floor, no schema change. DS-03 floating tab bar reverted to native.

</details>

<details>
<summary>Earlier milestone: v1.1 Accounts, Assets & Household Polish (shipped 2026-06-20)</summary>

**Goal:** Grow My Home from an automated expense tracker into a light household finance + ops hub — account-aware spend with self-transfer detection, a net-worth asset tracker, smarter daily-routine reminders, and a stability/UX cleanup pass.

- Stabilization — fixed crash vectors, category ordering, daily-routine reset.
- Accounts management — bank accounts with live balances + per-account spend.
- Self-transfer detection — auto-detect + confirm; excluded from spend.
- Asset tracker — MF/stocks/NPS + account balances → net worth (free AMFI NAV, manual override, SIP automation, NPS NAV refresh).
- Notes enhancement — daily routine in calendar, timed notifications, drag-reorder, streak/history.

Local-only, free-data-only, auto-detect+confirm (never silent), additive CloudKit-ready schema (V5→V9).

</details>

## What This Is

A personal iOS app for a two-person household (Reo and his wife) that consolidates day-to-day "home ops" into one place. v1.0 shipped (2026-06-03): an automated expense tracker fed by bank email alerts (Gmail) with manual fallback, categories/tags/per-category budgets, a notes + reminders hub (inline checklists, recurrence, local notifications, calendar), an overview dashboard with Swift Charts, and a Face ID gate. It is deliberately built for two specific users, not for distribution, on a CloudKit-ready SwiftData schema that can absorb new household features (chores, calendar, grocery, etc.) and post-v1 sync without rework.

## Core Value

**"Everything our household needs in one place, with the expense tracker so automated that I never have to think about logging a transaction."**

If everything else fails, the email-driven expense ingestion + manual fallback must work reliably. That is the single feature that decides whether this app gets used daily or abandoned.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. All v1.0 (56/56 requirements). -->

- ✓ Manual expense entry — add/edit/delete end-to-end via custom decimal keypad — v1.0 (Phase 1)
- ✓ INR currency with en-IN formatting (₹1,00,000.00), money as `Decimal`, dates UTC — v1.0 (Phase 1)
- ✓ CloudKit-ready SwiftData schema (all optional/defaulted, no `.unique`), VersionedSchema + migration plan proven against bundled stores — v1.0 (Phase 1)
- ✓ India-tuned predefined categories + custom categories; single-tag (multi-tag-ready schema) — v1.0 (Phase 2)
- ✓ Per-category monthly budgets with ₹-remaining + % progress bars (80%/100% threshold colors) — v1.0 (Phase 2)
- ✓ Month view of expenses grouped by category with tap-through — v1.0 (Phase 2)
- ✓ Notes & reminders hub — block notes (text + inline checklists), pin, search, auto-save — v1.0 (Phase 3)
- ✓ Reminders with recurrence + end rules, local notifications (Complete/Snooze/deep-link), calendar view — v1.0 (Phase 3, scope expanded from plain notes)
- ✓ Overview dashboard — spend-vs-budget bar, top-3 categories, pinned-note card, quick-add — v1.0 (Phase 4)
- ✓ Swift Charts — spend-by-category (`BarMark`) + spend-over-time (`LineMark` with range control) — v1.0 (Phase 4)
- ✓ Face ID app lock with full LAError handling + passcode fallback; Settings shell — v1.0 (Phase 5)
- ✓ Gmail read-only OAuth (ASWebAuthenticationSession + PKCE, no SDK), Keychain token, 30-day backfill, Sync now, last-synced, reconnect CTA — v1.0 (Phase 6)
- ✓ Automated bank-email ingestion — HDFC + ICICI parsers, 0.85-confidence triage, Review Inbox, dedup, reversal/refund handling, merchant normalization, parser provenance, best-effort BGAppRefreshTask — v1.0 (Phase 7)
- ✓ On-device AI Insight card on Analytics — FoundationModels (Apple Intelligence) natural-language spending insight, silent absence on unavailable devices, streaming typewriter + Reduce-Motion degradation, numeric-integrity verifier (no model-invented figures), templated fallback — v1.2 (Phase 16; on-device sign-off 2026-06-27) [AI-01..AI-05]
- ✓ Accounts management + self-transfer detection + net-worth asset tracker (MF/stocks/NPS via free AMFI NAV, manual override, SIP automation, NPS NAV refresh) + daily-routine notes enhancement; stabilization pass — v1.1 (Phases 8–12, SchemaV5→V9)
- ✓ Full neumorphic (Soft UI) redesign — single-source design system + `NeuSurface`, every screen restyled, Overview spend donut, dedicated Analytics screen, and full light-mode support with byte-identical dark rendering — v1.2 (Phases 13–17)
- ✓ Private P2P household sync — transport-agnostic merge engine (syncID + LWW + tombstones), AirDrop snapshot exchange + automatic MultipeerConnectivity sync over home WiFi, first-run bootstrap, trustworthy sync surface; no cloud, CloudKit-ready SchemaV9→V11 — v1.3 (Phases 18–19) [SYNC-01..05]
- ✓ Kitchen inventory — pantry stock, per-item low-stock thresholds, auto-restocking shopping list; a synced neumorphic surface with on-device model-chosen pantry icons — v1.3 (Phases 20, 22) [KTCH-01..04, ICON-01..03]
- ✓ Overview filtering — account subset × custom date range, reusing confirmed-self-transfer exclusion, one-tap clear — v1.3 (Phase 21) [OVF-01..03]

### Active

<!-- Current milestone: v1.3.1 UX Polish (Phase 23). REQ-IDs in .planning/REQUIREMENTS.md. -->

v1.3.1 UX Polish — interim polish milestone (see REQUIREMENTS.md):
- [ ] **NAV-01**: Custom floating nav bar replacing the native tab bar (#33)
- [ ] **OVF-04**: Overview declutter — one spend-by-category view, remove duplicated donut/budget overlap (#34)
- [ ] **EDIT-01**: Tap-to-edit any expense row shown anywhere in the app (#35)

v1.4 Finance & AI Depth — queued next, tracked as GitHub issues, REQ-IDs assigned when formalized:
- Security debt first: merge the 4 un-landed Phase-05 Face ID review fixes (#31); paired-device allowlist for auto-sync so it no longer trusts any LAN peer (#43)
- Finance depth: bill/subscription reminders (#27), recurring-transaction detection (#28), data exports (#29), account scope pill in Expenses (#44)
- Smarter AI: better-grounded Overview insight / follow-ups / trend narratives, incl. not counting investments as spend (#30)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- **Android / cross-platform** — Both users are on iPhone; cross-platform doubles work for zero benefit.
- **SMS reading on iOS** — iOS does not expose SMS to third-party apps; pursuing this is wasted effort. Email-based ingestion replaces it.
- **Cloud / cross-Apple-ID sharing when phones are apart** — Reliable CloudKit sharing needs the $99/yr Apple Developer Program. v1.3 shipped free P2P sync for the two phones **on the same network** (AirDrop + MultipeerConnectivity); sync-when-apart via a cloud relay stays deferred as the future paid-upgrade trigger.
- **Open-Banking / Plaid / TrueLayer integrations** — Cost, complexity, and weaker India coverage versus free Gmail-based ingestion.
- **Multi-currency display / FX conversion in v1** — Schema will accommodate it; UI will not. Adds complexity for no current need.
- **watchOS app, widgets, complications** — Explicitly a post-v1 goal once the core app is loved and used daily.
- **Multi-household / sharing with people other than wife** — App is built for one specific household forever.
- **Receipt OCR / camera capture** — Not in v1. Reconsider after manual-entry friction data exists.
- **Recurring / scheduled expenses, bill reminders** — Defer; revisit once tag/budget loop is proven.
- ~~**Investments, net worth, account-balance tracking** — out of charter.~~ **Reversed in v1.1** — the app is intentionally growing into a light household-finance hub. Asset tracking (MF/stocks/NPS/balances), net worth, and accounts management are now in scope. Constraint retained: free data sources only, manual override always available.
- **Web or macOS clients** — iOS-only is a deliberate constraint to keep scope small.

## Context

**Current state (v1.3, 2026-07-22):** Swift 6.2 / SwiftUI / SwiftData, iOS 17+, schema at SchemaV11. No longer single-device — data syncs P2P between two phones (foreground-only, over AirDrop + MultipeerConnectivity), still local-only with no cloud. Neumorphic light+dark UI; on-device Apple FoundationModels used for the AI Insight card and pantry icons. v1.3 requirements 15/15 complete. Deferred debt carried at close (all mirrored in the GitHub tracker): test-infra multi-container crash (#24), doc/Nyquist gaps (#25), v1.0-era human-verification passes (#26), and one v1.3 kitchen verification that is de-facto validated (shipped to both phones, in daily use). Two known security gaps queued first for v1.4: un-landed Face ID review fixes (#31) and auto-sync trusting any LAN peer (#43).

**Users:** Reo (primary, developer) and his wife. Two iPhones, two Apple Watches. iCloud users. Based in India. Daily-use household tool — not a side project to ship publicly.

**Domain context — banking in India:**
- Indian banks (HDFC, ICICI, SBI, Axis, etc.) push transaction alerts via SMS *and* email. SMS is the de-facto behavior on Android apps like Walnut, but iOS blocks all third-party SMS access.
- Email alerts are the only legitimate zero-touch ingestion path on iOS. Bank email alerts must be enabled in each bank's net-banking portal (one-time setup).
- Gmail API has a generous free tier (1 billion quota units/day) — well within a household-app budget.
- Email formats vary per bank; parsing needs per-bank regex/templates with manual-entry fallback when parsing confidence is low.

**Developer context:**
- Reo has React Native experience but **no prior native iOS / Swift / Xcode** background. The project doubles as a learning vehicle for Swift + SwiftUI + CloudKit.
- Strong preference for TDD and prototyping-first iteration.
- Working on macOS with Xcode installed (implied by Swift choice).

**Ingestion architecture (v1):**
- Gmail OAuth on first launch → app polls inbox in background (BackgroundTasks framework) for new bank emails
- Per-bank parser (template + regex) extracts amount, merchant, card, timestamp
- Low-confidence parses surface in an "inbox" for one-tap review/correct/save
- Parsed expenses written to local store (Core Data or SwiftData) with a tag suggestion

**Sharing architecture (post-v1):**
- Schema designed for CloudKit `CKRecord` compatibility from day one (UUID primary keys, no FK fan-out, optional fields tolerant of conflict)
- When the $99/yr upgrade happens, a phase migrates local store → CloudKit private DB → shared zone with wife's Apple ID

## Constraints

- **Tech stack**: Swift + SwiftUI, iOS 17+ minimum — Modern SwiftData/Observation APIs; both phones are recent.
- **Persistence (v1)**: SwiftData (preferred) or Core Data — local-first, CloudKit-ready models.
- **Backend (post-v1)**: CloudKit shared zone — free within Apple ID quotas, no server to host, native to ecosystem.
- **Budget**: Low to zero recurring cost. $99/yr Apple Developer Program is the only acceptable spend, and only after v1 validation. No paid third-party services (Supabase/Firebase/Plaid).
- **Distribution (v1)**: Free Apple Developer provisioning, single-user (Reo's phone only). 7-day rebuild cycle accepted.
- **Distribution (post-v1)**: TestFlight via $99/yr Apple Developer Program, install on wife's phone, weekly rebuild eliminated.
- **Performance**: Two users, low volume — performance is not a constraint. Do not over-engineer.
- **Security**: Face ID app lock required (financial data). Gmail OAuth tokens in Keychain. No analytics, no telemetry, no third-party SDKs.
- **Development style**: TDD by default. Prototype first, iterate. Pedagogy-aware — Reo is new to Swift.
- **Schema durability**: Adding a new "home" feature (chores, calendar, grocery, etc.) must not require breaking changes. Use a generic `HouseholdItem`-style base or strict per-feature models with shared concerns extracted — decided in architecture phase.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| iOS-only, no cross-platform | Both users on iPhone; goals include watchOS widgets which RN can't deliver | ✓ Good — v1.0 shipped iOS-only |
| Swift + SwiftUI (not React Native) | iOS-only removes RN's main benefit; doubles as Swift learning vehicle | ✓ Good — full v1.0 built in Swift 6.2 / SwiftUI / SwiftData |
| CloudKit for sync (when sync arrives) | Free, native, fits 2-user shared-data model, no backend to host | — Deferred — v1.3 shipped free P2P sync (MultipeerConnectivity + AirDrop) instead; CloudKit stays the future paid-upgrade trigger for sync-when-apart. Schema kept CloudKit-ready throughout. |
| Free P2P sync over MultipeerConnectivity + AirDrop (not CloudKit) | CloudKit/iCloud/Push are paid-only; MC needs no entitlement on a free Personal Team; a two-person household shares home WiFi | ✓ Good — v1.3 shipped foreground-only encrypted P2P with a tested transport-agnostic merge engine (LWW + tombstones), reused verbatim across AirDrop + Multipeer |
| App-level identity + LWW + tombstones for merge (no `.unique`) | Schema has no unique constraints (CloudKit-ready); identity must be app-level `syncID: UUID`, conflicts resolve last-writer-wins on `updatedAt`, deletes need tombstones or they resurrect | ✓ Good — v1.3 golden round-trip idempotence proven; no-resurrection pinned by test |
| On-device model for pantry icons (closed category set) | Reuse the Phase-16 FoundationModels stack; a fake SF Symbol draws nothing silently, so the model must pick from a closed enum Swift maps to a verified symbol | ✓ Good — v1.3 Phase 22; device-local, never persisted or synced, keyword-table fallback |
| Gmail-based email ingestion (not SMS) | iOS blocks SMS access; email is the only legitimate zero-touch path on iOS | ✓ Good — Phase 7 ingested real HDFC/ICICI emails zero-touch |
| Single-user v1 on Reo's phone | Free Apple Developer account can't do reliable CloudKit sharing across Apple IDs | ✓ Good — v1.0 runs local-only on one device |
| Defer $99/yr Apple Developer cost | "Prove before paying" — validate the app is used daily before committing the only recurring spend | — Pending (v2 trigger; awaiting real v1 usage) |
| Notes = text body + optional checklists (single model) | Maximum flexibility for grocery / recipes / brainstorms without two separate entities | ✓ Good — block model (text + inline checklists) shipped Phase 3 |
| Predefined categories + custom tags, single tag default, schema supports multiple | Sane defaults reduce setup friction; multi-tag schema is future-proof | ✓ Good — Phase 2 |
| Face ID required to open app | Financial data; toggleable in settings for paranoia override | ✓ Good — Phase 5, full LAError handling |
| INR single-currency v1, schema multi-currency-ready | Simplifies v1 UI; schema absorbs future travel/forex without migration | ✓ Good — en-IN throughout |
| TDD as default development style | User preference; aligns with shipping-confidence in a learning-vehicle project | ✓ Good — Wave-0 RED scaffolds + pure-helper GREEN used across phases |
| Phase 3 scope expanded to Notes + Reminders hub | One coherent household hub (reminders, recurrence, notifications, calendar) instead of deferring | ✓ Good — shipped in one phase, human UAT passed |
| Gmail OAuth split (Phase 6 isolation → Phase 7 pipeline) | De-risk the riskiest auth/network sub-system before building parsers on top | ✓ Good — isolated proof simplified Phase 7 wiring |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-07-22 — v1.3.1 UX Polish milestone started (Phase 23); v1.4 Finance & AI Depth queued next.*
