@echo off
setlocal
cd /d "%~dp0"
if exist "%~dp0scripts\setup-wizard.ps1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup-wizard.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1"
)
pause
