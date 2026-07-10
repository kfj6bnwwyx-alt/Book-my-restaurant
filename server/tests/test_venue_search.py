from app import main as main_module

RESY_HIT = {
    "venue_id": "101", "name": "Carbone", "url_slug": "carbone",
    "locality": "New York", "lat": 40.72, "lng": -73.99,
}
OT_HIT = {"venue_id": "202", "name": "Carbone", "locality": "New York"}


def test_search_resy(client, auth, monkeypatch):
    async def fake(query, lat=40.7128, lng=-74.006):
        assert query == "carbone"
        return [RESY_HIT]

    monkeypatch.setattr(main_module.resy, "search_venues", fake)
    r = client.get("/venues/search", params={"q": "carbone"}, headers=auth)
    assert r.status_code == 200
    assert r.json() == [RESY_HIT]


def test_search_opentable(client, auth, monkeypatch):
    async def fake(term, lat=40.7128, lng=-74.006):
        return [OT_HIT]

    monkeypatch.setattr(main_module.opentable, "search_restaurants", fake)
    r = client.get(
        "/venues/search",
        params={"q": "carbone", "provider": "opentable"},
        headers=auth,
    )
    assert r.status_code == 200
    assert r.json() == [OT_HIT]


def test_search_requires_key(client):
    r = client.get("/venues/search", params={"q": "carbone"})
    assert r.status_code == 401


def test_search_requires_query(client, auth):
    r = client.get("/venues/search", headers=auth)
    assert r.status_code == 422
