-- Индексы для ускорения графиков и опроса датчиков (PostgreSQL).
-- Безопасно запускать повторно: IF NOT EXISTS.

-- Основной запрос графиков: readings по sensor_id за период
CREATE INDEX IF NOT EXISTS ix_readings_sensor_id_ts
    ON readings (sensor_id, ts DESC);

-- Запросы по машине за период (fleet / machines endpoint)
CREATE INDEX IF NOT EXISTS ix_readings_machine_id_ts
    ON readings (machine_id, ts DESC);

-- Комбинированный фильтр machine + sensor + время
CREATE INDEX IF NOT EXISTS ix_readings_machine_sensor_ts
    ON readings (machine_id, sensor_id, ts DESC);

-- Поиск машины по IP (location_label) — используется Flutter
CREATE INDEX IF NOT EXISTS ix_machines_location_label
    ON machines (location_label);

-- Быстрый поиск датчика по машине и каналу (BLOCK worker)
CREATE UNIQUE INDEX IF NOT EXISTS ix_sensors_machine_channel
    ON sensors (machine_id, channel_index);

-- События / уведомления по машине
CREATE INDEX IF NOT EXISTS ix_events_machine_id_ts
    ON events (machine_id, ts DESC);
