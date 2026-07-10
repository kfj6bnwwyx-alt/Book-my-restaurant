# Provider search-to-add + unlinked-spot cleanup — design

**Date:** 2026-07-10 · **Status:** approved (user, this session)

## Problem

The Spots list is dominated by the bulk Google Takeout import — hundreds of
unlinked pins, most of them noise. Adding a restaurant today means Apple Maps
search → import as unlinked pin → open it → pick a provider → link a candidate.
The user wants to add restaurants through a search that surfaces real bookable
venues directly, and to clear out the imported noise.

## Decisions (user-approved)

1. **Search Resy/OpenTable directly.** Results are bookable venues; a picked
   result creates a pin that is *born linked* (provider + venue_id set). No
   separate Link step.
2. **Keep Apple Maps as a fallback** inside the same sheet, for places not on
   Resy/OpenTable. Those add unlinked pins, as today.
3. **Bulk-clear unlinked spots** — one destructive action (with count +
   confirmation) that deletes every pin with no venue link. Linked spots
   untouched. Re-adding is cheap via the new search.

## Server (FastAPI, `server/app/main.py`)

### `GET /venues/search`
Query params: `q` (required), `provider` (`resy` | `opentable`, default
`resy`), `lat` / `lng` (optional geo bias, default NYC — same defaults as the
existing client functions).

Thin wrapper over the existing `resy.search_venues()` /
`opentable.search_restaurants()`. Returns the provider's own relevance order
(no re-ranking):

```json
[{ "venue_id": "1234", "name": "Carbone", "locality": "New York",
   "lat": 40.72, "lng": -73.99 }]
```

OpenTable results carry `city` as `locality`; fields absent from a provider are
`null`. Provider errors surface through the existing `ResyError` /
`OpenTableError` exception handlers (502 with a message).

### `POST /pins`
Body: `{ name, address?, lat, lng, provider, venue_id }`. Creates a pin with
`provider`, `venue_id`, `linked_name = name`, `linked_at = now` set — born
linked. **Dedupe:** if a pin with the same `(provider, venue_id)` exists,
return that pin (200, `"existing": true`) instead of duplicating. Response is
the pin in the same shape as `GET /pins` items.

### `POST /pins/clear-unlinked`
Deletes every pin where `venue_id IS NULL`. Returns `{ "deleted": <count> }`.
POST (not DELETE with query flags) so it can never be confused with
`DELETE /pins/{id}`.

## iOS

### Rework `AddSpotSheet` (`Features/Pins/Views/AddSpotSheet.swift`)
- Keep the persisted city field; its geocoded center becomes the `lat`/`lng`
  bias for `/venues/search` **and** the Apple Maps region constraint (as
  today).
- Add a Resy / OpenTable provider toggle (same pattern as LinkPinView). Resy
  default.
- Single search field, debounced ~300 ms, cancels in-flight requests. Results
  in two sections:
  - **Bookable on <provider>** — rows from `/venues/search`: name + locality,
    provider glyph. Tap → `POST /pins` → toast "Spot added — linked to Resy"
    → dismiss.
  - **Apple Maps (adds unlinked)** — up to 3 autocomplete completions from the
    existing `LocalSearch`, plus the "Add “query” as-is" row. Tap → existing
    GeoJSON-import path, unchanged.
- If `/venues/search` 404s (live server predates the endpoint), show the
  existing friendly "server out of date → rebuild the HA add-on" message; the
  Apple Maps section still works in that state.

### Settings sheet: "Clear unlinked spots"
- Destructive row next to bulk import. Shows a confirmation dialog with the
  live count ("Delete 212 unlinked spots? Linked spots are kept.") sourced
  from `PinsViewModel.pins`; calls `POST /pins/clear-unlinked`; reloads;
  toast with the deleted count.
- Hidden when there are no unlinked spots.

### APIClient additions
`searchVenues(query:provider:lat:lng:)`, `createLinkedPin(_:)`,
`clearUnlinkedPins()` — same request/decode helpers, same error mapping as the
rest of the client.

## Not changing
Bulk import (CSV/GeoJSON), LinkPinView (still used by pins that arrive
unlinked via import/share/Apple-Maps fallback), swipe-to-delete and
multi-select delete, the Spots map, share extension.

## Error handling
- Provider search failures → inline error in the sheet; Apple Maps section
  unaffected.
- `POST /pins` duplicate → treated as success (the spot exists and is linked).
- Clear-unlinked failures → existing error alert; list reloads regardless.

## Testing
- Server: exercise the three endpoints against a local run (search both
  providers, dedupe on POST /pins, clear-unlinked leaves linked pins).
- iOS: build; manual pass — search/add on both providers, fallback add,
  server-out-of-date state, clear-unlinked confirm + count.

## Rollout
Server half is live only after merge to `main` + HA add-on **Rebuild** (same
pending step as the timezone fix). Note in PLAN.md.
