param(
    [string]$ApiUrl = "",
    [bool]$PresetCloud = $true,
    [bool]$EnableDemo = $false,
    # full = облако + BLE; lite = только Bluetooth (без сервера)
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

$app = Join-Path $root "mobile\hydrowin"
$mingit = "C:\flutter\bin\mingit\cmd"
if (Test-Path $mingit) {
    $env:Path = "$mingit;$env:Path"
}

$defines = @(
    "--flavor=$Variant",
    "--dart-define=APP_VARIANT=$Variant"
)

if ($Variant -eq "lite") {
    # Lite: без облака; демо-парк включён
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

Set-Location $app
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

flutter build apk --release @defines
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$apkName = "app-$Variant-release.apk"
$apkSrc = Join-Path $app "build\app\outputs\flutter-apk\$apkName"
if (-not (Test-Path $apkSrc)) {
    # запасной путь (иногда Flutter кладёт в outputs/apk)
    $alt = Join-Path $app "build\app\outputs\apk\$Variant\release\app-$Variant-release.apk"
    if (Test-Path $alt) { $apkSrc = $alt }
}

$outDir = "C:\GidroVin\Android"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if ($Variant -eq "lite") {
    $gidroVinApk = Join-Path $outDir "GidroVin-Lite.apk"
} else {
    $gidroVinApk = Join-Path $outDir "GidroVin.apk"
}

if (Test-Path $apkSrc) {
    Copy-Item -Force $apkSrc $gidroVinApk
} else {
    Write-Host "APK не найден: ожидался $apkName" -ForegroundColor Red
    Get-ChildItem (Join-Path $app "build\app\outputs") -Recurse -Filter "*.apk" -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host "  найден: $($_.FullName)" }
    exit 1
}

$releaseAndroid = Join-Path $root "release\android"
New-Item -ItemType Directory -Force -Path $releaseAndroid | Out-Null
Copy-Item -Force $apkSrc (Join-Path $releaseAndroid (Split-Path $gidroVinApk -Leaf))

Write-Host ""
Write-Host "Вариант: $Variant" -ForegroundColor Cyan
Write-Host "APK: $gidroVinApk" -ForegroundColor Green
Write-Host "     $apkSrc" -ForegroundColor Green
