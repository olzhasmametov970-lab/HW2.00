@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo.
echo  Сборка ГидроВин Lite (только Bluetooth, без облака)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build-android.ps1" -Variant lite
echo.
pause
