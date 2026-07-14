@echo off
setlocal
set "LOG=E:\SteamLibrary\steamapps\common\RSDragonwilds\RSDragonwilds\Binaries\Win64\ue4ss\UE4SS.log"
set "STATUS=E:\SteamLibrary\steamapps\common\RSDragonwilds\RSDragonwilds\Binaries\Win64\ue4ss\Mods\RSDWCustomBuilds\last_status.txt"
echo.
echo === RSDW Custom Builds - read output ===
echo.
if exist "%STATUS%" (
  echo --- last_status.txt ---
  type "%STATUS%"
  echo.
) else (
  echo last_status.txt not found yet - run rsdw_builds_status in game first.
  echo.
)
echo --- opening UE4SS.log ---
if exist "%LOG%" (
  notepad "%LOG%"
) else (
  echo Log not found: %LOG%
  pause
)
