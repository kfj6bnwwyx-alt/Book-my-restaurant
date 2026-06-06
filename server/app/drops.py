"""Reservation-drop logic: schedule math, window availability, slot selection,
and booking. A "drop" is a venue that releases its tables on a fixed schedule.

The two jobs here:
1. Read the entire release window so the app can show every day and time at once.
2. When the user arms auto-book, grab the best matching tables the instant the
   drop opens (the scheduler calls run_autobook).

Resy only: booking commits money and only Resy is bookable through this server.
"""

import asyncio
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from . import resy
from .config import get_settings
from .db import AutoBookRun, BookingRecord, Drop

WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
PRIME_TARGET_MIN = 19 * 60 + 30  # 7:30 PM, the center of "prime time"


def _tz(drop: Drop) -> ZoneInfo:
    return ZoneInfo(drop.timezone or "America/New_York")


def _at(tz: ZoneInfo, d: date, hhmm: str) -> datetime:
    hh, mm = (int(x) for x in hhmm.split(":"))
    return datetime(d.year, d.month, d.day, hh, mm, tzinfo=tz)


def _add_months(dt: datetime, n: int) -> datetime:
    m = dt.month - 1 + n
    y = dt.year + m // 12
    m = m % 12 + 1
    return dt.replace(year=y, month=m, day=min(dt.day, 28))


def releases_around(drop: Drop, now: datetime = None) -> tuple[datetime, datetime]:
    """Return (previous_release, next_release) bracketing `now`, tz-aware."""
    tz = _tz(drop)
    now = now or datetime.now(tz)
    today = now.date()

    if drop.cadence == "daily":
        cand = _at(tz, today, drop.release_time)
        nxt = cand if cand > now else cand + timedelta(days=1)
        return nxt - timedelta(days=1), nxt

    if drop.cadence == "monthly":
        dom = min(drop.release_dom or 1, 28)
        cand = _at(tz, today.replace(day=dom), drop.release_time)
        if cand > now:
            return _add_months(cand, -1), cand
        return cand, _add_months(cand, 1)

    if drop.cadence == "biweekly":
        anchor = date.fromisoformat(drop.anchor_date) if drop.anchor_date else today
        periods = (today - anchor).days // 14
        base = anchor + timedelta(days=periods * 14)
        cand = _at(tz, base, drop.release_time)
        if cand > now:
            cand -= timedelta(days=14)
        return cand, cand + timedelta(days=14)

    # weekly (default)
    wd = drop.release_weekday if drop.release_weekday is not None else 2
    back = (today.weekday() - wd) % 7
    cand = _at(tz, today - timedelta(days=back), drop.release_time)
    if cand > now:
        cand -= timedelta(days=7)
    return cand, cand + timedelta(days=7)


def next_release(drop: Drop, now: datetime = None) -> datetime:
    return releases_around(drop, now)[1]


def status(drop: Drop, now: datetime = None) -> dict:
    """Open/upcoming state plus the countdown the app renders."""
    tz = _tz(drop)
    now = now or datetime.now(tz)
    prev, nxt = releases_around(drop, now)
    is_open = now < prev + timedelta(days=drop.window_days)
    return {
        "open": is_open,
        "status": "open" if is_open else "upcoming",
        "next_release": nxt.isoformat(),
        "opens_in_seconds": max(0, int((nxt - now).total_seconds())),
        "window_start": prev.date().isoformat(),
        "window_end": (prev.date() + timedelta(days=drop.window_days - 1)).isoformat(),
    }


def window_dates(drop: Drop, now: datetime = None) -> list[str]:
    """The dates to show in the grid: today through the end of the released window."""
    tz = _tz(drop)
    now = now or datetime.now(tz)
    prev, _ = releases_around(drop, now)
    end = prev.date() + timedelta(days=drop.window_days - 1)
    start = max(now.date(), prev.date())
    days = []
    d = start
    while d <= end:
        days.append(d.isoformat())
        d += timedelta(days=1)
    # Fall back to a plain forward window if the schedule math leaves us empty.
    if not days:
        days = [(now.date() + timedelta(days=i)).isoformat() for i in range(drop.window_days)]
    return days


async def fetch_window(drop: Drop, party_size: int, days: list[str] = None) -> list[dict]:
    """Concurrently read availability for every day in the window (Resy)."""
    if drop.provider != "resy":
        raise ValueError("drops support Resy only")
    days = days or window_dates(drop)

    async def one(day: str) -> dict:
        try:
            slots = await resy.find(drop.venue_id, day, party_size)
            return {"day": day, "slots": slots, "available": len(slots) > 0}
        except Exception as e:  # one bad day shouldn't sink the window
            return {"day": day, "slots": [], "available": False, "error": str(e)[:200]}

    results = await asyncio.gather(*[one(d) for d in days])
    results.sort(key=lambda r: r["day"])
    return results


