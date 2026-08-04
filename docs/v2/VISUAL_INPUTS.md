# v2 — Visual inputs

> ✅ **Mostly resolved 2026-08-04.** The user lifted rule 5 for one session, and the app was
> built fresh, launched, and driven through every screen against the live agent and real
> pipeline data. Findings are in [OBSERVED.md](OBSERVED.md); the screenshots are committed
> in [screens/](screens/).
>
> Everything this document originally asked for in Tiers 1 and 2 has been captured, and both
> design questions have since been answered by the user. **Nothing here blocks
> implementation.** What remains is one optional nice-to-have (§"Still worth capturing") and
> the inspiration ask below, which would improve V2.4 but doesn't gate it.

---

## Answered by the observation pass

| Original ask | Answer |
|---|---|
| Monitor resolution and scaling | **2560 × 1600 @ 150%** |
| The real window size | **1253 × 1013 logical**, content ≈ **1168 × 973** — landscape, not tall/narrow. Corrected in OBSERVED §1 and patched through SCREENS.md |
| All seven screens at real size | `screens/01`–`07` |
| Library at real zoom, with real thumbnails | `screens/05-library.png` (portrait) and `screens/08-library-rowcrops.png` (strips) — which surfaced the per-folder aspect-ratio defect, OBSERVED §3 |
| Services terminal with real ANSI | `screens/04-services.png` — output is monochrome, so the light terminal palette is safe (THEMES §8) |
| Live mid-run | `screens/03-live.png` — entity-ingest, real run. The 420px column was ~95% empty |
| Insights, all tabs | `screens/06-insights.png` |

## Still worth capturing later

- **Live during a real `entity-scrape` run.** The capture caught entity-ingest, which
  produces one small card. Scrape produces ~20 portrait composites and is what the card
  widths must actually be tuned against. Not blocking — grab it whenever a scrape happens
  to be running, before **V2.8**.
- **Notification center, open, with real notifications.** Not captured; it's a popover that
  needs a click on the bell. Before **V2.5**.

---

## What screenshots cannot answer — these still need you

### 1. ⭐ Any app whose look you want this to have

The single most useful thing you can still give me. Screenshots of anything — Grafana,
Linear, Raycast, a game launcher, a synth UI, a website, a poster, one of the design
inspirations you listed.

[THEMES.md](THEMES.md) proposes six themes reasoned from what a control center needs. What
you personally find good-looking is not derivable from source or from screenshots of the
current app. If two of the six are close and one isn't, knowing that before **V2.4** saves
building the wrong one.

### 2. What currently annoys you

Not a screenshot — a list. "X always takes two clicks", "I can never find Y", "the Z number
is meaningless to me."

The audit found structural problems by reading code and the observation pass found visual
ones by looking. Neither can find **friction**, and friction is what an overhaul should be
aimed at. If any of it contradicts [SCREENS.md](SCREENS.md), your version wins.

### 3. How you actually review a batch today

Roughly how long does reviewing ~50 images take, and what's the real sequence of clicks?
This shapes review mode's keyboard map (SCREENS §5b) more than any screenshot can — it's
the difference between designing for what I think the job is and what it actually is.

---

## ✅ Both design decisions answered (2026-08-04)

### A. Double-click in the Library grid — **lightbox**

The user doesn't use double-click at all, so repurposing it costs nothing. Copy-id moves to
the right-click menu, where it already exists (`library_tile.dart:58`), and double-click
opens the large single-image view. Plain click / Space / arrows / Shift-range are untouched
(D48). See SCREENS §5c.

### B. Default theme on first launch — **Classic**

v2.0.0 opens in Classic, so nothing changes visually until the user picks another theme from
the new Appearance tab. See THEMES §1.

---

## Repeating the capture

Rule 5 remains in force by default; it was lifted for one session by explicit request. If
you want another pass, say so and the method in OBSERVED §"How these were captured" makes it
about five minutes: `flutter clean` → dart-MCP `launch_app` on `windows` → Win32 clicks at
logical `x = 40, y = 65 + 64n` for the nav rail → `Graphics.CopyFromScreen` per screen.

Two gotchas worth remembering:

- `launch_app` returns the **`flutter run` host pid**, not the window's. The real window
  belongs to a child `ia_control_center.exe` — find it with `Get-Process`.
- `flutter_driver` is unavailable: the app never calls `enableFlutterDriverExtension()`.
  Adding a `driver_main.dart` entrypoint would make future passes far more precise than
  coordinate clicking, and is worth doing if this happens more than once.
