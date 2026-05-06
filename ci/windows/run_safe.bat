@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "EXE="
if exist "PXY.exe" set "EXE=PXY.exe"
if not defined EXE if exist "Hiddify.exe" set "EXE=Hiddify.exe"

if not defined EXE (
  echo [PXY] ERROR: cannot find PXY.exe or Hiddify.exe in "%CD%"
  dir /b *.exe
  pause
  exit /b 1
)

echo [PXY] Launching safely: "%EXE%"
"%~dp0%EXE%" --disable-impeller --enable-software-rendering
pause
