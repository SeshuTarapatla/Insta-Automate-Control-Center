# v2 — Visual inputs needed from you

Rule 5 means I never drive the app, so I have **never seen it render**. Everything in
[AUDIT.md](AUDIT.md) and [SCREENS.md](SCREENS.md) was derived by reading source, which is
reliable for structure and constraints and completely blind to how it actually looks.

Three of the v2 design decisions are outright **bets on an aspect ratio I've inferred from
arithmetic in `main.dart`** — the vertical Flows pipeline, the stacked Live split, and the
Overview bento grid's column count. Screenshot **#1 alone** confirms or kills all three.

Nothing here blocks checkpoints V2.1–V2.4 (the foundation and theme work). **Get #1–#3 in
before V2.5**, when screen layout work starts.

---

## Tier 1 — get these first (blocks V2.5 onward)

### 1. The whole screen, as you actually use it ⭐ highest value

The scrcpy mirror **and** the control center side by side, full desktop, nothing cropped.

`main.dart` computes the window as "fill everything right of the mirror" and I've inferred
~1250 × 1400 logical px from the geometry math there, but I don't know the monitor
resolution, the real scale factor, or how much room the mirror actually takes. If the app
is wider or shorter than I think, the vertical-pipeline and stacked-split decisions need
revisiting **before** they're built rather than after.

Please also just tell me: **monitor resolution and Windows scaling %** (Settings → System →
Display). That's a one-line answer that removes most of the guesswork on its own.

### 2. All seven screens, at the real window size

Overview · Flows · Live · Services · Library · Insights · Settings.

Default state is fine — I want to see how each screen actually fills that shape, where the
dead space is, and where things are cramped. The audit predicts specific problems
(Overview scrolling for two screens, the Live right column being narrow, the Library
toolbar taking two rows); these confirm or correct them.

### 3. Settings, all five tabs

Flows · Limits · Queue · Devices · Ops. The Limits tab especially — it's a `Wrap` of
`LimitCard`s whose count and arrangement I can't predict from source, and it's one of the
denser screens.

---

## Tier 2 — get these before the screen they affect

### 4. Live, mid-run, with real data — for **V2.8**

Ideally during an `entity-scrape` run, since that's the flow the current 420px column was
tuned against. If you can catch a second flow (scan or classify) too, that's better —
their card widths differ (320 / 420) and I want to see how both actually sit.

What I'm looking for: whether the images are readable at the sizes they render, how much
of the right column is card versus gutter, and how the log console reads next to them.

### 5. Library, at each zoom level — for **V2.9 / V2.10**

Small, Medium and Large, in a folder with real thumbnails (`scrape_queued` or
`gender_valid`). Review mode's entire premise is that a 1080×2246 profile page is
unjudgeable at thumbnail size — I'd like to see exactly how unjudgeable, so I can size the
review image correctly.

Also: **roughly how long does reviewing a batch of ~50 take you today, and what's the
actual sequence of clicks?** That's more useful than any screenshot for getting the
keyboard map right.

### 6. Services, with the terminal streaming — for **V2.4 and V2.11**

Any service, mid-output, with visible ANSI color if you can catch it.

This one has a **specific decision riding on it**: Daylight and Swiss are light themes, and
[THEMES.md](THEMES.md) §8 introduces a light terminal palette for them. If the services
emit dark-on-dark ANSI, that palette produces unreadable output and the right answer is to
keep the terminal dark in light themes (which VS Code and most IDEs do). I need to see real
output to call it.

### 7. Insights, all three tabs — for **V2.11**

Funnel · Ranking · Daily limits. The funnel's `CustomPainter` trapezoid (D78) and the
hand-built ranking table (D77) both survive v2 intact, so I want to see what I'm preserving
rather than redesign around a mental model of it.

### 8. Notification center, open — for **V2.5**

With a few real notifications in it. It's a `CompositedTransformFollower` popover and I
can't picture its real proportions against the title bar.

---

## Tier 3 — helpful, not blocking

### 9. Any app whose look you want this to have

The single most useful thing you can give me beyond screenshots of our own app. Screenshots
of anything — Grafana, Linear, Raycast, a game launcher, a synth UI, a website, a poster.

I've proposed six themes ([THEMES.md](THEMES.md)) from a reading of what a control center
needs, but "what you actually find good-looking" is not something I can derive. If two of
the six are close and one isn't, knowing that early saves building the wrong one.

### 10. Anything that currently annoys you

Not a screenshot — just a list. "The X always takes two clicks", "I can never find Y",
"the Z number is meaningless to me." The audit found structural problems by reading code;
it cannot find *friction*, and friction is what an overhaul should be aimed at.

If any of it contradicts something in [SCREENS.md](SCREENS.md), your version wins.

---

## How to give them to me

Drop the files anywhere and paste the paths, or attach them. `d:\Coding\` or the scratchpad
both work. Named by screen (`overview.png`, `live-scrape.png`) saves a round trip.

---

## Two questions that need an answer, not a screenshot

### A. Double-click in the Library grid

Today double-click **copies the image id** (`library_tile.dart:84`). SCREENS §5c proposes
it opens a **lightbox** instead, with copy-id moving to the right-click menu where it
already exists.

Flagged rather than assumed because it changes an interaction you use daily, and the
library's selection mechanics are a recorded preference of yours (D48). **Do you use
double-click-to-copy?** If yes, the lightbox gets a different key and nothing changes.

### B. The default theme on first launch

The plan keeps **Classic** as the default so nothing changes for you until you choose
otherwise. If you'd rather v2.0.0 open in **Command Deck** — which is the one designed for
how this app is actually used — say so and it becomes the default, with Classic still one
click away.
