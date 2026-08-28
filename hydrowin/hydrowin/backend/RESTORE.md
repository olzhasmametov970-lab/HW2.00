# Restore из backup

## Что уже есть

Папка бэкапа, например:

```text
backend/backups/20260728_145526/
  .env.backup
  hydrowin_pg_dump.sql
  device_registry.csv
  ...
```

## Быстрое восстановление БД

Из папки `backend`:

```powershell
cd C:\Users\Admin2\Desktop\HW2.0\hydrowin\hydrowin\backend

# только PostgreSQL (текущий .env не трогаем)
.\restore-from-backup.ps1 -BackupDir .\backups\20260728_145526 -Yes

# БД + .env из бэкапа
.\restore-from-backup.ps1 -BackupDir .\backups\20260728_145526 -RestoreEnv -Yes

# БД + .env + конфиги Mosquitto
.\restore-from-backup.ps1 -BackupDir .\backups\20260728_145526 -RestoreEnv -RestoreMosquittoConfig -Yes
```

Без `-Yes` скрипт спросит подтверждение.

## Что делает скрипт

1. поднимает Postgres;
2. останавливает `api`, чтобы не писала в БД;
3. заливает `hydrowin_pg_dump.sql` в базу `hydrowin`;
4. поднимает все сервисы снова;
5. проверяет `http://127.0.0.1:8090/health`.

## После restore

```powershell
docker compose ps
docker compose logs --tail 50 api
curl.exe -s http://127.0.0.1:8090/health
curl.exe -s https://app.hydrowin.ru/v1/health
```

## Важно

- Restore **перезаписывает** текущую БД данными из дампа.
- В дампе **нет plaintext `device_key`**, только `api_key_hash`.
- Plaintext ключи храните отдельно (реестр плат / Serial / ответ create device).
- Перед restore скрипт при `-RestoreEnv` сохраняет текущий `.env` как `.env.before-restore-YYYYMMDD_HHMMSS`.
