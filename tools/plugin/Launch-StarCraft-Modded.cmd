@echo off
rem StarCraft Modded -- double-click to play. Everything the mod needs happens right here,
rem in plain sight: the presenter is copied into game\, the feature switches are the
rem SCPLUGIN_* variables below, and scinject.exe starts the game with scplugin.dll loaded.
rem Nothing outside this folder is written.
setlocal
cd /d "%~dp0"

if not exist "game\StarCraft.exe" (
    echo No game\StarCraft.exe found.
    echo Copy the contents of your StarCraft: Brood War 1.16.1 folder into the game folder
    echo next to this file ^(a copy, not your only install^), then double-click again.
    pause
    exit /b 1
)

rem Only the 1.16.1 build has the addresses this mod patches; any other build may crash.
certutil -hashfile "game\StarCraft.exe" SHA256 | findstr /i "ad6b58b27b8948845ccfa69bcfcc1b10d6aa7a27a371ee3e61453925288c6a46" >nul
if errorlevel 1 (
    echo game\StarCraft.exe is not the StarCraft: Brood War 1.16.1 build this mod is made for.
    echo It may crash. Press a key to try anyway, or close this window.
    pause
)

rem cnc-ddraw presents the widened frame: borderless full screen, aspect ratio kept, cursor
rem locked to the window. Hold Ctrl or Right Alt to free the cursor.
copy /y "plugin\cnc-ddraw\ddraw.dll" "game\ddraw.dll" >nul
copy /y "plugin\cnc-ddraw-release.ini" "game\ddraw.ini" >nul

if not exist "logs" mkdir "logs"
set SCPLUGIN_LOG=%~dp0logs\sc-plugin.log
set SCPLUGIN_LOG_COMMANDS=0
set SCPLUGIN_MODE=fanout
set SCPLUGIN_CIRCLES=1
set SCPLUGIN_HUDROW=1
set SCPLUGIN_PRODQ=1
set SCPLUGIN_PRODFAN=1
set SCPLUGIN_UPGQ=1
set SCPLUGIN_QUEUEIND=1
set SCPLUGIN_WIDESCREEN=1
set SCPLUGIN_WS_STAGE=3
rem Geometry preset: 1280x880 (default), 1280x720 (16:9, 1.5x on a 1080p screen),
rem 1536x864 (16:9, 1.25x on a 1080p screen, more map, smaller UI).
set SCPLUGIN_WS_GEOMETRY=1280x880
set SCPLUGIN_STORM_PRESENT=widen

rem --early loads the DLL before the game's first instruction, where the widescreen patches
rem must land. --no-wait-exit lets this window close once the game is up.
"plugin\scinject.exe" "%~dp0game\StarCraft.exe" "%~dp0plugin\scplugin.dll" --early --no-wait-exit
if errorlevel 1 pause
