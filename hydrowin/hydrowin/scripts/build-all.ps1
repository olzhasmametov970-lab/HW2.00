param(
    [string]$ApiUrl = "",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $PSScriptRoot "release-config.ps1"

if (Test-Path $configPath) {
    . $configPath
}

if ([string]::IsNullOrWhiteSpace($ApiUrl)) {
    $ApiUrl = $ReleaseApiUrl
}
if ([string]::IsNullOrWhiteSpace($ApiUrl)) {
    $ApiUrl = "https://app.hydrowin.ru/v1"
}

$presetCloud = $true
$enableDemo = $true
if (Get-Variable -Name ReleasePresetCloud -ErrorAction SilentlyContinue) {
    $presetCloud = [bool]$ReleasePresetCloud
}
if (Get-Variable -Name ReleaseEnableDemo -ErrorAction SilentlyContinue) {
    $enableDemo = [bool]$ReleaseEnableDemo
}

$releaseRoot = Join-Path $root "release"
$androidOut = Join-Path $releaseRoot "android"
$windowsOut = Join-Path $releaseRoot "windows"
$webOut = Join-Path $releaseRoot "web"
$app = Join-Path $root "mobile\hydrowin"

Write-Host "=== HydroWin build: Android + Windows + Web ===" -ForegroundColor Cyan
Write-Host "API: $ApiUrl"

$okAndroid = $false
$okWindows = $false
$okWeb = $false

if (-not $SkipBuild) {
    $commonArgs = @{
        ApiUrl = $ApiUrl
        PresetCloud = $presetCloud
        EnableDemo = $enableDemo
    }

    Write-Host "--- Android ---" -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot "build-android.ps1") @commonArgs
    if ($LASTEXITCODE -eq 0) { $okAndroid = $true }

    Write-Host "--- Windows ---" -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot "build-windows.ps1") @commonArgs
    if ($LASTEXITCODE -eq 0) { $okWindows = $true }

    Write-Host "--- Web ---" -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot "build-web.ps1") @commonArgs
    if ($LASTEXITCODE -eq 0) { $okWeb = $true }
}

New-Item -ItemType Directory -Force -Path $androidOut, $windowsOut, $webOut | Out-Null

$apkSrc = Join-Path $app "build\app\outputs\flutter-apk\app-full-release.apk"
$apkDst = Join-Path $androidOut "GidroVin.apk"
if (-not (Test-Path $apkSrc)) {
    $legacy = Join-Path $app "build\app\outputs\flutter-apk\app-release.apk"
    if (Test-Path $legacy) { $apkSrc = $legacy }
}
if (Test-Path $apkSrc) {
    Copy-Item -Force $apkSrc $apkDst
    New-Item -ItemType Directory -Force -Path "C:\GidroVin\Android" | Out-Null
    Copy-Item -Force $apkSrc "C:\GidroVin\Android\GidroVin.apk"
    $okAndroid = $true
    @(
        "GidroVin Android (full)"
        ""
        "File: GidroVin.apk"
        "Lite: run Sobrat-Lite-APK.bat -> GidroVin-Lite.apk"
        "Install via USB (not messengers)."
        "API: $ApiUrl"
        ""
        "Modes: Cloud login / One machine / Fleet"
        "Demo mode: off (production)"
    ) | Set-Content -Path (Join-Path $androidOut "README.txt") -Encoding UTF8
}

$winExe = Join-Path $app "build\windows\x64\runner\Release\hydrowin.exe"
if (Test-Path $winExe) {
    Get-ChildItem (Split-Path $winExe) | Copy-Item -Destination $windowsOut -Recurse -Force
    $okWindows = $true
    @"
@echo off
cd /d "%~dp0"
start "" "hydrowin.exe"
"@ | Set-Content -Path (Join-Path $windowsOut "START.bat") -Encoding ASCII
} else {
    @(
        "Windows .exe not built yet."
        ""
        "Install Visual Studio 2022 with:"
        "  Desktop development with C++"
        ""
        "Then run: Sobrat-prilozheniya.bat"
    ) | Set-Content -Path (Join-Path $windowsOut "NEED-VISUAL-STUDIO.txt") -Encoding UTF8
}

$webIndex = Join-Path $app "build\web\index.html"
if (Test-Path $webIndex) {
    Get-ChildItem (Split-Path $webIndex) | Copy-Item -Destination $webOut -Recurse -Force
    $okWeb = $true
    @"
@echo off
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
"@ | Set-Content -Path (Join-Path $webOut "START.bat") -Encoding ASCII
}

$statusAndroid = if ($okAndroid) { "OK - GidroVin.apk" } else { "NOT READY" }
$statusWindows = if ($okWindows) { "OK - START.bat" } else { "NOT READY - see windows\NEED-VISUAL-STUDIO.txt" }
$statusWeb = if ($okWeb) { "OK - START.bat" } else { "NOT READY" }

@(
    "HydroWin release folder"
    "======================="
    ""
    "Path: $releaseRoot"
    ""
    "Android: $statusAndroid"
    "Windows: $statusWindows"
    "Web:     $statusWeb"
    ""
    "API: $ApiUrl"
    "Modes: Cloud login / Fleet (demo off for production)"
) | Set-Content -Path (Join-Path $releaseRoot "README.txt") -Encoding UTF8

Write-Host ""
Write-Host "Release folder: $releaseRoot" -ForegroundColor Green
Write-Host "  Android: $(if ($okAndroid) { 'OK' } else { 'missing' })"
Write-Host "  Windows: $(if ($okWindows) { 'OK' } else { 'missing' })"
Write-Host "  Web:     $(if ($okWeb) { 'OK' } else { 'missing' })"

if (-not $okAndroid -and -not $okWindows -and -not $okWeb) { exit 1 }
