# Безопасность HydroWin

## Уже в коде

### Backend
- JWT access (15 мин) + refresh rotation; logout отзывает все refresh пользователя
- Пароли: bcrypt + буквы/цифры/спецсимвол (10–72)
- Device keys только как SHA-256; `ensure-device` **запрещён** при `ENVIRONMENT=production`
- Rate limit на `/auth/*` и `/ingest/telemetry` (ключ по `X-Real-IP` от Caddy)
- Публичная регистрация выкл. (`ALLOW_PUBLIC_REGISTER=false`)
- CORS без `*`+credentials; localhost в CORS запрещён в production
- `/docs` / OpenAPI скрыты при `ENVIRONMENT=production`
- Production старт падает при слабом `JWT_SECRET` / demo device key / неполном SMTP|Telegram (если включены)
- В production **не** сидится демо-парк (HydroMaker / Client*) и lab-машина BLOCK
- Заглушка `/v1/data` удалена

### Mobile
- Токены в Keystore/Keychain (`encryptedSharedPreferences: true`)
- Wi‑Fi пароль / APN pass / device key — secure storage
- Android: `allowBackup=false`, cleartext только localhost/эмулятор
- `ENABLE_DEMO` по умолчанию **false**; release-скрипты — demo off
- Developer-пароль только через `--dart-define=DEV_PASSWORD=...` (пустой = закрыто)
- Кастомный API: HTTPS вне LAN

### Firmware
- Телеметрия по умолчанию: **HTTPS** (`TELEMETRY_TRANSPORT 0`)
- `TLS_INSECURE=0` по умолчанию; CA Let's Encrypt (ISRG Root X1)
- Placeholder `DEVICE_KEY` / `MACHINE_ID` / пустой Wi‑Fi — задаются Serial/BLE/NVS
- MQTT `:1883` только LAN (`TELEMETRY_TRANSPORT 2`), не для продакшена

### Docker
- PostgreSQL и API **не** публикуются на хост (только Caddy :80/:443)
- MQTT слушает только `127.0.0.1:1883`
- **sslip.io** не в `API_DOMAIN`; Caddy отвечает 410 на `5-165-27-141.sslip.io`

## Сделать на сервере вручную

1. **HTTPS + DNS** — `app.hydrowin.ru` → API (см. `DEPLOY-HTTPS.md`, `website/CABINET.md`)
2. Сменить `JWT_SECRET`, пароль БД (`hydrowin_secret` недопустим на рынке), уникальные device keys
3. Сменить пароли существующих учёток
4. Firewall: 443 (+ SSH); не публиковать 5432/8090/1883
5. Ротировать SMTP / Telegram / OpenCellID, если секреты светились
6. Полный чеклист: `PRODUCTION_READY.md`

```bash
python -c "import secrets; print(secrets.token_urlsafe(48))"
```
