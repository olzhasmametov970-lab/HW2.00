"""Unit tests for pump / runtime accumulator rules."""

from datetime import datetime, timedelta
from types import SimpleNamespace

from app.runtime_accumulator import accumulate_runtime, pump_is_on


def _machine(**kwargs):
    base = dict(
        pump_on_pressure_bar=20.0,
        pump_on_temperature_c=35.0,
        pump_was_on=False,
        pump_hours=0.0,
        pump_starts=0,
        engine_hours=0.0,
        uptime_hours=0.0,
        last_seen_at=None,
    )
    base.update(kwargs)
    return SimpleNamespace(**base)


def test_pump_on_by_pressure():
    m = _machine()
    assert pump_is_on(machine=m, pressure=25.0, temperature=10.0, pressure_ok=True)


def test_pump_on_by_temperature_when_pressure_low():
    m = _machine(pump_on_pressure_bar=20.0, pump_on_temperature_c=35.0)
    assert pump_is_on(
        machine=m, pressure=0.5, temperature=40.0, pressure_ok=True
    )


def test_pump_off_when_pressure_fault_even_if_hot():
    m = _machine()
    assert not pump_is_on(
        machine=m, pressure=None, temperature=80.0, pressure_ok=False
    )


def test_pump_on_by_temperature_without_pressure_sensor():
    m = _machine()
    assert pump_is_on(
        machine=m, pressure=None, temperature=40.0, pressure_ok=True
    )


def test_accumulate_counts_start_and_hours():
    m = _machine(last_seen_at=datetime(2026, 8, 5, 9, 0, 0))
    now = datetime(2026, 8, 5, 9, 1, 0)
    accumulate_runtime(
        m,
        now,
        pressure=0.4,
        temperature=40.0,
        pressure_ok=True,
    )
    assert m.pump_was_on is True
    assert m.pump_starts == 1
    assert m.pump_hours == pytest_approx(1 / 60)


def pytest_approx(value, rel=1e-6):
    class A:
        def __eq__(self, other):
            return abs(float(other) - value) <= rel * max(1.0, abs(value))

        def __repr__(self):
            return f"approx({value})"

    return A()


if __name__ == "__main__":
    test_pump_on_by_pressure()
    test_pump_on_by_temperature_when_pressure_low()
    test_pump_off_when_pressure_fault_even_if_hot()
    test_pump_on_by_temperature_without_pressure_sensor()
    test_accumulate_counts_start_and_hours()
    print("ok")
