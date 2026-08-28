param(
    [string]$ApiUrl = "",
    [bool]$PresetCloud = $true,
    [bool]$EnableDemo = $false
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $PSScriptRoot "release-config.ps1"
if (Test-Path $configPath) { . $configPath }
if ([string]::IsNullOrWhiteSpace($ApiUrl)) { $ApiUrl = $ReleaseApiUrl }
# Публичный API (тот же хост, что и web, путь /v1)
if ([string]::IsNullOrWhiteSpace($ApiUrl)) {
    $ApiUrl = "https://app.hydrowin.ru/v1"
}
if (Get-Variable -Name ReleasePresetCloud -ErrorAction SilentlyContinue) {
    $PresetCloud = [bool]$ReleasePresetCloud
}
if (Get-Variable -Name ReleaseEnableDemo -ErrorAction SilentlyContinue) {
    $EnableDemo = [bool]$ReleaseEnableDemo
}

$app = Join-Path $root "mobile\hydrowin"
# Web = только Full (облако). Lite BLE в браузере не имеет смысла.
$defines = @(
    "--dart-define=APP_VARIANT=full",
    "--dart-define=API_BASE_URL=$ApiUrl"
)
if ($PresetCloud) { $defines += "--dart-define=PRESET_CLOUD=true" }
if ($EnableDemo) { $defines += "--dart-define=ENABLE_DEMO=true" }
if (Get-Variable -Name ReleaseCartoBasemapKey -ErrorAction SilentlyContinue) {
    if (-not [string]::IsNullOrWhiteSpace($ReleaseCartoBasemapKey)) {
        $defines += "--dart-define=CARTO_BASEMAP_KEY=$ReleaseCartoBasemapKey"
    }
}

Set-Location $app
flutter pub get
flutter build web --release @defines
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$webBuild = Join-Path $app "build\web"
$webOut = Join-Path $root "release\web"
$backendWeb = Join-Path $root "backend\web"
$gidroVinWeb = "C:\GidroVin\Web"
New-Item -ItemType Directory -Force -Path $webOut, $backendWeb, $gidroVinWeb | Out-Null

# Чистая копия (без README.txt-заглушки мешать не будет — перезапишем)
Get-ChildItem $backendWeb -Force | Where-Object { $_.Name -ne ".gitkeep" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem $webBuild -Force | Copy-Item -Destination $webOut -Recurse -Force
Get-ChildItem $webBuild -Force | Copy-Item -Destination $backendWeb -Recurse -Force
Get-ChildItem $webBuild -Force | Copy-Item -Destination $gidroVinWeb -Recurse -Force

$startBat = @"
@echo off
chcp 65001 >nul
cd /d "%~dp0"
set PORT=8765
where python >nul 2>&1
if errorlevel 1 (
  echo Install Python from python.org
  pause
  exit /b 1
)
start "" "http://127.0.0.1:%PORT%"
python -m http.server %PORT% --bind 127.0.0.1
"@
Set-Content (Join-Path $webOut "START.bat") -Value $startBat -Encoding ASCII
Set-Content (Join-Path $gidroVinWeb "START.bat") -Value $startBat -Encoding ASCII

$sanitize = Join-Path (Split-Path -Parent $PSScriptRoot) "scripts\sanitize-release.ps1"
if (Test-Path $sanitize) {
    & $sanitize -Targets @($webOut, $gidroVinWeb)
}

Write-Host ""
Write-Host "Web Full: $webOut" -ForegroundColor Green
Write-Host "Backend static (Caddy): $backendWeb" -ForegroundColor Green
Write-Host "Локально: $gidroVinWeb\START.bat" -ForegroundColor Green
Write-Host ""
Write-Host "На Ubuntu после scp backend/web:" -ForegroundColor Yellow
Write-Host "  cd ~/hydrowin-backend && docker compose restart caddy" -ForegroundColor Yellow
Write-Host "Открыть: https://app.hydrowin.ru/" -ForegroundColor Yellow
