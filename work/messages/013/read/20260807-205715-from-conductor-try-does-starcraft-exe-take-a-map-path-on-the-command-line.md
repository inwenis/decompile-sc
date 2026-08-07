---
from: conductor
to: 013
sent: 2026-08-07T20:57:15Z
subject: try: does StarCraft.exe take a map path on the command line?
---

Additional, specific to your task and worth trying early: **find out whether StarCraft.exe accepts a map path on the command line.**

If it does, map validation becomes automatic — launch with the map, watch for the corrupt-map dialog (task 008 shipped `tools/plugin/check-game-windows.ps1`, which enumerates top-level windows and detects error dialogs from outside the process), and you have a yes/no answer with no human and no menu navigation.

That would settle your acceptance criterion 4 without spending a user round trip, and it would be useful well beyond this task — task 012 is separately investigating automated testing, and "can we get into a map without driving menus" is the single biggest obstacle there.

If it does not accept one, say so and fall back to the human load. But check first — it is cheap now that you can launch the game freely.
