"""Match Google Maps saved pins to provider venues.

Google Takeout exports saved lists as GeoJSON (one feature per place). Each
feature carries a business name, address, and coordinates. We fuzzy-match the
name and bias by proximity, then let the app confirm ambiguous matches once.
"""

import csv
import io
import json
import math

from rapidfuzz import fuzz


def load_pins_from_geojson(raw: dict) -> list:
    feats = raw.get("features", [])
    pins = []
    for f in feats:
        props = f.get("properties", {})
        loc = props.get("Location", {}) or {}
        name = loc.get("Business Name") or props.get("name") or props.get("Title")
        geom = f.get("geometry", {}) or {}
        coords = geom.get("coordinates") or [None, None]
        if not name or coords[0] is None:
            continue
        pins.append(
            {
                "name": name,
                "address": loc.get("Address") or props.get("address"),
                "lat": coords[1],
                "lng": coords[0],
            }
        )
    return pins


def load_pins_from_csv(text: str) -> list:
    """Current Google Takeout 'Saved' list export (Title,Note,URL,Tags,Comment).

    It carries only names -- no coordinates or addresses -- so pins import with
    lat/lng 0 (a 'no location' sentinel) and rely on the name. Candidate search
    defaults to NYC when a pin has no coordinates, and the user confirms each
    match in the link screen.
    """
    reader = csv.DictReader(io.StringIO(text))
    pins = []
    for row in reader:
        name = (row.get("Title") or row.get("title") or "").strip()
        if not name:
            continue
        pins.append({"name": name, "address": None, "lat": 0.0, "lng": 0.0})
    return pins


def load_pins_from_text(text: str) -> list:
    """Accept either the legacy GeoJSON export or the current Takeout CSV."""
    stripped = text.lstrip()
    if stripped[:1] in ("{", "["):
        return load_pins_from_geojson(json.loads(text))
    return load_pins_from_csv(text)


def _haversine_km(lat1, lng1, lat2, lng2) -> float:
    if None in (lat1, lng1, lat2, lng2):
        return 9999.0
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def rank_matches(pin: dict, candidates: list) -> list:
    """Score venue candidates for a pin. Returns sorted [(score, candidate)]."""
    scored = []
    for v in candidates:
        name_score = fuzz.token_set_ratio(pin["name"], v.get("name") or "")
        dist = _haversine_km(pin["lat"], pin["lng"], v.get("lat"), v.get("lng"))
        # Distance penalty: within 1km is free, falls off after.
        dist_penalty = 0 if dist <= 1 else min(30, (dist - 1) * 4)
        scored.append((round(name_score - dist_penalty, 1), v))
    scored.sort(reverse=True, key=lambda x: x[0])
    return scored


def best_match(pin: dict, candidates: list, threshold: float = 80.0):
    ranked = rank_matches(pin, candidates)
    if ranked and ranked[0][0] >= threshold:
        return ranked[0]
    return None
