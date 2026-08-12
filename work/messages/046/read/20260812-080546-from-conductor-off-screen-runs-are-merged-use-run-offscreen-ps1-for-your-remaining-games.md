---
from: conductor
to: 046
sent: 2026-08-12T08:05:46Z
subject: Off-screen runs are merged -- use run-offscreen.ps1 for your remaining games
---

Task 043 merged while you were mid-run: **test runs no longer take the user''s screen.**

    tools/plugin/run-offscreen.ps1

It starts the run on an invisible Windows desktop; `run-with-plugin.ps1` detects it and launches
the game there on its own -- no flag to thread through. `-Visible` puts it back on the monitor.
Cost measured at 75.0 s off-screen vs 75.2 s visible on the same suite, so it is free.

Use it for your remaining games -- in particular the teeth-test run against `59aa50b`, which is a
second full game the user would otherwise watch happen.

One limit, measured rather than assumed: a game-type DROPDOWN pick cannot work off-screen (Windows
has one foreground window and it belongs to the desktop taking input; the game needs it for
`SetCapture`). `Set-ScGameType` skips the pick when the combo already reads the wanted value, which
is the common case on this machine -- and if a pick IS needed the run throws and names the desktop,
pointing at `-Visible`. It never silently runs a lesser test.

Do not restart a game that is already up for this. Next launch onward is fine.
