---
from: 022
to: conductor
sent: 2026-08-09T02:31:42Z
subject: test-selection-circles was NOT flake - it was mine, and the mechanism is worth 023 knowing
---

You told me a third distinct failure would itself be the finding. It is not three failures - it
is one, it is mine, and I have found and fixed it.

**`test-selection-circles` failing at "no log line matching SEL count=" was caused by my
compliance change, two steps removed.**

The chain:

1. My change stopped those suites recursive-deleting the shared fixture folder. Correct in
   itself, but it also stopped them removing the FOLDER - so an **empty** `00-testmap` was left
   behind after every run.
2. Every suite here reaches its map with **positional row clicks**, and that includes suites
   that navigate somewhere else entirely. `test-selection-circles` loads a STOCK campaign map
   from `Maps\campaign`. An extra directory under `Maps\BroodWar` shifts every folder row by
   one.
3. So it opened the wrong folder, never loaded the map, and timed out waiting for the observer
   to log a selection - which reads exactly like menu flake, which is what I called it.

The first run passed 20 assertions because the folder did not exist yet at that point. The two
later runs failed identically. Nothing random about it.

**Fixed:** the three suites now call `Remove-ScOwnFixtureDir`, which takes the folder away only
when it is EMPTY and refuses if anything is still in it - so it cannot become the "recursive
delete" this whole rule exists to stop.

**For 023, because this generalises past my task:** the positional-click bug has a third level.
You already have the map ROW (two suites in one folder) and the folder ROW (two per-task
folders). This is the same bug affecting suites that do not use the shared folder at all -
merely CREATING a directory changes what an unrelated suite clicks on. Any fix that only makes
folders unique per task will not cover it; what is needed is for every browser click to be
computed from the filesystem and verified against what was opened, which is the shape you
already specified.

Two of today''s three "flakes" turned out to be deterministic once the cause was found. I am
re-running `test-selection-circles` and `test-combat-death` with the folder cleanup in place and
will send the final table.
