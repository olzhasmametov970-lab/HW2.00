@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo.
echo  Сборка ГидроВин: Android + Windows + Web
echo  (нужен Flutter: flutter doctor)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build-all.ps1"
echo.
pause
