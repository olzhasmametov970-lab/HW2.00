# Деплой HydroWin backend на 5.165.27.141 (Windows Server + Docker)
# Запуск С СЕРВЕРА (через RDP) или удалённо через WinRM с этой машины:
#
#   cd C:\Users\Admin2\Desktop\HW2.0\hydrowin\hydrowin\backend
#   .\deploy-to-prod.ps1
#
# Телеметрия: платы шлют HTTPS POST /v1/ingest/telemetry + X-Device-Key.

$ErrorActionPreference = "Stop"

$RemoteHost = "5.165.27.141"
$User = "Admin2"
$LocalBackend = $PSScriptRoot
$RemoteBackend = "C:\hydrowin\backend"

Write-Host "=== HydroWin deploy to $RemoteHost ===" -ForegroundColor Cyan
Write-Host "Local:  $LocalBackend"
Write-Host "Remote: $RemoteBackend"
Write-Host ""
Write-Host "Сначала найдём backend на сервере (docker compose)."
Write-Host "Нужен пароль Admin2 для WinRM."
Write-Host ""

$secure = Read-Host -AsSecureString "Password for ${User}@${RemoteHost}"
$cred = New-Object System.Management.Automation.PSCredential($User, $secure)

$session = New-PSSession -ComputerName $RemoteHost -Credential $cred -ErrorAction Stop

try {
    Write-Host "`n[1/5] Inspect remote..." -ForegroundColor Yellow
    Invoke-Command -Session $session -ScriptBlock {
        $env:COMPUTERNAME
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>&1
        Write-Host "---"
        @(
            "C:\hydrowin\backend",
            "C:\hydrowin\hydrowin\backend",
            "D:\hydrowin\backend",
            "$env:USERPROFILE\hydrowin\backend",
            "C:\Users\Admin2\hydrowin\backend"
        ) | ForEach-Object {
            if (Test-Path $_) { Write-Host "FOUND: $_" }
        }
        Get-ChildItem -Path C:\, D:\ -Filter "docker-compose.yml" -Recurse -ErrorAction SilentlyContinue -Depth 4 |
            Where-Object { $_.FullName -match "hydrowin|backend" } |
            Select-Object -ExpandProperty FullName
    }

    Write-Host "`nEnter remote backend path (must contain docker-compose.yml), or press Enter for $RemoteBackend"
    $entered = Read-Host "Path"
    if (-not [string]::IsNullOrWhiteSpace($entered)) {
        $RemoteBackend = $entered.Trim()
    }

    Write-Host "`n[2/5] Sync backend files (app/, sql/, Dockerfile, compose, env)..." -ForegroundColor Yellow
    Invoke-Command -Session $session -ScriptBlock {
        param($p)
        New-Item -ItemType Directory -Force -Path $p | Out-Null
        New-Item -ItemType Directory -Force -Path "$p\app" | Out-Null
        New-Item -ItemType Directory -Force -Path "$p\sql" | Out-Null
    } -ArgumentList $RemoteBackend

    # Copy trees
    Copy-Item -Path "$LocalBackend\app\*" -Destination (Join-Path "\\$RemoteHost\$(($RemoteBackend -replace ':', '$'))\app") -Recurse -Force -ErrorAction SilentlyContinue
    # UNC may fail if admin share disabled — fall back to PSSession Copy-Item
    $destOk = $false
    try {
        Copy-Item -ToSession $session -Path "$LocalBackend\app" -Destination $RemoteBackend -Recurse -Force
        Copy-Item -ToSession $session -Path "$LocalBackend\sql" -Destination $RemoteBackend -Recurse -Force
        Copy-Item -ToSession $session -Path "$LocalBackend\Dockerfile" -Destination $RemoteBackend -Force
        Copy-Item -ToSession $session -Path "$LocalBackend\docker-compose.yml" -Destination $RemoteBackend -Force
        Copy-Item -ToSession $session -Path "$LocalBackend\requirements.txt" -Destination $RemoteBackend -Force
        if (Test-Path "$LocalBackend\.env.production") {
            Copy-Item -ToSession $session -Path "$LocalBackend\.env.production" -Destination "$RemoteBackend\.env.production" -Force
        }
        $destOk = $true
    }
    catch {
        Write-Host "Copy-Item -ToSession failed: $_" -ForegroundColor Red
        throw
    }

    if (-not $destOk) { throw "File sync failed" }

    Write-Host "`n[3/5] Ensure .env exists on server..." -ForegroundColor Yellow
    Invoke-Command -Session $session -ScriptBlock {
        param($p)
        $envPath = Join-Path $p ".env"
        if (-not (Test-Path $envPath)) {
            if (Test-Path (Join-Path $p ".env.production")) {
                Copy-Item (Join-Path $p ".env.production") $envPath
                Write-Host "Created .env from .env.production"
            }
            else {
                throw ".env not found in $p — create it manually"
            }
        }
        Write-Host "--- .env (redacted secrets) ---"
        Get-Content $envPath | ForEach-Object {
            if ($_ -match "SECRET|PASSWORD|KEY") { ($_ -replace "=.*", "=***") } else { $_ }
        }
    } -ArgumentList $RemoteBackend

    Write-Host "`n[4/5] docker compose build && up -d api ..." -ForegroundColor Yellow
    Invoke-Command -Session $session -ScriptBlock {
        param($p)
        Set-Location $p
        docker compose build api
        if ($LASTEXITCODE -ne 0) { throw "docker compose build failed" }
        docker compose up -d api
        if ($LASTEXITCODE -ne 0) { throw "docker compose up failed" }
        Start-Sleep -Seconds 3
        docker compose ps
        docker compose logs --tail 40 api
    } -ArgumentList $RemoteBackend

    Write-Host "`n[5/5] Smoke checks..." -ForegroundColor Yellow
    Invoke-Command -Session $session -ScriptBlock {
        curl.exe -s -w "`nHTTP:%{http_code}`n" "http://127.0.0.1:8090/v1/machines" | Select-Object -First 5
        curl.exe -s -w "`nHTTP:%{http_code}`n" "http://127.0.0.1:8090/v1/admin/ensure-device?machine_id=5cfce6fe-ac6b-413e-a3d2-0eecdc04df67"
    }

    Write-Host "`n=== DONE ===" -ForegroundColor Green
    Write-Host "Проверьте логи api: ingest идёт через HTTPS POST /v1/ingest/telemetry."
}
finally {
    Remove-PSSession $session -ErrorAction SilentlyContinue
}
