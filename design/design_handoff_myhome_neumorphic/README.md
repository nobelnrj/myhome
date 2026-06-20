# Handoff: MyHome — Neumorphic (Soft UI) Personal Finance App

## Overview
MyHome is a personal-finance iOS app: an **Overview** (cash-flow + budgets + spending breakdown), an **Analytics** screen (spend trends, AI insight, by-category bars), plus Activity, Budgets, Notes, and Settings. This handoff targets **one visual style: Neomorphism (Soft UI)** — soft, extruded charcoal surfaces with dual light/dark shadows, lit by a single **canary-yellow accent**.

The prototype actually supports six interchangeable skins, but **for this handoff implement only the Neomorphism style.** The bundled prototype is pinned to open in it.

## About the Design Files
The files in this bundle are **design references created in HTML/React (Babel-in-browser)** — a prototype showing intended look and behavior, **not production code to copy directly**. The task is to **recreate this design in your target codebase** (React, SwiftUI, Vue, etc.) using its established patterns, component library, and conventions. If no environment exists yet, pick the most appropriate framework and implement there.

Everything renders inside a 402×874 iOS device frame. Ignore the device bezel/status bar if your target is a real iOS app — reproduce the **screen content**.

## Fidelity
**High-fidelity.** Colors, typography, spacing, radii, and shadows are final and exact (values below). Recreate the UI pixel-faithfully using your codebase's libraries. The numeric/sample data is placeholder — wire to real data.

---

## The Neumorphic System (most important section)

Neomorphism = surfaces are the **same family of color as the background**, raised or recessed purely by **two opposite shadows** (a light source from top-left). No translucency, no blur, near-invisible borders. The single saturated accent (yellow) is used sparingly for emphasis so it reads as "lit."

### Core tokens (exact)
| Token | Value | Use |
|---|---|---|
| Canvas background | `#1C1C23` | App background + device bg |
| Raised surface | `#1F1F27` | Default card/tile fill |
| Raised surface (strong) | `#22222C` | Hero / elevated cards, tab bar, sheets |
| Elevated control | `#262630` | Segmented selection, pickers |
| Recessed fill | `#15151B` | Progress/bar tracks, inputs (looks inset) |
| Recessed fill (alt) | `#16161C` / `#191920` | Secondary inset fills |
| Hairline separator | `rgba(255,255,255,0.05)` | Row dividers |
| Inset/edge separator | `rgba(0,0,0,0.30)` | Bottom edge of recessed wells |

### Shadows (the heart of the style)
- **Raised card** (`--card-shadow` / `--glass-shadow`):
  `-6px -6px 14px rgba(255,255,255,0.035), 7px 7px 18px rgba(0,0,0,0.55)`
- **Floating element** (hero, sheets, tab bar — `--glass-shadow-float`):
  `-9px -9px 22px rgba(255,255,255,0.04), 11px 11px 28px rgba(0,0,0,0.62)`
- **Inner rim** on raised surfaces (`--glass-rim`):
  `inset 1px 1px 1px rgba(255,255,255,0.045), inset -1px -1px 1px rgba(0,0,0,0.30)`
- **Recessed well** (apply to tracks/inputs to look pressed-in):
  `inset 2px 2px 5px rgba(0,0,0,0.5), inset -2px -2px 5px rgba(255,255,255,0.035)`
- **Border**: effectively none — `1px solid rgba(255,255,255,0.025)` (optional; the shadows define edges).

> Rule of thumb: **raised** = light shadow top-left + dark shadow bottom-right. **Recessed** = the same two shadows _inset_ and swapped in feel. Pressed/active state on a raised control = swap to the recessed (inset) shadow.

### Accent & semantic colors
| Token | Value | Meaning |
|---|---|---|
| Accent / brand "glow" | `#FFD60A` (canary yellow) | Active tab, key CTAs, highlights, Analytics tile |
| Accent soft | `rgba(255,214,10,0.16)` | Active-tab pill background, soft fills |
| Positive / income (`--pos`) | `#34E29B` | Income, positive net, "up" |
| Negative / expense (`--neg`) | `#FF6B6B` | Spend, negative net, "down" |
| Orange | `#FFB020` | Minor warnings |

On yellow surfaces, text/icons use near-black `#1A1404` for contrast.

