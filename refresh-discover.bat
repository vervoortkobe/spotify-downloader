@echo off
REM Triggers a Discover cache refresh on the ONLINE backend (see refresh-discover.ps1).
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0refresh-discover.ps1"
if errorlevel 1 (
  pause
  exit /b 1
)
echo [INFO] Trigger sent. Scraping runs in background for a few minutes, then check Discover in the app.
pause
