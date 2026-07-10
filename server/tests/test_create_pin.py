BODY = {
    "name": "Carbone", "address": "New York", "lat": 40.72, "lng": -73.99,
    "provider": "resy", "venue_id": "101",
}


def test_create_pin_is_born_linked(client, auth):
    r = client.post("/pins", json=BODY, headers=auth)
    assert r.status_code == 200
    pin = r.json()
    assert pin["linked"] is True
    assert pin["provider"] == "resy"
    assert pin["venue_id"] == "101"
    assert pin["existing"] is False

    listed = client.get("/pins", headers=auth).json()
    assert len(listed) == 1 and listed[0]["linked"] is True


def test_create_pin_dedupes_on_provider_venue(client, auth):
    first = client.post("/pins", json=BODY, headers=auth).json()
    again = client.post("/pins", json={**BODY, "name": "Carbone NYC"}, headers=auth)
    assert again.status_code == 200
    assert again.json()["id"] == first["id"]
    assert again.json()["existing"] is True
    assert len(client.get("/pins", headers=auth).json()) == 1


def test_create_pin_defaults_coordinates_to_zero(client, auth):
    r = client.post(
        "/pins",
        json={"name": "Dept of Culture", "provider": "resy", "venue_id": "303"},
        headers=auth,
    )
    assert r.status_code == 200
    assert r.json()["lat"] == 0 and r.json()["lng"] == 0
