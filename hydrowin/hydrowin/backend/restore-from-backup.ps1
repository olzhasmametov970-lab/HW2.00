# HydroWin: восстановление из backup
#
# Пример:
#   cd backend
#   .\restore-from-backup.ps1 -BackupDir .\backups\20260728_145526
#   .\restore-from-backup.ps1 -BackupDir .\backups\20260728_145526 -RestoreEnv
#   .\restore-from-backup.ps1 -BackupDir .\backups\20260728_145526 -Yes
#
# ВНИМАНИЕ: восстанавливает PostgreSQL поверх текущей БД (данные после дампа будут потеряны).

param(
    [Parameter(Mandatory = $true)]
    [string]$BackupDir,

    [switch]$RestoreEnv,
    [switch]$RestoreMosquittoConfig,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Test-Path $BackupDir)) {
    throw "Папка backup не найдена: $BackupDir"
}

$BackupDir = (Resolve-Path $BackupDir).Path
$dump = Join-Path $BackupDir 'hydrowin_pg_dump.sql'
$envBackup = Join-Path $BackupDir '.env.backup'

if (-not (Test-Path $dump)) {
    throw "Нет файла дампа: $dump"
}

Write-Host "Backup: $BackupDir"
Write-Host "Dump:   $dump"
Write-Host ""
Write-Host "Это ПЕРЕЗАПИШЕТ текущую базу hydrowin из дампа."
if (-not $Yes) {
    $answer = Read-Host "Продолжить? (yes/no)"
    if ($answer -ne 'yes') {
        Write-Host "Отменено."
        exit 0
    }
}

if ($RestoreEnv) {
    if (-not (Test-Path $envBackup)) {
        throw "Нет .env.backup в $BackupDir"
    }
    if (Test-Path '.\.env') {
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        Copy-Item '.\.env' ".\.env.before-restore-$stamp"
        Write-Host "Текущий .env сохранён как .env.before-restore-$stamp"
    }
    Copy-Item $envBackup '.\.env' -Force
    Write-Host "Восстановлен .env из .env.backup"
}

if ($RestoreMosquittoConfig) {
    $pairs = @(
        @{ Src = 'mosquitto.conf.backup'; Dst = '.\mosquitto\mosquitto.conf' },
        @{ Src = 'mosquitto.acl.backup'; Dst = '.\mosquitto\acl' },
        @{ Src = 'mosquitto.docker-entrypoint.sh.backup'; Dst = '.\mosquitto\docker-entrypoint.sh' }
    )
    foreach ($p in $pairs) {
        $src = Join-Path $BackupDir $p.Src
        if (Test-Path $src) {
            Copy-Item $src $p.Dst -Force
            Write-Host "Восстановлен $($p.Dst)"
        }
    }
}

Write-Host "Поднимаю db..."
docker compose up -d db
if ($LASTEXITCODE -ne 0) { throw 'docker compose up db failed' }

Write-Host "Жду готовности Postgres..."
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    docker compose exec -T db pg_isready -U hydrowin -d hydrowin | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $ready = $true
        break
    }
    Start-Sleep -Seconds 2
}
if (-not $ready) {
    throw 'Postgres не готов'
}

Write-Host "Останавливаю api (чтобы не писала в БД во время restore)..."
docker compose stop api | Out-Null

Write-Host "Восстанавливаю SQL dump..."
Get-Content -Path $dump -Raw | docker compose exec -T db psql -U hydrowin -d hydrowin
if ($LASTEXITCODE -ne 0) {
    throw 'psql restore failed'
}

Write-Host "Запускаю сервисы..."
docker compose up -d
if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed' }

Start-Sleep -Seconds 4
Write-Host ""
Write-Host "Статус:"
docker compose ps
Write-Host ""
Write-Host "Проверка:"
try {
    $h = Invoke-RestMethod -Uri 'http://127.0.0.1:8090/health' -TimeoutSec 10
    Write-Host "local /health => $($h.status)"
} catch {
    Write-Host "local /health пока недоступен: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Restore завершён."
Write-Host "Помните: plaintext device_key в дампе нет — только api_key_hash."
Write-Host "Реестр устройств (если нужен): $(Join-Path $BackupDir 'device_registry.csv')"
