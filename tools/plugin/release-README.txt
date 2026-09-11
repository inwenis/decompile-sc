StarCraft Modded (Brood War 1.16.1)

Double-click Launch-StarCraft-Modded.cmd. It finds your StarCraft: Brood War 1.16.1
install on its own (the path the installer registered). If it cannot, it asks; you
can also drag your StarCraft folder onto it. Only 1.16.1 works; the launcher tells
you if the exe is a different build.

While the game runs, cnc-ddraw's ddraw.dll and ddraw.ini (the window presenter) sit
in your StarCraft folder; when you quit they are removed and any ddraw.dll you had
before is put back. Nothing else is written there and your game files are never
changed. Saves, profiles, replays and screenshots land where they always did.
Offline and single-player only: never take a modified game online.

Features: select more than 12 units (right-click the bottom row to page through),
select buildings of one type and queue units for all of them, queue more than 5
units in a building, queue upgrades, widescreen. Hold Ctrl or Right Alt to free
the mouse from the window.

If it does not start: the launcher window says why, and logs\sc-plugin.log has the
details. If Windows warns about a downloaded file ("Windows protected your PC"):
More info, Run anyway.

Source and build: https://github.com/inwenis/decompile-sc
Third party: cnc-ddraw v7.1.0.0 (plugin\cnc-ddraw\ddraw.dll), MIT,
https://github.com/FunkyFr3sh/cnc-ddraw
