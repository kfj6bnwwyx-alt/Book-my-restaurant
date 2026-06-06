# ResyBooker — handoff / current state

Continuation notes for picking this up on another machine (e.g. a MacBook).

## TL;DR

The **backend is live** on Home Assistant at `https://resy.brentbrooks.com`,
authenticating to Resy, with availability, drops, watches, and auto-book all
running. The **iOS app is partially built**; the remaining work is in Xcode:
point it at the server and build the screens that aren't coded yet.

## Live deployment

- Runs as a **Home Assistant local add-on** (`home-assistant/resybooker/`) on the
  HA OS box (a `linux/arm64` machine, e.g. Green/Yellow/Pi), data center `ewr`.
- Public URL: **`https://resy.brentbrooks.com`** via the Cloudflare tunnel named
  **home-assistant** → Published application route `resy.brentbrooks.com` →
  `http://local-resybooker:8080` (the add-on's internal hostname).
- Manage it: **HA → Apps → ResyBooker** (Log / Configuration / Rebuild tabs).
- **Deploy a change:** push to `main`, then on HA: Apps → ResyBooker → ⋮ →
  **Rebuild**. The Dockerfile cache-busts and re-clones `main` (repo is public, so
  no auth needed on the box).
- Health check: `curl https://resy.brentbrooks.com/health`.

## Config and secrets

- **app_key**: lives in the add-on **Configuration** tab (`app_key`). NOT in the
  repo (the repo is public). The same value must go in the iOS app's
  `Constants.swift` `appKey` and in any `X-App-Key` header. Read it from the HA
  add-on config when you need it; rotate by generating a new random string and
  updating both places.
- **resy_email / resy_password**: in the add-on config. The server logs in and
  auto-refreshes the Resy token from these (a browser-like header set is required,
  already handled in `server/app/resy.py`).
- **resy_payment_method_id**: `17474744` (amex ending 3001).
  ⚠️ **That card is expired (12/2025).** Availability, drops, and watches work,
  but the final **booking step will be rejected by Resy** until you add a current
  card at resy.com, then `GET /resy/payment-methods` again for the new id and
  update the config.
- **Database**: SQLite on the add-on's persistent `/data` volume. To wipe it,
  delete `/data/resybooker.db` or uninstall the add-on (clears `/data`); the
  schema (pins, bookings, drops, watches) is recreated on next start.

## Repo layout

- `server/` — FastAPI backend. `app/`: `main` (routes), `config`, `db` (SQLModel),
  `resy`, `opentable`, `matching`, `drops`, `scheduler` (in-process worker),
  `watches`. Docker + `Caddyfile` for the VPS path.
- `ios/ResyBooker/` — SwiftUI app. `DesignSystem/` has tokens + state components
  (built). Feature screens are partial (see Next steps).
- `home-assistant/` — the HA add-on (`resybooker/`) and `README.md` (the actual
  deployment path in use).
- `DEPLOY.md` — Hetzner VPS path, plus a pointer to the HA path.
- `PRODUCT.md` / `DESIGN.md` — strategic + visual design system.
- `docs/design-notes.md` — Pencil design-file notes (screen inventory, component
  ids, gotchas).

## Backend features (all live)

- `GET /availability` — check every linked spot at once for a date/time/party.
- `GET/POST /pins`, `/pins/import`, `/pins/{id}/candidates`, `/pins/{id}/link`.
- `POST /book` — one-tap Resy booking.
- `GET/POST/PATCH/DELETE /drops`, `/drops/{id}/window`, `/reserve`, `/run`,
  `/runs` — venues that release tables on a schedule (daily/weekly/biweekly/
  monthly), full-window view, multi-select reserve, and auto-book at release time.
- `GET/POST/PATCH/DELETE /watches`, `/watches/{id}/check` — poll one venue/date
  until a table appears, then notify or auto-book.
- The scheduler (`scheduler.py`) runs in-process; **run a single uvicorn worker**.
- Full endpoint list: `server/app/main.py` docstring and `server/README.md`.

## Design

- ~38 screens designed in Pencil at `Pen/Book-my-restaurant` (open via the Pencil
  MCP; if you have OneDrive synced on the Mac the file comes with it). The system
  is fully captured in `DESIGN.md`; the screen list and component ids are in
  `docs/design-notes.md`.
- Two-accent system: **orange = action/selection**, **green = vital status only**.
  Cool-tinted dark theme.
- The SwiftUI design system (tokens + state components) is already coded in
  `ios/ResyBooker/DesignSystem/` and maps 1:1 to the Pencil components.

## Next steps (on the MacBook)

1. `git clone https://github.com/kfj6bnwwyx-alt/Book-my-restaurant.git`.
2. Open the iOS app in Xcode (create the project and add the sources per
   `SETUP.md`; the `DesignSystem/` group is the foundation to build on).
3. Set `ios/ResyBooker/Utilities/Constants.swift`:
   `apiBaseURL = https://resy.brentbrooks.com`, `appKey =` (from the HA add-on
   config).
4. Add a valid card on resy.com, re-run `GET /resy/payment-methods`, and update
   `resy_payment_method_id` in the add-on config so booking works.
5. Build the iOS screens that aren't coded yet: the **Drops** and **Watches**
   features and the loading/empty/error/success **state screens**. Start from the
   `DesignSystem` components and follow the Pencil designs / `docs/design-notes.md`.
6. Optional: smoke-test the live API end to end (import pins → link → availability)
   with curl before deep app work.
