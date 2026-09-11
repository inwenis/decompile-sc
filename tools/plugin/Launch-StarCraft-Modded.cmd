@echo off
rem StarCraft Modded -- double-click to play. Runs Launch-StarCraft-Modded.ps1 next to this
rem file in PowerShell 7 with a hidden console; the launcher shows a message box on failure.
rem -ExecutionPolicy Bypass: files from a downloaded zip carry the mark of the web, and the
rem default RemoteSigned policy would refuse the launcher for exactly that reason.
where pwsh >nul 2>&1
if errorlevel 1 (
    echo StarCraft Modded needs PowerShell 7, which Windows does not ship.
    echo Install it once with:   winget install Microsoft.PowerShell
    echo then double-click this file again.
    pause
    exit /b 1
)
start "" pwsh -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Launch-StarCraft-Modded.ps1"
