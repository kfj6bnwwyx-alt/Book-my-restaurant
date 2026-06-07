# ResyBooker — Plan / backlog

Living checklist of what's done, what's pending, and the setup steps that need
you. Tell Claude "add X to the plan" any time and it lands here.

## Branches & deploy
- **iOS app** lives on branch **`ios-design-buildout`** (not merged to `main`, not pushed). Build locally with ⌘R.
- **Server** deploys from **`origin/main`** → the HA add-on re-clones `main` on **Rebuild**.
  Latest server on main: CSV import + NYC candidate fallback + `PATCH /pins/{id}` (`6a3c548`).
- **After any server change: HA → Apps → ResyBooker → ⋮ → Rebuild.**

## Done
- [x] Dark design system + floating 3-tab shell (Tables / Drops / Spots)
- [x] Tables: search summary + editor, AVAILABLE / NO TABLES, all states
- [x] Spots: dark list, Link Venue (provider toggle + scored candidates)
- [x] Drops: overview, live countdown, two-week grid + multi-select reserve, create-drop, auto-book setup
- [x] Booking: Confirm → Securing → Confirmed / Failed
- [x] App key in **Keychain**, entered in-app, **verified on save** (distinguishes "no key" vs "rejected 401")
- [x] Import: GeoJSON **and** Google Takeout **CSV** (names-only; matches near NYC) — bulk import moved into **Settings**
- [x] **Add a spot** via Apple Maps autocomplete (search-to-add), exact coordinates
- [x] **Spots map** (MapKit): linked/unlinked pins, tap to Link / open Maps / Resy
- [x] **Resolve missing locations** (Settings): backfills coordinates for name-only spots
- [x] **Share-to-app** extension code (`ShareToResyBooker`) — queues shared places via App Group

## Needs you (setup)
- [ ] **Rebuild the HA add-on** to activate CSV import + resolve-locations endpoint
- [ ] **Share extension App Group**: add `group.house-connect.Book-my-restaurant` to BOTH targets (app + ShareToResyBooker), then ⌘R
- [ ] **Open `design/Book-my-restaurant.pen` in Pencil** so Claude can align the design to the app (MCP only edits the open file)
- [ ] **Replace the expired Resy card** (Amex …3001, exp 12/2025): add a current card at resy.com → `GET /resy/payment-methods` → update `resy_payment_method_id` in the add-on config. Until then the final **booking step fails** (availability/drops/watches work).

## Not built yet
- [ ] **Align the Pencil file** to the app (blocked on opening the .pen): Spots header (+/map/gear), Add-a-spot search, Settings menu, Spots map, "App key rejected" state
- [ ] **Watches** feature (server endpoints exist; no iOS UI)
- [ ] **Onboarding** first-run flow
- [ ] Merge `ios-design-buildout` → `main` / push when ready

## Known quirks
- **OneDrive** keeps resurrecting the old `Book my restaurant/` folder and shuffling the `.pen` files — delete the stray folder if it returns; the real design is `design/Book-my-restaurant.pen`.
- **Non-NYC spots** (London/SF/etc.) get poor Resy candidates — Resy is NYC-centric and search defaults to NYC.
- **Google has no API** for saved lists; Takeout CSV + share-to-app are the only paths in.
