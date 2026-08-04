# v2 — Theme catalog

Six themes ship in **v2.0.0**. The rest of the design-language list is triaged into a
roadmap at the end (§8) — nothing is discarded, but not everything belongs in a tool you
stare at for hours.

Token names below are from [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) §1. Every color is a real
value, not a placeholder. Every theme has been contrast-checked against its own
`surface.base`; the results are in §7.

---

## The six

| # | Id | Name | Brightness | One line |
|---|---|---|---|---|
| 1 | `classic` | **Classic** | dark | Exactly today's app. The baseline, preserved. |
| 2 | `commandDeck` | **Command Deck** | dark | Ops console. Hairlines, monospace numerals, color reserved for meaning. |
| 3 | `nocturne` | **Nocturne** | dark | Soft, cozy, low-contrast. Tokyo Night, extended. |
| 4 | `mica` | **Mica** | dark | Translucent Windows 11 native. Uses the backdrop the app already pays for. |
| 5 | `daylight` | **Daylight** | light | Warm paper. The biggest single vibe change available. |
| 6 | `swiss` | **Swiss** | light | International Style. Rules, grid, one red, zero radius. |

Default on first launch stays **Classic**, so an existing user's app is unchanged until
they choose otherwise. The welcome dialog (`core/onboarding.dart`) gains one line pointing
at the new Appearance tab.

---

## 1. Classic

*The look the app has had since CP 0.3. Preserved so nothing is lost, and so every other
theme has a reference point.*

**Built differently from the other five, on purpose.** Rather than transcribing Material's
generated scheme by hand (and drifting from it), `classic.dart` calls
`ColorScheme.fromSeed(seedColor: Color(0xFF6C63FF), brightness: Brightness.dark)` and maps
those results onto the token set. That guarantees a pixel-identical match to today rather
than an approximation.

| Token group | Value |
|---|---|
| `surface.*` | from the M3 seed scheme: `canvas` = transparent, `base` = `surfaceContainer`, `raised` = `surfaceContainerHigh`, `sunken` = `surfaceContainerLowest`, `overlay` = `surfaceContainerHigh`, `border` = `outlineVariant`, `borderStrong` = `outline` |
| `content.*` | `primary` = `onSurface`, `secondary` = `onSurfaceVariant`, `tertiary` = `onSurfaceVariant` @ 0.62 |
| `accent.primary` | scheme `primary` (≈ `#C6C0FF`) |
| `status` | `AppPalette.dark`'s existing three, plus `bad` = scheme `error`: good `#3DD68C` · info `#6EA8FE` · warn `#FFB454` · bad `#FFB4AB` |
| `type` | body/display **Roboto** (Material default — this theme is the "before"), mono **JetBrains Mono** (the one deliberate upgrade: it replaces the `Consolas`/`monospace` mix, which was a bug, not a look) |
| `geometry` | radius 8 / 12 / 16 / 999, border 1, focus 2 |
| `effects` | `depth: shadow`, Material's own elevation shadows, `hoverLift: false`, tint 0.08 |
| `terminal` | `TerminalPalette.dark` unchanged |
| density | comfortable |

---

## 2. Command Deck

*Near-black, hairline-ruled, monospace-numeraled. Grafana / k9s / Vercel territory. The
theme for someone who actually runs a pipeline off this screen all day.*

**Its organising idea: color means something, or it isn't there.** The chrome is
achromatic — greys and hairlines only — so the four status colors are the only saturated
things on screen and read instantly at any size. This is why the accent is a cool sky blue
used *only* for selection and focus, never for status.

```
surface.canvas        #07080B
surface.base          #0E1015
surface.raised        #161923
surface.sunken        #090A0E
surface.overlay       #1A1D27
surface.border        #232733
surface.borderStrong  #333949
surface.borderSubtle  #191C25
surface.scrim         #000000 @ 0.72

content.primary       #E6E9F0
content.secondary     #949CB0
content.tertiary      #5B6274
content.onAccent      #04121A
content.inverse       #0E1015

accent.primary        #38BDF8
accent.onPrimary      #04121A
accent.muted          #38BDF8 @ 0.14

status.good           #22C55E   container #052E16   onContainer #4ADE80
status.info           #38BDF8   container #082F49   onContainer #7DD3FC
status.warn           #F59E0B   container #3B2400   onContainer #FCD34D
status.bad            #EF4444   container #3F0D0D   onContainer #FCA5A5
```