### Text colors
| Token | Value |
|---|---|
| Primary label | `#ECEDF4` |
| Secondary label | `rgba(220,223,238,0.56)` |
| Tertiary label | `rgba(220,223,238,0.32)` |
| Quaternary label | `rgba(220,223,238,0.16)` |

### Typography
- Family: system — `-apple-system, "SF Pro Display", "SF Pro Text", system-ui, sans-serif`
- Large title: 34px / 700 / letter-spacing 0.37px
- Section headers: 22px / 700 / -0.4px
- Card titles: 16–17px / 600 / -0.3px
- Body / row text: 14–17px / 400–500
- Big money readouts: 46–56px / **weight 200** (ultra-thin) / letter-spacing -2 to -2.5px
- Stat numbers: 21–24px / 300 / -0.6px
- Labels/eyebrows: 11.5–13px / 600 / uppercase / letter-spacing 0.6–1.4px
- Tab labels: 10px / 500–600
- Numerals use `font-variant-numeric: tabular-nums`.

### Radii & spacing
- Card radius: **26px** (neumorphic cards are generously rounded)
- Tiles/inner radius: 16–22px; pills/bars: 999px
- Screen horizontal padding: 16px
- Inter-card gap: 12–22px
- Tab bar: floating capsule, 62px tall, radius 34px, bottom offset 24px
- Icon tiles: 26–40px square, radius ≈ 28% of size

### Motion
- Spring easing: `cubic-bezier(.34,1.32,.42,1)`; soft: `cubic-bezier(.32,.72,0,1)`
- Money values "roll" (odometer count-up, easeOutCubic, ~780ms) on mount/change
- Press feedback: `.tap` dims to 0.45 opacity; a soft water-ripple is layered on press
- **Neomorphism has no plasma/ambient background** — the canvas is a flat solid `#1C1C23`.

---

## Screens / Views

### 1. Overview (`src/home.jsx`)
- **Purpose**: at-a-glance month finances and entry points.
- **Layout**: scroll view, 16px side padding, collapsing large title "Overview". Top eyebrow "JUNE 2026".
- **Components (top → bottom):**
  - **Net cash flow hero** (floating raised card, radius 28, float shadow): eyebrow "NET CASH FLOW"; a Positive/Negative pill (pos/neg tinted); huge signed amount in pos/neg color (weight 200); a 2-up row of **Income** and **Spent** stat tiles (recessed fill, icon chip + label + rolling amount); a **budget usage bar** (recessed track `#15151B`, fill gradient `yellow → green`, or solid `--neg` if over) with "% of ₹X budget" and "₹Y left/over".
  - **Review-inbox banner** (raised card): yellow-tinted envelope icon tile, "N expenses to review", "Imported from Gmail · tap to confirm", chevron. Navigates to Activity (review filter).
  - **Analytics card** (raised card row): **solid yellow icon tile** (`#FFD60A`) with a line-chart glyph in near-black, title "Analytics", subtitle "Trends, insights & breakdowns", chevron. **Opens the Analytics screen.**
  - **"Where it's going"** donut card: ring donut (spend by category, each category its own color), center "SPENT" + rolling total, legend of top 4 categories with colored dots + amounts.
  - **Budgets** glance: up to 3 category rows (icon tile, name, spent/limit, progress bar). "See all" → Budgets.
  - **Income** glance + **Recent** expenses: grouped list rows (icon tile, merchant, "Category · date", amount; income amounts in green with "+").

### 2. Analytics (`src/analytics.jsx`) — opened from the Overview Analytics card
- **Purpose**: spending trends, AI insight, category breakdown.
- **Header**: back button (circular soft control, yellow chevron) + "Spending overview" / **Analytics**; trailing soft circular "slider" filter button.
- **Time-range tabs**: segmented Week / Month / Year with a sliding "liquid ink" highlight; active label sits on the highlight. (In neumorphism, render the track recessed and the highlight as a raised yellow-ish pill.)
- **Total spend**: eyebrow "TOTAL SPEND", large amount (weight 300), a delta chip (▲/▼ %, green if down / coral if up), "vs last month".
- **Spending-trend card** (floating raised): smooth area line chart that draws left→right; gradient line `yellow(glow) → coral(neg) → light`, soft fill under it, animated scanning dot, peak marker; x-axis labels.
- **AI Insight card** (raised): violet left edge-glow + breathing orb (secondary violet accent, intentional), eyebrow "AI INSIGHT", typewriter-revealed insight text.
- **By category**: list of horizontal bars — icon chip + name + amount; bar track recessed, fill is the category color, staggered grow-in, tap a bar for a glass tooltip (amount + % of spend).

