@echo off
setlocal EnableExtensions
set "DIR=%~dp0"
cd /d "%DIR%"

call :pick_exe
if not defined EXE (
  echo [PXY] ERROR: cannot find app exe in "%DIR%"
  pause
  exit /b 1
)

set "SAFE_FLAGS=--disable-impeller --enable-software-rendering"
echo [PXY] Launching SAFE: "%DIR%%EXE%" %SAFE_FLAGS% %*
start "" "%DIR%%EXE%" %SAFE_FLAGS% %*
exit /b 0

:pick_exe
set "EXE="
for %%F in (PXY.exe pxy.exe Hiddify.exe hiddify.exe HiddifyApp.exe hiddify-app.exe) do (
  if exist "%%F" set "EXE=%%F"
)
if defined EXE exit /b 0

for %%F in (*.exe) do (
  if /I not "%%F"=="HiddifyCli.exe" (
    set "EXE=%%F"
    exit /b 0
  )
)
exit /b 0
