# StarCraft Modded (Brood War 1.16.1)

Select more than 12 units, control groups past 12, production queue past 5, one Train click
for every selected building, upgrade queue, widescreen. What to expect on screen and the
known cosmetic imperfections: `widescreen-card.md`.

## Setup, once

1. Install PowerShell 7 if you do not have it: open a terminal and run
   `winget install Microsoft.PowerShell`
2. Copy the contents of your own StarCraft: Brood War 1.16.1 folder into `game\`
   (StarCraft.exe, storm.dll, the .mpq files, everything). A copy, not your only install:
   the launcher writes `ddraw.dll` into it. Only 1.16.1 works; the launcher checks and
   tells you if the exe is a different build.
3. Double-click `Launch-StarCraft-Modded.cmd`.

Nothing outside this folder is written. Saves, profiles, replays and screenshots live
under `game\` as they always did. Offline and single-player only: never take a modified
game online.

## If it does not start

1. A message box says why; the details are in `logs\launch-error.log`.
2. Windows may block files that came from a downloaded zip: right-click the zip,
   Properties, tick Unblock, then extract again.
3. SmartScreen on `scinject.exe`: More info, Run anyway. It is the injector that loads the
   mod into the game. Source and build: https://github.com/inwenis/decompile-sc

## Screen

Borderless full screen, aspect ratio kept, cursor locked to the window (hold Ctrl or Right
Alt to free it). For a 2x window instead, on a monitor at least as big as the `width` and
`height` lines in `plugin\cnc-ddraw-2x.ini`: set `fullscreen=false` in that file.

## Third party

cnc-ddraw v7.1.0.0 (`plugin\cnc-ddraw\ddraw.dll`), MIT, https://github.com/FunkyFr3sh/cnc-ddraw
