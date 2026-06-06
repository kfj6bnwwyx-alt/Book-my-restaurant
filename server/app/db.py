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
    created_at: datetime = Field(default_factory=datetime.utcnow)


def init_db():
    SQLModel.metadata.create_all(engine)


def get_session():
    with Session(engine) as session:
        yield session
