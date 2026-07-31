@echo off
setlocal

set "AEGIS_SCRIPT=%~dp0Install.ps1"
if not defined AEGIS_BASE_URL set "AEGIS_BASE_URL=https://github.com/Marek-Codex/AEGIS/raw/refs/heads/main"

if exist "%AEGIS_SCRIPT%" goto run

set "AEGIS_TEMP_DIR=%TEMP%\AEGIS-%RANDOM%-%RANDOM%"
mkdir "%AEGIS_TEMP_DIR%" >nul 2>nul
if errorlevel 1 (
  echo Failed to create a temporary directory.
  exit /b 1
)
set "AEGIS_SCRIPT=%AEGIS_TEMP_DIR%\Install.ps1"
echo Downloading AEGIS...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri '%AEGIS_BASE_URL%/Install.ps1' -OutFile '%AEGIS_SCRIPT%'"

if errorlevel 1 (
  echo Failed to download AEGIS.
  rmdir /s /q "%AEGIS_TEMP_DIR%" >nul 2>nul
  exit /b 1
)

:run
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%AEGIS_SCRIPT%" %*
set "AEGIS_EXIT=%ERRORLEVEL%"

if defined AEGIS_TEMP_DIR rmdir /s /q "%AEGIS_TEMP_DIR%" >nul 2>nul
if not "%AEGIS_EXIT%"=="0" echo AEGIS exited with code %AEGIS_EXIT%.
exit /b %AEGIS_EXIT%
