"""Availability polling for a specific restaurant and date (a "watch").

A watch repeatedly checks one venue for a target day, party, and time window, and
either notifies or auto-books the moment a matching table appears (typically a
cancellation). The scheduler drives the polling; this module does one check.
Resy only, since auto-book commits money.
"""

from datetime import date, datetime
from zoneinfo import ZoneInfo

from . import resy
from .config import get_settings
from .db import BookingRecord, Watch


def _tz(w: Watch) -> ZoneInfo:
    return ZoneInfo(w.timezone or "America/New_York")


def _slot_time(slot: dict) -> str:
    raw = slot.get("time") or ""
    tail = raw.split(" ")[-1] if " " in raw else raw
    return tail[:5]


def is_expired(w: Watch, now: datetime = None) -> bool:
    """A watch is spent once its target date is in the past (in its own tz)."""
    now = now or datetime.now(_tz(w))
    return date.fromisoformat(w.day) < now.date()


async def matches(w: Watch) -> list[dict]:
    """Bookable slots for the watch's day inside its time window, soonest first."""
    slots = await resy.find(w.venue_id, w.day, w.party_size)
    out = []
    for s in slots:
        if not s.get("config_token"):
            continue
        t = _slot_time(s)
        if t < w.earliest or t > w.latest:
            continue
        out.append({**s, "time_str": t})
    out.sort(key=lambda s: s["time_str"])
    return out


async def run_watch(w: Watch, session) -> dict:
    """Check once. Notify or auto-book on a hit; mutate the watch in place.

    The caller commits. Returns a small status dict for manual triggers.
    """
    w.last_checked = datetime.utcnow()

    if is_expired(w):
        w.active, w.status = False, "expired"
        session.add(w)
        return {"status": "expired"}

    try:
        found = await matches(w)
    except Exception as e:
        w.status, w.found_detail = "error", str(e)[:200]
        session.add(w)
        return {"status": "error", "error": str(e)[:200]}

    if not found:
        w.status = "watching"
        session.add(w)
        return {"status": "watching", "found": 0}

    if not w.autobook:
        w.status, w.active = "found", False
        w.found_detail = ", ".join(s["time_str"] for s in found[:6])
        session.add(w)
        return {"status": "found", "times": [s["time_str"] for s in found]}

    # Auto-book: try matches in order until one commits.
    pmid = get_settings().resy_payment_method_id
    if not pmid:
        w.status, w.found_detail = "error", "no payment method set"
        session.add(w)
        return {"status": "error", "error": "no payment method set"}

    for s in found:
        det = await resy.details(s["config_token"], w.day, w.party_size)
        if not det["book_token"]:
            continue  # taken between find and details; try the next
        res = await resy.book(det["book_token"], pmid)
        ok = bool(res.get("resy_token"))
        session.add(
            BookingRecord(
                pin_id=w.pin_id,
                provider="resy",
                venue_id=w.venue_id,
                venue_name=w.venue_name,
                day=w.day,
                party_size=w.party_size,
                slot_time=s.get("time"),
                resy_token=res.get("resy_token"),
                status="confirmed" if ok else "failed",
                source="watch",
            )
        )
        if ok:
            w.status, w.active = "booked", False
            w.found_detail = f'{s["time_str"]} ({res.get("reservation_id")})'
            session.add(w)
            return {
                "status": "booked",
                "time": s["time_str"],
                "reservation_id": res.get("reservation_id"),
            }

    # Saw tables but they were all taken before we could book; keep watching.
    w.status = "watching"
    session.add(w)
    return {"status": "watching", "found": len(found), "note": "all taken before booking"}
