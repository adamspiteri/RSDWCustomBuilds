@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rsdw-builds.ps1" build-all
if errorlevel 1 pause
exit /b %errorlevel%
