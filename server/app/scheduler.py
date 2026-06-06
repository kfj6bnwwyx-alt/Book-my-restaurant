"""Background worker that fires auto-book the moment a drop opens.

It polls relaxed when no release is near and tightens to one-second polling in
the two minutes around a release, so an armed drop is grabbed within ~1s of
opening. A drop is run at most once per release instant (tracked by
last_run_cycle), and only within a grace window so a server that was down for a
day does not back-fire a stale release.
"""

import asyncio
from datetime import datetime

from sqlmodel import Session, select

from . import drops as drops_logic
from .db import Drop, engine

RELAX_SECONDS = 30
TIGHT_SECONDS = 1
NEAR_WINDOW = 120  # seconds before a release where we tighten polling
GRACE_SECONDS = 2 * 3600  # don't fire for a release older than this

_started = False


def start() -> None:
    global _started
    if _started:
        return
    _started = True
    asyncio.create_task(_loop())


async def _loop() -> None:
    while True:
        try:
            sleep_for = await _run_due_and_plan()
        except Exception:
            sleep_for = RELAX_SECONDS
        await asyncio.sleep(sleep_for)


async def _run_due_and_plan() -> int:
    """Fire any drops whose release just passed; return seconds until next poll."""
    soonest = RELAX_SECONDS
    with Session(engine) as session:
        drops = session.exec(select(Drop).where(Drop.autobook_enabled == True)).all()  # noqa: E712
        for drop in drops:
            try:
                tz = drops_logic._tz(drop)
                now = datetime.now(tz)
                prev, nxt = drops_logic.releases_around(drop, now)

                # Tighten polling as the next release approaches.
                secs_to_next = (nxt - now).total_seconds()
                if 0 < secs_to_next <= NEAR_WINDOW:
                    soonest = TIGHT_SECONDS

                cycle = prev.isoformat()
                already_ran = drop.last_run_cycle == cycle
                fresh = 0 <= (now - prev).total_seconds() <= GRACE_SECONDS
                if not already_ran and fresh:
                    await drops_logic.run_autobook(drop, session)
                    drop.last_run_cycle = cycle
                    session.add(drop)
                    session.commit()
            except Exception:
                # One bad drop must not stop the worker.
                continue
    return soonest
