"""Агрегация по временным корзинам без TimescaleDB (plain PostgreSQL)."""

from sqlalchemy import Float, func


def time_bucket_seconds(ts_column, seconds: int, label: str = "period"):
    """Группировка по интервалу N секунд через floor(epoch / N)."""
    epoch = func.extract("epoch", ts_column).cast(Float)
    bucket = (func.floor(epoch / seconds) * seconds).cast(Float)
    return func.to_timestamp(bucket).label(label)


def bucket_1min(ts_column):
    return func.date_trunc("minute", ts_column).label("period")


def bucket_5min(ts_column):
    return time_bucket_seconds(ts_column, 300)


def bucket_6hours(ts_column):
    return time_bucket_seconds(ts_column, 6 * 3600)


def bucket_hour(ts_column):
    return func.date_trunc("hour", ts_column).label("period")


def bucket_day(ts_column):
    return func.date_trunc("day", ts_column).label("period")


def bucket_for_span_minutes(ts_column, span_minutes: int):
    if span_minutes <= 60:
        return bucket_1min(ts_column)
    if span_minutes <= 1440:
        return bucket_1min(ts_column)
    if span_minutes <= 10080:
        return bucket_hour(ts_column)
    if span_minutes <= 43200:
        return bucket_6hours(ts_column)
    return bucket_day(ts_column)
