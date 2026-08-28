# Две (и больше) плат → две разные машины

Каждая плата = **своя машина** в приложении.

| | Плата 1 | Плата 2 |
|---|---------|---------|
| `MACHINE_ID` | UUID машины A | UUID машины B |
| `DEVICE_KEY` | ключ A | ключ B |
| `DEVICE_ID` | ESP32-HYDRO-01 | ESP32-HYDRO-02 |
| Каналы | 0, 1 | 0, 1 |

Данные идут параллельно в **две карточки** в парке.

## PowerShell: ключ для машины B

```powershell
$login = Invoke-RestMethod -Method POST "http://5.165.27.141:8090/v1/auth/login" -ContentType "application/json" -Body '{"email":"maker@hydrowin.ru","password":"HydroMaker2026!"}'
$token = $login.access_token

# Список машин → возьми id второй станции
$machines = Invoke-RestMethod -Method GET "http://5.165.27.141:8090/v1/machines" -Headers @{ Authorization = "Bearer $token" }
$machines.items | Select-Object id, code, name

# Подставь UUID машины B
$machineB = "2253cd6d-2804-49a4-9bb4-8b4d0083eea2"

Invoke-RestMethod -Method POST "http://5.165.27.141:8090/v1/machines/id/$machineB/devices" `
  -Headers @{ Authorization = "Bearer $token" } `
  -ContentType "application/json" `
  -Body '{"device_id":"ESP32-HYDRO-02"}'
```

Сохрани из ответа `device_key` → в `config.h` платы 2.

## config.h платы 2 (пример)

```cpp
#define DEVICE_KEY         "ключ-из-ответа-API"
#define DEVICE_ID          "ESP32-HYDRO-02"
#define MACHINE_ID         "2253cd6d-2804-49a4-9bb4-8b4d0083eea2"
#define CHANNEL_PRESSURE   0
#define CHANNEL_TEMP       1
```

Плата 1 остаётся на своём `MACHINE_ID` и своём ключе (можно оставить старый `hydro-demo-...` после `ensure-device`, или тоже создать через `/devices`).
