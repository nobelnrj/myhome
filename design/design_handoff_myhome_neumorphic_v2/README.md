# Handoff: MyHome — Neumorphic Redesign v2 (Dark)

## Overview
A five-screen redesign of the MyHome personal-finance iOS app in a **dark neumorphic (soft-UI) style**: Overview hero, spending breakdown donut, Budgets, Activity feed, and Analytics. This v2 iteration modernizes the charts (glowing rounded-cap arcs, recessed pill bar charts, glowing trend line) and CTAs (extruded pill buttons, one gradient-yellow primary), inspired by soft-UI references while staying on the existing dark token system.

## About the Design Files
The file in this bundle (`MyHome Redesign — Neumorphic v2.html`) is a **design reference created in HTML** — a static mock showing intended look, not production code. The task is to **recreate these screens in the target codebase's existing environment** (SwiftUI, React Native, etc.) using its established patterns — or, if no app exists yet, pick the most appropriate mobile framework and implement there. Do not ship the HTML.

## Fidelity
**High-fidelity.** Colors, typography, spacing, shadows, and chart geometry are final. Recreate pixel-perfectly using the codebase's component conventions.

## Canvas
Each screen is a 402 px-wide mobile frame (iPhone-class), dark background, 16 px horizontal padding, 40 px frame radius. All numerals use tabular figures (`font-variant-numeric: tabular-nums`). Font: SF Pro / system.

## Design Tokens

### Surfaces
- `--canvas: #1C1C23` — screen background
- `--raised: #1F1F27` — standard card
- `--raised-strong: #22222C` — hero/featured card, raised buttons
- `--elevated: #262630` — segmented-control thumb, chart value pill
- `--recess: #15151B` — inset wells/tracks
- `--recess-alt: #16161C` — chart plot inset
- `--hairline: rgba(255,255,255,0.05)` — row dividers

### Text
- `--label1: #ECEDF4` (primary)
- `--label2: rgba(220,223,238,0.56)` (secondary)
- `--label3: rgba(220,223,238,0.32)` (tertiary)

### Accent & semantic
- `--accent: #FFD60A` (yellow) · `--accent-soft: rgba(255,214,10,0.16)`
- `--pos: #34E29B` (income/positive) · `--neg: #FF6B6B` (spend/negative)
- `--violet: #A78BFA` (AI insight)

### Category colors
- Rent `#818CF8` · Health `#A78BFA` · Dining `#FB923C` · Groceries `#2DD4BF` · Fuel `#F472B6` · Utilities `#7DD3FC` · ATM `#2DD4BF` · Other `#94A3B8`

### Neumorphic shadow recipes (the core of the style)
- **Card** (`--card-shadow`): `-6px -6px 14px rgba(255,255,255,0.035), 7px 7px 18px rgba(0,0,0,0.55)`
- **Float / featured** (`--float-shadow`): `-9px -9px 22px rgba(255,255,255,0.04), 11px 11px 28px rgba(0,0,0,0.62)`
- **Rim light** (`--rim`, added to every card): `inset 1px 1px 1px rgba(255,255,255,0.045), inset -1px -1px 1px rgba(0,0,0,0.30)`
- **Well / inset** (`--well`): `inset 2px 2px 5px rgba(0,0,0,0.5), inset -2px -2px 5px rgba(255,255,255,0.035)`
- Cards: radius 26 px, `background: --raised` (or `--raised-strong` for featured) + card/float shadow + rim.
- Tracks/wells: `background: --recess`, pill radius, well shadow.

### Type scale
- Screen title: 34/700, letter-spacing 0.37px
- Section header: 22/700, ls −0.4px
- Hero amount: 52/600, ls −1.5px
- Stat amount: 24/600 · Card amounts: 15–32/600
- Eyebrow: 12/600, ls 1.2px, uppercase, `--label2`
- Body/rows: 15/500 primary, 12.5–13 tertiary
- Minimum text size: 11px (chart axis labels only)

