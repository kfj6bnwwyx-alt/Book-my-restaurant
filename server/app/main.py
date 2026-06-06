"""ResyBooker API. One shared key, personal use.

Endpoints:
  GET  /health
  GET  /pins                         list saved pins + link status
  POST /pins/import                  import Google Takeout GeoJSON
  GET  /pins/{id}/candidates         provider venue candidates for a pin
  POST /pins/{id}/link               confirm pin -> venue mapping
  GET  /availability                 fan out across linked pins for date/time/party
  POST /book                         book a Resy slot
  GET  /resy/payment-methods         helper to find your payment_method_id
"""

import asyncio
from datetime import datetime
from typing import Optional

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from pydantic import BaseModel
from sqlmodel import Session, select

from . import opentable, resy
from .config import get_settings
from .db import BookingRecord, Pin, get_session, init_db
from .matching import load_pins_from_text, rank_matches

app = FastAPI(title="ResyBooker")


@app.on_event("startup")
def _startup():
    init_db()


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


class BookBody(BaseModel):
    pin_id: Optional[int] = None
    venue_id: str
    venue_name: str
    day: str  # YYYY-MM-DD
    party_size: int
    config_token: str  # from /availability slot


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
