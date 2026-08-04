# v2.0.0 — UI/UX overhaul

Planning docs for the Insta-Automate Control Center's v2 redesign. Written 2026-08-04 on
branch `feat/v2-ui-overhaul`, against `main` @ `f25210e`.

**The app is functionally complete and correct.** Phases 0–7 are all accepted; every flow,
service, library operation, ops job and insight works. Nothing in v2 is a bug fix. This is
entirely about how the app looks, how it's structured, and how it feels to use for hours at
a time.

---

## The problem, in one paragraph

The app's entire theme is four lines — `useMaterial3`, `brightness: dark`, one
`colorSchemeSeed`, one transparent background (`app.dart:15-21`). None of `ThemeData`'s
~40 component sub-themes are set. So every card, button, chip, field, tab, tooltip and
dialog renders at Material's default, and every deviation from that default has been
hand-coded at the call site over eight phases. The result works well and looks like a
default Flutter app — which is exactly what it is, underneath. Meanwhile three screens
present their data in shapes that hide the most important thing about it: Flows renders a
five-stage pipeline as five disconnected cards with none of the queues between them,
Overview duplicates Flows instead of summarising it, and Library — the daily workhorse
holding 7,655 files — shows images too small to judge and hides its own primary actions
until something is selected.

## The approach

Build a real token layer on Material 3 rather than adopting a component framework. The
insight: **the app doesn't look generic because it uses Material — it looks generic because
it uses Material's defaults.** Filling in those 40 sub-themes from a token set changes the
look completely while every existing layout, and every hard-won overflow fix in it, keeps
working. Then re-architect the three screens whose shape actively hides information.

---

## Read in this order

| # | Doc | What it is |
|---|---|---|
| 0 | **[OBSERVED.md](OBSERVED.md)** | ⭐ What the app **actually looks like** — measured, with committed [screenshots](screens/). Corrects four things the source-only audit got wrong. Read this first. |
| 1 | **[AUDIT.md](AUDIT.md)** | Current-state debt, with file:line evidence for every claim. The "why". |
| 2 | **[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)** | Token architecture, typography, motion doctrine, accessibility floor. The "how". |
| 3 | **[THEMES.md](THEMES.md)** | Six shipping themes with real values, plus the backlog roadmap for the rest of the inspiration list. |
| 4 | **[COMPONENTS.md](COMPONENTS.md)** | The shared `ui/` vocabulary every screen is rebuilt from. |
| 5 | **[SCREENS.md](SCREENS.md)** | Per-screen re-architecture with wireframes. The "what". |
| 6 | **[PLAN_V2.md](PLAN_V2.md)** | Thirteen checkpoints, each a commit boundary with a manual test. |
| 7 | **[VISUAL_INPUTS.md](VISUAL_INPUTS.md)** | Mostly resolved by the observation pass. **Two open questions still need the user's answer.** |

---

## Decisions already taken (don't relitigate)

| Decision | Where |
|---|---|
| Own token layer on Material 3, **not** `shadcn_ui` / `forui` / `fluent_ui` | DESIGN_SYSTEM §0 |
| Add `flutter_animate` + `phosphor_flutter`; nothing else | DESIGN_SYSTEM §0 |
| Bundle Inter + JetBrains Mono as assets; **not** `google_fonts` | DESIGN_SYSTEM §2 |
| Six themes ship: Classic · Command Deck · Nocturne · Mica · Daylight · Swiss | THEMES §1–6 |
| Bento is a **layout pattern** (Overview), not a theme; Glassmorphism is served by Mica; Neumorphism/Claymorphism/Skeuomorphism/Brutalism are argued against, not merely deferred | THEMES §10 |
| Flows becomes a **vertical** pipeline (the screen wastes ~55% of its height; wide nodes hold everything in one row) | SCREENS §2, OBSERVED §7 |
| Live keeps a **horizontal** split, made resizable — ⚠️ reversed after observation | SCREENS §3, OBSERVED §7 |
| Library grid gets a **per-folder cell aspect ratio** — 40–82% of every cell is wasted today | SCREENS §5a-0, OBSERVED §3 |
| `fl_chart` stays on `^0.69.0` through v2.0.0 | PLAN_V2, "what v2 does not do" |
| Default theme on first launch stays Classic | THEMES §1 — *but see VISUAL_INPUTS question B* |

## Scope boundary

> **Everything is inside `app/`.** No agent changes, no pipeline changes, no helm changes,
> no mobile changes. No redeploys, no pod restarts, no cross-repo branches. Every piece of
> data the redesign needs is already served by an existing endpoint.
>
> If a checkpoint appears to need an agent change, it almost certainly doesn't — stop and
> re-check. If it genuinely does, that's a scope decision for the user.

## Protected behaviour

Things that exist because of a real bug, a real user preference, or a real platform
limitation, and must survive v2 intact. Full list in AUDIT's closing section; the ones most
at risk of being "cleaned up" by accident:

- **D48 / `feedback-multiselect-toggle`** — plain click and Space toggle; arrows move focus
  only; no modifier required. A recorded user preference.
- **D84's six `_StatusKind` states** and the cooldown-only countdown rule — hard-won across
  two repos.
- **D77's flexible-column table** and **D78's funnel painter** — both exist because
  Material's stock widgets provably couldn't do the job. Retheme, never revert.
- **`title_bar.dart:93-98`'s faked maximize** — a Win32 caption-glitch workaround, not
  styling.
- **`StatusDot`'s transient pulse** — the one piece of genuinely meaningful motion already
  in the app.
- **Every `maxLines: 1` + `TextOverflow.ellipsis`** — each is a fixed overflow (D87, D89,
  D93).
- **The ten layout tests in `app/test/`** — they encode overflow regressions `flutter
  analyze` cannot see (D19). They must keep passing, and v2 adds more.

---

## For the implementing session

Start with **[PLAN_V2.md](PLAN_V2.md)** and work one checkpoint at a time. Suggested
opening prompt:

> Read `docs/v2/README.md` and everything it links, and look at the screenshots in
> `docs/v2/screens/`. We're on `feat/v2-ui-overhaul`. Implement checkpoint **V2.1** from
> `docs/v2/PLAN_V2.md`. Stop at its checkpoint test and hand over — don't commit until I've
> run it.

Project rules from `CLAUDE.md` apply unchanged. The three that matter most here:

- **Rule 4** — the checkpoint test happens *before* the commit. `flutter analyze` +
  `flutter test` are part of that gate; overflow is a paint-time error both are otherwise
  blind to.
- **Rule 5** — the user drives the app. Build it, analyze it, test it, start it, then stop
  and hand over with a specific list of what to check. Never click or screenshot it.
- **Rule 7** — no compromise on UI/UX.

One checkpoint per session is the right granularity for Sonnet. V2.3 (the 90-file
migration) may need two, and splits cleanly by feature directory.

Record decisions in `docs/DECISIONS.md` as they're made, continuing the `D` numbering —
**next is D94**.
