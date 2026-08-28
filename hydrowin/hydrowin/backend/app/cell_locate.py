"""Резолв координат по соте (MCC/MNC/LAC/CID).

Сначала свой кэш в PostgreSQL (cell_cache.py), затем Unwired (pk.*) / OpenCellID.
"""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

from app.config import settings

_CACHE_TTL_S = 24 * 3600
_cache: dict[tuple[int, int, int, int], tuple[float, dict[str, Any]]] = {}


def _cache_get(key: tuple[int, int, int, int]) -> dict[str, Any] | None:
    hit = _cache.get(key)
    if hit is None:
        return None
    ts, value = hit
    if time.time() - ts > _CACHE_TTL_S:
        _cache.pop(key, None)
        return None
    return value


def _cache_put(key: tuple[int, int, int, int], value: dict[str, Any]) -> None:
    _cache[key] = (time.time(), value)


def _http_json(url: str, *, data: bytes | None = None, timeout: int = 6) -> dict[str, Any] | None:
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "User-Agent": "HydroWin/1.0",
            "Content-Type": "application/json",
        },
        method="POST" if data is not None else "GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        print(f"CELL locate сеть: {exc}")
        return None
    try:
        data_j = json.loads(raw)
    except json.JSONDecodeError:
        print(f"CELL locate не JSON: {raw[:180]}")
        return None
    return data_j if isinstance(data_j, dict) else None


def _point(lat: float, lon: float, acc: float | None) -> dict[str, Any]:
    accuracy_m = float(acc) if acc is not None else 800.0
    accuracy_m = max(100.0, min(accuracy_m, 50_000.0))
    return {"lat": lat, "lon": lon, "accuracy_m": accuracy_m, "source": "cell"}


def _unwired(
    *,
    token: str,
    mcc: int,
    mnc: int,
    lac: int,
    cid: int,
    radio: str,
) -> dict[str, Any] | None:
    radio_u = (radio or "lte").strip().lower()
    if radio_u not in {"gsm", "umts", "lte", "cdma", "nr"}:
        radio_u = "lte"
    payload = json.dumps(
        {
            "token": token,
            "radio": radio_u,
            "mcc": mcc,
            "mnc": mnc,
            "cells": [{"lac": lac, "cid": cid}],
            "address": 0,
        }
    ).encode("utf-8")
    data = _http_json("https://us1.unwiredlabs.com/v2/process.php", data=payload)
    if not data:
        return None
    if str(data.get("status") or "").lower() != "ok":
        print(
            f"CELL Unwired: {data.get('message') or data.get('status')} "
            f"(mcc={mcc} mnc={mnc} lac={lac} cid={cid})"
        )
        return None
    try:
        lat = float(data["lat"])
        lon = float(data["lon"])
    except (KeyError, TypeError, ValueError):
        return None
    return _point(lat, lon, data.get("accuracy"))


def _opencellid_get(
    *,
    token: str,
    mcc: int,
    mnc: int,
    lac: int,
    cid: int,
    radio: str,
) -> dict[str, Any] | None:
    radio_u = (radio or "lte").strip().upper()
    if radio_u not in {"GSM", "UMTS", "LTE", "NR", "CDMA"}:
        radio_u = "LTE"
    qs = urllib.parse.urlencode(
        {
            "key": token,
            "mcc": mcc,
            "mnc": mnc,
            "lac": lac,
            "cellid": cid,
            "radio": radio_u,
            "format": "json",
        }
    )
    data = _http_json(f"https://opencellid.org/cell/get?{qs}")
    if not data:
        return None
    if data.get("error"):
        print(
            f"CELL OpenCellID: {data.get('error')} "
            f"(mcc={mcc} mnc={mnc} lac={lac} cid={cid})"
        )
        return None
    try:
        lat = float(data["lat"])
        lon = float(data["lon"])
    except (KeyError, TypeError, ValueError):
        return None
    return _point(lat, lon, data.get("range") or data.get("accuracy"))


def locate_cell(cell: dict[str, Any] | None) -> dict[str, Any] | None:
    """Вернуть {lat, lon, accuracy_m, source} или None."""
    if not isinstance(cell, dict):
        return None
    try:
        mcc = int(cell["mcc"])
        mnc = int(cell["mnc"])
        lac = int(cell["lac"])
        cid = int(cell["cid"])
    except (KeyError, TypeError, ValueError):
        print(f"CELL payload битый: {cell}")
        return None
    if mcc <= 0 or cid <= 0:
        return None
    cache_key = (mcc, mnc, lac, cid)
    cached = _cache_get(cache_key)
    if cached is not None:
        return cached
    token = (settings.opencellid_api_key or "").strip()
    if not token:
        return None
    radio = str(cell.get("radio") or "lte")
    found = None
    if token.startswith("pk."):
        found = _unwired(
            token=token, mcc=mcc, mnc=mnc, lac=lac, cid=cid, radio=radio
        )
    if found is None:
        found = _opencellid_get(
            token=token, mcc=mcc, mnc=mnc, lac=lac, cid=cid, radio=radio
        )
    if found:
        _cache_put(cache_key, found)
        print(
            f"CELL {mcc}-{mnc} lac={lac} cid={cid} → "
            f"{found['lat']:.5f}, {found['lon']:.5f} (~{found['accuracy_m']:.0f} м)"
        )
    return found
