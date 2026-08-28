"""MQTT subscriber: телеметрия плат → ingest_telemetry.

Топик: hydrowin/telemetry/{device_id}
Payload: industrial {"d":[[ts,p0,t1,t2,p1],...]} или verbose JSON,
плюс device_key (аналог X-Device-Key).
"""

from __future__ import annotations

import asyncio
import json
import logging
import threading
from typing import Any

from app.config import settings
from app.database import SessionLocal
from app.models import Device
from app.security import hash_device_key
from app.seed import ingest_telemetry
from app.telemetry_format import normalize_telemetry_payloads

logger = logging.getLogger("hydrowin.mqtt")

TOPIC_PREFIX = "hydrowin/telemetry/"


def _parse_topic_device_id(topic: str) -> str | None:
    if not topic.startswith(TOPIC_PREFIX):
        return None
    device_id = topic[len(TOPIC_PREFIX) :].strip()
    if not device_id or "/" in device_id:
        return None
    return device_id


def _handle_message(topic: str, payload: bytes) -> None:
    topic_device = _parse_topic_device_id(topic)
    if topic_device is None:
        logger.warning("MQTT: игнор топика %s", topic)
        return

    try:
        data: dict[str, Any] = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        logger.warning("MQTT: плохой JSON на %s: %s", topic, exc)
        return

    device_key = str(data.pop("device_key", "") or data.pop("api_key", "") or "").strip()
    if not device_key:
        logger.warning("MQTT: нет device_key в payload (%s)", topic_device)
        return

    body_device = str(data.get("device_id") or "").strip()
    if body_device and body_device != topic_device:
        logger.warning(
            "MQTT: device_id в теле ≠ топик (%s vs %s)", body_device, topic_device
        )
        return
    data["device_id"] = topic_device

    key_hash = hash_device_key(device_key)
    db = SessionLocal()
    try:
        device = db.query(Device).filter(Device.api_key_hash == key_hash).first()
        if device is None:
            logger.warning("MQTT: неверный device_key для %s", topic_device)
            return
        if device.device_id != topic_device:
            logger.warning(
                "MQTT: ключ принадлежит %s, топик %s", device.device_id, topic_device
            )
            return
        payloads = normalize_telemetry_payloads(data, device)
        last_mid = None
        for payload in payloads:
            ingest_telemetry(db, device, payload)
            last_mid = payload.get("message_id")
        print(f"MQTT: accepted {topic_device} msg={last_mid}", flush=True)
        logger.info("MQTT: accepted %s msg=%s", topic_device, last_mid)
    except ValueError as exc:
        print(f"MQTT: reject {topic_device}: {exc}", flush=True)
        logger.warning("MQTT: reject %s: %s", topic_device, exc)
        db.rollback()
    except Exception as exc:
        print(f"MQTT: ошибка ingest {topic_device}: {exc}", flush=True)
        logger.exception("MQTT: ошибка ingest %s", topic_device)
        db.rollback()
    finally:
        db.close()


class MqttTelemetryWorker:
    """Фоновый поток с paho-mqtt (не блокирует event loop FastAPI)."""

    def __init__(self) -> None:
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()

    def start(self) -> None:
        if not settings.mqtt_enabled:
            print("   MQTT-воркер: ВЫКЛ")
            return
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(
            target=self._run, name="mqtt-telemetry", daemon=True
        )
        self._thread.start()
        print(
            f"   MQTT-воркер: ВКЛ  "
            f"{settings.mqtt_host}:{settings.mqtt_port}  "
            f"topic={TOPIC_PREFIX}#"
        )

    def stop(self) -> None:
        self._stop.set()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=5)

    def _run(self) -> None:
        try:
            import paho.mqtt.client as mqtt
        except ImportError:
            logger.error("paho-mqtt не установлен — MQTT выключен")
            return

        client = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION2,
            client_id=settings.mqtt_client_id,
            protocol=mqtt.MQTTv311,
        )
        client.username_pw_set(settings.mqtt_api_user, settings.mqtt_api_password)

        def on_connect(client, userdata, flags, reason_code, properties=None):
            rc = getattr(reason_code, "value", reason_code)
            if rc == 0:
                client.subscribe(f"{TOPIC_PREFIX}#", qos=1)
                logger.info("MQTT connected, subscribed %s#", TOPIC_PREFIX)
            else:
                logger.error("MQTT connect failed rc=%s", reason_code)

        def on_message(client, userdata, msg):
            try:
                _handle_message(msg.topic, msg.payload)
            except Exception:
                logger.exception("MQTT on_message")

        client.on_connect = on_connect
        client.on_message = on_message

        while not self._stop.is_set():
            try:
                client.connect(settings.mqtt_host, settings.mqtt_port, keepalive=60)
                client.loop_start()
                while not self._stop.is_set():
                    self._stop.wait(1.0)
                client.loop_stop()
                client.disconnect()
            except Exception as exc:
                logger.warning("MQTT reconnect soon: %s", exc)
                self._stop.wait(settings.mqtt_reconnect_seconds)


mqtt_worker = MqttTelemetryWorker()


async def start_mqtt_worker() -> None:
    """Запуск из FastAPI lifespan (thread)."""
    await asyncio.to_thread(mqtt_worker.start)


async def stop_mqtt_worker() -> None:
    await asyncio.to_thread(mqtt_worker.stop)
