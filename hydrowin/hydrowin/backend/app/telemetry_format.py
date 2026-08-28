"""Форматы телеметрии ingest.

Промышленный (рекомендуется):
  {"d":[[unix_ts, ch0, ch1, ch2, ch3, ch4, ch5, faultMask], ...]}
  Порядок: время, CH0–CH5, затем faultMask (2 бита × канал, uint16).
  Старые платы (4 канала): [unix_ts, p0, t1, t2, p1] или + faultMask —
  принимаются для совместимости.
  device/machine — из X-Device-Key (или device_key в MQTT).

Устаревший verbose — message_id/device_id/machine_id/ts/sensors[].
"""

from __future__ import annotations

import hashlib
from datetime import datetime, timezone
from typing import Any

from pydantic import BaseModel, Field, ValidationError

from app.models import Device

# Макс. каналов (ADC1 / BLE / HTTPS) — CH0–CH5
INDUSTRIAL_CHANNELS_MAX = 6
INDUSTRIAL_CHANNELS_LEGACY = 4
MAX_INDUSTRIAL_ROWS = 60


def _industrial_fault_for_channel(fault_mask: int, channel: int) -> str | None:
    bits = (int(fault_mask) >> (channel * 2)) & 0x3
    if bits == 1:
        return "open"
    if bits == 2:
        return "short"
    return None


def _parse_industrial_row_layout(row: list | tuple) -> tuple[int, bool, int]:
    """Вернуть (n_channels, has_fault_mask, fault_index).

    Форматы:
      - 8+: [ts, ch0..ch5, fault] — актуальный
      - 7:  [ts, ch0..ch5] — 6 каналов без fault
      - 6:  [ts, ch0..ch3, fault] — legacy
      - 5:  [ts, ch0..ch3] — legacy без fault
    """
    n = len(row)
    if n >= 8:
        return INDUSTRIAL_CHANNELS_MAX, True, 1 + INDUSTRIAL_CHANNELS_MAX
    if n == 7:
        return INDUSTRIAL_CHANNELS_MAX, False, -1
    if n == 6:
        return INDUSTRIAL_CHANNELS_LEGACY, True, 1 + INDUSTRIAL_CHANNELS_LEGACY
    if n >= 5:
        return INDUSTRIAL_CHANNELS_LEGACY, False, -1
    raise ValueError(
        "industrial: строка должна быть "
        "[unix_ts, ch0..ch5, faultMask] (8) или legacy "
        "[unix_ts, p0, t1, t2, p1] (±fault)"
    )


