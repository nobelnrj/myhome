# Feature Research

**Domain:** Personal household ops iOS app — automated expense tracker (Gmail-ingested) + shared note keeper, two-person Indian household
**Researched:** 2026-05-28
**Confidence:** MEDIUM-HIGH (based on training-data knowledge of iOS finance apps, Indian bank email formats, and iOS 17/18 APIs; web validation was not available at research time)

---

## Scoping Principle

This is a 2-person household tool, not a market product. Every feature is judged against one question: **"would this make Reo + wife reach for the app instead of Apple Notes + a spreadsheet on day 30?"** Anything that doesn't pass that bar — no matter how standard in YNAB/Mint/Walnut — is an anti-feature here.

PROJECT.md already excludes: Android, SMS reading, cross-Apple-ID sharing in v1, OCR, recurring bills, investments, multi-currency UI, web/macOS, multi-household, watchOS, widgets-as-MVP. This document does not re-litigate any of those — it categorizes the remaining surface area.

---

## Feature Landscape — Expense Tracker

### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Gmail OAuth + background poll for bank emails | Core value prop — "I never have to log a transaction" | HIGH | iOS BackgroundTasks framework; tokens in Keychain; per-bank parser templates. The ONE feature that decides app survival. |
| Per-bank email parsers (HDFC, ICICI, SBI, Axis, Kotak at minimum) | Each bank has its own format; one regex doesn't fit all | HIGH | Templated extractors with confidence score. Low-confidence → review inbox. |
| Manual expense entry (amount, date, category, note) | SMS-only banks, cash, parser failures all need a fallback | LOW | Must be 4-tap-max: open → amount keypad → category → save. |
| Review/inbox for low-confidence parses | Auto-ingestion is never 100% — user must confirm ambiguous ones | MEDIUM | One-tap accept; tap-to-edit fields; swipe-to-discard. Drives parser improvements over time. |
| Predefined category list at first launch | Empty-category onboarding is friction; Indian users have predictable categories | LOW | Ship with: Groceries, Dining, Fuel, Utilities, Rent, Transport, Shopping, Health, Entertainment, UPI Transfer, ATM, Misc. |
| Custom tags (single tag default, multi-tag schema) | Categories alone don't capture "Trip to Goa" or "Diwali shopping" | LOW (schema)<br>MEDIUM (UI for multi-tag) | Schema as future-proof per PROJECT.md decisions. UI starts single-tag. |
| Per-category monthly budget | Stated requirement; without it, expenses are just a log not a tool | MEDIUM | Default month = calendar month. Resets on 1st. |
| Budget progress visualization (per-category bar) | The "are we OK this month?" glance | LOW | Bar + percentage + ₹ remaining. Color shift at 80% / 100%. |
| Month view grouped by category | The primary "how did we do this month?" surface | MEDIUM | Sectioned list. Tap category → drilldown to transactions. |
| Edit / delete an expense | Auto-ingested transactions are sometimes wrong (refunds, duplicates, wife's card) | LOW | Hard delete in v1 (no audit trail needed — 2 users, mutual trust). |
| Duplicate detection on ingestion | Same transaction can arrive via email twice (alert + statement); also bank sometimes resends | MEDIUM | Dedup key: amount + merchant-substring + date within ±1 day. Mark suspected duplicates in inbox, don't auto-merge. |
| ₹ display with Indian comma grouping (1,00,000 not 100,000) | Wrong formatting screams "not built for India" — instant trust kill | LOW | `NumberFormatter` with `Locale(identifier: "en_IN")`. Test against ₹1, ₹999, ₹1,000, ₹1,00,000, ₹1,00,00,000. |
| Face ID app lock (toggle in settings) | Financial data; PROJECT.md mandates | LOW | `LocalAuthentication` framework. Lock on background, unlock on foreground (configurable grace period optional). |
| Empty state on first launch | A blank app screams "broken" — needs to teach the user what to do | LOW | Hero card explaining email connect + sample entries; "Connect Gmail" CTA. |
| Pull-to-refresh on transaction list | iOS convention for "go check now" | LOW | Triggers manual Gmail poll independent of background schedule. |

### Differentiators (Competitive Advantage vs Apple Notes + Spreadsheet)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Zero-touch ingestion with named-merchant cleanup | Walnut/CRED have it on Android via SMS — being the first to do this *reliably on iPhone for Indian banks* is the entire reason this app exists | HIGH | Per-bank parser + merchant normalizer ("AMAZON IN BLR" → "Amazon", "ZOMATO ONL BANGAL" → "Zomato"). Maintained as a small lookup table. |
| Tag/category suggestion from merchant history | Once you tag "Zomato → Dining" twice, the third one is pre-suggested | MEDIUM | Plain lookup table (merchant → most-frequent category) seeded from prior user actions. No ML needed. Huge daily-use lever. |
| "Quick add" widget on Lock Screen / Home Screen | One-tap to open the app pre-filled to manual entry (for cash expenses while paying the auto-rickshaw) | MEDIUM | iOS 17+ interactive widget. **NOTE: PROJECT.md lists widgets as post-v1.** Recommend revisiting this AFTER ingestion is solid — it's a high-leverage post-v1 win for daily use. |
| Siri / App Intents shortcut: "Hey Siri, add ₹500 cash expense" | Cash + on-the-go entry without unlocking | MEDIUM | iOS 17 `AppIntent`. Pairs with widget. Same post-v1 timing as widget. |
| Spotlight search of transactions by merchant/note | Search "swiggy" globally on iPhone → app surfaces matches | MEDIUM | `CoreSpotlight` indexing on transaction insert. Low effort given SwiftData; high "wow this is well-built" payoff. |
| Inbox-driven parser learning | When user corrects a parsed merchant or category in the review inbox, save that mapping forever | MEDIUM | Persistent merchant-rename and merchant→category maps. Compounds: review inbox shrinks over weeks. |
| Single shared truth in the home overview | Both spouses see the same monthly bar — no "where did the money go?" arguments | LOW (post-CloudKit) | Real value lands when CloudKit sharing arrives. In v1, single-user already wins over spreadsheet because it's auto-updated. |
| Comparison vs prior month at a glance | "This month vs last month, ±X%" in the overview | LOW | Trivial once month aggregates exist. Big perceived intelligence for tiny cost. |
| Charts that respect Indian comma grouping AND short month labels | Generic chart libraries get this wrong | LOW | Swift Charts (iOS 16+) with custom AxisValueFormatter. |
| Haptic feedback on save / budget threshold cross | Modern iOS apps feel "alive" with subtle haptics; finance apps mostly don't bother | LOW | `UIImpactFeedbackGenerator`. Cheap polish, large delight. |
| Dynamic Type + Dark Mode from day one | Wife may prefer larger text or dark; default-good accessibility separates "real iOS app" from "RN port" | LOW | SwiftUI gives this nearly free if you don't fight it. Test at XXL. |

### Anti-Features (Deliberately Avoid)

| Feature | Why Requested | Why Problematic for 2-User Household | Alternative |
|---------|---------------|--------------------------------------|-------------|
| Split transactions (one expense across multiple categories) | YNAB / Splitwise standard | Adds UI complexity (sub-rows, residual rounding, edit cascades) for a case that occurs <5% of the time in a 2-person household | Tag the whole expense with the dominant category; add a note for context. Or split into two manual entries. |
| Recurring transaction detection / "subscription tracker" | Mint / Rocket Money flagship | Schema, UI, notifications all balloon. 2 users can recall their own Netflix sub. | Defer until manual data shows >10 repeat merchants/month. PROJECT.md already defers this. |
| Multiple "accounts" UI with balances | Mint / Monarch standard | We are NOT tracking balances (PROJECT.md says so) — only outflows from email alerts. Per-card view is a "nice-to-have" that bloats schema. | Capture source-card as a tag on each transaction. If "spend by card" is wanted later, it's a filter, not a schema rewrite. |
| Reconciliation / "mark as cleared" workflow | Banking-app standard | We're not balancing a checkbook. Email alerts ARE the source of truth; there's nothing to reconcile against. | Skip entirely. |
| Dispute / refund linking | Bank app feature | 2 users will remember disputes themselves; refunds will arrive as new email alerts (negative or "credit" alerts) and can be entered as negative expenses or simply tagged "Refund". | Allow negative-amount entries; nothing more. |
| Rules engine ("IF merchant contains X THEN category = Y, tag = Z, budget = W") | Power-user finance apps | Editor UI is huge; configuration debt is huge; 2 users have <50 merchants total | Just remember the last category per merchant (suggestion lookup table). 90% of the value at 5% of the cost. |
| Envelope / zero-based budgeting modes | YNAB philosophy | Wrong mental model for a household that wants observability, not behavioral coaching | Single mode: per-category monthly cap with warnings. Don't expose a "method picker". |
| Onboarding wizard with category customization upfront | Most apps do this | Pre-launch category creation is decision fatigue when user hasn't seen a single transaction yet | Ship sensible defaults; let user rename/add categories later from a settings screen. |
| Notification for *every* parsed transaction | "Real-time feel" | Each bank email already pushes a notification — duplicating it is noise that gets the app silenced inside a week | Only notify on (a) budget threshold crossings, (b) low-confidence parses awaiting review, and only if user opts in. |
| Weekly/monthly email/PDF reports | "Engagement" features | Both users open the app daily; reports are for absent stakeholders | Skip. Charts inside the app are the report. |
| Goal tracking ("save ₹50,000 for vacation") | Mint / Monarch staple | Out of charter — this is a *spend* tracker, not a *savings* planner. | Track savings goals in a Note with a checklist. The Note keeper already covers it informally. |
| Multi-user spending attribution ("this was Reo's spend vs wife's spend") | Couples-finance feature | Adds a "payer" field, filters, charts — all to surface info the household doesn't actually argue about | Each transaction's source-card-tag already implies the spender. Don't formalize it. |
| Cryptocurrency, stocks, investment, net worth | Common upsell in finance apps | Explicitly out of charter per PROJECT.md | Hard no. |
| Currency conversion UI | Travel feature | PROJECT.md says schema-ready, UI-not. Showing a USD/AED → INR converter is creep. | Schema field exists; UI shows INR always. |
| Receipt photo attachment | "Just in case" feature | Storage, thumbnail UI, full-screen viewer, share-sheet handling — all for a use case that hasn't been measured | Defer. PROJECT.md already defers. A note can hold a photo if absolutely needed in v1. |
| Voice memo entry | iOS-native flex | Requires speech-to-text, parsing of "five hundred rupees on groceries today", error handling. High effort, low daily-use payoff for a 2-person household. | Siri + App Intent (post-v1) gives 90% of the value with Apple doing the STT. |
| Gamification / streaks / achievements | Mainstream consumer apps | Patronizing for a household tool. Wife will hate it. | None. |
| In-app ads / paywalls / Pro tier | SaaS norm | This is not a SaaS. | None. |
| Telemetry / analytics SDK | Industry default | PROJECT.md forbids; financial data privacy + 2-user feedback loop is direct conversation | None. |

---

## Feature Landscape — Note Keeper

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Note = title + free-form body | PROJECT.md requirement | LOW | Plain text body is enough for v1. |
| Optional checklist items inside any note | PROJECT.md requirement; the "grocery list" use case | MEDIUM | Inline checkable rows mixed with text. Tap to toggle, drag to reorder. |
| Recent-first list of all notes | PROJECT.md requirement | LOW | Sort by `updatedAt` desc. |
| Create / edit / delete a note | Basic CRUD | LOW | Swipe-to-delete with confirmation. |
| Auto-save on every keystroke (or on background) | Apple Notes set the expectation; explicit Save buttons feel dated | LOW | Debounce 500ms; persist via SwiftData. |
| Search across note title + body | A 50-note pile is unmanageable without search | LOW | `.searchable` modifier — built into SwiftUI lists. |
| Pin a note | PROJECT.md home overview surfaces pinned notes | LOW | Boolean flag; pinned section at top of list. |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Checklist progress shown in note list ("3 of 8") | At-a-glance "what's left on the grocery list?" without opening | LOW | Compute on the fly from checklist items. |
| "Convert checked items to expense" action | Grocery checklist → multi-line expense with one tap (post-v1, but a uniquely-household feature) | MEDIUM | Bridges the two features in a way no off-the-shelf app does. Consider for v1.x. |
| Lock Screen widget for a specific pinned note | Wife adds "milk" while at the store without opening anything | MEDIUM | iOS 17+ interactive widget. Post-v1 per PROJECT.md, but flag as high-leverage. |
| Share Sheet receive (text/URL from Safari → new note) | Capture recipes, addresses, links without typing | LOW | `Share Extension` target. Modest setup cost, high "this is my real notes app" payoff. |
| Spotlight search of notes by title + body | Find notes from iPhone home screen | LOW | `CoreSpotlight`. Same plumbing as expense search. |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Rich text / markdown formatting (bold, headings, lists) | Apple Notes / Bear standard | Editor toolbar, render layer, paste handling, edge-case bugs. 2 users writing grocery lists don't need it. | Plain text body. If it ever matters, add later. |
| Folders / nested folders | Notes app standard | UI tree, drag-and-drop, "where did I put it?" cognitive load — for a 2-user note pile that will plateau at <100 notes | Skip. Search + pin handles discovery. Tags are also overkill at this volume. |
| Tags on notes (separate from expense tags) | Power-user note app convention | Two tag systems (expense tags + note tags) doubles vocabulary maintenance for no benefit | Skip. Use the note title to convey type ("Grocery — May 28"). |
| Image / audio attachments in notes | Apple Notes standard | File storage, thumbnails, sharing pipeline. Apple Notes already exists for this. | Skip. Differentiation isn't here. |
| Note versioning / history | "Undo when wife edits" anxiety | Storage cost; UI for version diffing | Skip. Trust + verbal coordination handles 2-user editing. |
| Collaborative real-time cursors | Google Docs feature | Hard with CloudKit; not needed for grocery lists | Skip permanently. Last-writer-wins is fine. |
| Drawing / sketch / handwriting | iPad / Apple Pencil feature | Both users use iPhone, not iPad | Skip. |
| Note templates | Productivity-app feature | YAGNI at 2 users | Skip. Duplicate-a-note is enough. |
| Encryption per-note | "Lock my journal" feature | Face ID on the whole app is already the security boundary | Skip; the app lock IS the protection. |
| Reminders attached to notes | Apple Reminders crossover | Apple Reminders exists; don't compete | Skip; if a checklist item is time-sensitive, the user can use Reminders. |

---

## Feature Landscape — Home Overview Screen

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Current-month spend vs budget bar | PROJECT.md requirement | LOW | Single bar, summed across all categories' budgets. ₹X of ₹Y spent. |
| Top 3 categories this month | PROJECT.md requirement | LOW | Sorted desc by amount; show category, amount, % of total. |
| Pinned notes / most recent checklist | PROJECT.md requirement | LOW | Card showing first 1–3 pinned notes, tappable. |
| "Add expense" + "Add note" quick actions | Without these, the overview is a dead-end screen | LOW | Floating action button or top-right `+` menu. |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Today's spend (running total) | "Did we already overspend today?" — the most useful daily glance | LOW | Sum of today's transactions on the overview card. |
| Inbox count badge ("2 transactions to review") | Surfaces pending action without going hunting | LOW | Small pill on the overview that taps into the review inbox. |
| Vs-last-month delta on the spend bar | Context that "₹38,000 spent" needs ("up 12% from April") | LOW | Single stored aggregate per closed month. |
| "Streak" of days with at-least-one-expense logged | Reassures the user that ingestion is working — silence is scary in a finance app | LOW | Implicit health indicator without being gamified. |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Customizable dashboard cards | Power-app feature | Drag-handles, hidden states, "where's my widget?" support burden | Fixed layout. If it's not useful, redesign — don't make the user redesign. |
| Multiple "views" / tabbed dashboards | Mint-style | YAGNI; one well-designed overview > three half-designed ones | One screen. |
| News feed / spending tips / personalized advice | Engagement features | Patronizing; nobody asked | None. |

---

## Cross-Cutting Features

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Dark mode | iOS user expectation since 2019 | LOW | Free with SwiftUI semantic colors. Don't hard-code hex. |
| Dynamic Type support | Accessibility expectation; wife may want larger text | LOW | Use `.font(.body)` not `.system(size: 14)`. Test at XXL. |
| Locale `en_IN` formatting throughout | Trust signal | LOW | Centralize a `Formatters` namespace; use Locale `en_IN` for currency and `dd MMM yyyy` for dates. |
| Empty states with guidance | "No expenses yet" should teach, not just show a void | LOW | One illustration + one CTA per empty screen. |
| Error states for Gmail auth / network | OAuth tokens expire; network drops happen | MEDIUM | Inline banner in the inbox/overview when Gmail sync is broken. Don't fail silently. |
| Background-fetch failure recovery | iOS may throttle BackgroundTasks | MEDIUM | Manual "sync now" + last-synced timestamp visible. |
| Settings screen | Toggle Face ID, manage categories, manage budgets, sign out of Gmail | LOW | Standard SwiftUI `Form`. |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Haptic feedback (save success, budget cross, swipe) | Polish; signals quality | LOW | `UIImpactFeedbackGenerator`. Cheap. |
| First-run experience tuned to "connect Gmail, see your first parsed transaction within 60 seconds" | Sets the bar that the app actually works | MEDIUM | The most important UX moment — the wow that earns daily use. Worth designing carefully. |
| Consistent ₹ formatting (no rogue NSDecimalNumber rounding bugs) | Money apps must not be wrong about money | LOW (with discipline) | Use `Decimal` everywhere; never `Double`. One arithmetic helper module. |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Light/dark/auto theme picker | "User preference" | iOS already has system-wide dark mode toggle — don't duplicate | Honor the system setting. |
| Custom color theme picker | Personalization | Maintenance burden; sets wrong expectation for app polish | Skip. One well-chosen palette. |
| Onboarding tour with 5+ screens | "Educational" | Users skip it; valuable info gets buried | Inline empty-state guidance only. |

---

## India-Specific Features

This is where generic templates fail and the app earns trust.

### Table Stakes (India)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Indian numbering: ₹1,00,000 (lakh) not ₹100,000 | Wrong format = "this app isn't built for me" | LOW | `NumberFormatter` with `Locale(identifier: "en_IN")` handles it. Verify ₹ symbol prefix (not suffix). |
| Per-bank email templates: HDFC, ICICI, SBI, Axis, Kotak | These 5 cover ~80% of urban Indian households' cards | HIGH | See parsing notes below. Each has 2–3 alert subtypes (debit card / credit card / UPI / NEFT). |
| UPI transaction parsing | UPI is now the dominant transaction type in India (>14B txns/month nationally as of late 2025) | HIGH | UPI alerts have format like "INR 250.00 debited from A/c XX1234 to VPA merchant@upi on 28-May-26". Extract VPA as merchant. |
| Recognize "credit" / "refund" / "reversal" emails | Refunds arrive as the same format with opposite verb; treating them as expenses doubles the spend | MEDIUM | Parser must flag direction. Store as negative or with a `direction` enum. |
| Date parsing: `DD-MMM-YY`, `DD/MM/YYYY`, `DD MMM YYYY` | Indian banks use varied formats; all DD-first | LOW | Try multiple DateFormatters with `Locale(identifier: "en_IN")` and `posix` for parsing. |
| Indian category defaults | Generic lists miss UPI, ATM, Recharge, Maid, Auto/Cab | LOW | Defaults: Groceries, Dining, Fuel, Utilities, Rent, Auto/Cab, Shopping (Amazon/Flipkart), Health/Pharmacy, Entertainment, Recharge/DTH, Maid/Help, UPI to Person, ATM, Misc. |
| Merchant normalization for Indian aggregators | Raw bank text is "AMAZON IN BLR 7AB", "ZOMATO ONL BANGAL", "SWIGGY BANGALORE" — useless without cleanup | MEDIUM | Lookup table of ~30 common merchants to clean names. |

### Differentiators (India)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Separate "UPI to person" vs "UPI to merchant" detection | Sending ₹500 to friend ≠ spending ₹500 at restaurant; conflating breaks budgets | MEDIUM | Heuristic: VPA contains `@paytm`, `@ybl`, `@oksbi`, `@ibl` → likely person; VPA contains brand name or merchant category code → merchant. Imperfect; let user correct in review inbox. |
| Auto-tag spends from common Indian merchants | "Swiggy → Dining", "BPCL → Fuel", "Tata Power → Utilities" out of the box | LOW (seed table) | Bundled seed data; user corrections compound on top. |
| Festive-month awareness (optional) | Diwali / wedding-season spike is real; surfacing "October usually higher" prevents budget panic | LOW | Just an annotation on the comparison-vs-prior-month indicator. Don't over-engineer. |
| Credit card statement-cycle awareness | Indian credit cards have non-calendar billing cycles (e.g. 16th–15th); calendar-month budgets misalign | MEDIUM | Per-card "billing cycle start day" setting; optional alternate view. Probably v1.x, not v1. |

### Anti-Features (India)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Multi-currency UI (USD, AED, etc. for travel) | International travel common from India | PROJECT.md says no for v1; schema-ready is enough | Note travel expenses with a tag; mental conversion is fine for 1–2 trips/year. |
| Investment / mutual-fund / SIP tracking | Indian users often want this in one place | Out of charter; complex; KFintech/CAMS scraping is a separate beast | Skip permanently. |
| Tax-section labeling (80C, 80D, etc.) | Indian-tax appeal | Annual not daily; spreadsheet does this fine once a year | Skip. Tag with "Tax" if needed. |
| Direct UPI app integration ("pay from inside this app") | Convenience | Massive PCI/RBI compliance burden; unrelated to "tracking" | Skip permanently. |

### Indian Bank Email Format — Parsing Notes

Based on standard templates these banks have used for years (no recent indication of major format changes; verify against live samples during the parser-build phase):

- **HDFC Bank**
  - Common subjects: `Update on your HDFC Bank Credit Card`, `Alert : You have done a UPI transaction`, `Debit card transaction alert`
  - Body anchors: `Rs.` or `INR` followed by amount; `at ` or `to VPA ` for merchant; `on DD-MM-YY`; `Info: <merchant code>`
  - Quirks: HTML-only emails; amount may have decimals or not; sometimes both `Rs.` and `INR` appear

- **ICICI Bank**
  - Common subjects: `Transaction alert for your ICICI Bank Credit Card`, `UPI transaction alert`
  - Body anchors: `INR ` amount; `Info: <merchant>`; `at <merchant>`; date in `DD-Mon-YY` format
  - Quirks: Reference numbers (`Ref no XXXXXXXXX`) useful for dedup

- **SBI**
  - Common subjects: `Transaction Alert`, `INB Transaction`
  - Body anchors: `Rs.` amount; `at <merchant>` or `transferred to <name>`; date `DDMonYY` (no separators sometimes)
  - Quirks: Long, verbose body; lots of disclaimer text — anchor extraction must be tight

- **Axis Bank**
  - Common subjects: `Thank you for using your Axis Bank Credit Card`, `UPI alert`
  - Body anchors: `INR ` amount; `at <merchant>`; `on DD-MM-YYYY`
  - Quirks: Cleaner HTML; predictable structure

- **Kotak**
  - Common subjects: `Transaction alert`, `Kotak UPI alert`
  - Body anchors: `Rs.` or `INR `; `at <merchant>` or `to <VPA>`
  - Quirks: Sometimes plain-text only; sometimes both HTML and plain-text

- **Common parsing strategy**
  - Per-bank Sender-domain match (`@hdfcbank.net`, `@icicibank.com`, `@sbi.co.in`, `@axisbank.com`, `@kotak.com`) routes to that bank's parser.
  - Each parser returns `(amount, merchantRaw, dateUTC, last4OfCard?, direction, confidence)`.
  - Confidence < 0.8 → review inbox, don't auto-save.
  - **Empirical truth**: parsers will break when banks tweak templates. Build the inbox flow such that broken parses are a small annoyance (one tap to fix) rather than a silent loss.

---

## Feature Dependencies

```
Gmail OAuth
    └──enables──> Bank email ingestion
                       └──requires──> Per-bank parsers
                       │                  └──requires──> Merchant normalizer
                       │                  └──feeds────> Review inbox
                       │                                     └──improves──> Per-merchant category memory
                       └──requires──> BackgroundTasks scheduling
                       └──requires──> Duplicate detection

Categories (predefined + custom)
    └──required-by──> Per-category budgets
                            └──required-by──> Budget progress bars
                            └──required-by──> Home overview "top 3 categories"
    └──required-by──> Month view grouping
    └──required-by──> Category breakdown chart

Decimal money type
    └──required-by──> All amount arithmetic (sums, budgets, deltas, charts)

INR Indian-locale formatter
    └──required-by──> Every screen that shows money

Transaction model with date
    └──required-by──> Month view
    └──required-by──> Spend-over-time chart
    └──required-by──> Comparison vs prior month
    └──required-by──> "Today's spend" overview tile

Note model (title + body + checklist items)
    └──required-by──> Note list
    └──required-by──> Pinned notes on overview
    └──required-by──> Note search
    └──required-by──> Checklist progress indicator

Face ID lock
    └──depends-on──> nothing (foundational, can ship first)

Spotlight indexing
    └──depends-on──> Transaction model AND Note model
    └──enhances──> Search experience for both

Widgets / App Intents (post-v1)
    └──depends-on──> Transaction model + manual-entry flow being stable
```

### Dependency Notes

- **Per-bank parsers require per-bank email samples** — can't build them without sample emails in hand. The parser-build phase must start with a "collect 50 historical bank emails from each user's Gmail" step.
- **Budgets require categories which require the transaction model** — the natural build order is: schema → manual entry → categories → budgets → overview cards, then layer email ingestion on top.
- **Review inbox sits between parsers and the category-memory feature** — it's the human-in-the-loop that makes the suggestion table good. Build the inbox before optimizing the parser.
- **Charts depend on time-bucketed aggregates** — pre-compute monthly category sums; don't scan the transaction table on every chart render.
- **Spotlight indexing on note + expense should be one shared mechanism** — pulled out into a `SpotlightIndexer` service to avoid duplicate code.
- **CloudKit-readiness is a schema concern, not a feature** — every model has a UUID PK and avoids fan-out FKs from day one (per PROJECT.md). This isn't a feature to plan; it's a discipline.

---

## MVP Definition

### Launch With (v1)

The "this is usable daily within a week" cut.

- [ ] **Face ID app lock** — financial app prerequisite (small, foundational)
- [ ] **Manual expense entry** — works before Gmail, becomes fallback after (small)
- [ ] **Predefined categories + custom add/edit/rename** — required for everything downstream (small)
- [ ] **Per-category monthly budgets** — core requirement (medium)
- [ ] **Month view grouped by category** — primary review surface (medium)
- [ ] **Note: title + body + inline checklist** — full note feature (medium)
- [ ] **Note list, pin, search** — basic note management (small)
- [ ] **Home overview: spend-vs-budget bar, top 3 categories, pinned note card** — required (small once data exists)
- [ ] **₹ Indian-locale formatting everywhere** — non-negotiable trust signal (small with discipline)
- [ ] **Dark mode + Dynamic Type** — modern iOS baseline (small if not fought)
- [ ] **Gmail OAuth + at least 2 bank parsers (HDFC + ICICI; pick whichever covers Reo's daily cards first)** — the core value prop, gated on having sample emails (large)
- [ ] **Review inbox for low-confidence / unknown parses** — required because parsers will be wrong on day one (medium)
- [ ] **Duplicate detection on ingestion** — required to keep auto-ingest trustworthy (medium)
- [ ] **Merchant normalization seed table (~20 common merchants)** — required for "this app is built for India" feel (small)
- [ ] **Spend-by-category + spend-over-time charts** — required per PROJECT.md (medium with Swift Charts)
- [ ] **Settings: Face ID toggle, manage categories/budgets, Gmail sign out, last sync timestamp** — required (small)

### Add After Validation (v1.x)

Triggered when daily use is established.

- [ ] **Additional bank parsers (SBI, Axis, Kotak, + any card Reo/wife use)** — trigger: a transaction landed in inbox and parser was missing (medium each)
- [ ] **Per-merchant category memory (auto-suggest)** — trigger: 20+ manual category corrections logged (medium)
- [ ] **Spotlight indexing for transactions + notes** — trigger: search feels too local; user searches from home screen (medium)
- [ ] **Share Sheet receive for notes** — trigger: user copy-pastes URLs into notes more than 5 times (small)
- [ ] **Comparison vs prior month on overview** — trigger: month-end retrospectives happen (small)
- [ ] **Today's spend tile** — trigger: user asks "what did we spend today?" verbally (small)
- [ ] **Notifications: budget threshold + review-inbox pending** — trigger: user misses budget overages (small)
- [ ] **Haptics polish pass** — trigger: any time before showing it to wife (small)
- [ ] **Merchant rename memory** — trigger: same correction made twice (small)

### Future Consideration (v2+)

Defer until product-market fit is established (post-CloudKit, post-$99/yr decision).

- [ ] **CloudKit sharing with wife's Apple ID** — the v2 trigger event by definition
- [ ] **Home Screen + Lock Screen widgets** (quick-add expense, pinned-note glance) — high-leverage but post-v1 per PROJECT.md
- [ ] **App Intents / Siri shortcut** ("Hey Siri, add ₹500 cash expense") — pairs with widgets
- [ ] **Watch app** — explicitly post-v1
- [ ] **"Convert checked items to expense"** bridge action — household-unique feature; needs both expense and note features mature
- [ ] **Credit-card billing-cycle aware view** — only if budgets misaligning to calendar months becomes a real complaint
- [ ] **Recurring / scheduled expenses** — only if manual data shows >10 repeat merchants
- [ ] **Receipt OCR** — only if manual-entry friction data justifies it
- [ ] **Chores / calendar / grocery as separate household features** — proves the "schema absorbs new features" claim from PROJECT.md

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Gmail OAuth + bank ingestion (HDFC + ICICI) | HIGH | HIGH | P1 |
| Manual expense entry | HIGH | LOW | P1 |
| Review inbox for low-confidence parses | HIGH | MEDIUM | P1 |
| Duplicate detection | HIGH | MEDIUM | P1 |
| Categories (predefined + custom) | HIGH | LOW | P1 |
| Per-category monthly budgets | HIGH | MEDIUM | P1 |
| Month view + budget bars | HIGH | MEDIUM | P1 |
| Notes (title/body/checklist) | HIGH | MEDIUM | P1 |
| Note list / pin / search | HIGH | LOW | P1 |
| Home overview screen | HIGH | LOW (given data) | P1 |
| INR Indian-locale formatting | HIGH | LOW | P1 |
| Face ID app lock | HIGH | LOW | P1 |
| Dark mode + Dynamic Type | MEDIUM | LOW | P1 |
| Merchant normalization seed table | HIGH | LOW | P1 |
| Spend-by-category + spend-over-time charts | MEDIUM | MEDIUM | P1 |
| Additional bank parsers (SBI/Axis/Kotak) | HIGH (when needed) | MEDIUM each | P2 |
| Per-merchant category memory | HIGH | MEDIUM | P2 |
| Spotlight indexing | MEDIUM | MEDIUM | P2 |
| Today's spend overview tile | MEDIUM | LOW | P2 |
| Vs-prior-month comparison | MEDIUM | LOW | P2 |
| Share Sheet receive for notes | MEDIUM | LOW | P2 |
| Notifications (budget threshold, inbox pending) | MEDIUM | LOW | P2 |
| Haptics polish | LOW | LOW | P2 |
| CloudKit sharing | HIGH (when v2) | HIGH | P3 |
| Widgets + App Intents | HIGH (when v2) | MEDIUM | P3 |
| Checklist → expense bridge | MEDIUM | MEDIUM | P3 |
| Credit-card billing-cycle view | LOW | MEDIUM | P3 |
| Receipt OCR | LOW (deferred) | HIGH | P3 |
| Recurring expense detection | LOW (deferred) | HIGH | P3 |

**Priority key:**
- P1: Must have for v1 launch — the daily-use bar
- P2: Add after v1.x once daily-use proves which P2s matter most
- P3: Future / CloudKit / post-$99-decision

---

## Competitor Feature Analysis

| Feature | Walnut (defunct on iOS, was Android SMS) | CRED / Money Manager India | Apple Notes + Spreadsheet (the actual competition) | Our Approach |
|---------|------------------------------------------|----------------------------|---------------------------------------------------|--------------|
| Auto-ingestion | SMS (Android only) | Manual + statement upload | None | Gmail-based, iOS-native, zero-touch |
| Categories | Auto-tagged from SMS heuristics | Predefined + custom | Manual in spreadsheet columns | Predefined + custom + per-merchant memory (P2) |
| Budgets | Per-category | Per-category | Manual formulas | Per-category monthly, with progress bar |
| Notes | None | None | Yes (separate app) | Integrated — same home overview |
| Sharing | None | None | iCloud-shared notes work, spreadsheet via shared file | CloudKit shared in v2 |
| ₹ formatting | Yes | Yes | Yes (locale) | Yes (locale `en_IN`) |
| iOS native polish (widgets, Spotlight, haptics, Dynamic Type) | N/A | Mediocre | Excellent (Apple) | Match Apple-Notes-tier polish — the actual bar |
| Privacy | Sent SMS to servers (controversial) | Server-stored | On-device | On-device (v1), CloudKit private (v2) — never leaves Apple ecosystem |
| Cost | Free + ads | Free + cross-sells loans | Free | Free (and never any of that) |

**The real bar isn't Walnut. It's Apple Notes + a Google Sheet.** Anything this app does worse than that combo will get the app deleted within a month. The two things this combo cannot do are (a) automatically ingest bank transactions and (b) show "₹X of ₹Y this month" without manual upkeep. Those are the differentiators worth fighting for; everything else is "be at least as good as Apple Notes."

---

## Sources

- **PROJECT.md** — `/Users/reo/My Projects/my-home/.planning/PROJECT.md` (scope, out-of-scope, key decisions)
- **iOS API knowledge** (training data): SwiftUI iOS 17+, SwiftData, BackgroundTasks, LocalAuthentication, Swift Charts, CoreSpotlight, App Intents (iOS 16+), interactive widgets (iOS 17+), Live Activities (iOS 16.1+ — not used in v1)
- **Indian bank email formats** (training data, plus Reo's own inbox as the empirical source during the parser-build phase) — HDFC, ICICI, SBI, Axis, Kotak templates
- **UPI ecosystem context** (training data) — NPCI UPI alerts, VPA conventions (`@oksbi`, `@ybl`, `@paytm`, `@ibl`)
- **Indian numbering** — `Locale(identifier: "en_IN")` for ₹1,00,000 (lakh) format
- **Competitor reference** — Walnut (Android-only, iOS unsupported), CRED Money Manager, Money Manager / Money Lover (App Store category leaders in India)
- **Web search was not available at research time** — Reo should validate (a) iOS 18+ App Intents and widget guidance and (b) live samples of each bank's current email template during the parser-build phase, as templates do change.

---

## Open Questions for the Roadmap Phase

These are deliberately unresolved here — the roadmapper or discuss-phase should decide:

1. **Which bank parsers ship in v1?** Probably whichever 2 cover Reo's primary cards. Wife's cards can ship in v1.1.
2. **Manual entry first or email ingestion first?** Both are needed; manual is the safer first phase because it validates schema + UI before staking the project on parser reliability.
3. **Default starting month for budgets** — calendar 1st-of-month, or align to credit-card cycle? Default to calendar; revisit if it bites.
4. **How long to keep historical Gmail polling history** — backfill 30 days on first connect? 90? Trade-off between "instant value" and parser failure visibility.
5. **Where exactly to draw the "review confidence threshold"** — calibration question that needs real data; ship at 0.8 and adjust.
6. **Notification opt-in flow timing** — at first launch (annoying), at first budget threshold cross (smart), or never until user asks (most respectful)?

---
*Feature research for: Personal household-ops iOS app (expense tracker + note keeper) for a two-person Indian household*
*Researched: 2026-05-28*