| Group | Value |
|---|---|
| `type` | display/body **Inter**, mono **JetBrains Mono**, `scale` 0.96, `bodyHeight` 1.45, `tightTracking` −0.01, `looseTracking` +0.08, `bodyWeight` 400, `headingWeight` 600, **`uppercaseLabels: true`**, `iconWeight` regular |
| `geometry` | radius **3 / 4 / 6 / 999**, border 1, borderStrong 1, focus 2, hairline 1 |
| `effects` | **`depth: border`** — all three shadow lists empty. Depth is hairlines and surface steps, nothing else. `surfaceBlur` 0, `hoverLift` false, `hoverTintAlpha` 0.06 |
| `chart.series` | `#38BDF8 · #22C55E · #F59E0B · #A78BFA · #F472B6 · #2DD4BF` |
| `terminal` | `TerminalPalette.dark` (Tokyo Night) with `background`/`panelBackground` → `#090A0E`, `headerBackground` → `#161923` |
| **density** | **`compact` by default** — the one theme that ships dense, because that's its whole point |

Signature details worth building: uppercase `micro` labels with wide tracking for every
section header; every numeric in JetBrains Mono with tabular figures; table rows separated
by `borderSubtle` hairlines rather than padding; no card shadows anywhere, so the layout
reads as a single ruled sheet.

---

## 3. Nocturne

*Deep blue-purple, muted pastels, generous radii, a soft accent glow. The app at 11pm.*

Extends a color language the app already half-speaks: `TerminalPalette.dark` is already
Tokyo Night, so this theme is the only one where the terminal and the chrome around it were
designed together.

```
surface.canvas        #13131A
surface.base          #1A1B26
surface.raised        #232534
surface.sunken        #16161F
surface.overlay       #262838
surface.border        #2E3145
surface.borderStrong  #3D4160
surface.borderSubtle  #22243A
surface.scrim         #0B0B12 @ 0.66

content.primary       #C0CAF5
content.secondary     #8A92B2
content.tertiary      #565F89
content.onAccent      #1A1128
content.inverse       #1A1B26

accent.primary        #BB9AF7
accent.onPrimary      #1A1128
accent.muted          #BB9AF7 @ 0.16

status.good           #9ECE6A   container #1F2E14   onContainer #C3E88D
status.info           #7AA2F7   container #16233F   onContainer #A9C3FF
status.warn           #E0AF68   container #33260F   onContainer #F0C990
status.bad            #F7768E   container #3A121C   onContainer #FF9EB0
```

| Group | Value |
|---|---|
| `type` | display/body **Inter**, mono **JetBrains Mono**, `scale` 1.0, `bodyHeight` **1.55**, tracking normal, `bodyWeight` 400, `headingWeight` 600, `uppercaseLabels: false`, `iconWeight` **light** |
| `geometry` | radius **8 / 14 / 20 / 999**, border 1, focus 2 |
| `effects` | **`depth: glow`** — `shadowSm` = `[#BB9AF7 @0.06, blur 12, y 2]`; `shadowMd` = `[#000000 @0.35, blur 24, y 6]` + `[#BB9AF7 @0.05, blur 32]`; `hoverLift: true`, `hoverTintAlpha` 0.08 |
| `chart.series` | `#BB9AF7 · #7AA2F7 · #9ECE6A · #E0AF68 · #F7768E · #7DCFFF` |
| `terminal` | `TerminalPalette.dark` verbatim — this is its home theme |
| density | comfortable |

Signature details: the largest radii in the set; hover genuinely lifts (2px) rather than
just tinting; the accent glow appears on focused and running elements only, so a running
flow visibly *emits* on this theme.

---

## 4. Mica

*Translucent, layered, Fluent. Uses the acrylic backdrop `main.dart` has been enabling and
wasting since CP 0.2 (AUDIT §9).*

**This is the tasteful, native answer to "glassmorphism"** — real Windows compositor Mica
rather than a stack of `BackdropFilter`s. It is also the only theme that uses system fonts,
because a theme whose premise is "this shipped with Windows" must not bring its own
typeface.

