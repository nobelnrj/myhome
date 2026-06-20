# My Home

## Current State

**Shipped:** v1.1 Accounts, Assets & Household Polish (2026-06-20) — see [milestones/v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md). The app is now a light household finance hub: account-aware spend with self-transfer detection, a net-worth Asset Tracker (free AMFI MF NAV + manual holdings + SIP automation), and daily-routine notes — on top of the v1.0 MVP (automated Gmail expense ingestion, budgets, notes/reminders, overview, Face ID).

## Next Milestone: v1.2 Neumorphic Redesign

**Goal:** A full neumorphic (Soft UI) visual redesign of the entire app, plus the design handoff's net-new surfaces — making My Home look and feel like a polished, cohesive personal-finance product rather than a stock SwiftUI app.

**Target work (to be formalized via /gsd-new-milestone):**
- **Neumorphic design system** — implement the exact tokens (charcoal surfaces, dual light/dark shadows, canary-yellow accent, 26px radii, floating capsule tab bar, rolling money readouts) from `design/design_handoff_myhome_neumorphic/`.
- **Restyle every screen** — Overview, Activity, Budgets, Notes, Settings AND the unshown surfaces (Accounts, Assets/Net-worth, Transfer Inbox, Gmail/Ingestion) to one consistent neumorphic look (decided: restyle all).
- **Dedicated Analytics screen** (net-new) — time-range tabs, spending-trend area chart, by-category bars, delta chips.
- **AI Insight card** (net-new) — natural-language spending insight powered by **Apple FoundationModels on-device** (free, private, offline; no API/keys).
- **"Where it's going" spend donut** (net-new) on Overview.

**Key context:**
- Still local-only (no CloudKit/sharing — remains the v2.0 trigger gated on the $99/yr upgrade).
- AI Insight is **on-device only** (FoundationModels, iOS 26 / Apple Intelligence) — finance data never leaves the device; gracefully degrades where unsupported.
- This is primarily a visual/UX milestone over a feature-complete app — redesign first, then layer in the net-new surfaces.

<details>
<summary>Previous milestone: v1.1 Accounts, Assets & Household Polish (shipped 2026-06-20)</summary>

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

### Active

<!-- Next milestone (v1.1) scope — to be defined via /gsd-new-milestone. -->

v1.1 scope — to be assigned REQ-IDs in REQUIREMENTS.md:
- Accounts management (bank accounts, balances, per-account spend)
- Self-transfer auto-detection + confirm (exclude from spend)
- Asset tracker (MF / stocks / NPS / account balances → net worth) with free public NAV/quote APIs
- Notes enhancement (daily routine → calendar daily reminder; day-to-day features)
- Stabilization fixes (add-category ordering, sync/notes crash, daily-routine end-of-day reset)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- **Android / cross-platform** — Both users are on iPhone; cross-platform doubles work for zero benefit.
- **SMS reading on iOS** — iOS does not expose SMS to third-party apps; pursuing this is wasted effort. Email-based ingestion replaces it.
- **Real cross-Apple-ID sharing in v1** — Requires the $99/yr Apple Developer Program for reliable CloudKit sharing. v1 is single-user on Reo's phone; sharing is a deliberate later phase after the upgrade decision.
- **Open-Banking / Plaid / TrueLayer integrations** — Cost, complexity, and weaker India coverage versus free Gmail-based ingestion.
- **Multi-currency display / FX conversion in v1** — Schema will accommodate it; UI will not. Adds complexity for no current need.
- **watchOS app, widgets, complications** — Explicitly a post-v1 goal once the core app is loved and used daily.
- **Multi-household / sharing with people other than wife** — App is built for one specific household forever.
- **Receipt OCR / camera capture** — Not in v1. Reconsider after manual-entry friction data exists.
- **Recurring / scheduled expenses, bill reminders** — Defer; revisit once tag/budget loop is proven.
- ~~**Investments, net worth, account-balance tracking** — out of charter.~~ **Reversed in v1.1** — the app is intentionally growing into a light household-finance hub. Asset tracking (MF/stocks/NPS/balances), net worth, and accounts management are now in scope. Constraint retained: free data sources only, manual override always available.
- **Web or macOS clients** — iOS-only is a deliberate constraint to keep scope small.

## Context

**Current state (v1.0, 2026-06-03):** ~16,000 LOC Swift across 106 files, 209 commits over ~6 days. Stack: Swift 6.2 / SwiftUI / SwiftData, iOS 17+, schema at SchemaV4, local-only on one device. All 56 v1 requirements complete. 4 open human-verification artifacts deferred (manual on-device UAT/verification passes — see STATE.md). Confidence threshold (0.85) and BGAppRefreshTask behavior want real-week validation.

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
| CloudKit for sync (when sync arrives) | Free, native, fits 2-user shared-data model, no backend to host | — Pending (deferred to v2; schema kept CloudKit-ready throughout) |
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
*Last updated: 2026-06-08 — started milestone v1.1 (Accounts, Assets & Household Polish)*
