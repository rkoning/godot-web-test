@echo off
rem Double-click friendly wrapper around build-windows.ps1 (same options apply).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-windows.ps1" %*
if errorlevel 1 pause