class GpsPoint(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    accuracy_m: float | None = Field(default=None, ge=0, le=100_000)


class CellTower(BaseModel):
    mcc: int = Field(ge=1, le=999)
    mnc: int = Field(ge=0, le=999)
    lac: int = Field(ge=0, le=65535)
    cid: int = Field(ge=1, le=268435455)
    radio: str | None = Field(default="lte", max_length=8)


class TelemetrySensorValue(BaseModel):
    channel: int = Field(ge=0, le=5, description="CH0–CH5 (ADC1, макс. 6)")
    value: float
    current_ma: float | None = Field(default=None, ge=0, le=100)
    fault: str | None = Field(default=None, pattern="^(open|short)$")
    status: str | None = Field(
        default=None, pattern="^(ok|warning|critical)$"
    )


class TelemetryIngest(BaseModel):
    """Verbose JSON (совместимость)."""

    message_id: str = Field(min_length=1, max_length=128)
    device_id: str = Field(min_length=1, max_length=128)
    machine_id: str = Field(min_length=1, max_length=64)
    ts: str = Field(min_length=1, max_length=64)
    gps: GpsPoint | None = None
    cell: CellTower | None = None
    sensors: list[TelemetrySensorValue] = Field(max_length=6)


def _device_tag(device_id: str) -> str:
    return hashlib.sha256(device_id.encode("utf-8")).hexdigest()[:8]


def _unix_to_iso(ts_unix: int) -> str:
    return datetime.fromtimestamp(int(ts_unix), tz=timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )


def expand_industrial(raw: dict[str, Any], device: Device) -> list[dict[str, Any]]:
    """Развернуть {"d":[...]} в список payload для ingest_telemetry."""
    rows = raw.get("d")
    if not isinstance(rows, list) or not rows:
        raise ValueError("industrial: поле d — непустой массив")
    if len(rows) > MAX_INDUSTRIAL_ROWS:
        raise ValueError(f"industrial: больше {MAX_INDUSTRIAL_ROWS} строк в d")

    tag = _device_tag(device.device_id)
    explicit_mid = str(raw.get("message_id") or "").strip() or None
    out: list[dict[str, Any]] = []

    for i, row in enumerate(rows):
        if not isinstance(row, (list, tuple)):
            raise ValueError(f"industrial: строка {i} — не массив")
        try:
            n_ch, has_fault_mask, fault_idx = _parse_industrial_row_layout(row)
        except ValueError as exc:
            raise ValueError(f"industrial: строка {i}: {exc}") from exc

        try:
            ts_unix = int(row[0])
        except (TypeError, ValueError) as exc:
            raise ValueError(f"industrial: плохой unix_ts в строке {i}") from exc

        if ts_unix == 0:
            # Плата ещё без NTP — время приёма на сервере
            now = datetime.now(timezone.utc)
            ts_iso = now.strftime("%Y-%m-%dT%H:%M:%SZ")
            ts_unix = int(now.timestamp())
        elif ts_unix < 1_000_000_000 or ts_unix > 4_000_000_000:
            raise ValueError(f"industrial: unix_ts вне диапазона в строке {i}")
        else:
            ts_iso = _unix_to_iso(ts_unix)

        sensors: list[dict[str, Any]] = []
        fault_mask = 0
        if has_fault_mask:
            try:
                fault_mask = int(row[fault_idx])
            except (TypeError, ValueError):
                fault_mask = 0

        for ch in range(n_ch):
            raw_val = row[1 + ch]
            if raw_val is None:
                continue
            try:
                value = float(raw_val)
            except (TypeError, ValueError) as exc:
                raise ValueError(
                    f"industrial: плохое значение ch{ch} в строке {i}"
                ) from exc
            if value != value:  # NaN
                continue
            fault = (
                _industrial_fault_for_channel(fault_mask, ch)
                if has_fault_mask
                else None
            )
            # Только без faultMask: 0..3.2 — ток мА (обрыв), не бар.
            # С faultMask=0 и value=1 бар это нормальное давление у низа шкалы.
            if not has_fault_mask and not fault and 0 < value < 3.2:
                fault = "open"
            entry: dict[str, Any] = {"channel": ch, "value": value}
            if has_fault_mask:
                # Явный OK/fault — seed не должен гадать по value=1..3 бар.
                entry["fault"] = fault
                if fault:
                    entry["current_ma"] = value
            elif fault:
                entry["fault"] = fault
                entry["current_ma"] = value
            sensors.append(entry)

        if explicit_mid and len(rows) == 1:
            message_id = explicit_mid[:36]
        else:
            # ≤36 символов (колонка ingest_dedup.message_id)
            message_id = (
                f"d-{tag}-{ts_unix}" if len(rows) == 1 else f"d-{tag}-{ts_unix}-{i}"
            )
            message_id = message_id[:36]

        out.append(
            {
                "message_id": message_id,
                "device_id": device.device_id,
                "machine_id": device.machine_id,
                "ts": ts_iso,
                "sensors": sensors,
                "gps": raw.get("gps"),
                "cell": raw.get("cell"),
            }
        )
    return out


def normalize_telemetry_payloads(
    raw: dict[str, Any], device: Device
) -> list[dict[str, Any]]:
    """Принять industrial или verbose → список dict для ingest_telemetry."""
    if "d" in raw:
        return expand_industrial(raw, device)

    try:
        body = TelemetryIngest.model_validate(raw)
    except ValidationError as exc:
        raise ValueError(str(exc)) from exc
    return [body.model_dump()]
