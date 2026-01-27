@echo off
cd /d "%~dp0"

echo.
echo ================================
echo   Ollama Service Installer
echo ================================
echo.
echo This will:
echo   1. Request administrator rights
echo   2. Run install.ps1 with full privileges
echo.
echo Waiting...

:: Полностью экранированная команда
set "CMD=Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File \"%CD%\scripts\install.ps1\"; if ($?) { Write-Host \"SUCCESS: Done. Press Enter...\" -ForegroundColor Green; Read-Host } else { Write-Host \"ERROR: Failed. Press Enter...\" -ForegroundColor Red; Read-Host }' -Verb RunAs"

powershell -Command "%CMD%" 

pause
