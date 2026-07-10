import os

# Must be set before importing app modules: config reads env at import and
# db.py creates the engine from DB_URL at import.
os.environ["APP_KEY"] = "test-key"
os.environ["DB_URL"] = "sqlite:///./test_resybooker.db"

import pytest
from fastapi.testclient import TestClient
from sqlmodel import SQLModel

from app import scheduler
from app.db import engine
from app.main import app

AUTH = {"X-App-Key": "test-key"}


@pytest.fixture()
def client(monkeypatch):
    # Don't start the background polling loop in tests.
    monkeypatch.setattr(scheduler, "start", lambda: None)
    with TestClient(app) as c:
        yield c


@pytest.fixture(autouse=True)
def clean_db():
    SQLModel.metadata.create_all(engine)
    yield
    with engine.begin() as conn:
        for table in reversed(SQLModel.metadata.sorted_tables):
            conn.execute(table.delete())


@pytest.fixture()
def auth():
    return AUTH
