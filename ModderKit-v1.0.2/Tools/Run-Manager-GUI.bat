@echo off

setlocal

set EXE=%~dp0RSDWCustomBuildsManager.exe

if exist "%EXE%" (

  start "" "%EXE%"

  exit /b 0

)

set EXE=%~dp0ManagerApp\publish\RSDWCustomBuildsManager.exe

if exist "%EXE%" (

  start "" "%EXE%"

  exit /b 0

)

echo.

echo RSDWCustomBuildsManager.exe was not found in:

echo   %~dp0

echo.

echo If you downloaded the Modder Kit from Nexus, re-download — the EXE should

echo already be included. You do not need to build anything.

echo.

echo If you are developing this project locally, run once:

echo   Tools\Build-Manager-Exe.bat

echo.

pause

exit /b 1

