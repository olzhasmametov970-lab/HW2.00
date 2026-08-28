@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo.
echo  Сборка ГидроВин Lite для Windows (ноутбук)
echo  Результат: C:\GidroVin\Windows_Lite\  и  GidroVin-Lite-Windows.zip
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build-windows.ps1" -Variant lite
echo.
pause
