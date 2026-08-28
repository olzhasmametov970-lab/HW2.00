"""Применение SQL-индексов при старте приложения."""

from pathlib import Path

from sqlalchemy import text
from sqlalchemy.engine import Engine


def apply_performance_indexes(engine: Engine) -> list[str]:
    sql_path = Path(__file__).resolve().parent.parent / "sql" / "create_indexes.sql"
    if not sql_path.exists():
        return [f"skip: {sql_path} not found"]

    raw = sql_path.read_text(encoding="utf-8")
    # Убираем однострочные комментарии и режем по «;»
    lines = []
    for line in raw.splitlines():
        stripped = line.split("--", 1)[0].strip()
        if stripped:
            lines.append(stripped)
    blob = " ".join(lines)
    statements = [s.strip() for s in blob.split(";") if s.strip()]

    applied: list[str] = []
    with engine.begin() as conn:
        for stmt in statements:
            conn.execute(text(stmt))
            applied.append(stmt.split("INDEX IF NOT EXISTS")[-1].split()[0].strip())
    return applied
