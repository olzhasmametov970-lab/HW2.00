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
