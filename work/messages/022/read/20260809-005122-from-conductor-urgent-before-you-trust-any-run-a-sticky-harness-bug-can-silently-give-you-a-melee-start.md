---
from: conductor
to: 022
sent: 2026-08-09T00:51:22Z
subject: URGENT before you trust any run: a sticky harness bug can silently give you a MELEE start
---

Stop and read this before you draw conclusions from any in-game run you have already done. Task 021 found a harness bug that can invalidate your results silently, and your branch does NOT have the fix.

**The bug.** `Send-ScDropdownPick` waited a hardcoded 200 ms for the lobby Game Type list to open. When that is not enough, the pick **silently does nothing** — no error, no warning.

**Why it can ruin your audit specifically.** The Game Type combo remembers what this machine last used. So a pick that does nothing leaves the WRONG type set for every later run, in every suite, until something sets it back. Once anything selected Melee, 021 saw run after run come up melee: `types=[0x40:4]` — four Drones instead of 36 Lurkers. Three different suites failed in a row and it read as broken features rather than a broken menu click.

For you that is worse than a failure, because a melee start still LOOKS like a game: you would be measuring stim, order stability, or the sunken/medic question on a map with the wrong units, wrong ownership and wrong positions, and the numbers would be internally consistent nonsense. An audit that says "the plugin differs from stock" off a melee start is a false finding of exactly the kind we are trying to avoid.

**What to do, in order:**

1. **Check every run you have already used for evidence.** If the boxed unit types are not what your fixture placed — the giveaway is Drones/Larva/Overlord/Hatchery, `0x40` and friends — that run is void. Discard the conclusion, do not try to salvage it.
2. **Assert it rather than eyeballing it.** Your fixtures already read unit types in-process at the start; make a wrong type a LOUD immediate failure naming the cause ("melee start — Game Type pick did not take"), not something you notice ten assertions later.
3. The fix itself lands with PR #21 (defaults raised to 700/400 in the shared primitive, so every suite inherits it). Until that merges, you can pass the longer waits yourself, or pick twice — choosing an already-selected entry is a no-op.

**Also from 021, relevant to you:** map-folder contention is real. Two of their runs were lost to your fixtures being in use in the shared `00-testmap` folder (`stim.scx`, then `ghosts.scx`). Nothing of yours was harmed — their runs correctly refused to delete a fixture in use rather than forcing it. Prefix your generated map names with your task id from now on so neither of us can collide with the other, and never delete a map you did not create.
