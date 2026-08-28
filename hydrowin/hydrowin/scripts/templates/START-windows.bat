@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ========================================
echo   GidroVin - zapusk prilozheniya
echo ========================================
echo.

if not exist "hydrowin.exe" (
  echo ERROR: hydrowin.exe ne naiden!
  pause
  exit /b 1
)

echo Proverka API...
powershell -NoProfile -Command "try { Invoke-WebRequest -Uri 'http://5.165.27.141:8090/health' -TimeoutSec 5 | Out-Null; exit 0 } catch { exit 1 }"
if errorlevel 1 (
  echo.
  echo !!! API NE RABOTAET !!!
  echo Na servere Home-PC:
  echo   1. Ustanovite Docker Desktop
  echo   2. cd backend
  echo   3. docker compose up -d
  echo   4. Proverka: http://5.165.27.141:8090/health
  echo.
  timeout /t 5
)

start "" "hydrowin.exe"
