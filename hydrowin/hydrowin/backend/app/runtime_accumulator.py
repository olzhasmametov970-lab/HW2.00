"""Накопление времени работы блока, моточасов и счётчиков насоса."""

from __future__ import annotations

from datetime import datetime

from app.models import Machine, Sensor

# Максимальный зазор между пакетами, который ещё считаем «непрерывной» работой (сек).
_MAX_GAP_SEC = 180.0

_DEFAULT_PRESSURE_RUN_BAR = 50.0
_DEFAULT_TEMP_RUN_C = 35.0
_DEFAULT_PUMP_ON_PRESSURE_BAR = 20.0
_DEFAULT_PUMP_ON_TEMP_C = 35.0


def hydraulics_working(
    *,
    pressure: float | None,
    temperature: float | None,
    pressure_sensor: Sensor | None = None,
    temperature_sensor: Sensor | None = None,
) -> bool:
    """Моточасы: гидросистема под нагрузкой."""
    press_threshold = _DEFAULT_PRESSURE_RUN_BAR
    if pressure_sensor is not None and pressure_sensor.norm_min is not None:
        press_threshold = max(30.0, float(pressure_sensor.norm_min) * 0.4)

    temp_threshold = _DEFAULT_TEMP_RUN_C
    if temperature_sensor is not None and temperature_sensor.norm_min is not None:
        temp_threshold = float(temperature_sensor.norm_min)

    if pressure is not None and pressure >= press_threshold:
        return True
    if (
        pressure is not None
        and pressure >= press_threshold * 0.5
        and temperature is not None
        and temperature >= temp_threshold
    ):
        return True
    return False


def _pump_pressure_threshold(
    machine: Machine,
    pressure_sensor: Sensor | None,
) -> float:
    raw = getattr(machine, "pump_on_pressure_bar", None)
    if raw is not None:
        return float(raw)
    if pressure_sensor is not None:
        span = float(pressure_sensor.scale_max or 0) - float(
            pressure_sensor.scale_min or 0
        )
        if span > 0:
            return float(pressure_sensor.scale_min or 0) + span * 0.05
    return _DEFAULT_PUMP_ON_PRESSURE_BAR


def _pump_temperature_threshold(
    machine: Machine,
    temperature_sensor: Sensor | None,
) -> float:
    raw = getattr(machine, "pump_on_temperature_c", None)
    if raw is not None:
        return float(raw)
    if temperature_sensor is not None and temperature_sensor.norm_min is not None:
        return float(temperature_sensor.norm_min)
    return _DEFAULT_PUMP_ON_TEMP_C


def pump_is_on(
    *,
    machine: Machine,
    pressure: float | None,
    temperature: float | None = None,
    pressure_ok: bool = True,
    pressure_sensor: Sensor | None = None,
    temperature_sensor: Sensor | None = None,
) -> bool:
    """Насос включён.

    Правило:
    - давление > порог машины, ИЛИ
    - температура > порог И линия давления не в обрыве/КЗ (pressure_ok).

    pressure_ok=False, если датчик давления в fault open/short (значение отброшено).
    Если датчика давления нет — pressure_ok=True, можно опираться на температуру.
    """
    p_thr = _pump_pressure_threshold(machine, pressure_sensor)
    if pressure is not None and pressure > p_thr:
        return True

    if not pressure_ok:
        return False

    t_thr = _pump_temperature_threshold(machine, temperature_sensor)
    if temperature is not None and temperature > t_thr:
        return True
    return False


def accumulate_runtime(
    machine: Machine,
    now: datetime,
    *,
    pressure: float | None = None,
    temperature: float | None = None,
    pressure_ok: bool = True,
    pressure_sensor: Sensor | None = None,
    temperature_sensor: Sensor | None = None,
) -> None:
    """
    Обновляет накопители (не сбрасываются по дням):
    - uptime_hours — блок на связи;
    - engine_hours — моточасы (нагрузка ГС);
    - pump_hours — время работы насоса;
    - pump_starts — число запусков насоса (фронт выкл→вкл).
    """
    prev = machine.last_seen_at
    delta_h = 0.0
    if prev is not None:
        gap = (now - prev).total_seconds()
        if 0 < gap <= _MAX_GAP_SEC:
            delta_h = gap / 3600.0

    pump_on = pump_is_on(
        machine=machine,
        pressure=pressure,
        temperature=temperature,
        pressure_ok=pressure_ok,
        pressure_sensor=pressure_sensor,
        temperature_sensor=temperature_sensor,
    )
    was_on = bool(getattr(machine, "pump_was_on", False) or False)

    if delta_h > 0:
        machine.uptime_hours = float(machine.uptime_hours or 0.0) + delta_h
        if hydraulics_working(
            pressure=pressure,
            temperature=temperature,
            pressure_sensor=pressure_sensor,
            temperature_sensor=temperature_sensor,
        ):
            machine.engine_hours = float(machine.engine_hours or 0.0) + delta_h
        if pump_on:
            machine.pump_hours = float(getattr(machine, "pump_hours", None) or 0.0) + delta_h

    if pump_on and not was_on:
        machine.pump_starts = int(getattr(machine, "pump_starts", None) or 0) + 1

    machine.pump_was_on = pump_on
    machine.last_seen_at = now
