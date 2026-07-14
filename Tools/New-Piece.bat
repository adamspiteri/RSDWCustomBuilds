@echo off
setlocal
echo.
echo === RSDW Custom Builds - New Piece ===
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rsdw-builds.ps1" new-piece %*
if errorlevel 1 pause
exit /b %errorlevel%
