# My Home

## What This Is

A personal iOS app for a two-person household (Reo and his wife) that consolidates day-to-day "home ops" into one place. v1 covers two features — an automated expense tracker fed by bank email alerts, and a shared note keeper with optional checklists — plus a home overview screen. It is deliberately built for two specific users, not for distribution, with a future-proof schema that can absorb new household features (chores, calendar, grocery, etc.) without rework.

## Core Value

**"Everything our household needs in one place, with the expense tracker so automated that I never have to think about logging a transaction."**

If everything else fails, the email-driven expense ingestion + manual fallback must work reliably. That is the single feature that decides whether this app gets used daily or abandoned.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

**Phase 1: Foundation & Manual Expense Spine** (2026-05-29)

- [x] Manual expense entry — add/edit/delete an expense end-to-end (custom decimal keypad, ≤3-tap add)
- [x] INR as the v1 currency — en-IN formatting (₹1,00,000.00), money stored as `Decimal`, dates stored UTC
- [x] Local-only storage in v1 — SwiftData on an App Group store (single device, single user)
- [x] Schema designed so adding CloudKit sharing later is additive, not a rewrite — CloudKit-ready `@Model` (all optional/defaulted, no `@Attribute(.unique)`), VersionedSchema + migration plan proven against a bundled v1 store

**Phase 4: Overview & Charts** (2026-06-01)

- [x] Charts — spend-by-category (`BarMark`) and spend-over-time (`LineMark`/`AreaMark` with Week/Month/Year range) (EXP-10, EXP-11)
- [x] Current month spend vs. budget single bar with threshold colors (OVR-01)
- [x] Top 3 spend categories this month (OVR-02)
- [x] Pinned note / fallback checklist surfaced front-and-center with Notes deep-link (OVR-03)
- [x] Overview as the default launch tab; tabs reordered Home → Expenses → Budgets → Notes (OVR-04)

### Active

<!-- Current scope. Building toward these. -->

**Expense tracker**

- [ ] Ingest expenses automatically from bank email alerts (Gmail) — zero-touch for accounts/cards with email alerts enabled
- [ ] Predefined category list (Groceries, Fuel, Dining, etc.) plus user-created custom tags
- [ ] Per-category monthly budgets with progress visualization
- [ ] Month view of expenses grouped by category/tag
- [ ] Future-proof schema: multi-tag-per-expense, multi-account, multi-currency-ready (single currency in v1)

**Note keeper**

- [ ] Notes with title + free-form text body
- [ ] Optional checklist items embedded inside any note
- [ ] List of all notes with most-recent-first ordering

**Foundational**

- [ ] Face ID required to open the app (toggle in settings)

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
- **Investments, net worth, account-balance tracking** — This is an expense tracker, not personal-finance suite. Out of charter.
- **Web or macOS clients** — iOS-only is a deliberate constraint to keep scope small.

## Context

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
| iOS-only, no cross-platform | Both users on iPhone; goals include watchOS widgets which RN can't deliver | — Pending |
| Swift + SwiftUI (not React Native) | iOS-only removes RN's main benefit; doubles as Swift learning vehicle | — Pending |
| CloudKit for sync (when sync arrives) | Free, native, fits 2-user shared-data model, no backend to host | — Pending |
| Gmail-based email ingestion (not SMS) | iOS blocks SMS access; email is the only legitimate zero-touch path on iOS | — Pending |
| Single-user v1 on Reo's phone | Free Apple Developer account can't do reliable CloudKit sharing across Apple IDs | — Pending |
| Defer $99/yr Apple Developer cost | "Prove before paying" — validate the app is used daily before committing the only recurring spend | — Pending |
| Notes = text body + optional checklists (single model) | Maximum flexibility for grocery / recipes / brainstorms without two separate entities | — Pending |
| Predefined categories + custom tags, single tag default, schema supports multiple | Sane defaults reduce setup friction; multi-tag schema is future-proof | — Pending |
| Face ID required to open app | Financial data; toggleable in settings for paranoia override | — Pending |
| INR single-currency v1, schema multi-currency-ready | Simplifies v1 UI; schema absorbs future travel/forex without migration | — Pending |
| TDD as default development style | User preference; aligns with shipping-confidence in a learning-vehicle project | — Pending |

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
*Last updated: 2026-06-01 — Phase 4 (Overview & Charts) complete*
