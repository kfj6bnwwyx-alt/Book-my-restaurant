"""Resy unofficial API client.

The booking chain is: find (availability for a venue/day/party) -> details
(turns a slot config token into a book_token) -> book (commits with a payment
method already on file). Auth is the public ResyAPI key plus a per-session
X-Resy-Auth-Token. The token rotates; refresh_token() mints a fresh one from
email/password when calls start returning 401.
"""

import asyncio

import httpx

from .config import get_settings

BASE = "https://api.resy.com"


BROWSER_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)


def _auth_header_value() -> str:
    return f'ResyAPI api_key="{get_settings().resy_api_key}"'


def _headers(token: str) -> dict:
    return {
        "Authorization": _auth_header_value(),
        "X-Resy-Auth-Token": token,
        "X-Resy-Universal-Auth": token,
        "Origin": "https://resy.com",
        "Referer": "https://resy.com/",
        "User-Agent": BROWSER_UA,
        "Accept": "application/json",
        "X-Origin": "https://resy.com",
    }


class ResyError(Exception):
    pass


# Mutable so refresh_token can update it without restarting the process.
_token_cache = {"value": None}
# Serializes token refresh so a fan-out (e.g. an auto-book window) that 401s on
# many requests at once triggers exactly one login, not one per request.
_token_lock = asyncio.Lock()


def current_token() -> str:
    if _token_cache["value"]:
        return _token_cache["value"]
    _token_cache["value"] = get_settings().resy_auth_token
    return _token_cache["value"]


async def refresh_token(stale: str = None) -> str:
    """Mint a new auth token from email/password. Updates the in-process cache.

    Pass the token that just 401'd as `stale`: if another caller already
    refreshed while we waited for the lock, we return the fresh one instead of
    logging in again.
    """
    s = get_settings()
    if not (s.resy_email and s.resy_password):
        raise ResyError("RESY_EMAIL/RESY_PASSWORD not set; cannot refresh token")
    async with _token_lock:
        if stale is not None and _token_cache["value"] and _token_cache["value"] != stale:
            return _token_cache["value"]
        headers = {
            "Authorization": _auth_header_value(),
            "Origin": "https://resy.com",
            "Referer": "https://resy.com/",
            "User-Agent": BROWSER_UA,
            "Accept": "application/json",
            "X-Origin": "https://resy.com",
            "Content-Type": "application/x-www-form-urlencoded",
        }
        async with httpx.AsyncClient(timeout=20) as c:
            r = await c.post(
                f"{BASE}/3/auth/password",
                data={"email": s.resy_email, "password": s.resy_password},
                headers=headers,
            )
            if r.status_code != 200:
                raise ResyError(f"login failed: {r.status_code} {r.text[:200]}")
            token = r.json().get("token")
            if not token:
                raise ResyError("login response had no token")
            _token_cache["value"] = token
            return token


# Resy returns 419 (not just 401) when the auth token is missing or expired.
AUTH_FAIL = (401, 419)


async def _get(path: str, params: dict, retry: bool = True) -> dict:
    tok = current_token()
    async with httpx.AsyncClient(timeout=20) as c:
        r = await c.get(f"{BASE}{path}", params=params, headers=_headers(tok))
    if r.status_code in AUTH_FAIL and retry:
        await refresh_token(stale=tok)
        return await _get(path, params, retry=False)
    if r.status_code >= 400:
        raise ResyError(f"GET {path} -> {r.status_code} {r.text[:300]}")
    return r.json()


async def _post(path: str, *, json=None, data=None, retry: bool = True) -> dict:
    tok = current_token()
    headers = _headers(tok)
    if json is not None:
        headers["Content-Type"] = "application/json"
    else:
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    async with httpx.AsyncClient(timeout=20) as c:
        r = await c.post(f"{BASE}{path}", json=json, data=data, headers=headers)
    if r.status_code in AUTH_FAIL and retry:
        await refresh_token(stale=tok)
        return await _post(path, json=json, data=data, retry=False)
    if r.status_code >= 400:
        raise ResyError(f"POST {path} -> {r.status_code} {r.text[:300]}")
    return r.json()


async def search_venues(query: str, lat: float = 40.7128, lng: float = -74.006):
    """Find Resy venues by name. Returns a trimmed list of candidates."""
    body = {
        "query": query,
        "per_page": 10,
        "geo": {"latitude": lat, "longitude": lng},
    }
    data = await _post("/3/venuesearch/search", json=body)
    out = []
    for hit in data.get("search", {}).get("hits", []):
        out.append(
            {
                "venue_id": str(hit.get("id", {}).get("resy") or hit.get("objectID")),
                "name": hit.get("name"),
                "url_slug": hit.get("url_slug"),
                "locality": hit.get("locality"),
                "lat": hit.get("_geoloc", {}).get("lat"),
                "lng": hit.get("_geoloc", {}).get("lng"),
            }
        )
    return out


async def find(venue_id: str, day: str, party_size: int):
    """Availability for one venue. day is YYYY-MM-DD. Returns slot list."""
    params = {
        "lat": 0,
        "long": 0,
        "day": day,
        "party_size": party_size,
        "venue_id": venue_id,
    }
    data = await _get("/4/find", params)
    venues = data.get("results", {}).get("venues", [])
    slots = []
    for v in venues:
        for slot in v.get("slots", []):
            cfg = slot.get("config", {})
            slots.append(
                {
                    "config_token": cfg.get("token"),
                    "type": cfg.get("type"),
                    "time": slot.get("date", {}).get("start"),
                    "party_size": party_size,
                }
            )
    return slots


async def details(config_token: str, day: str, party_size: int) -> dict:
    """Turn a slot config token into a book_token."""
    body = {"config_id": config_token, "day": day, "party_size": party_size}
    data = await _post("/3/details", json=body)
    book_token = data.get("book_token", {}).get("value")
    return {
        "book_token": book_token,
        "cancellation": data.get("cancellation", {}),
        "raw": {k: data[k] for k in ("user", "venue") if k in data},
    }


async def book(book_token: str, payment_method_id: int) -> dict:
    """Commit the reservation. payment_method_id must already be on the account."""
    data = {
        "book_token": book_token,
        "struct_payment_method": '{"id":%d}' % payment_method_id,
        "source_id": "resy.com-venue-details",
    }
    res = await _post("/3/book", data=data)
    return {
        "resy_token": res.get("resy_token"),
        "reservation_id": res.get("reservation_id"),
        "raw": res,
    }


async def list_payment_methods() -> list:
    """Read saved cards from /2/user so you can find your payment_method_id."""
    data = await _get("/2/user", {})
    return data.get("payment_methods", [])