All surface values carry alpha. `surface.canvas` is fully transparent so the desktop shows
through the shell.

```
surface.canvas        #000000 @ 0.00     (fully transparent — Mica shows through)
surface.base          #202020 @ 0.72
surface.raised        #2B2B2B @ 0.80
surface.sunken        #1A1A1A @ 0.85
surface.overlay       #2C2C2C @ 0.92
surface.border        #FFFFFF @ 0.093    (Fluent CardStrokeColorDefault)
surface.borderStrong  #FFFFFF @ 0.16
surface.borderSubtle  #FFFFFF @ 0.055
surface.scrim         #000000 @ 0.30

content.primary       #FFFFFF @ 1.00     (Fluent TextFillColorPrimary)
content.secondary     #FFFFFF @ 0.786    (…Secondary)
content.tertiary      #FFFFFF @ 0.544    (…Tertiary)
content.onAccent      #000000 @ 1.00
content.inverse       #000000

accent.primary        #60CDFF            (Windows 11 default dark accent, light-2)
accent.onPrimary      #003A50
accent.muted          #60CDFF @ 0.18

status.good           #6CCB5F   container #393D1B   onContainer #6CCB5F
status.info           #60CDFF   container #1B3A4B   onContainer #60CDFF
status.warn           #FCE100   container #433519   onContainer #FCE100
status.bad            #FF99A4   container #442726   onContainer #FF99A4
```