def _slot_time(slot: dict) -> str:
    """Resy slot time looks like '2026-06-20 19:00:00'. Return 'HH:MM'."""
    raw = slot.get("time") or ""
    tail = raw.split(" ")[-1] if " " in raw else raw
    return tail[:5]


def select_slots(drop: Drop, window: list[dict]) -> list[dict]:
    """Apply auto-book preferences and return bookable candidates, best first."""
    acceptable = {d.strip() for d in drop.ab_days.split(",") if d.strip()}
    out = []
    for day in window:
        wd = WEEKDAYS[date.fromisoformat(day["day"]).weekday()]
        if acceptable and wd not in acceptable:
            continue
        for slot in day["slots"]:
            if not slot.get("config_token"):
                continue
            t = _slot_time(slot)
            if t < drop.ab_earliest or t > drop.ab_latest:
                continue
            out.append({**slot, "day": day["day"], "time_str": t})

    def minutes(s):
        return int(s["time_str"][:2]) * 60 + int(s["time_str"][3:5])

    if drop.ab_priority == "earliest":
        out.sort(key=lambda s: (s["day"], s["time_str"]))
    elif drop.ab_priority == "latest":
        out.sort(key=lambda s: (s["day"], s["time_str"]), reverse=True)
    else:  # prime: closest to 7:30 PM, then soonest day
        out.sort(key=lambda s: (abs(minutes(s) - PRIME_TARGET_MIN), s["day"]))
    return out[:25]


async def _book_slot(drop: Drop, slot: dict, party_size: int, source: str, session) -> dict:
    """Resolve a config token to a booking. Records the outcome locally."""
    day = slot["day"]
    label = slot.get("time_str") or _slot_time(slot)
    det = await resy.details(slot["config_token"], day, party_size)
    if not det["book_token"]:
        return {"day": day, "time": label, "status": "taken"}
    pmid = get_settings().resy_payment_method_id
    if not pmid:
        return {"day": day, "time": label, "status": "error", "error": "no payment method set"}
    res = await resy.book(det["book_token"], pmid)
    ok = bool(res.get("resy_token"))
    session.add(
        BookingRecord(
            pin_id=drop.pin_id,
            provider="resy",
            venue_id=drop.venue_id,
            venue_name=drop.venue_name,
            day=day,
            party_size=party_size,
            slot_time=slot.get("time"),
            resy_token=res.get("resy_token"),
            status="confirmed" if ok else "failed",
            source=source,
        )
    )
    return {
        "day": day,
        "time": label,
        "status": "confirmed" if ok else "failed",
        "reservation_id": res.get("reservation_id"),
    }


async def reserve_slots(drop: Drop, slots: list[dict], party_size: int, session) -> dict:
    """Book an explicit, user-chosen set of slots (the grid's multi-select)."""
    results = []
    for s in slots:
        try:
            results.append(await _book_slot(drop, s, party_size, "drop", session))
        except Exception as e:
            results.append(
                {"day": s.get("day"), "time": s.get("time"), "status": "error", "error": str(e)[:200]}
            )
    session.commit()
    booked = sum(1 for r in results if r["status"] == "confirmed")
    return {"booked": booked, "requested": len(slots), "results": results}


async def run_autobook(drop: Drop, session) -> AutoBookRun:
    """Fetch the window, pick the best matches, and book up to ab_max of them."""
    try:
        window = await fetch_window(drop, drop.ab_party_size)
    except Exception as e:
        run = AutoBookRun(drop_id=drop.id, status="error", detail=str(e)[:300])
        session.add(run)
        return run

    candidates = select_slots(drop, window)
    if not candidates:
        run = AutoBookRun(
            drop_id=drop.id, status="none", detail="No slots matched your preferences."
        )
        session.add(run)
        return run

    confirmed, attempted, results = 0, 0, []
    for slot in candidates:
        if confirmed >= drop.ab_max:
            break
        attempted += 1
        try:
            res = await _book_slot(drop, slot, drop.ab_party_size, "autobook", session)
        except Exception as e:
            res = {"day": slot["day"], "time": slot["time_str"], "status": "error", "error": str(e)[:200]}
        results.append(res)
        if res["status"] == "confirmed":
            confirmed += 1

    status_ = "success" if confirmed >= drop.ab_max else ("partial" if confirmed else "none")
    detail = "; ".join(f'{r["day"]} {r["time"]}: {r["status"]}' for r in results)[:500]
    run = AutoBookRun(
        drop_id=drop.id, status=status_, booked=confirmed, attempted=attempted, detail=detail
    )
    session.add(run)
    return run
