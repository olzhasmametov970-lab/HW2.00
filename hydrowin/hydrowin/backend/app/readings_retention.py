"""Очистка и архивация показаний (совместимый entrypoint)."""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.config import settings
from app.readings_archive import maintain_readings_storage, purge_raw_readings


def purge_old_readings(db: Session, *, days: int | None = None) -> int:
    """Совместимость: rollup + purge. Возвращает число удалённых сырых строк."""
    if days is not None and days != settings.readings_retention_days:
        # Точечная чистка без rollup (ручной вызов со своим сроком).
        from datetime import datetime, timedelta

        from app.models import Reading

        cutoff = datetime.utcnow() - timedelta(days=max(1, days))
        deleted = (
            db.query(Reading)
            .filter(Reading.ts < cutoff)
            .delete(synchronize_session=False)
        )
        db.commit()
        return int(deleted or 0)

    stats = maintain_readings_storage(db)
    return int(stats.get("raw_deleted") or 0)


# Для скриптов, которым нужен полный отчёт.
run_storage_maintenance = maintain_readings_storage


if __name__ == "__main__":
    from app.database import SessionLocal

    db = SessionLocal()
    try:
        stats = maintain_readings_storage(db)
        print(stats)
        print(
            f"Raw keep {settings.readings_retention_days}d, "
            f"archive keep {settings.readings_archive_days}d"
        )
    finally:
        db.close()
