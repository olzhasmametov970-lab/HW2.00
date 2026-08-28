FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY sql ./sql

ENV PYTHONUNBUFFERED=1
ENV UVICORN_WORKERS=1
EXPOSE 8090

# 1 worker: lifespan (create_all / MQTT / purge) безопасен.
# Масштаб: поднять workers после выноса миграций из lifespan.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port 8090 --workers ${UVICORN_WORKERS:-1}"]
