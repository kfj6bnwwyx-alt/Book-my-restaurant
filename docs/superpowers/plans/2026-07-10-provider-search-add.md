# Provider Search-to-Add + Clear-Unlinked Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add restaurants by searching Resy/OpenTable directly (spots arrive already linked), keep Apple Maps as a fallback, and add a one-tap "clear unlinked spots" cleanup for the noisy Google Maps import.

**Architecture:** Three small FastAPI endpoints wrap the existing `resy.search_venues()` / `opentable.search_restaurants()` functions and the `Pin` model. The iOS `AddSpotSheet` is reworked to query the new search endpoint (debounced) with the existing Apple-Maps completer demoted to a fallback section. A destructive "Clear unlinked spots" row lands in the Spots Settings sheet.

**Tech Stack:** FastAPI + SQLModel (server, `server/`), SwiftUI + actor-based `APIClient` (iOS, `ios/ResyBooker/`). New: pytest + fastapi TestClient for the server.

**Spec:** `docs/superpowers/specs/2026-07-10-provider-search-add-design.md`

## Global Constraints

- Work happens on branch `ios-design-buildout` (repo convention; PRs to `main`).
- Server JSON is snake_case; iOS DTOs map via `CodingKeys` (see `ios/ResyBooker/Models/DTOs.swift`).
- All new endpoints require the app key: `dependencies=[Depends(require_key)]`.
- Providers are the strings `"resy"` and `"opentable"` everywhere.
- iOS: unlocated spots use the `lat == 0 && lng == 0` convention ("Resolve missing locations" backfills them). Keep it.
- iOS 404 with FastAPI default body = stale server → show the "rebuild the HA add-on" guidance (`APIError.isMissingEndpoint`).
- iOS design system: `RBColor`/`RBSpacing`/`RBRadius`/`.rbCard()`; match existing view style.
- Commit after every task; messages in the repo's imperative style, ending with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Server test harness + `GET /venues/search`

**Files:**
- Create: `server/tests/__init__.py` (empty)
- Create: `server/tests/conftest.py`
- Create: `server/tests/test_venue_search.py`
- Modify: `server/app/main.py` (new endpoint after `reject_candidate`, ~line 318; docstring endpoint list at top)

**Interfaces:**
- Consumes: `resy.search_venues(query, lat, lng)`, `opentable.search_restaurants(term, lat, lng)` (existing).
- Produces: `GET /venues/search?q=&provider=&lat=&lng=` → JSON array of `{venue_id, name, locality, lat?, lng?, url_slug?}` (provider order, no re-ranking). Test fixtures `client`, `auth` reused by Tasks 2–3.

- [ ] **Step 1: Create the test environment**

```bash
cd /Users/brentbrooks/Code/Book-my-restaurant/server
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt pytest
```

Add `.venv/` and `test_resybooker.db` to `.gitignore` if not already ignored (check repo root `.gitignore`).

- [ ] **Step 2: Write conftest + failing test**

`server/tests/conftest.py`:

```python
import os

# Must be set before importing app modules: config reads env at import and
# db.py creates the engine from DB_URL at import.
os.environ["APP_KEY"] = "test-key"
os.environ["DB_URL"] = "sqlite:///./test_resybooker.db"

import pytest
from fastapi.testclient import TestClient
from sqlmodel import SQLModel

from app import scheduler
from app.db import engine
from app.main import app

AUTH = {"X-App-Key": "test-key"}


@pytest.fixture()
def client(monkeypatch):
    # Don't start the background polling loop in tests.
    monkeypatch.setattr(scheduler, "start", lambda: None)
    with TestClient(app) as c:
        yield c


@pytest.fixture(autouse=True)
def clean_db():
    SQLModel.metadata.create_all(engine)
    yield
    with engine.begin() as conn:
        for table in reversed(SQLModel.metadata.sorted_tables):
            conn.execute(table.delete())


@pytest.fixture()
def auth():
    return AUTH
```

`server/tests/test_venue_search.py`:

