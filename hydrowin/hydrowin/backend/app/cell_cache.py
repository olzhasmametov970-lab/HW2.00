"""Свой бесплатный кэш вышек: учимся по GNSS или ручной точке на карте."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy.orm import Session

from app.models import CellTowerCache, Machine


def parse_cell(cell: dict[str, Any] | None) -> tuple[int, int, int, int] | None:
    if not isinstance(cell, dict):
        return None
    try:
        mcc = int(cell["mcc"])
        mnc = int(cell["mnc"])
        lac = int(cell["lac"])
        cid = int(cell["cid"])
    except (KeyError, TypeError, ValueError):
        return None
    if mcc <= 0 or cid <= 0:
        return None
    return mcc, mnc, lac, cid


def touch_machine_cell(machine: Machine, cell: dict[str, Any] | None) -> None:
    """Запомнить последнюю соту машины (для привязки ручной точки)."""
    parsed = parse_cell(cell)
    if parsed is None:
        return
    mcc, mnc, lac, cid = parsed
    machine.last_cell_mcc = mcc
    machine.last_cell_mnc = mnc
    machine.last_cell_lac = lac
    machine.last_cell_cid = cid


def lookup_cached_cell(db: Session, cell: dict[str, Any] | None) -> dict[str, Any] | None:
    parsed = parse_cell(cell)
    if parsed is None:
        return None
    mcc, mnc, lac, cid = parsed
    row = (
        db.query(CellTowerCache)
        .filter(
            CellTowerCache.mcc == mcc,
            CellTowerCache.mnc == mnc,
            CellTowerCache.lac == lac,
            CellTowerCache.cid == cid,
        )
        .first()
    )
    if row is None:
        return None
    print(
        f"CELL cache {mcc}-{mnc} lac={lac} cid={cid} → "
        f"{row.lat:.5f}, {row.lon:.5f} (~{row.accuracy_m or 100:.0f} м, {row.source})"
    )
    return {
        "lat": row.lat,
        "lon": row.lon,
        "accuracy_m": float(row.accuracy_m or 100.0),
        "source": "cell",
    }


def remember_cell_tower(
    db: Session,
    cell: dict[str, Any] | None,
    *,
    lat: float,
    lon: float,
    accuracy_m: float | None,
    source: str,
) -> None:
    parsed = parse_cell(cell)
    if parsed is None:
        return
    if lat < -90 or lat > 90 or lon < -180 or lon > 180:
        return
    mcc, mnc, lac, cid = parsed
    acc = float(accuracy_m) if accuracy_m is not None else 50.0
    acc = max(10.0, min(acc, 5000.0))
    row = (
        db.query(CellTowerCache)
        .filter(
            CellTowerCache.mcc == mcc,
            CellTowerCache.mnc == mnc,
            CellTowerCache.lac == lac,
            CellTowerCache.cid == cid,
        )
        .first()
    )
    if row is None:
        row = CellTowerCache(
            mcc=mcc,
            mnc=mnc,
            lac=lac,
            cid=cid,
            lat=float(lat),
            lon=float(lon),
            accuracy_m=acc,
            source=source[:16],
        )
        db.add(row)
        print(
            f"CELL cache + {mcc}-{mnc} lac={lac} cid={cid} "
            f"← {lat:.5f}, {lon:.5f} ({source})"
        )
        return
    # Точнее — обновляем; manual/gnss не затираем грубым cell.
    if row.accuracy_m is not None and acc >= float(row.accuracy_m) and source == "cell":
        return
    row.lat = float(lat)
    row.lon = float(lon)
    row.accuracy_m = acc
    row.source = source[:16]
    row.updated_at = datetime.utcnow()
    print(
        f"CELL cache ~ {mcc}-{mnc} lac={lac} cid={cid} "
        f"← {lat:.5f}, {lon:.5f} ({source})"
    )


def remember_cell_from_machine(
    db: Session,
    machine: Machine,
    *,
    lat: float,
    lon: float,
    accuracy_m: float | None,
) -> None:
    if machine.last_cell_cid is None or machine.last_cell_cid <= 0:
        return
    remember_cell_tower(
        db,
        {
            "mcc": machine.last_cell_mcc,
            "mnc": machine.last_cell_mnc,
            "lac": machine.last_cell_lac,
            "cid": machine.last_cell_cid,
        },
        lat=lat,
        lon=lon,
        accuracy_m=accuracy_m or 30.0,
        source="manual",
    )
