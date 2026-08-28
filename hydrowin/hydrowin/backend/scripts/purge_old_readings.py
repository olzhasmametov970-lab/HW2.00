#!/usr/bin/env python3
"""Ручной запуск: rollup hourly/daily + очистка raw/архива."""

from app.readings_archive import maintain_readings_storage
from app.database import SessionLocal
from app.config import settings


def main() -> None:
    db = SessionLocal()
    try:
        stats = maintain_readings_storage(db)
        print(stats)
        print(
            f"Policy: raw {settings.readings_retention_days}d, "
            f"archive {settings.readings_archive_days}d"
        )
    finally:
        db.close()


if __name__ == "__main__":
    main()
