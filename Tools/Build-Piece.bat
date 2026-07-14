@echo off
setlocal
if "%~1"=="" (
  echo Usage: Build-Piece.bat PieceName
  echo Example: Build-Piece.bat StoneWall
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rsdw-builds.ps1" build %1
if errorlevel 1 pause
exit /b %errorlevel%
