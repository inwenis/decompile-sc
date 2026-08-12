---
from: conductor
to: user
sent: 2026-08-12T09:05:12Z
subject: That game window 08:59-09:07 was ours and I under-announced it -- plus 045 caught my own fix being wrong
---

Correcting an announcement I gave you incompletely, and one piece of good news.

## The game window on your screen, 08:59-09:07Z

I told you at 09:00Z that task 047 "has the machine for a short run". I did not tell you it was a
**VISIBLE** run — a StarCraft window on your monitor for about eight minutes. If you saw a game
come and go just now, that was it, and it was ours.

Why it had to be visible: that suite (`test-combat-death`) needs the game-type dropdown, which is
the one thing that cannot work on an invisible desktop — a dropdown needs the foreground, and only
the desktop taking your input can have one. It was the single launch that task required and there
will not be another.

It also predates your night-window rule by two minutes, so nobody broke it — the worker flagged
itself for a violation and I told it the clock says otherwise. The gap was mine: I announced the
run without announcing that it would be on your screen. From now on an announcement says WHERE.

## The good news from that run

Task 047 is done and clean. The check that was quietly wrong — a test asserting "6 hooks
installed" when the plugin legitimately installs 7 since task 036 — now asserts the hook
**composition by name** instead of a total. So the next time someone adds a hook, the test either
passes because it is listed, or fails saying exactly which hook appeared. It stops being a number
that rots.

## And a course correction on the flashing

The `DETACHED_PROCESS` fix I approved an hour ago turns out to be wrong, and 045 caught it by
testing rather than shipping: with no console at all, PowerShell never runs the script — it exits
0 having done nothing. Which is the same false-green shape we have been hunting all morning,
arriving from a new direction. It is now testing `CREATE_NO_WINDOW` instead, one spawn, with a
marker file that proves the script actually ran and a before/after count that proves no window
appeared.

I have also told it explicitly that "fix it by changing your Windows console settings in the
registry" is not on the table — that is your live machine configuration and hard rule 5 forbids it,
however well it might work.