### 3–6. Activity, Budgets, Notes, Settings
Standard grouped-list iOS screens (`src/expenses.jsx`, `src/budgets.jsx`, `src/notes.jsx`, `src/settings.jsx`) using the same neumorphic surfaces, rows, toggles, segmented controls, and sheets. Add/Edit Expense, Budget edit, Note editor, Reminder picker, and Notifications are modal sheets (`src/addexpense.jsx`, `src/ui.jsx` Sheet/PushView).

---

## Interactions & Behavior
- **Tab bar**: 5 tabs (Home, Activity, Budgets, Notes, Settings) — floating capsule; active tab shows a soft yellow pill + yellow icon/label with a subtle glow; sliding highlight animates between tabs.
- **Analytics**: opens as a full-screen overlay over the app (currently instant; a 300ms fade/scale-in is desirable). Back button closes it.
- **Money roll**: amounts count up on mount and animate on change (toggleable).
- **Press**: `.tap`/row press → opacity dim + ripple. Recessed controls should visually "press in."
- **Sheets**: slide up from bottom, dim backdrop, grabber handle, 320–340ms `cubic-bezier(.32,.72,0,1)`.
- **Review flow**: confirm/dismiss Gmail-imported expenses moves them into the list.
- **Budget state**: sample data has Under/Over variants (drives over-budget coloring).

## State Management
- `tab` (active tab), `analyticsOpen` (overlay), per-sheet open flags (`addOpen`, `editingBudget`, `noteId`, `reminderOpen`, `notifOpen`).
- Data: `expenses`, `income`, `budgets` (derived from limits + spend), `review` inbox, `reminders`, `notes`, `limits`.
- Actions: add/edit/delete expense, confirm/dismiss review, edit/clear budget, CRUD notes + reminders, sync.
- All data is local sample data in `src/data.jsx` — replace with your data layer.

## Design Tokens
See **The Neumorphic System** above for the complete, exact token set (colors, shadows, radii, type, motion). Category palette (`src/tokens.jsx → CAT_COLORS`): groceries `#2DD4BF`, dining `#FB923C`, fuel `#F472B6`, utilities `#7DD3FC`, rent `#818CF8`, auto `#38BDF8`, shopping `#E879F9`, health `#A78BFA`, subscriptions `#22D3EE`, entertainment `#C084FC`, other `#94A3B8`.

## Assets
- **Icons**: custom inline SF-Symbol-style SVG set in `src/icons.jsx` (`<Icon name size color weight fill/>`). No external icon font needed; map to your icon library (SF Symbols on iOS).
- **Fonts**: system fonts only.
- No raster images.

## Files (where the design lives)
- `MyHome.html` — entry; loads everything. **Pinned to open in Neomorphism** (`src/app.jsx → TWEAK_DEFAULTS.style = "neuro"`).
- `src/tokens.jsx` — design tokens; the `neuro` branch of `buildThemeVars()` is the source of truth for this style.
- `src/app.jsx` — app shell, state, navigation, tab bar, Analytics overlay wiring.
- `src/home.jsx` — Overview (+ Analytics entry button).
- `src/analytics.jsx` + `src/analytics.css` — Analytics screen.
- `src/ui.jsx` — primitives (Screen, Row, GroupedList, Toggle, Segmented, ProgressBar, TabBar, Sheet, PushView).
- `src/glass.jsx` — surface primitive (in neuro: opaque, dual-shadow, no blur).
- `src/motion.jsx` — rolling numbers, ripple, (plasma — unused in neuro).
- `src/icons.jsx`, `src/data.jsx`, `src/charts.jsx`, `src/calendar.jsx`, `src/expenses.jsx`, `src/budgets.jsx`, `src/notes.jsx`, `src/settings.jsx`, `src/addexpense.jsx` — screens & helpers.
- `frames/ios-frame.jsx` — device bezel (ignore for a real iOS build).
- `tweaks-panel.jsx` — in-prototype controls (not part of the product).

## How to preview the reference
Open `MyHome.html` in a browser — it opens directly in the Neomorphism style. (The Tweaks panel still lets you preview the other five skins for comparison; ignore them for this handoff.)
