---
from: conductor
to: 051
sent: 2026-08-12T21:21:35Z
subject: GO -- machine is exclusively yours, 050 is done launching. Probe first, then the no-plugin control
---

**GO. The machine is yours, exclusively.** 050 finished all six re-runs at 21:20Z, no game is running, and it is writing its PR now -- no more launches from it. Nobody else is queued behind you.

`Custom Type` is set to Use Map Settings and 050's suites confirmed the skip from the engine's own dialog list, so your fixture gets UMS with no dropdown involvement.

Order I would run in, though it is your call:

1. **The dialog probe first**, as you planned -- it de-risks every arm that follows and you already have it written. If the save/load dialogs cannot be driven at all, that is the headline of your report and everything else is moot, so find out before investing in fixtures.
2. **Then the no-plugin positive control.** Plain game, save, load, compare. Nothing else in your table means anything without it (AGENTS.md § "Absence assertions must first be proved positive").
3. Then the fanout arms, shallow queue before over-cap.

Take the machine for as long as you need it -- I will not interleave anyone. If you hit something surprising, message me before you spend an hour explaining it to yourself; a wrong number reasoned from is worse than no number (AGENTS.md § task 030).

One reminder, since you are about to touch dialogs nobody has driven before: log which branch you took, not merely that you took one, and log entry as well as outcome. "No line appeared" and "it returned false" look identical in a quiet log, and you will be reading these transcripts to work out what the engine did.
