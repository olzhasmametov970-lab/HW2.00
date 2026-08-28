$ErrorActionPreference = "Continue"
$gidroRoot = "C:\GidroVin"
$win = Join-Path $gidroRoot "Windows"
$apk = Join-Path $gidroRoot "Android\GidroVin.apk"

Write-Host "=== Проверка сборки ГидроВин ===" -ForegroundColor Cyan

$ok = $true

function Test-FileExists($path, $label) {
    if (Test-Path $path) {
        $size = (Get-Item $path).Length
        Write-Host "[OK] $label ($([math]::Round($size/1MB, 2)) MB)" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $label — не найден: $path" -ForegroundColor Red
        $script:ok = $false
    }
}

Test-FileExists (Join-Path $win "hydrowin.exe") "Windows exe"
Test-FileExists (Join-Path $win "flutter_windows.dll") "flutter_windows.dll"
Test-FileExists (Join-Path $win "data\app.so") "data\app.so"
Test-FileExists (Join-Path $win "data\icudtl.dat") "data\icudtl.dat"
Test-FileExists $apk "Android APK"

Write-Host ""
Write-Host "--- API ---" -ForegroundColor Yellow
try {
    $r = Invoke-WebRequest -Uri "http://5.165.27.141:8090/health" -TimeoutSec 5 -UseBasicParsing
    Write-Host "[OK] API отвечает: $($r.Content)" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] API недоступен: http://5.165.27.141:8090/health" -ForegroundColor Red
    Write-Host "       Запустите backend на Home-PC: docker compose up -d" -ForegroundColor Yellow
    $ok = $false
}

Write-Host ""
Write-Host "--- Запуск Windows (5 сек) ---" -ForegroundColor Yellow
Get-Process hydrowin -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 1
$exe = Join-Path $win "hydrowin.exe"
if (Test-Path $exe) {
    $p = Start-Process $exe -PassThru -WorkingDirectory $win
    Start-Sleep 5
    if ($p.HasExited) {
        Write-Host "[FAIL] hydrowin.exe завершился с кодом $($p.ExitCode)" -ForegroundColor Red
        $ok = $false
    } else {
        Write-Host "[OK] hydrowin.exe работает (pid $($p.Id))" -ForegroundColor Green
        Stop-Process $p -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
if ($ok) {
    Write-Host "Итог: сборка в порядке. Если вход не работает — проверьте API." -ForegroundColor Green
} else {
    Write-Host "Итог: есть проблемы (см. выше)." -ForegroundColor Red
    exit 1
}
