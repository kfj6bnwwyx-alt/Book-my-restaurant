import json

GEOJSON = json.dumps({
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [-73.99 + i * 0.01, 40.72]},
            "properties": {"name": f"Noise {i}"},
        }
        for i in range(3)
    ],
})

LINKED = {
    "name": "Carbone", "lat": 40.72, "lng": -73.99,
    "provider": "resy", "venue_id": "101",
}


def test_clear_unlinked_keeps_linked_pins(client, auth):
    imported = client.post("/pins/import", json={"geojson": GEOJSON}, headers=auth)
    assert imported.json()["imported"] == 3
    client.post("/pins", json=LINKED, headers=auth)

    r = client.post("/pins/clear-unlinked", headers=auth)
    assert r.status_code == 200
    assert r.json() == {"deleted": 3}

    remaining = client.get("/pins", headers=auth).json()
    assert len(remaining) == 1
    assert remaining[0]["name"] == "Carbone" and remaining[0]["linked"] is True


def test_clear_unlinked_when_none(client, auth):
    r = client.post("/pins/clear-unlinked", headers=auth)
    assert r.json() == {"deleted": 0}
