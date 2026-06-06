# ResyBooker

Personal Resy/OpenTable reservation tool: a FastAPI server (`server/`) plus a
SwiftUI iOS app (`ios/`). Checks availability across your saved spots, books in
one tap, tracks scheduled reservation "drops", and polls specific venues until a
table appears.

> **Picking this up / current state:** read **[HANDOFF.md](HANDOFF.md)** first. It
> covers the live deployment, config, and what's left to do.
>
> **Deploying:** Home Assistant add-on (in use) → [home-assistant/README.md](home-assistant/README.md).
> Hetzner VPS path → [DEPLOY.md](DEPLOY.md). Server API → [server/README.md](server/README.md).
> Design system → [DESIGN.md](DESIGN.md) / [docs/design-notes.md](docs/design-notes.md).

---

## ResyBooker server

Personal-use back end that fronts the Resy and OpenTable unofficial APIs behind
your own clean JSON API. Runs on your Hetzner VPS in Docker, fronted by Caddy
for TLS at e.g. resy.brentbrooks.com.

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

## Notes

- All endpoints except /health require the `X-App-Key` header.
- Token refresh is automatic on 401 if email/password are set.
- If Resy responses start 400ing, the public RESY_API_KEY may have rotated;
  grab the current one from the resy.com web app and update .env.
- OpenTable is availability-only by design. Booking goes through Resy.
