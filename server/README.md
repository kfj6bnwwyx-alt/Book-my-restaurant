# ResyBooker server

Personal-use back end that fronts the Resy and OpenTable unofficial APIs behind
your own clean JSON API. Runs on your Hetzner VPS in Docker, fronted by Caddy
for TLS at e.g. resy.brentbrooks.com.

For full VPS provisioning (Hetzner server, cloud-init, Caddy, DNS), see
[../DEPLOY.md](../DEPLOY.md). The quick version is below.

## First run

1. `cp .env.example .env` and fill it in.
   - `APP_KEY`: `openssl rand -hex 24` — paste the same value into the iOS app.
   - `RESY_AUTH_TOKEN`: from a logged-in resy.com session (DevTools > Network >
     any api.resy.com call > X-Resy-Auth-Token header). Or set RESY_EMAIL /
     RESY_PASSWORD and the server mints + refreshes the token itself.
   - `RESY_PAYMENT_METHOD_ID`: start the server, call
     `GET /resy/payment-methods` with your X-App-Key, copy the id of the card
     you want to book with.
2. `docker compose up -d --build`
3. Caddy reverse proxy (Caddyfile):
   ```
   resy.brentbrooks.com {
       reverse_proxy 127.0.0.1:8080
   }
   ```
   Add an A/AAAA record for resy.brentbrooks.com in Pair Domains DNS to the VPS.

## Bootstrapping data

1. Google Takeout > Saved > export your lists as GeoJSON.
2. POST the GeoJSON text to `/pins/import`.
3. For each pin, `GET /pins/{id}/candidates?provider=resy`, pick the right
   venue, `POST /pins/{id}/link`.
4. `GET /availability?day=2026-06-12&party_size=2` returns who has tables.
5. `POST /book` with a slot's config_token to reserve.

## Drops

Some venues release their tables in scheduled tranches ("drops"), e.g. every two
weeks at noon for a two-week window. A drop tracks one venue's schedule, exposes
the entire release window for hand-picking, and can auto-book the instant it opens.

- `POST /drops` to track one. Resy only. Body:
  ```json
  {
    "venue_id": "12345", "venue_name": "Ambassador's Clubhouse", "pin_id": 7,
    "cadence": "biweekly", "anchor_date": "2026-06-18", "release_time": "12:00",
    "window_days": 14, "timezone": "America/New_York"
  }
  ```
  `cadence` is `daily` | `weekly` (set `release_weekday` 0=Mon..6=Sun) |
  `biweekly` (set `anchor_date`, a known release date) | `monthly` (set
  `release_dom` 1..28). `release_time` is local to `timezone`.
- `GET /drops` lists them with a computed `status` (open / upcoming),
  `next_release`, and `opens_in_seconds` for the countdown.
- `GET /drops/{id}/window?party_size=2` returns every day in the window with all
  its times, for the grid.
- `POST /drops/{id}/reserve` books a hand-picked set:
  `{ "party_size": 2, "slots": [{ "config_token": "...", "day": "2026-06-20" }] }`.
- `PATCH /drops/{id}` arms and configures auto-book:
  ```json
  {
    "autobook_enabled": true, "ab_party_size": 2, "ab_days": "Fri,Sat,Sun",
    "ab_earliest": "17:00", "ab_latest": "21:00", "ab_max": 1, "ab_priority": "prime"
  }
  ```
  A background worker then grabs the best matches within ~1s of the next release.
- `POST /drops/{id}/run` triggers auto-book now (useful for testing).
  `GET /drops/{id}/runs` shows recent run outcomes.

## Watches

A drop is for scheduled releases. A watch is for everything else: poll one venue
for a specific date and time window until a table appears (e.g. a cancellation),
then notify or auto-book. Resy only.

- `POST /watches`:
  ```json
  {
    "venue_id": "12345", "venue_name": "4 Charles Prime Rib", "pin_id": 9,
    "day": "2026-06-20", "party_size": 2, "earliest": "18:00", "latest": "21:00",
    "autobook": true, "interval_seconds": 60, "timezone": "America/New_York"
  }
  ```
  The worker polls every `interval_seconds` (floored at 20s). With `autobook`
  true it grabs the first matching table; otherwise it flips `status` to `found`
  and stops. A watch expires once its `day` is in the past.
- `GET /watches` lists them with `status` (watching / found / booked / expired /
  error) and `last_checked`.
- `PATCH /watches/{id}` to pause (`active:false`), resume, or retune the window.
- `POST /watches/{id}/check` polls once now (for testing).

## Notes

- All endpoints except /health require the `X-App-Key` header.
- Token refresh is automatic on 401 if email/password are set.
- If Resy responses start 400ing, the public RESY_API_KEY may have rotated;
  grab the current one from the resy.com web app and update .env.
- OpenTable is availability-only by design. Booking and drops go through Resy.
- The background worker (drop auto-book + watch polling) runs in-process and
  dedupes per release cycle, so run a single uvicorn worker (the default here).
  Multiple workers would each run the scheduler and could double-book. Drop and
  watch schedules are evaluated in each record's own `timezone`.