```python
from app import main as main_module

RESY_HIT = {
    "venue_id": "101", "name": "Carbone", "url_slug": "carbone",
    "locality": "New York", "lat": 40.72, "lng": -73.99,
}
OT_HIT = {"venue_id": "202", "name": "Carbone", "locality": "New York"}


def test_search_resy(client, auth, monkeypatch):
    async def fake(query, lat=40.7128, lng=-74.006):
        assert query == "carbone"
        return [RESY_HIT]

    monkeypatch.setattr(main_module.resy, "search_venues", fake)
    r = client.get("/venues/search", params={"q": "carbone"}, headers=auth)
    assert r.status_code == 200
    assert r.json() == [RESY_HIT]


def test_search_opentable(client, auth, monkeypatch):
    async def fake(term, lat=40.7128, lng=-74.006):
        return [OT_HIT]

    monkeypatch.setattr(main_module.opentable, "search_restaurants", fake)
    r = client.get(
        "/venues/search",
        params={"q": "carbone", "provider": "opentable"},
        headers=auth,
    )
    assert r.status_code == 200
    assert r.json() == [OT_HIT]


def test_search_requires_key(client):
    r = client.get("/venues/search", params={"q": "carbone"})
    assert r.status_code == 401


def test_search_requires_query(client, auth):
    r = client.get("/venues/search", headers=auth)
    assert r.status_code == 422
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd server && .venv/bin/pytest tests/test_venue_search.py -v`
Expected: FAIL — 404 (route doesn't exist) on the first two, `test_search_requires_key` may fail with 404 vs 401.

- [ ] **Step 4: Implement the endpoint**

In `server/app/main.py`, after `reject_candidate` (before the `# ---------- availability fan-out ----------` divider):

```python
# ---------- venue search (search-to-add) ----------


@app.get("/venues/search", dependencies=[Depends(require_key)])
async def venues_search(
    q: str = Query(..., min_length=1),
    provider: str = Query("resy"),
    lat: float = Query(40.7128),
    lng: float = Query(-74.006),
):
    """Free-text venue search on a booking provider. Results are bookable
    venues in the provider's own relevance order; the app adds one as a
    born-linked pin via POST /pins."""
    if provider == "resy":
        return await resy.search_venues(q, lat, lng)
    return await opentable.search_restaurants(q, lat, lng)
```

Also add to the module docstring endpoint list (after the `/pins` block):

```
  GET    /venues/search              free-text provider venue search (search-to-add)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd server && .venv/bin/pytest tests/test_venue_search.py -v`
Expected: 4 passed.

- [ ] **Step 6: Commit**

```bash
git add server/tests server/app/main.py .gitignore
git commit -m "server: GET /venues/search + pytest harness"
```

---

### Task 2: Server `POST /pins` — create a born-linked pin

**Files:**
- Modify: `server/app/main.py` (body model in the schemas section ~line 95; endpoint after `import_pins`; docstring list)
- Create: `server/tests/test_create_pin.py`

**Interfaces:**
- Consumes: `Pin` model (`app/db.py`), fixtures from Task 1.
- Produces: `POST /pins` body `{name, address?, lat, lng, provider, venue_id}` → pin JSON in the `GET /pins` item shape plus `"existing": bool`. iOS Task 4 decodes this as `PinDTO` (extra key ignored).

- [ ] **Step 1: Write the failing test**

`server/tests/test_create_pin.py`:

```python
BODY = {
    "name": "Carbone", "address": "New York", "lat": 40.72, "lng": -73.99,
    "provider": "resy", "venue_id": "101",
}


def test_create_pin_is_born_linked(client, auth):
    r = client.post("/pins", json=BODY, headers=auth)
    assert r.status_code == 200
    pin = r.json()
    assert pin["linked"] is True
    assert pin["provider"] == "resy"
    assert pin["venue_id"] == "101"
    assert pin["existing"] is False

    listed = client.get("/pins", headers=auth).json()
    assert len(listed) == 1 and listed[0]["linked"] is True


def test_create_pin_dedupes_on_provider_venue(client, auth):
    first = client.post("/pins", json=BODY, headers=auth).json()
    again = client.post("/pins", json={**BODY, "name": "Carbone NYC"}, headers=auth)
    assert again.status_code == 200
    assert again.json()["id"] == first["id"]
    assert again.json()["existing"] is True
    assert len(client.get("/pins", headers=auth).json()) == 1


def test_create_pin_defaults_coordinates_to_zero(client, auth):
    r = client.post(
        "/pins",
        json={"name": "Dept of Culture", "provider": "resy", "venue_id": "303"},
        headers=auth,
    )
    assert r.status_code == 200
    assert r.json()["lat"] == 0 and r.json()["lng"] == 0
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && .venv/bin/pytest tests/test_create_pin.py -v`
Expected: FAIL — 405 Method Not Allowed (no POST route on `/pins`).

- [ ] **Step 3: Implement**

In `server/app/main.py` schemas section, after `PinLocationBody`:

```python
class PinCreateBody(BaseModel):
    """Search-to-add: create a pin already linked to a provider venue."""

    name: str
    address: Optional[str] = None
    lat: float = 0.0  # 0/0 = unlocated; 'resolve missing locations' backfills
    lng: float = 0.0
    provider: str  # "resy" | "opentable"
    venue_id: str
```

After `import_pins` in the pins section:

```python
def _pin_json(p: Pin, existing: bool = False) -> dict:
    return {
        "id": p.id,
        "name": p.name,
        "address": p.address,
        "lat": p.lat,
        "lng": p.lng,
        "provider": p.provider,
        "venue_id": p.venue_id,
        "linked": p.venue_id is not None,
        "existing": existing,
    }


@app.post("/pins", dependencies=[Depends(require_key)])
def create_pin(body: PinCreateBody, session: Session = Depends(get_session)):
    """Create a born-linked pin from a /venues/search result. Dedupes on
    (provider, venue_id) so re-adding a venue can't duplicate it."""
    dup = session.exec(
        select(Pin).where(Pin.provider == body.provider, Pin.venue_id == body.venue_id)
    ).first()
    if dup:
        return _pin_json(dup, existing=True)
    pin = Pin(
        name=body.name,
        address=body.address,
        lat=body.lat,
        lng=body.lng,
        provider=body.provider,
        venue_id=body.venue_id,
        linked_name=body.name,
        linked_at=datetime.utcnow(),
    )
    session.add(pin)
    session.commit()
    session.refresh(pin)
    return _pin_json(pin)
```

Docstring list, after `/pins/import`:

```
  POST   /pins                       create a pin already linked to a venue (search-to-add)
```

- [ ] **Step 4: Run all server tests**

Run: `cd server && .venv/bin/pytest -v`
Expected: all pass (Task 1's four + these three).

- [ ] **Step 5: Commit**

```bash
git add server/app/main.py server/tests/test_create_pin.py
git commit -m "server: POST /pins creates a born-linked pin (dedupe on provider+venue)"
```

---

### Task 3: Server `POST /pins/clear-unlinked`

**Files:**
- Modify: `server/app/main.py` (endpoint after `delete_pin`; docstring list)
- Create: `server/tests/test_clear_unlinked.py`

**Interfaces:**
- Consumes: fixtures from Task 1; `POST /pins` and `POST /pins/import` to seed data.
- Produces: `POST /pins/clear-unlinked` → `{"deleted": <int>}`. iOS Task 4 decodes as `ClearUnlinkedResponse`.

- [ ] **Step 1: Write the failing test**

`server/tests/test_clear_unlinked.py`:

```python
import json

GEOJSON = json.dumps({
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [-73.99 + i * 0.01, 40.72]},
            "properties": {"location": {"name": f"Noise {i}"}},
        }
        for i in range(3)
    ],
})

LINKED = {
    "name": "Carbone", "lat": 40.72, "lng": -73.99,
    "provider": "resy", "venue_id": "101",
}


def test_clear_unlinked_keeps_linked_pins(client, auth):
    assert client.post("/pins/import", json={"geojson": GEOJSON}, headers=auth).json()["imported"] == 3
    client.post("/pins", json=LINKED, headers=auth)

    r = client.post("/pins/clear-unlinked", headers=auth)
    assert r.status_code == 200
    assert r.json() == {"deleted": 3}

    remaining = client.get("/pins", headers=auth).json()
    assert len(remaining) == 1
    assert remaining[0]["name"] == "Carbone" and remaining[0]["linked"] is True


def test_clear_unlinked_when_none(client, auth):
    r = client.post("/pins/clear-unlinked", headers=auth)
    assert r.json() == {"deleted": 0}
```

Note: if the import seeding fails (parser expects a different GeoJSON shape), check `load_pins_from_text` in `server/app/matching.py` and adjust `GEOJSON` to match — the test's point is 3 unlinked pins + 1 linked pin, however seeded. Falling back to seeding unlinked pins directly through a `Session` is fine.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd server && .venv/bin/pytest tests/test_clear_unlinked.py -v`
Expected: FAIL — 404 on `/pins/clear-unlinked`.

- [ ] **Step 3: Implement**

In `server/app/main.py`, after `delete_pin`:

```python
@app.post("/pins/clear-unlinked", dependencies=[Depends(require_key)])
def clear_unlinked_pins(session: Session = Depends(get_session)):
    """Delete every pin with no venue link — prunes bulk-import noise in one
    call. Linked pins are untouched. POST (not DELETE) so it can never be
    mistaken for DELETE /pins/{id}."""
    unlinked = session.exec(select(Pin).where(Pin.venue_id == None)).all()  # noqa: E711
    for p in unlinked:
        session.delete(p)
    session.commit()
    return {"deleted": len(unlinked)}
```

Docstring list, after `DELETE /pins/{id}`:

```
  POST   /pins/clear-unlinked        delete every unlinked pin (prune import noise)
```

- [ ] **Step 4: Run all server tests**

Run: `cd server && .venv/bin/pytest -v`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add server/app/main.py server/tests/test_clear_unlinked.py
git commit -m "server: POST /pins/clear-unlinked prunes import noise in one call"
```

---

### Task 4: iOS wire types, APIClient, and PinsViewModel methods

**Files:**
- Modify: `ios/ResyBooker/Models/DTOs.swift` (append after `PinLocationRequest`)
- Modify: `ios/ResyBooker/Services/APIClient.swift` (new section after the Pins section, ~line 141)
- Modify: `ios/ResyBooker/Features/Pins/PinsViewModel.swift` (new methods after `importGeoJSON`; new computed count after `unlocatedCount`)

**Interfaces:**
- Consumes: Task 1–3 endpoints; existing `request`/`decode` helpers, `fail(_:)`, `load()`.
- Produces (used by Tasks 5–6):
  - `struct VenueSearchResultDTO: Codable, Identifiable, Hashable` — `venueId: String`, `name: String?`, `locality: String?`, `lat: Double?`, `lng: Double?`
  - `struct PinCreateRequest: Codable` — `name, address?, lat, lng, provider, venueId`
  - `APIClient.searchVenues(query:provider:lat:lng:) async throws -> [VenueSearchResultDTO]`
  - `APIClient.createLinkedPin(_:) async throws -> PinDTO`
  - `APIClient.clearUnlinkedPins() async throws -> Int`
  - `PinsViewModel.unlinkedCount: Int`
  - `PinsViewModel.searchVenues(query:provider:lat:lng:) async throws -> [VenueSearchResultDTO]` (rethrows so the sheet can detect `isMissingEndpoint`)
  - `PinsViewModel.addLinkedPin(_ req: PinCreateRequest) async -> Bool`
  - `PinsViewModel.clearUnlinked() async -> Int?`

- [ ] **Step 1: Add DTOs**

Append to `ios/ResyBooker/Models/DTOs.swift` after `PinLocationRequest`:

```swift
/// One row from GET /venues/search — a bookable venue on Resy/OpenTable.
/// Resy results carry coordinates; OpenTable's don't (lat/lng nil).
struct VenueSearchResultDTO: Codable, Identifiable, Hashable {
    var id: String { venueId }
    let venueId: String
    let name: String?
    let locality: String?
    let lat: Double?
    let lng: Double?

    enum CodingKeys: String, CodingKey {
        case name, locality, lat, lng
        case venueId = "venue_id"
    }
}

/// POST /pins — create a pin already linked to a provider venue.
struct PinCreateRequest: Codable {
    let name: String
    let address: String?
    let lat: Double
    let lng: Double
    let provider: String
    let venueId: String

    enum CodingKeys: String, CodingKey {
        case name, address, lat, lng, provider
        case venueId = "venue_id"
    }
}

struct ClearUnlinkedResponse: Codable {
    let deleted: Int
}
```

- [ ] **Step 2: Add APIClient methods**

In `ios/ResyBooker/Services/APIClient.swift`, after `rejectCandidate` (before `// MARK: - Availability`):

```swift
    // MARK: - Venue search / search-to-add

    /// Free-text venue search on a provider. lat/lng bias results to a city.
    func searchVenues(
        query: String, provider: String, lat: Double?, lng: Double?
    ) async throws -> [VenueSearchResultDTO] {
        var q = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "provider", value: provider),
        ]
        if let lat { q.append(URLQueryItem(name: "lat", value: String(lat))) }
        if let lng { q.append(URLQueryItem(name: "lng", value: String(lng))) }
        let data = try await request("/venues/search", query: q)
        return try decode([VenueSearchResultDTO].self, data)
    }

    /// Create a pin that arrives already linked (from a search result).
    /// The server dedupes on (provider, venue_id).
    func createLinkedPin(_ req: PinCreateRequest) async throws -> PinDTO {
        let body = try encoder.encode(req)
        let data = try await request("/pins", method: "POST", body: body)
        return try decode(PinDTO.self, data)
    }

    /// Delete every unlinked pin in one call; returns how many were removed.
    func clearUnlinkedPins() async throws -> Int {
        let data = try await request("/pins/clear-unlinked", method: "POST")
        return try decode(ClearUnlinkedResponse.self, data).deleted
    }
```

- [ ] **Step 3: Add PinsViewModel methods**

In `ios/ResyBooker/Features/Pins/PinsViewModel.swift`, after `unlocatedCount`:

```swift
    var unlinkedCount: Int { pins.filter { !$0.linked }.count }
```

After `importGeoJSON`:

```swift
    /// Provider venue search for the add-a-spot sheet. Rethrows so the sheet
    /// can distinguish a stale server (isMissingEndpoint) from other errors.
    func searchVenues(
        query: String, provider: String, lat: Double?, lng: Double?
    ) async throws -> [VenueSearchResultDTO] {
        try await api.searchVenues(query: query, provider: provider, lat: lat, lng: lng)
    }

    /// Add a venue picked from provider search as a born-linked pin.
    func addLinkedPin(_ req: PinCreateRequest) async -> Bool {
        do {
            _ = try await api.createLinkedPin(req)
            await load()
            return true
        } catch {
            fail(error)
            return false
        }
    }

    /// Delete every unlinked pin in one server call. Returns the deleted
    /// count, or nil on failure (errorMessage is set).
    func clearUnlinked() async -> Int? {
        do {
            let deleted = try await api.clearUnlinkedPins()
            await load()
            return deleted
        } catch {
            fail(error)
            return nil
        }
    }
```

- [ ] **Step 4: Build to verify**

```bash
cd /Users/brentbrooks/Code/Book-my-restaurant/ios
xcodebuild -project ResyBooker.xcodeproj -scheme ResyBooker \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`. (If the scheme name differs, list with `xcodebuild -list -project ResyBooker.xcodeproj`.)

- [ ] **Step 5: Commit**

```bash
git add ios/ResyBooker/Models/DTOs.swift ios/ResyBooker/Services/APIClient.swift ios/ResyBooker/Features/Pins/PinsViewModel.swift
git commit -m "iOS: API surface for venue search, born-linked pins, clear-unlinked"
```

---

### Task 5: iOS — rework AddSpotSheet around provider search

**Files:**
- Modify: `ios/ResyBooker/Features/Pins/Views/AddSpotSheet.swift` (full rewrite below)
- Modify: `ios/ResyBooker/Features/Pins/Views/PinsView.swift:92-98` (the `.sheet(isPresented: $showingAdd)` — `onAdded` closure now receives the toast message)

**Interfaces:**
- Consumes: Task 4's `VenueSearchResultDTO`, `PinCreateRequest`, `PinsViewModel.searchVenues/addLinkedPin`; existing `LocalSearch`, `SpotGeoJSON.oneFeature`, `APIError.isMissingEndpoint`, `RBSectionLabel`, design tokens.
- Produces: `AddSpotSheet(viewModel:onAdded:)` where `onAdded: (String) -> Void` carries the toast text.

- [ ] **Step 1: Rewrite AddSpotSheet**

Replace the full contents of `ios/ResyBooker/Features/Pins/Views/AddSpotSheet.swift`:

```swift
import SwiftUI
import MapKit
import CoreLocation

/// Add a spot by searching the booking providers directly. Results from
/// /venues/search are real Resy/OpenTable venues, so a picked spot is born
/// linked — no separate Link step. Apple Maps stays as a fallback section for
/// places not on either provider; those add unlinked, like the old flow.
///
/// Searches are biased to a city (persisted): its geocoded center is sent to
/// /venues/search and constrains the Apple Maps completer (regionPriority
/// .required), so same-named venues in other metros don't leak in.
struct AddSpotSheet: View {
    let viewModel: PinsViewModel
    var onAdded: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @AppStorage("addSpotCity") private var city = "New York, NY"
    @AppStorage("addSpotProvider") private var provider = "resy"
    @State private var cityCenter: CLLocationCoordinate2D?
    @State private var resolvingCity = false

    @State private var query = ""
    @State private var search = LocalSearch()
    @State private var providerResults: [VenueSearchResultDTO] = []
    @State private var searching = false
    @State private var serverOutdated = false
    @State private var searchTask: Task<Void, Never>?
    @State private var adding = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                RBColor.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: RBSpacing.md) {
                    cityField
                    providerToggle
                    searchField
                    if let error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(RBColor.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 18)
                    }
                    resultsList
                }
                .padding(.top, RBSpacing.sm)
                .disabled(adding)
                if adding {
                    ProgressView().controlSize(.large).tint(RBColor.accent)
                }
            }
            .navigationTitle("Add a spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(RBColor.accent)
                }
            }
            .task { await applyCity() }
        }
        .tint(RBColor.accent)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: City constraint

    private var cityField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SEARCHING IN")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RBColor.textMuted)
                .padding(.horizontal, 18)
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(RBColor.accent)
                TextField("City (e.g. New York, NY)", text: $city)
                    .foregroundStyle(RBColor.textPrimary)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await applyCity() } }
                if resolvingCity {
                    ProgressView().controlSize(.small)
                } else if cityCenter != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(RBColor.success)
                } else {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(RBColor.amber)
                }
            }
            .font(.system(size: 16))
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .rbCard(fill: RBColor.surface2, bordered: false)
            .padding(.horizontal, 18)
        }
    }

    /// Geocode the typed city → bias provider search + constrain Apple Maps,
    /// then re-run the current query against both.
    private func applyCity() async {
        let q = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { cityCenter = nil; return }
        resolvingCity = true
        let placemark = try? await CLGeocoder().geocodeAddressString(q).first
        resolvingCity = false
        guard let center = placemark?.location?.coordinate else { cityCenter = nil; return }
        cityCenter = center
        search.setCity(center: center)
        queryChanged(query)
    }

    // MARK: Provider toggle

    private var providerToggle: some View {
        HStack(spacing: 0) {
            ForEach(["resy", "opentable"], id: \.self) { p in
                Button {
                    guard provider != p else { return }
                    provider = p
                    providerResults = []
                    queryChanged(query)
                } label: {
                    Text(p.providerDisplayName)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(provider == p ? RBColor.accentInk : RBColor.textSecondary)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(provider == p ? RBColor.accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: RBRadius.small, style: .continuous)
                .fill(RBColor.surface2)
        )
        .padding(.horizontal, 18)
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(RBColor.textMuted)
            TextField("Search a restaurant", text: $query)
                .foregroundStyle(RBColor.textPrimary)
                .autocorrectionDisabled()
                .onChange(of: query) { _, q in queryChanged(q) }
            if searching {
                ProgressView().controlSize(.small).tint(RBColor.accent)
            }
            if !query.isEmpty {
                Button { query = ""; queryChanged("") } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(RBColor.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 16))
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .rbCard(fill: RBColor.surface2, bordered: false)
        .padding(.horizontal, 18)
    }

    /// Debounced fan-out: Apple Maps autocomplete updates immediately (it has
    /// its own throttling); the provider search waits 300 ms for typing to
    /// settle and cancels any in-flight run.
    private func queryChanged(_ q: String) {
        search.update(query: q)
        searchTask?.cancel()
        error = nil
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            providerResults = []
            searching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await runProviderSearch(trimmed)
        }
    }

    private func runProviderSearch(_ q: String) async {
        searching = true
        defer { searching = false }
        do {
            let results = try await viewModel.searchVenues(
                query: q, provider: provider,
                lat: cityCenter?.latitude, lng: cityCenter?.longitude
            )
            guard !Task.isCancelled else { return }
            providerResults = results
            serverOutdated = false
        } catch let apiError as APIError where apiError.isMissingEndpoint {
            providerResults = []
            serverOutdated = true
        } catch is CancellationError {
        } catch {
            providerResults = []
            self.error = error.localizedDescription
        }
    }

    // MARK: Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if serverOutdated {
                    outdatedNotice
                } else if !providerResults.isEmpty {
                    RBSectionLabel(title: "BOOKABLE ON \(provider.providerDisplayName.uppercased())")
                    ForEach(providerResults) { venue in
                        resultRow(
                            title: venue.name ?? "Unknown",
                            subtitle: venue.locality ?? "",
                            icon: "checkmark.seal.fill"
                        ) {
                            Task { await addVenue(venue) }
                        }
                    }
                }
                if !trimmedQuery.isEmpty && (!search.results.isEmpty || !providerResults.isEmpty || serverOutdated) {
                    RBSectionLabel(title: "APPLE MAPS — ADDS UNLINKED")
                        .padding(.top, providerResults.isEmpty && !serverOutdated ? 0 : RBSpacing.sm)
                }
                ForEach(Array(search.results.prefix(3).enumerated()), id: \.offset) { _, completion in
                    resultRow(title: completion.title, subtitle: completion.subtitle, icon: "mappin.circle.fill") {
                        Task { await pick(completion) }
                    }
                }
                if !trimmedQuery.isEmpty {
                    resultRow(
                        title: "Add “\(trimmedQuery)”",
                        subtitle: "Use this name as-is, in \(city)",
                        icon: "mappin.circle.fill"
                    ) {
                        Task { await addRaw() }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    /// The live server predates /venues/search; Apple Maps below still works.
    private var outdatedNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your booking server is out of date")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RBColor.textPrimary)
            Text("Searching Resy/OpenTable needs a newer server. Rebuild the ResyBooker add-on in Home Assistant (Settings → Add-ons → ResyBooker → Rebuild). Apple Maps below still works.")
                .font(.system(size: 13))
                .foregroundStyle(RBColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rbCard(fill: RBColor.surface2, bordered: false)
    }

    private func resultRow(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: RBSpacing.md) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(RBColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(RBColor.textPrimary).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 12.5)).foregroundStyle(RBColor.textSecondary).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(RBColor.textMuted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rbCard(radius: RBRadius.small)
        }
        .buttonStyle(.plain)
    }

    // MARK: Adding

    /// Provider result → born-linked pin. OpenTable results carry no
    /// coordinates; 0/0 marks the pin unlocated so "Resolve missing
    /// locations" can backfill it.
    private func addVenue(_ venue: VenueSearchResultDTO) async {
        adding = true; error = nil
        let ok = await viewModel.addLinkedPin(
            PinCreateRequest(
                name: venue.name ?? trimmedQuery,
                address: venue.locality,
                lat: venue.lat ?? 0,
                lng: venue.lng ?? 0,
                provider: provider,
                venueId: venue.venueId
            )
        )
        if ok {
            onAdded("Spot added — linked to \(provider.providerDisplayName)")
            dismiss()
        } else {
            error = viewModel.errorMessage ?? "Couldn't add the spot."
            adding = false
        }
    }

    private func pick(_ completion: MKLocalSearchCompletion) async {
        adding = true; error = nil
        if let resolved = await search.resolve(completion) {
            await add(name: resolved.name, address: resolved.address,
                      lat: resolved.coordinate.latitude, lng: resolved.coordinate.longitude)
        } else {
            error = "Couldn't resolve that place."; adding = false
        }
    }

    private func addRaw() async {
        adding = true; error = nil
        if let resolved = await search.resolve(text: trimmedQuery) {
            await add(name: resolved.name, address: resolved.address,
                      lat: resolved.coordinate.latitude, lng: resolved.coordinate.longitude)
        } else {
            // No match in the chosen city — keep the name, anchor on the city centre
            // so it still lands on the map (falls back to NYC if the city is unset).
            await add(name: trimmedQuery, address: city,
                      lat: cityCenter?.latitude ?? 40.7128,
                      lng: cityCenter?.longitude ?? -74.006)
        }
    }

    private func add(name: String, address: String, lat: Double, lng: Double) async {
        let geojson = SpotGeoJSON.oneFeature(name: name, address: address, lat: lat, lng: lng)
        if await viewModel.importGeoJSON(geojson) != nil {
            onAdded("Spot added")
            dismiss()
        } else {
            error = viewModel.errorMessage ?? "Couldn't add the spot."
            adding = false
        }
    }
}
```

- [ ] **Step 2: Update the call site in PinsView**

In `ios/ResyBooker/Features/Pins/Views/PinsView.swift`, the add sheet:

```swift
            .sheet(isPresented: $showingAdd) {
                if let vm = viewModel {
                    AddSpotSheet(viewModel: vm) { message in
                        toastText = message
                        showToast = true
                    }
                }
            }
```

- [ ] **Step 3: Build to verify**

```bash
cd /Users/brentbrooks/Code/Book-my-restaurant/ios
xcodebuild -project ResyBooker.xcodeproj -scheme ResyBooker \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`. (`RBSectionLabel(title:)` is valid — `count` defaults to nil, see `DesignSystem/RBScreenHeader.swift:26`.)

- [ ] **Step 4: Commit**

```bash
git add ios/ResyBooker/Features/Pins/Views/AddSpotSheet.swift ios/ResyBooker/Features/Pins/Views/PinsView.swift
git commit -m "iOS: Add-a-spot searches Resy/OpenTable directly; Apple Maps demoted to fallback"
```

---

### Task 6: iOS — "Clear unlinked spots" in Settings

**Files:**
- Modify: `ios/ResyBooker/Features/Settings/ServerConnection.swift` (SettingsSheet, after the `resolveRow` conditional in the PLACES section)

**Interfaces:**
- Consumes: `PinsViewModel.unlinkedCount`, `PinsViewModel.clearUnlinked()` (Task 4).
- Produces: user-facing cleanup action; nothing downstream.

- [ ] **Step 1: Add state + confirmation + row**

In `struct SettingsSheet`, add state:

```swift
    @State private var confirmClear = false
    @State private var clearing = false
    @State private var clearMessage: String?
```

In the PLACES `VStack`, after the `resolveRow` conditional:

```swift
                        if viewModel.unlinkedCount > 0 || clearMessage != nil {
                            clearUnlinkedRow
                        }
```

Add the row + dialog below `resolveRow`:

```swift
    /// One-tap prune of bulk-import noise: deletes every spot that was never
    /// linked to a venue. Linked spots are kept; anything deleted can be
    /// re-added in seconds via search.
    private var clearUnlinkedRow: some View {
        Button {
            guard !clearing, viewModel.unlinkedCount > 0 else { return }
            confirmClear = true
        } label: {
            HStack(spacing: RBSpacing.md) {
                Image(systemName: "trash")
                    .font(.system(size: 17))
                    .foregroundStyle(RBColor.red)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(clearing ? "Clearing…" : "Clear unlinked spots")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(RBColor.textPrimary)
                    Text(clearMessage ?? "Delete all \(viewModel.unlinkedCount) spots not linked to a venue")
                        .font(.system(size: 12.5)).foregroundStyle(RBColor.textMuted)
                }
                Spacer()
                if clearing {
                    ProgressView().tint(RBColor.accent)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(RBColor.textMuted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rbCard(fill: RBColor.surface)
        }
        .buttonStyle(.plain)
        .disabled(clearing)
        .confirmationDialog(
            "Delete \(viewModel.unlinkedCount) unlinked spots?",
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button("Delete \(viewModel.unlinkedCount) spots", role: .destructive) {
                clearing = true
                Task {
                    if let n = await viewModel.clearUnlinked() {
                        clearMessage = "Deleted \(n) spot\(n == 1 ? "" : "s")"
                    }
                    clearing = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Linked spots are kept. You can re-add anything via search.")
        }
    }
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/brentbrooks/Code/Book-my-restaurant/ios
xcodebuild -project ResyBooker.xcodeproj -scheme ResyBooker \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add ios/ResyBooker/Features/Settings/ServerConnection.swift
git commit -m "iOS: Clear unlinked spots (Settings) — one-tap prune of import noise"
```

---

### Task 7: PLAN.md + wrap-up

**Files:**
- Modify: `PLAN.md` (Done list + "Needs you" rebuild note)

**Interfaces:** none.

- [ ] **Step 1: Update PLAN.md**

Add to **Done**:

```markdown
- [x] **Search-to-add from Resy/OpenTable**: Add-a-spot now searches the booking providers directly (`GET /venues/search`) and creates born-linked pins (`POST /pins`, dedupes on provider+venue). Apple Maps demoted to a fallback section (adds unlinked). Server has its first pytest suite (`server/tests/`).
- [x] **Clear unlinked spots** (Settings): `POST /pins/clear-unlinked` deletes all import noise in one call, linked spots kept.
```

Update the existing rebuild bullet in **Needs you** to mention the new endpoints, e.g. append: "(the rebuild also picks up `GET /venues/search`, `POST /pins`, `POST /pins/clear-unlinked` — until then the add sheet shows the out-of-date notice and Settings clear fails)".

- [ ] **Step 2: Run everything one last time**

```bash
cd /Users/brentbrooks/Code/Book-my-restaurant/server && .venv/bin/pytest -v
cd /Users/brentbrooks/Code/Book-my-restaurant/ios && xcodebuild -project ResyBooker.xcodeproj -scheme ResyBooker -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3
```

Expected: all server tests pass; `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add PLAN.md
git commit -m "PLAN: search-to-add + clear-unlinked shipped; HA rebuild picks up new endpoints"
```
