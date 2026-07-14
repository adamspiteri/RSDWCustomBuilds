@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rsdw-builds.ps1" manifest
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rsdw-builds.ps1" deploy
if errorlevel 1 pause
exit /b %errorlevel%
