#!/bin/sh
set -eu

PASSWD=/mosquitto/data/passwd
API_USER="${MQTT_API_USER:-hydrowin-api}"
API_PASS="${MQTT_API_PASSWORD:-change-me-mqtt-api}"
DEV_USER="${MQTT_DEVICE_USER:-hydrowin-device}"
DEV_PASS="${MQTT_DEVICE_PASSWORD:-change-me-mqtt-device}"

mkdir -p /mosquitto/config /mosquitto/data /mosquitto/log

# Recreate passwd on each start from env.
mosquitto_passwd -b -c "$PASSWD" "$API_USER" "$API_PASS"
mosquitto_passwd -b "$PASSWD" "$DEV_USER" "$DEV_PASS"
chown mosquitto:mosquitto "$PASSWD" 2>/dev/null || true
chmod 0640 "$PASSWD"

exec /usr/sbin/mosquitto -c /mosquitto/config/mosquitto.conf
