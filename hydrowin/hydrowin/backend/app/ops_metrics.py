"""In-memory метрики ingest (на один uvicorn worker)."""

from __future__ import annotations

import os
import threading
import time
from collections import deque


_lock = threading.Lock()
_ingest_latencies_ms: deque[float] = deque(maxlen=500)
_ingest_total = 0
_ingest_errors = 0


def record_ingest_success(duration_seconds: float) -> None:
    global _ingest_total
    with _lock:
        _ingest_total += 1
        _ingest_latencies_ms.append(duration_seconds * 1000.0)


def record_ingest_error() -> None:
    global _ingest_errors
    with _lock:
        _ingest_errors += 1


def ingest_metrics_snapshot() -> dict:
    with _lock:
        vals = sorted(_ingest_latencies_ms)
        total = _ingest_total
        errors = _ingest_errors

    def percentile(p: float) -> float | None:
        if not vals:
            return None
        idx = min(len(vals) - 1, int(round((len(vals) - 1) * p)))
        return round(vals[idx], 2)

    return {
        "requests_total": total,
        "errors_total": errors,
        "latency_ms": {
            "samples": len(vals),
            "p50": percentile(0.50),
            "p95": percentile(0.95),
            "max": round(vals[-1], 2) if vals else None,
        },
    }


def system_metrics_snapshot() -> dict:
    cpu_percent: float | None = None
    load_1m: float | None = None
    try:
        import psutil

        cpu_percent = round(psutil.cpu_percent(interval=0.0), 1)
    except Exception:
        cpu_percent = None

    try:
        load_1m = round(os.getloadavg()[0], 2)
    except (AttributeError, OSError):
        load_1m = None

    return {
        "cpu_percent": cpu_percent,
        "load_1m": load_1m,
        "uptime_seconds": round(time.time() - _PROCESS_START, 1),
    }


_PROCESS_START = time.time()
