@echo off
rem StarCraft Modded -- double-click to play, or drag your StarCraft folder onto this file.
rem Everything the mod needs happens right here, in plain sight: find the game, put the
rem window presenter next to it for this session, set the SCPLUGIN_* feature switches,
rem start the game with scplugin.dll loaded, and put the game folder back when it exits.
setlocal
cd /d "%~dp0"

rem Which StarCraft? 1) the folder dropped onto this file or given as the argument,
rem 2) game\ next to this file, 3) the InstallPath the 1.16.1 installer registered, 4) ask.
set "GAME=%~1"
if not defined GAME if exist "game\StarCraft.exe" set "GAME=%~dp0game"
if not defined GAME for /f "tokens=2,*" %%a in ('reg query "HKLM\SOFTWARE\WOW6432Node\Blizzard Entertainment\Starcraft" /v InstallPath 2^>nul ^| find "InstallPath"') do set "GAME=%%b"
if not defined GAME set /p "GAME=Where is StarCraft: Brood War 1.16.1 installed? Paste the folder path and press Enter: "
set "GAME=%GAME:"=%"
if "%GAME:~-1%"=="\" set "GAME=%GAME:~0,-1%"
if not exist "%GAME%\StarCraft.exe" (
    echo No StarCraft.exe in "%GAME%".
    echo Drag your StarCraft: Brood War 1.16.1 folder onto this file and try again.
    pause
    exit /b 1
)
echo StarCraft: %GAME%

rem Only the 1.16.1 build has the addresses this mod patches; any other build may crash.
certutil -hashfile "%GAME%\StarCraft.exe" SHA256 | findstr /i "ad6b58b27b8948845ccfa69bcfcc1b10d6aa7a27a371ee3e61453925288c6a46" >nul
if errorlevel 1 (
    echo "%GAME%\StarCraft.exe" is not the StarCraft: Brood War 1.16.1 build this mod is made for.
    echo It may crash. Press a key to try anyway, or close this window.
    pause
)

rem cnc-ddraw shows the widened frame: borderless full screen, aspect ratio kept, cursor
rem locked to the window (hold Ctrl or Right Alt to free it). A ddraw proxy must sit next to
rem the exe, so it goes into the game folder for this session only. A ddraw.dll or ddraw.ini
rem already there is kept aside and put back on exit (one that is already ours is left alone).
set "KEEP_DLL="
set "KEEP_INI="
if exist "%GAME%\ddraw.dll" (fc /b "%GAME%\ddraw.dll" "plugin\cnc-ddraw\ddraw.dll" >nul 2>&1 && set "KEEP_DLL=1" || move /y "%GAME%\ddraw.dll" "%GAME%\ddraw.dll.before-modded" >nul)
if exist "%GAME%\ddraw.ini" (fc /b "%GAME%\ddraw.ini" "plugin\cnc-ddraw-release.ini" >nul 2>&1 && set "KEEP_INI=1" || move /y "%GAME%\ddraw.ini" "%GAME%\ddraw.ini.before-modded" >nul)
copy /y "plugin\cnc-ddraw\ddraw.dll" "%GAME%\ddraw.dll" >nul
copy /y "plugin\cnc-ddraw-release.ini" "%GAME%\ddraw.ini" >nul

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
set SCPLUGIN_STORM_PRESENT=widen

rem --early loads the DLL before the game's first instruction, where the widescreen patches
rem must land. This window stays until the game exits, then puts the game folder back.
echo Starting. Leave this window open; it closes with the game.
"plugin\scinject.exe" "%GAME%\StarCraft.exe" "%~dp0plugin\scplugin.dll" --early
if errorlevel 1 pause

if not defined KEEP_DLL del /q "%GAME%\ddraw.dll" 2>nul
if not defined KEEP_INI del /q "%GAME%\ddraw.ini" 2>nul
if exist "%GAME%\ddraw.dll.before-modded" move /y "%GAME%\ddraw.dll.before-modded" "%GAME%\ddraw.dll" >nul
if exist "%GAME%\ddraw.ini.before-modded" move /y "%GAME%\ddraw.ini.before-modded" "%GAME%\ddraw.ini" >nul
