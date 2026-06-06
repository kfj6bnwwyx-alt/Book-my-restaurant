"""OpenTable unofficial client, availability only.

OpenTable's web front end uses a GraphQL endpoint. Checking availability needs
no account. The query string and operation name drift over time; if results go
empty, open opentable.com in DevTools, find the availability XHR to /dapi/fe/gql,
and paste the current `query` text into AVAILABILITY_QUERY below.

Booking through OpenTable requires auth and is intentionally not implemented
here. Use Resy for the actual booking; use OpenTable to widen availability reads.
"""

import httpx

GQL = "https://www.opentable.com/dapi/fe/gql"

# Current as of build time. Replace if OpenTable changes their schema.
AVAILABILITY_QUERY = """
query RestaurantsAvailability($restaurantIds: [Int!]!, $date: Date, $time: Time,
    $partySize: Int) {
  availability(
    restaurantIds: $restaurantIds
    date: $date
    time: $time
    partySize: $partySize
  ) {
    restaurantId
    timeslots {
      dateTime
      available
      slotHash
    }
  }
}
""".strip()


class OpenTableError(Exception):
    pass


def _headers() -> dict:
    return {
        "Content-Type": "application/json",
        "Origin": "https://www.opentable.com",
        "Referer": "https://www.opentable.com/",
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
        ),
        "Accept": "application/json",
    }


async def availability(rid: int, day: str, time: str, party_size: int):
    """day YYYY-MM-DD, time HH:MM:SS. Returns list of available slot times."""
    payload = {
        "operationName": "RestaurantsAvailability",
        "variables": {
            "restaurantIds": [int(rid)],
            "date": day,
            "time": time,
            "partySize": party_size,
        },
        "query": AVAILABILITY_QUERY,
    }
    async with httpx.AsyncClient(timeout=20) as c:
        r = await c.post(GQL, json=payload, headers=_headers())
    if r.status_code >= 400:
        raise OpenTableError(f"{r.status_code} {r.text[:300]}")
    data = r.json()
    if data.get("errors"):
        raise OpenTableError(str(data["errors"])[:300])
    out = []
    for blk in data.get("data", {}).get("availability", []):
        for ts in blk.get("timeslots", []):
            if ts.get("available"):
                out.append({"time": ts.get("dateTime"), "slot_hash": ts.get("slotHash")})
    return out


async def search_restaurants(term: str, lat: float = 40.7128, lng: float = -74.006):
    """Resolve a name to OpenTable restaurant ids via the autocomplete endpoint."""
    url = "https://www.opentable.com/dapi/fe/gql"
    query = """
    query Autocomplete($term: String!, $latitude: Float, $longitude: Float) {
      autocomplete(term: $term, latitude: $latitude, longitude: $longitude) {
        restaurants { rid name address { city } }
      }
    }
    """.strip()
    payload = {
        "operationName": "Autocomplete",
        "variables": {"term": term, "latitude": lat, "longitude": lng},
        "query": query,
    }
    async with httpx.AsyncClient(timeout=20) as c:
        r = await c.post(url, json=payload, headers=_headers())
    if r.status_code >= 400:
        raise OpenTableError(f"{r.status_code} {r.text[:300]}")
    data = r.json()
    out = []
    for rest in (
        data.get("data", {}).get("autocomplete", {}).get("restaurants", []) or []
    ):
        out.append(
            {
                "venue_id": str(rest.get("rid")),
                "name": rest.get("name"),
                "locality": rest.get("address", {}).get("city"),
            }
        )
    return out
