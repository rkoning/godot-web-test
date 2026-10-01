@echo off
rem Double-click to play. Same options as play-desktop.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0play-desktop.ps1" %*
if errorlevel 1 pause
