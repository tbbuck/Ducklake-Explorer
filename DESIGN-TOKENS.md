# DuckLake Explorer — Stratum design tokens

> Status: **Draft** · 2026-09-10 · The exact palette, type, spacing and effect values
> behind the **Stratum** prototype. Companion to [UI-SPEC.md](./UI-SPEC.md). Source of
> truth for the SwiftUI Asset Catalog + `Theme`.

Two themes: **Day** (limestone) is the base; **Night** (JetBrains-Islands) applies under
`prefers-color-scheme: dark`. In SwiftUI: define each token as a semantic colour set with
`Any` + `Dark` appearances; a manual toggle just sets `.preferredColorScheme`.

## Colour

| Token | Day (light) | Night (dark) | Role |
|---|---|---|---|
| `backdrop` | `#E3E1D8` | `#131417` | Desktop behind the window ("island sea") |
| `bg` | `#EFEEE7` | `#1E1F22` | Window ground / editor canvas |
| `panel` | `#F7F6F0` | `#2B2D30` | Lifted sidebars ("islands") |
| `panel-2` | `#FCFBF6` | `#303236` | Cards, inputs, sticky headers |
| `panel-3` | `#F0EEE5` | `#35373C` | Hover / inset track |
| `line` | `#DAD5C9` | `#393B40` | Hairline dividers |
| `line-2` | `#C6C0B1` | `#45474D` | Stronger borders / control outlines |
| `text` | `#223038` | `#E3E5EA` | Primary text |
| `muted` | `#515B5A` | `#B4B8C0` | Secondary text |
| `muted-2` | `#6C736E` | `#8B9099` | Tertiary text / captions |
| `accent` | `#1E7A72` | `#3FA091` | Ink-teal — active, selection, links, primary buttons |
| `accent-2` | `#A97B36` | `#D6A55D` | Brass/amber — data types, histograms, deletes |
| `accent-soft` | `rgba(30,122,114,.12)` | `rgba(63,160,145,.16)` | Selection / hover fill (accent @ low alpha) |
| `accent-line` | `rgba(30,122,114,.34)` | `rgba(63,160,145,.42)` | Subtle accent borders / focus glow |
| `on-cool` | `#EEF5F2` | `#EEF5F2` | Text on an accent fill or a deep band |
| `on-warm` | `#17332E` | `#10201D` | Text on a light/shallow band |

**Strata ramp** (water-depth: surface → bedrock). Used for the history core-spine gradient,
the core-sample layers, and lake-card cores.

| Stop | Day | Night |
|---|---|---|
| `s-sand` (surface) | `#C4D6CE` | `#7CC8BD` |
| `s-silt` | `#99C1B6` | `#57ABA1` |
| `s-marl` | `#66A398` | `#3E8C83` |
| `s-shale` | `#3F857C` | `#2E6E68` |
| `s-slate` (depth) | `#256560` | `#204F4C` |

**Fixed / semantic**

- Traffic lights (both themes): red `#E8615A`, yellow `#E3B04A`, green `#5FBE67`.
- Diff/semantic: additions use `accent`, deletions/alterations use `accent-2` (no separate red/green — keeps the palette tight).
- History core-spine gradient: `linear-gradient(s-sand, s-silt 28%, s-marl 52%, s-shale 76%, s-slate)`.

## Typography

Two families (system SF is used only for native window chrome in the real app):

- **Hanken Grotesk** — display, headings, UI, body. Weights 400 / 500 / 600 / 700.
- **JetBrains Mono** — all data, SQL, paths, numerics, badges. Weights 400 / 500 / 600.

Scale (px / weight):

| Role | Face | Size / weight | Notes |
|---|---|---|---|
| Window title (`buildings`) | Hanken | 22 / 700 | `letter-spacing: -.02em` |
| Diff version (`v147`) | Hanken | 17 / 700 | |
| Section header (`History`) | Hanken | 15 / 700 | |
| Lake-card name | Hanken | 14.5 / 600 | |
| Snapshot version (`v147`) | Hanken | 14 / 600 | |
| Body / field labels | Hanken | 11.5–13 / 400–500 | |
| Commit message | Hanken | 12 / 400 | truncates with ellipsis |
| Metric value | JetBrains Mono | 15 / 500 | |
| Catalog table name | JetBrains Mono | 15 / 600 | |
| Grid / data cells | JetBrains Mono | 11.5–12.5 / 400 | |
| Column type (`BIGINT`) | JetBrains Mono | 11 / 400 | `accent-2`; geom/bool → `accent` |
| Panel eyebrow (`CORE SAMPLE`) | JetBrains Mono | 10 / 400 | `letter-spacing: .05em`, set in caps |
| Badges / pills / captions | JetBrains Mono | 9.5–10.5 / 400–500 | |

- Numeric columns use `tabular-nums`.
- Legibility floor ≈ 9.5px; muted text uses `muted`/`muted-2` (contrast-tuned per theme).

## Layout & sizing

**Window & chrome**

- Window: max-width ~1180–1200px; height 784px (main) / 700px (screens); radius **14px**; 1px `line-2` border.
- Titlebar: 46–48px tall. Traffic lights 12px circles, 8px gap.
- Search field 176–200 × 28px. "as of vN" chip: `accent` fill, `on-cool` text, radius 8px, padding 5×11.

**Main explorer** — three columns: **History 264px · Schema tree 212px · Inspector 1fr**.
Inspector detail splits **Core sample 300px · Schema/stats 1fr**, over a query rail.

**Screens** — Connect: two equal columns. Metadata: sidebar **250px** · grid 1fr. Secret rows: grid `18px · 1fr · auto`.

**Component sizes**

- History core-spine: **7px** wide, radius 4px; lamina notch 13×4px (active 15×6px + `0 0 8px accent-line` glow); active lamina left rail `inset 2px 0 0 accent`.
- Core-sample column: **78px** wide, radius 8px, `inset 0 0 18px rgba(0,0,0,.14)`; layer height ∝ `record_count`; inlined layer = 45° `s-sand`/`s-silt` stripes; delete "erosion" line = **2px dashed `accent-2`** + `0 0 9px` (accent-2 @ 45%).
- Column distributions (all **82px** wide): histogram 16px tall, bars `accent-2`, 1.5px gap; distinct/percent bar 8px tall, radius 4px, track `panel-3`, fill `accent` (or `accent-2` for booleans); geometry-mix 8px tall (`accent` polygon + `accent-2` point).
- Cards / inputs / buttons / notes: radius **8–12px**. Secret radio 16px circle. Chips/badges radius 4–5px; pills radius 5px. Segmented control: outer radius 10px, buttons radius 7px.
- Drop zone: 1.5px dashed `line-2`, radius 12px.

**Borders, focus, shadows**

- Hairlines 1px `line`; control borders 1px `line-2`; dashed section dividers 1px `line`.
- Focus ring: `2px solid accent`, `outline-offset: 2px`.
- Selection: left rail `inset 2px 0 0 accent`; active card `inset 0 0 0 1px accent` + `accent-soft` fill.
- Window shadow — Day `0 34px 80px -34px rgba(34,48,56,.42)`; Night `0 40px 90px -30px rgba(0,0,0,.7)`.
- Sheet/dialog shadow `0 30px 70px -25px rgba(0,0,0,.45)`.

**Spacing & motion**

- Side gutter ≥ 16px; panel padding 14–20px; card padding ~12px.
- Transitions: `.12s ease` on hover / active / toggle only. **Respect `prefers-reduced-motion`** (disable all). No non-interactive/ambient motion.