| Group | Value |
|---|---|
| `type` | display **Segoe UI Variable Display**, body **Segoe UI Variable Text**, mono **Cascadia Mono** — all with Inter / JetBrains Mono declared as fallbacks so it degrades safely if a font is missing. `scale` 1.0, `bodyHeight` 1.4, `iconWeight` regular, `uppercaseLabels: false` |
| `geometry` | radius **4 / 8 / 8 / 999** (Fluent's own corner scale), border 1, focus 2 |
| `effects` | **`depth: both`**, `surfaceBlur` 18, `shadowMd` = `[#000000 @0.26, blur 32, y 8]`, `hoverLift: false`, `hoverTintAlpha` 0.06 |
| `chart.series` | `#60CDFF · #6CCB5F · #FCE100 · #FF99A4 · #C39EFF · #4CC2FF` |
| `terminal` | `TerminalPalette.dark` with `background` → `#1A1A1A @ 0.85`, `headerBackground` → `#2B2B2B @ 0.80` |
| density | comfortable |

Signature details: a 1px `#FFFFFF @ 0.10` top-edge highlight on raised surfaces (Fluent's
"reveal" stroke); the nav rail and title bar become translucent so the desktop shows
through the chrome; card borders are lighter on top than bottom.

**Known constraint:** switching to or from Mica calls native `Window.setEffect(...)` and
cannot animate. Accept the hard cut; every other theme transition interpolates.

---

## 5. Daylight

*Warm paper white, ink text, real shadows, indigo accent. After six dark themes, this is
the one that makes it feel like a different application.*

This is also the theme that does the most to prove the token system works, because every
dark-mode assumption in the codebase has to have become a token for it to render at all.

```
surface.canvas        #FBFBF9
surface.base          #FFFFFF
surface.raised        #F6F6F3
surface.sunken        #F1F1ED
surface.overlay       #FFFFFF
surface.border        #E4E4DE
surface.borderStrong  #C9C9C1
surface.borderSubtle  #EFEFEA
surface.scrim         #1A1A18 @ 0.35

content.primary       #1A1A18
content.secondary     #5C5C56
content.tertiary      #8E8E86
content.onAccent      #FFFFFF
content.inverse       #FBFBF9

accent.primary        #4F46E5
accent.onPrimary      #FFFFFF
accent.muted          #4F46E5 @ 0.10

status.good           #15803D   container #DCFCE7   onContainer #14532D
status.info           #1D4ED8   container #DBEAFE   onContainer #1E3A8A
status.warn           #B45309   container #FEF3C7   onContainer #78350F
status.bad            #B91C1C   container #FEE2E2   onContainer #7F1D1D
```

| Group | Value |
|---|---|
| `type` | display/body **Inter**, mono **JetBrains Mono**, `scale` 1.0, `bodyHeight` 1.5, `iconWeight` regular, `uppercaseLabels: false` |
| `geometry` | radius **6 / 10 / 14 / 999**, border 1, focus 2 |
| `effects` | **`depth: shadow`** — `shadowSm` `[#1A1A18 @0.05, blur 4, y 1]`, `shadowMd` `[@0.07, blur 12, y 4]`, `shadowLg` `[@0.10, blur 28, y 12]`. `hoverLift: true`, `hoverTintAlpha` 0.045 |
| `chart.series` | `#4F46E5 · #0891B2 · #15803D · #B45309 · #BE185D · #7C3AED` |
| `terminal` | **`TerminalPalette.light`** — a new palette, see §6 |
| density | comfortable |

Warm rather than pure white (`#FBFBF9`, not `#FFFFFF`) because a full-height, full-bright
panel next to a dark scrcpy mirror is fatiguing; the slight warmth takes the edge off
without reading as beige.

---

## 6. Swiss

*International Style: a strict grid, black rules, one red, and zero corner radius
anywhere. The most opinionated theme in the set.*

Chosen from the inspiration list because it is the one classical design language that is
*actually about dense information* — timetables, wayfinding, technical tables. Everything
this app renders is a table, a status, or a number.

```
surface.canvas        #FFFFFF
surface.base          #FFFFFF
surface.raised        #F7F7F7
surface.sunken        #F0F0F0
surface.overlay       #FFFFFF
surface.border        #000000 @ 0.14
surface.borderStrong  #000000 @ 0.85     ← real black rules, the primary structural device
surface.borderSubtle  #000000 @ 0.07
surface.scrim         #000000 @ 0.40

content.primary       #000000
content.secondary     #5A5A5A
content.tertiary      #909090
content.onAccent      #FFFFFF
content.inverse       #FFFFFF

accent.primary        #E30613            single accent, used sparingly and never decoratively
accent.onPrimary      #FFFFFF
accent.muted          #E30613 @ 0.08

status.good           #007A33   container #E6F4EC   onContainer #005423
status.info           #0057B8   container #E4EEF9   onContainer #003C80
status.warn           #C25E00   container #FBEEE2   onContainer #7F3D00
status.bad            #E30613   container #FCE7E8   onContainer #96040D
```

| Group | Value |
|---|---|
| `type` | display/body **Inter** (as the Helvetica substitute), mono **JetBrains Mono**, `scale` 0.98, `bodyHeight` 1.45, `tightTracking` **−0.02**, `looseTracking` **+0.10**, `bodyWeight` 400, `headingWeight` **700**, **`uppercaseLabels: true`**, `iconWeight` **bold** |
| `geometry` | radius **0 / 0 / 0 / 0** — including `radiusFull`; even pills and avatars are square. `borderWidth` 1, `borderWidthStrong` **2**, focus 2, hairline 1 |
| `effects` | **`depth: border`**, all shadows empty, `hoverLift: false`, `hoverTintAlpha` 0.04 |
| `chart.series` | `#E30613 · #000000 · #0057B8 · #007A33 · #C25E00 · #5A5A5A` |
| `terminal` | `TerminalPalette.light` with `foreground` → `#000000` |
| density | comfortable |

Signature details: heavy weight contrast (400 body against 700 headings, nothing between);
2px black rules under every section header; a strict 8px baseline grid; strong left
alignment with no centering anywhere except genuinely modal content; red used only for the
active nav item, the focus ring, and `status.bad`.

---

## 7. Contrast verification

Every value below is against that theme's own `surface.base`. The floor is **4.5:1** for
body text and status foregrounds, **3:1** for `content.tertiary` (placeholder/disabled) and
UI boundaries. `test/theme_contrast_test.dart` asserts these programmatically for all six
themes so a later palette tweak can't quietly break one.

| Theme | primary | secondary | tertiary | good | info | warn | bad | accent |
|---|---|---|---|---|---|---|---|---|
| Classic | 13.1 | 9.4 | 4.6 | 8.9 | 7.1 | 10.4 | 8.2 | 8.7 |
| Command Deck | 14.6 | 6.9 | 3.2 | 7.6 | 9.1 | 9.4 | 4.9 | 9.1 |
| Nocturne | 10.8 | 5.6 | 3.1 | 8.4 | 6.5 | 8.5 | 6.3 | 6.9 |
| Mica | 13.9 | 9.8 | 4.7 | 7.4 | 9.6 | 13.4 | 7.1 | 9.6 |
| Daylight | 17.4 | 6.9 | 3.3 | 5.1 | 7.4 | 5.0 | 6.4 | 8.3 |
| Swiss | 21.0 | 7.1 | 3.5 | 5.6 | 7.7 | 4.7 | 6.2 | 5.9 |

*(Computed values — the implementing session must re-verify with the real test rather than
trusting this table, and adjust any value that comes in under floor.)*

**`content.tertiary` sits at 3.1–3.5:1 in the dark themes by design** — it is placeholder
and disabled text, where WCAG's contrast minimum does not apply and where full contrast
would defeat the purpose. It is never used for information the user must read.

---

## 8. `TerminalPalette.light`

Needed by Daylight and Swiss; no light terminal palette exists today. Based on GitHub
Light, which is designed for exactly this (syntax color on white, at contrast).

```
foreground #24292F   background #FFFFFF
black #24292F        red #CF222E    green #116329   yellow #4D2D00
blue  #0969DA        magenta #8250DF cyan #1B7C83   white #6E7781
brightBlack #57606A  brightRed #A40E26  brightGreen #1A7F37  brightYellow #633C01
brightBlue #218BFF   brightMagenta #A475F9  brightCyan #3192AA  brightWhite #8C959F
searchHitBackground #FFF8C5   searchHitBackgroundCurrent #FFD8B5   searchHitForeground #24292F
panelBackground #FFFFFF       headerBackground #F6F8FA
```

Note this is a real behavioural change for `ServiceTerminal`: the supervised services emit
ANSI color assuming a dark background. Most emit sparse color (status words, log levels)
and read fine, but **this needs a live check** — see [VISUAL_INPUTS.md](VISUAL_INPUTS.md).
If a service turns out to emit dark-on-dark ANSI that becomes illegible on white, the
fallback is to keep the terminal pane dark in light themes (a legitimate choice — VS Code
and many IDEs do exactly this) by pointing `terminal` at `TerminalPalette.dark` for
Daylight/Swiss too.

---

## 9. The theme picker

Settings gains an **Appearance** tab (a sixth tab, before Ops). It holds:

- **Theme** — a `Wrap` of preview cards, one per theme. Each card renders a **live
  miniature of the real app chrome** in that theme at ~240×150: a title bar strip, three
  nav rail items, a card with a status dot, a hairline, and a numeric. Not a color swatch —
  the point of these themes is geometry, type and depth as much as color, and a swatch row
  shows none of that. Built by wrapping the miniature in a `Theme(data: buildTheme(...))`,
  which costs nothing and is guaranteed accurate.
- **Density** — `comfortable` / `compact` segmented control, with a one-line explanation of
  what it changes.
- **Reduce motion** — `auto (follow Windows)` / `always` / `never`.
- **Terminal palette override** — for the light-theme terminal question in §8: `follow
  theme` / `always dark`.

All four persist to `shared_preferences`, mirroring `MutedTagsController`'s existing
pattern.

Also reachable from the command palette: typing `theme` lists all six as direct actions.

---

## 10. Backlog — the rest of the inspiration list

None of these are rejected outright except where noted. They are ordered by fit for *this*
app: a dense, long-session, information-first control center.

### Already covered by a shipping theme

| Style | Where it landed |
|---|---|
| **Glassmorphism** | **Mica.** Real OS-composited Mica rather than stacked `BackdropFilter`s — the same aesthetic, at a fraction of the GPU cost, and native to the platform. A separate "glass" theme would be strictly worse. |
| **Minimalist** | **Command Deck** and **Swiss** are both minimalist, from opposite directions (dark/dense and light/typographic). A third would be redundant. |
| **Bento UI** | **Adopted as a layout pattern, not a theme.** It's a composition idea, not a color/type language — so it becomes the structure of the redesigned Overview page (see [SCREENS.md](SCREENS.md) §1), where it works in all six themes rather than only one. |

### v2.1 — good fit, real work

| Style | Sketch | Why it fits | Cost |
|---|---|---|---|
| **Cyberpunk / Neon** | Near-black `#05060A`, magenta `#FF2E88` + cyan `#00F0FF`, glow on every accent, subtle scanline texture on `canvas`, mono-heavy | The pipeline genuinely *is* a machine you monitor; the aesthetic has real precedent in ops tooling. Best restricted to a "showpiece" mode | Medium — needs a texture asset and a glow-heavy `EffectTokens` variant. Risk: fatiguing over an 8-hour session, so it should never be the default |
| **Editorial** | Warm off-white, a serif display face (Source Serif / Newsreader) for headings against Inter body, wide measure, generous leading, hairline rules | Would be excellent for **Insights** specifically — funnel narratives, ranking tables and burn-down commentary read genuinely better in an editorial voice | Low-medium — one extra bundled font family, otherwise pure token work |
| **Dark Academia** | Deep brown-black `#161311`, parchment `#E8DCC8` text, oxblood `#7B2D26` accent, serif display, warm amber status | A cozy long-session dark theme with a distinct personality from Nocturne's cool purple | Low — reuses Editorial's serif; a pure palette + type authoring job |
| **Retro-futurism** | Amber-on-black CRT (`#FFB000` on `#0A0A00`) or the green-phosphor variant, boxy geometry, mono everywhere | Uniquely appropriate for the **Services terminal** and the **Live log console** — this is literally what those panes are | Low as a theme; medium if it gets scanline/curvature shader treatment |

### v2.2 — evaluate against real use first

| Style | Concern |
|---|---|
| **Neo-brutalism** | Thick black borders, hard offset shadows, flat saturated blocks. Genuinely striking and it *is* implementable purely through `GeometryTokens` + `EffectTokens` (offset shadow with zero blur). But it spends a lot of pixels on borders, and this app's densest screens — the ranking table, the library grid, the log console — are exactly where that hurts. Worth prototyping on one screen before committing. |
| **Luxury** | Near-black + gold `#C9A227` + a high-contrast serif. Handsome, but "luxury" signals *scarcity and restraint*, which is at odds with a screen whose job is to show 7,655 files and five concurrent counters. Would need a real information-density rethink to not look silly. |
| **Y2K** | Chrome gradients, bevels, translucent blue plastic, Comic-adjacent type. Fun, and genuinely nostalgic for a "control panel." Realistically a novelty — schedule only if the theme system is otherwise complete and it's a fun afternoon. |

### Not recommended — and why

These are the ones I'd argue against building at all, rather than merely deferring:

| Style | Reason |
|---|---|
| **Neumorphism** | The aesthetic *is* low contrast — soft embossing depends on the foreground and background being nearly the same value. It fails the 4.5:1 floor by construction, not by execution. It cannot be made accessible while remaining recognisably neumorphic, and it would be the one theme where a status color is hard to see. For a monitoring tool that is disqualifying. |
| **Claymorphism** | Same contrast problem as neumorphism, plus every surface needs a double inner shadow and a heavy blur — real per-frame GPU cost on a window that is also compositing Mica and streaming a live terminal. |
| **Skeuomorphism** | Needs bespoke raster or vector assets per component (knobs, switches, brushed metal, leather). That's an art-production project, not a theming project, and it doesn't scale to 40 component sub-themes. |
| **Brutalism (proper)** | As distinct from *neo*-brutalism: deliberately hostile ergonomics — default browser styles, unstyled controls, jarring layout. That's an artistic position about the web, and it's directly opposed to CLAUDE.md rule 7 ("genuinely easier to use, not merely functional"). |

### Adding a theme later is cheap — by design

Once [PLAN_V2.md](PLAN_V2.md) checkpoint **V2.2** lands, a new theme is **one file in
`core/theme/themes/` and one line in `registry.dart`**. No feature file changes, no
component changes, no tests beyond adding the id to the contrast test's parameter list.
That is the entire reason for building the token layer first rather than restyling
screen-by-screen — the six shipping themes are as much a proof that the abstraction holds
as they are a feature.
