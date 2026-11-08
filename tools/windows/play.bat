@echo off
rem Orbital Laser on the fork's Windows build. The game folder is game\ beside this file, so your own Horizon saves are left alone.
setlocal
set "HERE=%~dp0"
if not defined HORIZON_RESOURCES set "HORIZON_RESOURCES=%HERE%horizon\.local\horizon-client\26.3"
if not exist "%HORIZON_RESOURCES%\horizon-resources.json" (
  echo No prepared resources yet. Run prepare.bat first.
  pause
  exit /b 1
)
cd /d "%HERE%game"
set "WORLD=%~1"
if "%WORLD%"=="" set "WORLD=OrbitalTest"
"%HERE%horizon\horizon-ctl.exe" launch --world "%WORLD%" --creative --wait --game "%HERE%horizon\horizon-client.exe" --resources "%HORIZON_RESOURCES%"
if errorlevel 1 pause
