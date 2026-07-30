# MEMORY.md

Durable facts and decisions for this project. One line per entry, newest last.
Full context lives in [CLAUDE.md](CLAUDE.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
[docs/PLAN.md](docs/PLAN.md), and [docs/DECISIONS.md](docs/DECISIONS.md).

- **Context files stay in the repo** — `CLAUDE.md`, `MEMORY.md` and `docs/` never go anywhere
  else on the filesystem. User rule, applies to every session.
- **Other repos are feature-branch only** — `Insta-Automate`, `Insta-Automate-Client` and
  `Helmcharts` all work today; changes go on `feat/control-center` (or `feat/lan-agent`) and are
  never merged until the control center is accepted.
- **Architecture** — Flutter Windows app (`app/`) + Python `ia-agent` (`agent/`) in one repo; the
  agent is the Windows startup entry and owns service lifetime. See DECISIONS D1.
- **The scheduler is one file** — every hardcoded delay and trigger gate lives in
  `Insta-Automate/src/insta_automate/controllers/prefect.py`.
- **Two human gates** — `gender_valid → scrape_queued` and `scraped → follow_queued` are manual
  moves; they are the pipeline's real bottleneck and the reason the desktop gets curation parity.
- **Committed secrets** — `Insta-Automate/Dockerfile` holds the Postgres password, the Telegram
  bot token and two Telethon session strings in plaintext; `ia build` regenerates it, so it never
  needed committing. Rotation pending (PLAN Q10).
