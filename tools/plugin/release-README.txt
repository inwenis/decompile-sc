StarCraft Modded (Brood War 1.16.1)

1. Copy the contents of your StarCraft: Brood War 1.16.1 folder into game\
   (StarCraft.exe, storm.dll, the .mpq files, everything). A copy, not your only
   install: the launcher writes ddraw.dll into it. Only 1.16.1 works; the launcher
   tells you if the exe is a different build.
2. Double-click Launch-StarCraft-Modded.cmd.

Nothing to install and nothing outside this folder is written. Saves, profiles,
replays and screenshots land under game\ as they always did. Offline and
single-player only: never take a modified game online.

Features: select more than 12 units (right-click the bottom row to page through),
select buildings of one type and queue units for all of them, queue more than 5
units in a building, queue upgrades, widescreen. Hold Ctrl or Right Alt to free
the mouse from the window.

If it does not start: the launcher window says why, and logs\sc-plugin.log has the
details. Windows may warn about files from a downloaded zip ("Windows protected
your PC"): More info, Run anyway.

Source and build: https://github.com/inwenis/decompile-sc
Third party: cnc-ddraw v7.1.0.0 (plugin\cnc-ddraw\ddraw.dll), MIT,
https://github.com/FunkyFr3sh/cnc-ddraw
