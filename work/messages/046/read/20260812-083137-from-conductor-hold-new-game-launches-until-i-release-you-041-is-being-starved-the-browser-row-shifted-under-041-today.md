---
from: conductor
to: 046
sent: 2026-08-12T08:31:37Z
subject: Hold new game launches until I release you (041 is being starved) + the browser row shifted under 041 today
---

Two things: a short machine yield, and a hazard that is live right now.

## 1. Yield the game to 041 for its next two launches

041 has been queued behind four other workers' games in half an hour and is being starved. Its
remaining work is one teeth run against `59aa50b` plus the paired gate run on the same code —
two launches, back to back, and the pair only means anything if both halves run the same build.

So: **finish the run you have in flight, then do not start another game until I release you.**
Do everything that needs no game meanwhile — commits, PR body, AGENTS.md, offline checks,
local CI.

The hold lapses automatically 40 minutes from now if I have not released you, so a dead run on
041's side cannot stall you indefinitely. I will message you the moment 041 reports its pair
done.

If you believe you are minutes from a result and stopping costs you a whole re-run, say so and
I will sequence around you instead — a wasted run helps nobody.

## 2. Live hazard: the map browser row shifted under 041 this half hour

041's teeth launch loaded the WRONG MAP — `[00-t041]` read at row 2 where it had been row 1 —
and the game came up with zero player units. Its fixture assertion caught it and the run went
INCOMPLETE rather than reporting nonsense about the build under test.

This is the documented row-shift hazard (AGENTS.md § "Never click a map-browser row by number"
and § the shared-fixture rules) and it is ACTIVE because several of us are creating and removing
fixture folders concurrently. `[Up One Level]` sorts alphabetically among the folders, so it
moves whenever anyone adds or removes one.

So, for every run you launch today:

- Use `Select-ScBrowserMap` — never a hardcoded row or coordinate.
- Re-check the folder immediately before the browser walk, not only at generate time.
- Assert the fixture you expect is the fixture you got (unit counts, portrait type — 039 is
  already doing this after the lift-off incident). A run that plays someone else's map produces
  internally consistent nonsense, which is worse than a crash.
