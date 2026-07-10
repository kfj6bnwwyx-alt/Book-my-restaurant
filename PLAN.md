# ResyBooker — Plan / backlog

Living checklist of what's done, what's pending, and the setup steps that need
you. Tell Claude "add X to the plan" any time and it lands here.

## Branches & deploy
- **`ios-design-buildout` is merged to `main`** (PR #1, Jul 2026) — everything now lives on `main`; the branch is kept in sync with it. Build locally with ⌘R.
- **Server** deploys from **`origin/main`** → the HA add-on re-clones `main` on **Rebuild**.
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
- [x] **Pencil design aligned to the app**: 2-row day grids, Spots header (+/map/gear), and new screens (Settings, Add-a-spot search, Spots map, App-key-rejected) + critique fixes (amber countdown, type scale, link color, dash markers, text-muted token)
- [x] **City constraint on Add-a-spot**: persisted city geocoded + `regionPriority = .required` so search only returns venues in that metro (no wrong-city matches)
- [x] **Stand-in app icon**: orange fork-and-knife, light/dark/tinted appearances
- [x] **Remove potentials** (UX critique P1): swipe-to-delete + multi-select bulk delete on Spots, **Unlink** a linked spot, **"Not a match"** dismisses a candidate so it never resurfaces (`rejected_venues` persisted server-side)
- [x] **Restaurant across dates** (UX critique P1): per-venue 14-day availability view, party stepper, tap a night to book — reachable from a linked Spot **and** from a Tables result (calendar button, incl. the no-tables card)
- [x] **"Server out of date" error**: a FastAPI default 404 on `/availability/window` now explains the HA rebuild fix instead of a raw "Server 404"
- [x] **Watches** (iOS UI for the existing server endpoints): section on the Drops tab with status badges (watching/paused/found/booked/expired/error), detail view (check now, pause/resume, edit, remove), create sheet (night, party, time window, poll interval, notify/auto-book + deposit warning). Entry points: Drops tab, binoculars button on the per-restaurant dates view, and "Watch for a table" on its sold-out empty state. Resy only (server constraint).
- [x] **Onboarding** first-run flow: 3 dark pages (welcome → three tabs → connect server), skippable, shown once; devices that already have a key never see it
- [x] **Bug fix: reserve results said "Failed" on success** — the server returns `confirmed`/`taken`/`failed` per slot but the iOS ReserveResultSheet matched on `booked`, so every successful multi-select booking rendered red. iOS now matches the server strings.
- [x] **Bug fix: "tonight" vanished after ~8 PM ET** — `/availability/window` used naive `date.today()` in a UTC container, so the 14-day window started tomorrow during the app's core evening use. Now computed in America/New_York. **Fix is on `ios-design-buildout`; it reaches the live server only after merge to `main` + HA Rebuild.**
- [x] **Bug fix: share-import no longer pins failed geocodes to downtown Manhattan** — a shared place that can't be geocoded now imports name-only (lat/lng 0) so "Resolve missing locations" backfills it.
- [x] **Search-to-add from Resy/OpenTable**: Add-a-spot now searches the booking providers directly (`GET /venues/search`) and creates born-linked pins (`POST /pins`, dedupes on provider+venue). Apple Maps demoted to a fallback section (adds unlinked). Server has its first pytest suite (`server/tests/`).
- [x] **Clear unlinked spots** (Settings): `POST /pins/clear-unlinked` deletes all import noise in one call, linked spots kept.

## Needs you (setup)
- [ ] **Rebuild the HA add-on** — *do this again*: `main` now has the timezone fix for `/availability/window` (PR #1). HA → Apps → ResyBooker → ⋮ → Rebuild. Verified locally; the live server still runs the pre-merge build until this. Once the search-to-add branch merges, the rebuild also picks up `GET /venues/search`, `POST /pins`, `POST /pins/clear-unlinked` — until then the add sheet shows the out-of-date notice and Settings clear fails.
- [x] ~~Rebuild for pin delete/unlink/reject + `GET /availability/window`~~ — done (routes confirmed live).
- [x] **Open `design/Book-my-restaurant.pen` in Pencil** — done; design aligned to the app
- [x] **Share extension App Group**: added `group.house-connect.Book-my-restaurant` to both targets (entitlements wired)
- [x] **Resy card is fine** — the Amex …3001 was reissued past its printed 12/2025 expiry and the stored card still works in Resy (user-confirmed, Jul 2026). Same `resy_payment_method_id`, no config change needed. Booking is not blocked.

## Not built yet
- [ ] **Pencil design screens for Watches + Onboarding** (built app-first; align the .pen when Pencil is open next)
- [x] Merge `ios-design-buildout` → `main` / push when ready — **done (PR #1)**
- [ ] Watch notifications surface (server sets `notify`; how alerts reach the phone — HA notification? push? — is undecided)
- [ ] **Release radar** (venue-level watch): poll a restaurant's whole booking horizon on a slow interval and alert when *new days* become bookable — catches unannounced "new bank opened" moments that Watches (one fixed date) and Drops (known schedule) don't cover. Server has all the pieces (scheduler loop, `resy.find` fan-out, Watch as the model template). Depends on the notifications surface to be truly passive.
- [ ] Reservations list in-app (`BookingRecord` is logged server-side but there's no `GET /bookings`, no history screen, no add-to-calendar, no cancel)
- [ ] Surface auto-book run history (`GET /drops/{id}/runs` exists; nothing in the app calls it)

## Known quirks
- **OneDrive** keeps resurrecting the old `Book my restaurant/` folder and shuffling the `.pen` files — delete the stray folder if it returns; the real design is `design/Book-my-restaurant.pen`.
- **Non-NYC spots** (London/SF/etc.) get poor Resy candidates — Resy is NYC-centric and search defaults to NYC.
- **Google has no API** for saved lists; Takeout CSV + share-to-app are the only paths in.