## Screens

### 1 · Overview hero
- Eyebrow month ("JULY 2026"), 34px "Overview" title.
- Featured card (`--raised-strong`, float shadow): "NET CASH FLOW" eyebrow + red "Negative" pill (`rgba(255,107,107,0.14)` bg, `--neg` text); 52px net amount (−₹600, `--neg`); sub-caption.
- 2-up inset stat tiles (radius 18, well shadow): Income ₹14,000 (`--pos`) and Spent ₹14,600 (`--neg`), each with 7px color dot + uppercase label.
- Budget progress: 12px recessed track, fill = yellow→green gradient (`#FFD60A → #34E29B`), embossed fill (see Charts). Meta row: "33% of ₹44,000 budget used" / "₹29,400 left".
- **CTA row** (flex, gap 14, margin-top 18):
  - Primary: "＋ Add expense" — pill, `linear-gradient(150deg,#FFE04A,#F2C500)`, text `#231B00` 15/600, padding 14px 0, flex 1. Shadow: float + `inset 1.5px 1.5px 1.5px rgba(255,255,255,0.45)` + `0 8px 22px rgba(255,214,10,0.22)` (soft yellow halo).
  - Secondary: "Details" — pill, `--raised-strong` bg, `--accent` text, float + rim shadows.

### 2 · Where it's going (donut)
- Card contains a **circular well** (236px, `--recess` bg, well shadow) holding the donut SVG; a **raised center puck** (132px circle, `--raised` bg, card+rim shadow) shows eyebrow "Spent" + ₹14,600 (28/600).
- Donut: r 88, stroke-width 22, **rounded caps**, 4 segments with ~4px gaps (cap allowance baked into dash arrays). Each segment has a soft colored glow: `filter: drop-shadow(0 3px 9px <color @ 0.45 alpha>)`.
  - Rent 50% ₹7,300 · Health 27% ₹3,900 · Dining 12% ₹1,800 · Other 11% ₹1,600 (groceries/ATM/fuel folded in so no segment is too small for rounded caps)
- Legend below: rows with 7px dot, name, % (tertiary), amount (semibold), hairline dividers.

### 3 · Budgets
- Title row: 34px "Budgets" + raised "Manage" pill button (`--raised-strong`, accent text, 12px 22px padding). Month stepper "‹ July 2026 ›" with accent chevrons.
- Summary card: circular well (136px) + gradient ring (r 54, stroke 13, rounded cap, `#FFD60A → #34E29B`, 33% arc, glow `drop-shadow(0 4px 12px rgba(255,214,10,0.35))`) over a faint track (`rgba(0,0,0,0.18)`); raised puck (80px) with "33% / used". Right side: "LEFT TO SPEND" eyebrow, ₹29,400 (32/600), "₹14.6K of ₹44K".
- Category rows: card with 38px colored icon tile (radius 11, category color, dark stroke icon), name 16/600, "₹X left" caption (red "₹900 over" when over budget), right-aligned spent/of amounts. Below each row a 10px recessed progress bar with embossed category-color fill (Health over-budget bar uses `--neg` at 100%). Rows without budget show "No budget set".
- Screen data: Dining ₹5,100/₹8,000 (64%) · Rent ₹7,300/₹14,000 (52%) · Health ₹3,900/₹3,000 (over) · Groceries ₹900, no budget.

### 4 · Activity
- Title row: 34px "Activity" + raised circular 44px "+" button (accent glyph, float+rim shadow plus `0 6px 16px rgba(255,214,10,0.18)` halo).
- Transactions grouped by day: day header (uppercase 13/600 `--label2` left, signed day total right), then a card of rows.
- Row: 36px category icon tile, merchant 15/500, "Category · time" 12.5 tertiary, right amount 15/600. Income rows: tile `rgba(52,226,155,0.16)` with `--pos` arrow icon, amount `+₹14,000` in `--pos`.
- Data: Today (Swiggy ₹340, Zepto ₹620, HP Petrol ₹280), Yesterday (Rent ₹7,300, Apollo ₹3,900, Third Wave ₹460, Zomato ₹540, Blinkit ₹280), Mon 6 Jul (Salary +₹14,000), Sat 4 Jul (ATM ₹400, BESCOM ₹780).

