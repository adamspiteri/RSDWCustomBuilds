@echo off
setlocal
if "%~1"=="" (
  echo RSDW Custom Builds Manager
  echo.
  echo Usage:
  echo   Manager.bat check
  echo   Manager.bat build-from-files C:\Path\To\PieceFolder
  echo   Manager.bat install-pack C:\Path\To\PackFolder
  echo   Manager.bat rollback
  echo.
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rsdw-builds.ps1"
  exit /b 0
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rsdw-builds.ps1" %*
if errorlevel 1 pause
exit /b %errorlevel%
