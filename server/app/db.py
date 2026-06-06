from datetime import datetime
from typing import Optional

from sqlmodel import Field, SQLModel, create_engine, Session

from .config import get_settings

engine = create_engine(
    get_settings().db_url,
    connect_args={"check_same_thread": False}
    if get_settings().db_url.startswith("sqlite")
    else {},
)


class Pin(SQLModel, table=True):
    """A saved Google Maps place, optionally linked to a provider venue."""

    id: Optional[int] = Field(default=None, primary_key=True)
    name: str
    address: Optional[str] = None
    lat: float
    lng: float

    # Linkage. provider is "resy" or "opentable". venue_id is provider-specific.
    provider: Optional[str] = None
    venue_id: Optional[str] = None
    # For Resy, the slug/url-name; for OpenTable, the numeric rid as string.
    linked_name: Optional[str] = None
    linked_at: Optional[datetime] = None

    created_at: datetime = Field(default_factory=datetime.utcnow)


class BookingRecord(SQLModel, table=True):
    """Local log of bookings made through the app."""

    id: Optional[int] = Field(default=None, primary_key=True)
    pin_id: Optional[int] = None
    provider: str
    venue_id: str
    venue_name: str
    day: str
    party_size: int
    slot_time: Optional[str] = None
    resy_token: Optional[str] = None
    status: str = "confirmed"
    source: str = "manual"  # "manual" | "drop" | "autobook"
    created_at: datetime = Field(default_factory=datetime.utcnow)


class Drop(SQLModel, table=True):
    """A venue that releases reservations on a fixed schedule (a "drop").

    Resy only: auto-book commits money and only Resy is bookable here. cadence is
    one of daily | weekly | biweekly | monthly. The fields used per cadence:
      daily     -> release_time
      weekly    -> release_weekday (0=Mon..6=Sun) + release_time
      biweekly  -> anchor_date (a known release date, defines weekday + parity) + release_time
      monthly   -> release_dom (1..28) + release_time
    """

    id: Optional[int] = Field(default=None, primary_key=True)
    pin_id: Optional[int] = None
    provider: str = "resy"
    venue_id: str
    venue_name: str

    # Schedule (interpreted in `timezone`).
    cadence: str = "biweekly"
    release_weekday: Optional[int] = None
    release_dom: Optional[int] = None
    release_time: str = "12:00"  # local HH:MM (24h)
    anchor_date: Optional[str] = None  # YYYY-MM-DD, required for biweekly
    window_days: int = 14
    timezone: str = "America/New_York"
    watching: bool = True

    # Auto-book preferences. ab_days is a comma list of Mon..Sun (empty = any day).
    autobook_enabled: bool = False
    ab_party_size: int = 2
    ab_days: str = "Fri,Sat,Sun"
    ab_earliest: str = "17:00"
    ab_latest: str = "21:00"
    ab_max: int = 1
    ab_priority: str = "prime"  # prime | earliest | latest
    ab_notify_on_fail: bool = True

    # Dedupe: ISO of the release instant we last auto-ran for.
    last_run_cycle: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)


class AutoBookRun(SQLModel, table=True):
    """Log of one auto-book execution for a drop."""

    id: Optional[int] = Field(default=None, primary_key=True)
    drop_id: int
    ran_at: datetime = Field(default_factory=datetime.utcnow)
    status: str  # success | partial | none | error
    booked: int = 0
    attempted: int = 0
    detail: str = ""  # short human-readable summary


def init_db():
    SQLModel.metadata.create_all(engine)


def get_session():
    with Session(engine) as session:
        yield session
