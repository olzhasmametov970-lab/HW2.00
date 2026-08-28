"""In-memory sliding-window rate limiter (per process)."""

from __future__ import annotations

import threading
import time
from collections import defaultdict, deque

from fastapi import HTTPException, Request, status


class SlidingWindowLimiter:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._hits: dict[str, deque[float]] = defaultdict(deque)

    def check(self, key: str, *, limit: int, window_seconds: float) -> None:
        now = time.monotonic()
        cutoff = now - window_seconds
        with self._lock:
            q = self._hits[key]
            while q and q[0] < cutoff:
                q.popleft()
            if len(q) >= limit:
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail={
                        "code": "rate_limited",
                        "message": "Слишком много запросов. Подождите и попробуйте снова.",
                    },
                    headers={"Retry-After": str(int(window_seconds))},
                )
            q.append(now)


limiter = SlidingWindowLimiter()


def client_ip(request: Request) -> str:
    # Доверяем только заголовкам от Caddy (не клиентский X-Forwarded-For).
    real = (request.headers.get("x-real-ip") or "").strip()
    if real:
        return real
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        # Последний hop обычно ставит доверенный proxy; leftmost — spoofable.
        parts = [p.strip() for p in forwarded.split(",") if p.strip()]
        if parts:
            return parts[-1]
    if request.client and request.client.host:
        return request.client.host
    return "unknown"


def enforce_rate_limit(
    request: Request,
    *,
    scope: str,
    limit: int,
    window_seconds: float = 60.0,
    extra_key: str | None = None,
) -> None:
    ip = client_ip(request)
    key = f"{scope}:{ip}"
    if extra_key:
        key = f"{key}:{extra_key.lower()}"
    limiter.check(key, limit=limit, window_seconds=window_seconds)