### 5 · Analytics
- Back chip + "Spending overview / Analytics" header.
- Segmented control: recessed pill (well shadow, 4px padding); active segment = raised `--elevated` thumb with accent text.
- KPI: "TOTAL SPEND" eyebrow, ₹14,600 (40/600), red delta chip "▲ 8%", "vs last month".
- **Trend chart** card: inner **plot inset** (`--recess-alt`, radius 18, well shadow) containing SVG (viewBox 340×130): 4 faint horizontal gridlines (`rgba(255,255,255,0.045)`), smooth cubic spending line stroke 3.5 with yellow→red gradient (`#FFD60A → #FF6B6B`) and glow `feDropShadow(0 5px 5, #FFB43C @ .35)`, gradient area fill fading to transparent, peak marker = 4.5px red dot + 9px halo + floating value pill (`--elevated` rounded rect, "₹1,840", 12/600). X-axis dates below inset.
- **AI Insight card**: `--raised` card with violet left rail (3px, glow `0 0 14px rgba(167,139,250,0.55)`) + extra card shadow `-2px 0 18px rgba(167,139,250,0.28)`; 12px breathing violet orb (2.6s scale pulse, disabled under reduced-motion); "AI INSIGHT" eyebrow in violet; 14.5/1.5 body with bold highlight. This is the **one intentional glow accent** of the system — don't add glows elsewhere except charts.
- **By category — vertical pill bar chart**: 5 columns, each a recessed vertical pill well (42×150, radius 999, well shadow) with an inner glowing fill pill (9px inset each side/bottom, vertical light→base gradient of the category color, glow `0 0 16px 2px <color @ .45>`), label (12/500 `--label2`) and amount (13.5/600) below. Heights proportional to spend: Rent 126px ₹7.3K · Health 69px ₹3.9K · Dining 36px ₹1.8K · Groceries 26px ₹900 · Other 24px ₹700.

## Interactions & Behavior (intended, not implemented in mock)
- Hero CTAs: "Add expense" opens the add-transaction flow; "Details" opens a monthly breakdown.
- Donut segments and legend rows tap → filtered category transactions.
- Budgets "Manage" → budget editing; month stepper changes period.
- Activity "+" → add transaction; rows tap → transaction detail.
- Analytics segmented control switches Week/Month/Year data; charts should animate arc sweep / bar rise ~500ms ease-out on load.
- Press states: raised buttons should invert to a pressed/inset look (swap float shadow for well shadow) — standard neumorphic affordance.
- Respect reduced-motion: disable orb pulse and chart entrance animations.

## State Management
- Current month/period selection (Overview, Budgets, Analytics).
- Transactions (merchant, category, amount, timestamp, direction) → derive day groups, day totals, category totals, net cash flow.
- Budgets per category → derive % used, remaining, over-budget flag.
- AI insight string (generated server-side or on-device).

## Embossed fill recipe (all horizontal progress bars)
`box-shadow: inset 0 1.5px 1px rgba(255,255,255,0.28), inset 0 -1.5px 2px rgba(0,0,0,0.28)` on the colored fill, inside a recessed track.

## Assets
No external images. All icons are inline 24×24 stroke SVGs (2.2–2.4 stroke, round caps) with dark strokes on colored tiles — replace with the codebase's icon set (SF Symbols equivalents: house, fork.knife, cross.case, cart, fuelpump, bolt, creditcard, arrow.up).

## Files
- `MyHome Redesign — Neumorphic v2.html` — all five frames on one canvas (each frame is a `.frame` div; shared tokens in the `<style>` block at top). Global SVG filter defs (`#arcLift`, `#lineGlow`) sit just after `<body>`.
