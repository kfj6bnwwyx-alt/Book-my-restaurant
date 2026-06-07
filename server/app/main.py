"""ResyBooker API. One shared key, personal use.

Endpoints:
  GET    /health
  GET    /pins                       list saved pins + link status
  POST   /pins/import                import Google Takeout GeoJSON
  GET    /pins/{id}/candidates       provider venue candidates for a pin
  POST   /pins/{id}/link             confirm pin -> venue mapping
  GET    /availability               fan out across linked pins for date/time/party
  POST   /book                       book a Resy slot
  GET    /resy/payment-methods       helper to find your payment_method_id

  Drops (venues that release tables on a schedule):
  GET    /drops                      list drops + status/countdown/auto-book summary
  POST   /drops                      create a drop
  GET    /drops/{id}                 drop detail
  PATCH  /drops/{id}                 update schedule or auto-book preferences
  DELETE /drops/{id}                 remove a drop
  GET    /drops/{id}/window          the whole release window (every day + time)
  POST   /drops/{id}/reserve         book one or more selected slots
  POST   /drops/{id}/run             run auto-book now (manual trigger / test)
  GET    /drops/{id}/runs            recent auto-book run history

  Watches (poll a specific venue + date until a table appears):
  GET    /watches                    list watches + status
  POST   /watches                    start watching a venue/date/time window
  GET    /watches/{id}               watch detail
  PATCH  /watches/{id}               update or pause/resume a watch
  DELETE /watches/{id}               remove a watch
  POST   /watches/{id}/check         check now (manual trigger / test)
"""

import asyncio
from datetime import datetime
from typing import List, Optional

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlmodel import Session, select

from . import drops as drops_logic
from . import opentable, resy, scheduler
from . import watches as watch_logic
from .config import get_settings
from .db import AutoBookRun, BookingRecord, Drop, Pin, Watch, get_session, init_db
from .matching import load_pins_from_text, rank_matches

app = FastAPI(title="ResyBooker")


@app.on_event("startup")
async def _startup():
    init_db()
    scheduler.start()


@app.exception_handler(resy.ResyError)
async def _resy_error(request: Request, exc: resy.ResyError):
    # Surface the real upstream reason instead of a bare 500.
    return JSONResponse(status_code=502, content={"detail": f"Resy error: {exc}"})


@app.exception_handler(opentable.OpenTableError)
async def _opentable_error(request: Request, exc: opentable.OpenTableError):
    return JSONResponse(status_code=502, content={"detail": f"OpenTable error: {exc}"})


def require_key(x_app_key: str = Header(default="")):
    if x_app_key != get_settings().app_key:
        raise HTTPException(status_code=401, detail="bad app key")


# ---------- schemas ----------


class ImportBody(BaseModel):
    geojson: str  # raw Google Takeout GeoJSON text


class LinkBody(BaseModel):
    provider: str  # "resy" | "opentable"
    venue_id: str
    linked_name: Optional[str] = None


class PinLocationBody(BaseModel):
    lat: float
    lng: float
    address: Optional[str] = None


class BookBody(BaseModel):
    pin_id: Optional[int] = None
    venue_id: str
    venue_name: str
    day: str  # YYYY-MM-DD
    party_size: int
    config_token: str  # from /availability slot


class DropCreate(BaseModel):
    pin_id: Optional[int] = None
    provider: str = "resy"
    venue_id: str
    venue_name: str
    cadence: str = "biweekly"  # daily | weekly | biweekly | monthly
    release_weekday: Optional[int] = None  # 0=Mon..6=Sun (weekly)
    release_dom: Optional[int] = None  # 1..28 (monthly)
    release_time: str = "12:00"  # local HH:MM
    anchor_date: Optional[str] = None  # YYYY-MM-DD, required for biweekly
    window_days: int = 14
    timezone: str = "America/New_York"
    watching: bool = True


class DropUpdate(BaseModel):
    cadence: Optional[str] = None
    release_weekday: Optional[int] = None
    release_dom: Optional[int] = None
    release_time: Optional[str] = None
    anchor_date: Optional[str] = None
    window_days: Optional[int] = None
    timezone: Optional[str] = None
    watching: Optional[bool] = None
    autobook_enabled: Optional[bool] = None
    ab_party_size: Optional[int] = None
    ab_days: Optional[str] = None  # comma list of Mon..Sun, empty = any
    ab_earliest: Optional[str] = None
    ab_latest: Optional[str] = None
    ab_max: Optional[int] = None
    ab_priority: Optional[str] = None  # prime | earliest | latest
    ab_notify_on_fail: Optional[bool] = None


class SlotRef(BaseModel):
    config_token: str
    day: str  # YYYY-MM-DD
    time: Optional[str] = None


