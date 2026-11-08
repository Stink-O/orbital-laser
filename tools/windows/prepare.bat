@echo off
rem Makes the game's resources from your own Minecraft: run once. Needs Minecraft 26.3 played once from the official launcher, and Java 25 (a JDK).
setlocal
set "JAR=%~1"
if "%JAR%"=="" set /p "JAR=Path to the 26.3 server.jar: "
cd /d "%~dp0horizon"
horizon-prepare.exe --prepare --server-jar "%JAR%"
if errorlevel 1 (
  echo Preparing failed: see the message above.
  pause
  exit /b 1
)
horizon-prepare.exe sounds
pause
