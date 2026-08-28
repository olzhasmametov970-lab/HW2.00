"""Industrial telemetry keeps cell tower payload for GSM locate."""

from types import SimpleNamespace

from app.telemetry_format import expand_industrial


def test_expand_industrial_passes_cell():
    device = SimpleNamespace(device_id="dev-1", machine_id="m-1")
    raw = {
        "d": [[1700000000, 1, 2, None, None, 0]],
        "cell": {"mcc": 250, "mnc": 99, "lac": 10895, "cid": 218234113, "radio": "lte"},
    }
    out = expand_industrial(raw, device)
    assert len(out) == 1
    assert out[0]["cell"]["mcc"] == 250
    assert out[0]["cell"]["cid"] == 218234113
    assert out[0]["gps"] is None