class ReserveBody(BaseModel):
    party_size: int = 2
    slots: List[SlotRef]


class WatchCreate(BaseModel):
    pin_id: Optional[int] = None
    provider: str = "resy"
    venue_id: str
    venue_name: str
    day: str  # target YYYY-MM-DD
    party_size: int = 2
    earliest: str = "17:00"
    latest: str = "22:00"
    autobook: bool = False
    notify: bool = True
    interval_seconds: int = 60
    timezone: str = "America/New_York"


class WatchUpdate(BaseModel):
    day: Optional[str] = None
    party_size: Optional[int] = None
    earliest: Optional[str] = None
    latest: Optional[str] = None
    autobook: Optional[bool] = None
    notify: Optional[bool] = None
    interval_seconds: Optional[int] = None
    active: Optional[bool] = None
    timezone: Optional[str] = None


# ---------- pins ----------


@app.get("/health")
def health():
    return {"ok": True, "time": datetime.utcnow().isoformat()}


@app.get("/pins", dependencies=[Depends(require_key)])
def list_pins(session: Session = Depends(get_session)):
    pins = session.exec(select(Pin)).all()
    return [
        {
            "id": p.id,
            "name": p.name,
            "address": p.address,
            "lat": p.lat,
            "lng": p.lng,
            "provider": p.provider,
            "venue_id": p.venue_id,
            "linked": p.venue_id is not None,
        }
        for p in pins
    ]


@app.post("/pins/import", dependencies=[Depends(require_key)])
def import_pins(body: ImportBody, session: Session = Depends(get_session)):
    parsed = load_pins_from_text(body.geojson)
    existing = {(p.name, round(p.lat, 5)) for p in session.exec(select(Pin)).all()}
    added = 0
    for row in parsed:
        key = (row["name"], round(row["lat"], 5))
        if key in existing:
            continue
        session.add(
            Pin(name=row["name"], address=row.get("address"), lat=row["lat"], lng=row["lng"])
        )
        added += 1
    session.commit()
    return {"imported": added, "total_parsed": len(parsed)}


@app.get("/pins/{pin_id}/candidates", dependencies=[Depends(require_key)])
async def pin_candidates(
    pin_id: int,
    provider: str = Query("resy"),
    session: Session = Depends(get_session),
):
    pin = session.get(Pin, pin_id)
    if not pin:
        raise HTTPException(404, "pin not found")
    if provider == "resy":
        cands = await resy.search_venues(pin.name, pin.lat, pin.lng)
    else:
        cands = await opentable.search_restaurants(pin.name, pin.lat, pin.lng)
    ranked = rank_matches({"name": pin.name, "lat": pin.lat, "lng": pin.lng}, cands)
    return [{"score": s, **c} for s, c in ranked]


@app.post("/pins/{pin_id}/link", dependencies=[Depends(require_key)])
def link_pin(pin_id: int, body: LinkBody, session: Session = Depends(get_session)):
    pin = session.get(Pin, pin_id)
    if not pin:
        raise HTTPException(404, "pin not found")
    pin.provider = body.provider
    pin.venue_id = body.venue_id
    pin.linked_name = body.linked_name
    pin.linked_at = datetime.utcnow()
    session.add(pin)
    session.commit()
    return {"ok": True, "pin_id": pin_id}


@app.patch("/pins/{pin_id}", dependencies=[Depends(require_key)])
def update_pin(pin_id: int, body: PinLocationBody, session: Session = Depends(get_session)):
    """Backfill coordinates for a pin (used by the app's 'resolve locations')."""
    pin = session.get(Pin, pin_id)
    if not pin:
        raise HTTPException(404, "pin not found")
    pin.lat = body.lat
    pin.lng = body.lng
    if body.address:
        pin.address = body.address
    session.add(pin)
    session.commit()
    return {"ok": True, "pin_id": pin_id}


# ---------- availability fan-out ----------


@app.get("/availability", dependencies=[Depends(require_key)])
async def availability(
    day: str = Query(..., description="YYYY-MM-DD"),
    party_size: int = Query(2),
    time: str = Query("19:00:00", description="HH:MM:SS, used by OpenTable"),
    pin_id: Optional[int] = Query(None, description="single pin, else all linked"),
    session: Session = Depends(get_session),
):
    q = select(Pin).where(Pin.venue_id.is_not(None))
    if pin_id is not None:
        q = select(Pin).where(Pin.id == pin_id)
    pins = [p for p in session.exec(q).all() if p.venue_id]

    async def one(pin: Pin):
        try:
            if pin.provider == "resy":
                slots = await resy.find(pin.venue_id, day, party_size)
            else:
                slots = await opentable.availability(
                    int(pin.venue_id), day, time, party_size
                )
            return {
                "pin_id": pin.id,
                "name": pin.name,
                "provider": pin.provider,
                "venue_id": pin.venue_id,
                "slots": slots,
                "available": len(slots) > 0,
            }
        except Exception as e:  # one venue failing shouldn't kill the batch
            return {
                "pin_id": pin.id,
                "name": pin.name,
                "provider": pin.provider,
                "venue_id": pin.venue_id,
                "slots": [],
                "available": False,
                "error": str(e)[:200],
            }

    results = await asyncio.gather(*[one(p) for p in pins])
    results.sort(key=lambda r: (not r["available"], r["name"]))
    return {"day": day, "party_size": party_size, "results": results}


