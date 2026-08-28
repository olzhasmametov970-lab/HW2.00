"""
Каталог типов датчиков — единая точка расширения.

Максимум каналов блока: CH0–CH5 (6 × ADC1).

Чтобы добавить новый датчик в систему:
1. Добавьте запись в SENSOR_CATALOG ниже (type, unit, aliases, пороги).
2. Блок может слать ключ из aliases или chN / channel_N.
3. При первом пакете датчик создастся автоматически на свободном канале,
   либо админ добавит его через POST /machines/{id}/sensors.
"""

from __future__ import annotations

from typing import Any

# Макс. аналоговых входов платы (ADC1, совпадает с прошивкой MAX_SENSORS).
MAX_ADC_CHANNELS = 6
# GPIO: ch0→35, ch1→34, ch2→33, ch3→32, ch4→36, ch5→39
ADC1_GPIO = (35, 34, 33, 32, 36, 39)

# type → спецификация. channel_index в DEFAULT — предпочтительный стартовый канал
# (может быть переназначен при auto-create).
SENSOR_CATALOG: dict[str, dict[str, Any]] = {
    "pressure": {
        "name": "Давление",
        "unit": "бар",
        "preferred_channel": 0,
        "scale_min": 0,
        "scale_max": 400,
        "norm_min": 100,
        "norm_max": 250,
        "warn_high": 280,
        "critical_high": 300,
        "critical_low": 90,
        "aliases": frozenset({
            "press", "pressure", "p", "bar", "davlenie", "давление",
            "ch0", "channel0", "channel_0", "a0", "adc0",
        }),
    },
    "temperature": {
        "name": "Температура",
        "unit": "°C",
        "preferred_channel": 1,
        "scale_min": -50,
        "scale_max": 200,
        "norm_min": 40,
        "norm_max": 85,
        "warn_high": 90,
        "critical_high": 95,
        "critical_low": None,
        "aliases": frozenset({
            "temp", "temperature", "t", "temperatura", "температура",
            "ch1", "channel1", "channel_1", "a1", "adc1",
        }),
    },
    "flow": {
        "name": "Расход",
        "unit": "л/мин",
        "preferred_channel": 2,
        "scale_min": 0,
        "scale_max": 100,
        "norm_min": 5,
        "norm_max": 40,
        "warn_high": 50,
        "critical_high": 60,
        "critical_low": 2,
        "aliases": frozenset({
            "flow", "rashod", "расход", "lpm", "q",
            "ch2", "channel2", "channel_2", "a2", "adc2",
        }),
    },
    "level": {
        "name": "Уровень",
        "unit": "%",
        "preferred_channel": 3,
        "scale_min": 0,
        "scale_max": 100,
        "norm_min": 20,
        "norm_max": 90,
        "warn_high": 95,
        "critical_high": 98,
        "critical_low": 10,
        "aliases": frozenset({
            "level", "uroven", "уровень", "lvl",
            "ch3", "channel3", "channel_3",
        }),
    },
    "vibration": {
        "name": "Вибрация",
        "unit": "мм/с",
        "preferred_channel": 4,
        "scale_min": 0,
        "scale_max": 50,
        "norm_min": 0,
        "norm_max": 10,
        "warn_high": 15,
        "critical_high": 25,
        "critical_low": None,
        "aliases": frozenset({
            "vib", "vibration", "vibratsiya", "вибрация",
            "ch4", "channel4", "channel_4",
        }),
    },
    "current": {
        "name": "Ток / аналог",
        "unit": "мА",
        "preferred_channel": 5,
        "scale_min": 4,
        "scale_max": 20,
        "norm_min": 4,
        "norm_max": 20,
        "warn_high": None,
        "critical_high": None,
        "critical_low": None,
        "aliases": frozenset({
            "current", "ma", "tok", "ток", "analog",
            "ch5", "channel5", "channel_5", "a5", "adc5",
        }),
    },
}

# Совместимость со старым кодом: стартовый набор для новой машины
DEFAULT_SENSOR_TYPES = ("pressure", "temperature")


def catalog_entry(sensor_type: str) -> dict[str, Any] | None:
    return SENSOR_CATALOG.get(sensor_type)


def list_catalog() -> list[dict[str, Any]]:
    items = []
    for stype, spec in SENSOR_CATALOG.items():
        items.append({
            "type": stype,
            "name": spec["name"],
            "unit": spec["unit"],
            "preferred_channel": spec["preferred_channel"],
            "scale_min": spec["scale_min"],
            "scale_max": spec["scale_max"],
            "norm_min": spec.get("norm_min"),
            "norm_max": spec.get("norm_max"),
        })
    return items


def resolve_type_from_key(key: str) -> tuple[str | None, int | None]:
    """
    По ключу телеметрии возвращает (sensor_type, channel_hint).
    channel_hint — из chN / channel_N, иначе preferred_channel типа.
    """
    clean = key.lower().strip()

    # Явный канал: ch5, channel_5, channel5
    for prefix in ("channel_", "channel", "ch", "a", "adc"):
        if clean.startswith(prefix) and clean[len(prefix) :].isdigit():
            ch = int(clean[len(prefix) :])
            # Ищем тип по preferred_channel, иначе generic
            for stype, spec in SENSOR_CATALOG.items():
                if spec["preferred_channel"] == ch:
                    return stype, ch
            return None, ch

    for stype, spec in SENSOR_CATALOG.items():
        if clean in spec["aliases"]:
            return stype, int(spec["preferred_channel"])

    return None, None


def default_sensor_specs() -> list[dict[str, Any]]:
    """Спеки для ensure_machine_sensors (pressure + temperature по умолчанию)."""
    specs: list[dict[str, Any]] = []
    for stype in DEFAULT_SENSOR_TYPES:
        spec = SENSOR_CATALOG[stype]
        specs.append(spec_to_sensor_kwargs(stype, channel_index=spec["preferred_channel"]))
    return specs


def spec_to_sensor_kwargs(
    sensor_type: str,
    *,
    channel_index: int,
    name: str | None = None,
) -> dict[str, Any]:
    spec = SENSOR_CATALOG.get(sensor_type)
    if spec is None:
        return {
            "channel_index": channel_index,
            "name": name or f"Канал {channel_index + 1}",
            "type": sensor_type or "custom",
            "unit": "",
            "scale_min": 0,
            "scale_max": 100,
            "norm_min": None,
            "norm_max": 100,
            "warn_high": None,
            "critical_high": 999,
            "critical_low": None,
        }
    return {
        "channel_index": channel_index,
        "name": name or spec["name"],
        "type": sensor_type,
        "unit": spec["unit"],
        "scale_min": spec["scale_min"],
        "scale_max": spec["scale_max"],
        "norm_min": spec["norm_min"],
        "norm_max": spec["norm_max"],
        "warn_high": spec["warn_high"],
        "critical_high": spec["critical_high"],
        "critical_low": spec["critical_low"],
    }
