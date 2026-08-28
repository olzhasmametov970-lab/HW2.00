# Несколько ESP32 на одной станции

Одна **машина** (`MACHINE_ID`) = одна станция в приложении.  
Несколько **плат** = несколько `DEVICE_KEY`, каналы датчиков не пересекаются.

## Создать ключ для платы (PowerShell)

```powershell
$login = Invoke-RestMethod -Method POST "http://5.165.27.141:8090/v1/auth/login" `
  -ContentType "application/json" `
  -Body '{"email":"maker@hydrowin.ru","password":"HydroMaker2026!"}'
$token = $login.access_token

# UUID станции (один на все платы этой станции)
$machineId = "f4c32e25-bbdb-4d89-bb9d-9ac30573606c"

# Плата 1
Invoke-RestMethod -Method POST "http://5.165.27.141:8090/v1/machines/id/$machineId/devices" `
  -Headers @{ Authorization = "Bearer $token" } `
  -ContentType "application/json" `
  -Body '{"device_id":"ESP32-HYDRO-01"}'

# Плата 2
Invoke-RestMethod -Method POST "http://5.165.27.141:8090/v1/machines/id/$machineId/devices" `
  -Headers @{ Authorization = "Bearer $token" } `
  -ContentType "application/json" `
  -Body '{"device_id":"ESP32-HYDRO-02"}'
```

В ответе сохрани **`device_key`** (показывается один раз) → в `config.h` как `DEVICE_KEY`.

## config.h

| Плата | MACHINE_ID | DEVICE_ID | DEVICE_KEY | Каналы |
|-------|------------|-----------|------------|--------|
| 1 | одинаковый | ESP32-HYDRO-01 | ключ1 | 0, 1 |
| 2 | одинаковый | ESP32-HYDRO-02 | ключ2 | 2, 3 |

Список ключей (без секретов):

```powershell
Invoke-RestMethod -Method GET "http://5.165.27.141:8090/v1/machines/id/$machineId/devices" `
  -Headers @{ Authorization = "Bearer $token" }
```

После создания ключей перезапусти Docker / API, если бэкенд ещё без этих эндпоинтов.