# ---------- booking ----------


@app.post("/book", dependencies=[Depends(require_key)])
async def make_booking(body: BookBody, session: Session = Depends(get_session)):
    det = await resy.details(body.config_token, body.day, body.party_size)
    if not det["book_token"]:
        raise HTTPException(409, "slot no longer available")
    pmid = get_settings().resy_payment_method_id
    if not pmid:
        raise HTTPException(400, "RESY_PAYMENT_METHOD_ID not set on server")
    res = await resy.book(det["book_token"], pmid)
    rec = BookingRecord(
        pin_id=body.pin_id,
        provider="resy",
        venue_id=body.venue_id,
        venue_name=body.venue_name,
        day=body.day,
        party_size=body.party_size,
        resy_token=res.get("resy_token"),
        status="confirmed" if res.get("resy_token") else "unknown",
    )
    session.add(rec)
    session.commit()
    return {
        "ok": bool(res.get("resy_token")),
        "resy_token": res.get("resy_token"),
        "reservation_id": res.get("reservation_id"),
    }


@app.get("/resy/payment-methods", dependencies=[Depends(require_key)])
async def payment_methods():
    return await resy.list_payment_methods()


# ---------- drops ----------


def _drop_dict(drop: Drop) -> dict:
    return {
        "id": drop.id,
        "pin_id": drop.pin_id,
        "provider": drop.provider,
        "venue_id": drop.venue_id,
        "venue_name": drop.venue_name,
        "cadence": drop.cadence,
        "release_weekday": drop.release_weekday,
        "release_dom": drop.release_dom,
        "release_time": drop.release_time,
        "anchor_date": drop.anchor_date,
        "window_days": drop.window_days,
        "timezone": drop.timezone,
        "watching": drop.watching,
        "autobook_enabled": drop.autobook_enabled,
        "autobook": {
            "party_size": drop.ab_party_size,
            "days": drop.ab_days,
            "earliest": drop.ab_earliest,
            "latest": drop.ab_latest,
            "max": drop.ab_max,
            "priority": drop.ab_priority,
            "notify_on_fail": drop.ab_notify_on_fail,
        },
        **drops_logic.status(drop),
    }


def _get_drop(drop_id: int, session: Session) -> Drop:
    drop = session.get(Drop, drop_id)
    if not drop:
        raise HTTPException(404, "drop not found")
    return drop


@app.get("/drops", dependencies=[Depends(require_key)])
def list_drops(session: Session = Depends(get_session)):
    drops = session.exec(select(Drop)).all()
    out = [_drop_dict(d) for d in drops]
    out.sort(key=lambda d: (not d["open"], d["opens_in_seconds"]))
    return out


@app.post("/drops", dependencies=[Depends(require_key)])
def create_drop(body: DropCreate, session: Session = Depends(get_session)):
    if body.provider != "resy":
        raise HTTPException(400, "drops support Resy only")
    if body.cadence == "biweekly" and not body.anchor_date:
        raise HTTPException(400, "biweekly drops need anchor_date (a known release date)")
    drop = Drop(**body.model_dump())
    session.add(drop)
    session.commit()
    session.refresh(drop)
    return _drop_dict(drop)


@app.get("/drops/{drop_id}", dependencies=[Depends(require_key)])
def get_drop(drop_id: int, session: Session = Depends(get_session)):
    return _drop_dict(_get_drop(drop_id, session))


@app.patch("/drops/{drop_id}", dependencies=[Depends(require_key)])
def update_drop(drop_id: int, body: DropUpdate, session: Session = Depends(get_session)):
    drop = _get_drop(drop_id, session)
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(drop, field, value)
    session.add(drop)
    session.commit()
    session.refresh(drop)
    return _drop_dict(drop)


@app.delete("/drops/{drop_id}", dependencies=[Depends(require_key)])
def delete_drop(drop_id: int, session: Session = Depends(get_session)):
    drop = _get_drop(drop_id, session)
    session.delete(drop)
    session.commit()
    return {"ok": True, "drop_id": drop_id}


