# Ротация X-Device-Key для плат HydroWin (production API).
# Новые ключи сохраняются локально в device-keys-LOCAL.txt (в .gitignore).
#
# Использование:
#   cd hydrowin\hydrowin\scripts
#   .\rotate-device-keys.ps1
#
# После скрипта на каждой плате Serial 115200:
#   KEY <новый_device_key>
#   CFG

param(
    [string]$ApiBase = "https://app.hydrowin.ru/v1",
    [string]$AdminEmail = "admin@hydrowin.ru",
    [string]$OutFile = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutFile)) {
    $OutFile = Join-Path (Split-Path -Parent $PSScriptRoot) "device-keys-LOCAL.txt"
}

# Машины из старых serial_board*.txt (утекли в git). Правьте список при необходимости.
$Targets = @(
    @{ machine_id = "f4c32e25-bbdb-4d89-bb9d-9ac30573606c"; device_id = "ESP32-HYDRO-01" },
    @{ machine_id = "5ccd879f-1432-4f9b-9f12-b053d6444ed2"; device_id = "HW-HYDRO-03" },
    @{ machine_id = "8ff52953-d03d-4228-a263-367a6e631e63"; device_id = "HW-HYDRO-04" },
    @{ machine_id = "2253cd6d-2804-49a4-9bb4-8b4d0083eea2"; device_id = "ESP32-HYDRO-02" }
)

$secure = Read-Host "Пароль admin ($AdminEmail)" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

Write-Host "Login $ApiBase ..."
$login = Invoke-RestMethod -Method Post -Uri "$ApiBase/auth/login" `
    -ContentType "application/json" `
    -Body (@{ email = $AdminEmail; password = $plain } | ConvertTo-Json)

$hdr = @{ Authorization = "Bearer $($login.access_token)" }
$results = @()
$ts = (Get-Date).ToString("yyyy-MM-dd HH:mm")

foreach ($t in $Targets) {
    $mid = $t.machine_id
    $did = $t.device_id
    Write-Host "`n--- $did  machine=$mid ---"

    $list = Invoke-RestMethod -Uri "$ApiBase/machines/id/$mid/devices" -Headers $hdr
    $old = $list.items | Where-Object { $_.device_id -eq $did } | Select-Object -First 1

    if ($old) {
        Write-Host "Delete old device row $($old.id) ..."
        Invoke-RestMethod -Method Delete -Uri "$ApiBase/machines/id/$mid/devices/$($old.id)" -Headers $hdr | Out-Null
    } else {
        Write-Host "Old device not found (maybe already rotated)."
    }

    Write-Host "Create new key for $did ..."
    $created = Invoke-RestMethod -Method Post -Uri "$ApiBase/machines/id/$mid/devices" `
        -Headers $hdr -ContentType "application/json" `
        -Body (@{ device_id = $did } | ConvertTo-Json)

    $results += [PSCustomObject]@{
        date       = $ts
        device_id  = $created.device_id
        machine_id = $created.machine_id
        device_key = $created.device_key
    }
    Write-Host "OK new key for $did"
}

$header = @"
# HydroWin device keys — НЕ КОММИТИТЬ. Сгенерировано rotate-device-keys.ps1
# Serial на плате: KEY <device_key>
# date: $ts

"@

$lines = $results | ForEach-Object {
    "device_id=$($_.device_id)`nmachine_id=$($_.machine_id)`ndevice_key=$($_.device_key)`n---"
}
Set-Content -Path $OutFile -Value ($header + ($lines -join "`n")) -Encoding UTF8

Write-Host "`nSaved: $OutFile" -ForegroundColor Green
Write-Host "На каждой плате: KEY <device_key>  затем CFG" -ForegroundColor Yellow
