from typing import Any
import time

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.deps import get_device_by_key
from app.ops_metrics import record_ingest_error, record_ingest_success
from app.rate_limit import enforce_rate_limit
from app.seed import ingest_telemetry
from app.telemetry_format import (
    GpsPoint,
    TelemetryIngest,
    TelemetrySensorValue,
    normalize_telemetry_payloads,
)

router = APIRouter(tags=["telemetry"])

# Реэкспорт схем для OpenAPI / внешних импортов
__all__ = [
    "GpsPoint",
    "TelemetryIngest",
    "TelemetrySensorValue",
    "ingest",
    "router",
]


@router.post("/ingest/telemetry", status_code=202)
def ingest(
    body: dict[str, Any],
    request: Request,
    db: Session = Depends(get_db),
    device=Depends(get_device_by_key),
):
    """Телеметрия платы.

    Промышленный JSON (рекомендуется)::

        {"d":[[1718204001,12,28,29,0,null,null,0]]}

    где каждая строка: ``[unix_ts, ch0..ch5, faultMask]`` (CH0–CH5).
    ``faultMask`` — 2 бита на канал (uint16). Старые платы с 4 каналами
    принимаются. Аутентификация — заголовок ``X-Device-Key``.

    Verbose (совместимость): message_id, device_id, machine_id, ts, sensors[].
    """
    enforce_rate_limit(
        request,
        scope="ingest",
        limit=settings.ingest_rate_limit,
        window_seconds=settings.ingest_rate_window_seconds,
        extra_key=device.device_id,
    )
    started = time.perf_counter()
    try:
        payloads = normalize_telemetry_payloads(body, device)
        for payload in payloads:
            ingest_telemetry(db, device, payload)
    except ValueError as exc:
        record_ingest_error()
        raise HTTPException(
            status_code=400, detail={"code": "bad_request", "message": str(exc)}
        ) from exc
    except Exception:
        record_ingest_error()
        raise
    else:
        record_ingest_success(time.perf_counter() - started)
    return None