@app.get("/drops/{drop_id}/window", dependencies=[Depends(require_key)])
async def drop_window(
    drop_id: int,
    party_size: Optional[int] = Query(None, description="defaults to the drop's auto-book party size"),
    session: Session = Depends(get_session),
):
    drop = _get_drop(drop_id, session)
    ps = party_size or drop.ab_party_size
    results = await drops_logic.fetch_window(drop, ps)
    return {
        "drop_id": drop_id,
        "venue_name": drop.venue_name,
        "party_size": ps,
        "results": results,
        **drops_logic.status(drop),
    }


@app.post("/drops/{drop_id}/reserve", dependencies=[Depends(require_key)])
async def drop_reserve(drop_id: int, body: ReserveBody, session: Session = Depends(get_session)):
    drop = _get_drop(drop_id, session)
    slots = [s.model_dump() for s in body.slots]
    return await drops_logic.reserve_slots(drop, slots, body.party_size, session)


@app.post("/drops/{drop_id}/run", dependencies=[Depends(require_key)])
async def drop_run(drop_id: int, session: Session = Depends(get_session)):
    drop = _get_drop(drop_id, session)
    run = await drops_logic.run_autobook(drop, session)
    session.commit()
    return {
        "status": run.status,
        "booked": run.booked,
        "attempted": run.attempted,
        "detail": run.detail,
    }


@app.get("/drops/{drop_id}/runs", dependencies=[Depends(require_key)])
def drop_runs(drop_id: int, session: Session = Depends(get_session)):
    _get_drop(drop_id, session)
    runs = session.exec(
        select(AutoBookRun)
        .where(AutoBookRun.drop_id == drop_id)
        .order_by(AutoBookRun.ran_at.desc())
    ).all()
    return [
        {
            "id": r.id,
            "ran_at": r.ran_at.isoformat(),
            "status": r.status,
            "booked": r.booked,
            "attempted": r.attempted,
            "detail": r.detail,
        }
        for r in runs[:20]
    ]


# ---------- watches ----------


def _watch_dict(w: Watch) -> dict:
    return {
        "id": w.id,
        "pin_id": w.pin_id,
        "provider": w.provider,
        "venue_id": w.venue_id,
        "venue_name": w.venue_name,
        "day": w.day,
        "party_size": w.party_size,
        "earliest": w.earliest,
        "latest": w.latest,
        "autobook": w.autobook,
        "notify": w.notify,
        "interval_seconds": w.interval_seconds,
        "timezone": w.timezone,
        "active": w.active,
        "status": w.status,
        "found_detail": w.found_detail,
        "last_checked": w.last_checked.isoformat() if w.last_checked else None,
    }


def _get_watch(watch_id: int, session: Session) -> Watch:
    w = session.get(Watch, watch_id)
    if not w:
        raise HTTPException(404, "watch not found")
    return w


@app.get("/watches", dependencies=[Depends(require_key)])
def list_watches(session: Session = Depends(get_session)):
    watches = session.exec(select(Watch)).all()
    out = [_watch_dict(w) for w in watches]
    out.sort(key=lambda w: (not w["active"], w["day"]))
    return out


@app.post("/watches", dependencies=[Depends(require_key)])
def create_watch(body: WatchCreate, session: Session = Depends(get_session)):
    if body.provider != "resy":
        raise HTTPException(400, "watches support Resy only")
    w = Watch(**body.model_dump())
    session.add(w)
    session.commit()
    session.refresh(w)
    return _watch_dict(w)


@app.get("/watches/{watch_id}", dependencies=[Depends(require_key)])
def get_watch(watch_id: int, session: Session = Depends(get_session)):
    return _watch_dict(_get_watch(watch_id, session))


@app.patch("/watches/{watch_id}", dependencies=[Depends(require_key)])
def update_watch(watch_id: int, body: WatchUpdate, session: Session = Depends(get_session)):
    w = _get_watch(watch_id, session)
    fields = body.model_dump(exclude_unset=True)
    # Re-activating a watch should clear a terminal status so it polls again.
    if fields.get("active") and not w.active:
        w.status = "watching"
    for field, value in fields.items():
        setattr(w, field, value)
    session.add(w)
    session.commit()
    session.refresh(w)
    return _watch_dict(w)


@app.delete("/watches/{watch_id}", dependencies=[Depends(require_key)])
def delete_watch(watch_id: int, session: Session = Depends(get_session)):
    w = _get_watch(watch_id, session)
    session.delete(w)
    session.commit()
    return {"ok": True, "watch_id": watch_id}


@app.post("/watches/{watch_id}/check", dependencies=[Depends(require_key)])
async def check_watch(watch_id: int, session: Session = Depends(get_session)):
    w = _get_watch(watch_id, session)
    result = await watch_logic.run_watch(w, session)
    session.commit()
    return result
