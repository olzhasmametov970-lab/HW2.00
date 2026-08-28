# Safe API recreate on Windows Docker Desktop.
# Avoids "Starting" hang when host port 8090 is stuck in docker-proxy.
param(
  [switch]$Build
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Write-Host "==> Stopping api..."
docker compose stop api 2>$null
docker compose rm -f api 2>$null

# If something still listens on 8090 (legacy publish), wait briefly.
$deadline = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $deadline) {
  $busy = Get-NetTCPConnection -LocalPort 8090 -State Listen -ErrorAction SilentlyContinue
  if (-not $busy) { break }
  Start-Sleep -Seconds 1
}

if ($Build) {
  Write-Host "==> Building api..."
  docker compose build api
}

Write-Host "==> Starting api (internal :8090 only, via Caddy)..."
docker compose up -d api
docker compose ps api
Write-Host "==> Public health:"
try {
  (Invoke-RestMethod -Uri "https://app.hydrowin.ru/v1/health" -TimeoutSec 20) | ConvertTo-Json -Compress
} catch {
  Write-Host $_.Exception.Message
}
