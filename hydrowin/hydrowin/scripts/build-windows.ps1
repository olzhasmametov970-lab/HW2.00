param(
    [string]$ApiUrl = "",
    [bool]$PresetCloud = $true,
    [bool]$EnableDemo = $false,
    [ValidateSet("full", "lite")]
    [string]$Variant = "full"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $PSScriptRoot "release-config.ps1"
if (Test-Path $configPath) { . $configPath }
if ([string]::IsNullOrWhiteSpace($ApiUrl)) { $ApiUrl = $ReleaseApiUrl }
if ([string]::IsNullOrWhiteSpace($ApiUrl)) { $ApiUrl = "https://app.hydrowin.ru/v1" }
if (Get-Variable -Name ReleasePresetCloud -ErrorAction SilentlyContinue) {
    $PresetCloud = [bool]$ReleasePresetCloud
}
if (Get-Variable -Name ReleaseEnableDemo -ErrorAction SilentlyContinue) {
    $EnableDemo = [bool]$ReleaseEnableDemo
}

$mingit = "C:\flutter\bin\mingit\cmd"
if (Test-Path $mingit) {
    $env:Path = "$mingit;C:\flutter\bin;$env:Path"
}

$defines = @("--dart-define=APP_VARIANT=$Variant")
if ($Variant -eq "lite") {
    $PresetCloud = $false
    $defines += "--dart-define=ENABLE_DEMO=true"
} else {
    $defines += "--dart-define=API_BASE_URL=$ApiUrl"
    if ($PresetCloud) { $defines += "--dart-define=PRESET_CLOUD=true" }
    if ($EnableDemo) { $defines += "--dart-define=ENABLE_DEMO=true" }
}

if (Get-Variable -Name ReleaseCartoBasemapKey -ErrorAction SilentlyContinue) {
    if (-not [string]::IsNullOrWhiteSpace($ReleaseCartoBasemapKey)) {
        $defines += "--dart-define=CARTO_BASEMAP_KEY=$ReleaseCartoBasemapKey"
    }
}

$buildRoot = "C:\hydrowin"
$app = Join-Path $buildRoot "mobile\hydrowin"
$winRelease = Join-Path $app "build\windows\x64\runner\Release"

if ($Variant -eq "lite") {
    $out = Join-Path $root "release\windows-lite"
    $gidroVinNew = "C:\GidroVin\Windows_Lite"
    $gidroVin = "C:\GidroVin\Windows_Lite_copy"
    $zipName = "GidroVin-Lite-Windows.zip"
} else {
    $out = Join-Path $root "release\windows"
    $gidroVinNew = "C:\GidroVin\Windows_new"
    $gidroVin = "C:\GidroVin\Windows"
    $zipName = "GidroVin-Windows.zip"
}

if (-not (Test-Path $buildRoot)) {
    New-Item -ItemType Directory -Path $buildRoot | Out-Null
}

Write-Host "Variant: $Variant" -ForegroundColor Cyan
Write-Host "Sync project -> $buildRoot" -ForegroundColor Cyan
robocopy $root $buildRoot /MIR /XD build .dart_tool .gradle ephemeral /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null

Set-Location $app
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter config --enable-windows-desktop

$iconScript = Join-Path $app "scripts\regenerate-windows-icon.py"
if (Test-Path $iconScript) {
    Write-Host "Regenerating Windows app icon..." -ForegroundColor Cyan
    python $iconScript
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

function Invoke-WindowsDartRebuild {
    param([string[]]$BuildDefines)
    $hashRoot = Join-Path $app ".dart_tool\flutter_build"
    if (-not (Test-Path $hashRoot)) { return $false }
    $hashDir = Get-ChildItem $hashRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $hashDir) { return $false }
    foreach ($stamp in @(
            "kernel_snapshot_program.stamp",
            "aot_elf_release.stamp",
            "windows_aot_bundle.stamp",
            "release_bundle_windows-x64_assets.stamp"
        )) {
        Remove-Item (Join-Path $hashDir.FullName $stamp) -Force -ErrorAction SilentlyContinue
    }
    $msbuild = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
    if (-not $msbuild) { return $false }
    $assembleProj = Join-Path $app "build\windows\x64\flutter\flutter_assemble.vcxproj"
    if (-not (Test-Path $assembleProj)) { return $false }
    & $msbuild $assembleProj /p:Configuration=Release /p:Platform=x64 /m | Out-Null
    if ($LASTEXITCODE -ne 0) { return $false }

    $releaseData = Join-Path $winRelease "data"
    New-Item -ItemType Directory -Force -Path $releaseData | Out-Null
    Copy-Item -Force (Join-Path $app "build\windows\app.so") (Join-Path $releaseData "app.so")
    $assetsSrc = Join-Path $app "build\flutter_assets"
    if (Test-Path $assetsSrc) {
        $assetsDest = Join-Path $releaseData "flutter_assets"
        if (Test-Path $assetsDest) { Remove-Item $assetsDest -Recurse -Force }
        Copy-Item -Recurse -Force $assetsSrc $assetsDest
    }
    return (Test-Path (Join-Path $releaseData "app.so"))
}

Write-Host "flutter build windows --release $($defines -join ' ')" -ForegroundColor Yellow
flutter build windows --release @defines
if ($LASTEXITCODE -ne 0) {
    Write-Host "Full Windows build failed; rebuilding Dart only (native DLLs kept)..." -ForegroundColor Yellow
    if (-not (Test-Path $winRelease)) {
        foreach ($seed in @($gidroVinNew, $gidroVin, (Join-Path $root "release\windows"), (Join-Path $root "release\windows-lite"))) {
            if (Test-Path (Join-Path $seed "hydrowin.exe")) {
                New-Item -ItemType Directory -Force -Path $winRelease | Out-Null
                robocopy $seed $winRelease /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
                break
            }
        }
    }
    if (-not (Invoke-WindowsDartRebuild -BuildDefines $defines)) { exit 1 }
}

New-Item -ItemType Directory -Force -Path $out, $gidroVinNew, $gidroVin | Out-Null

Get-Process hydrowin -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

function Copy-Release($dest) {
    if (Test-Path $dest) {
        Get-ChildItem $dest -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    robocopy $winRelease $dest /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
}

Copy-Release $out
Copy-Release $gidroVinNew
Copy-Release $gidroVin

$startBat = @(
    '@echo off'
    'chcp 65001 >nul'
    'cd /d "%~dp0"'
    'start "" "hydrowin.exe"'
) -join "`r`n"
foreach ($dir in @($out, $gidroVinNew, $gidroVin)) {
    Set-Content (Join-Path $dir "START.bat") -Value $startBat -Encoding ASCII
}

$required = @("hydrowin.exe", "flutter_windows.dll", "data\app.so", "data\icudtl.dat")
$missing = @()
foreach ($rel in $required) {
    if (-not (Test-Path (Join-Path $gidroVinNew $rel))) { $missing += $rel }
}
if ($missing.Count -gt 0) {
    Write-Host "ERROR: missing files in $gidroVinNew" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

$fileCount = (Get-ChildItem $gidroVinNew -Recurse -File).Count
$appSoTime = (Get-Item (Join-Path $gidroVinNew "data\app.so")).LastWriteTime
$pubVer = Select-String -Path (Join-Path $app "pubspec.yaml") -Pattern '^version:\s*(.+)$' | ForEach-Object { $_.Matches[0].Groups[1].Value }
$builtAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
if ($Variant -eq "lite") {
    $modeLine = "Mode: BLE only (no cloud / no login)"
} else {
    $demoState = if ($EnableDemo) { "enabled" } else { "disabled" }
    $modeLine = "API: $ApiUrl`r`nDemo: $demoState"
}
$versionText = @(
    "GidroVin Windows ($Variant)"
    "Version: $pubVer"
    "Built: $builtAt"
    "APP_VARIANT: $Variant"
    $modeLine
) -join "`r`n"
foreach ($dir in @($out, $gidroVinNew, $gidroVin)) {
    Set-Content (Join-Path $dir "VERSION.txt") -Value $versionText -Encoding UTF8
}

if ($Variant -eq "lite") {
    $readme = @(
        "GidroVin Windows - Lite"
        "======================="
        ""
        "1. Unzip the ZIP completely into any folder."
        "2. Run START.bat (or hydrowin.exe)."
        "3. Needs Windows 10/11 x64 and Bluetooth for BLE."
        ""
        "Lite: Bluetooth to the block only, no server/login."
    ) -join "`r`n"
} else {
    $readme = @(
        "GidroVin Windows - Full"
        "======================="
        ""
        "1. Unzip the ZIP completely into any folder."
        "2. Run START.bat (or hydrowin.exe)."
        "3. Needs Windows 10/11 x64. Cloud needs internet to API."
    ) -join "`r`n"
}
Set-Content (Join-Path $out "README.txt") -Value $readme -Encoding UTF8
Set-Content (Join-Path $gidroVinNew "README.txt") -Value $readme -Encoding UTF8

$sanitize = Join-Path $PSScriptRoot "sanitize-release.ps1"
if (Test-Path $sanitize) {
    & $sanitize -Targets @($out, $gidroVinNew, $gidroVin)
}

$zipDir = "C:\GidroVin"
New-Item -ItemType Directory -Force -Path $zipDir | Out-Null
$zipPath = Join-Path $zipDir $zipName
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $gidroVinNew '*') -DestinationPath $zipPath -Force

Write-Host ""
Write-Host "Windows OK ($Variant): $gidroVinNew ($fileCount files, app.so: $appSoTime)" -ForegroundColor Green
Write-Host "ZIP for laptop: $zipPath" -ForegroundColor Green
Write-Host "Project:        $out" -ForegroundColor Green
