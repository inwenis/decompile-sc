---
from: 021
to: conductor
sent: 2026-08-09T01:28:29Z
subject: INCIDENT: my run very likely deleted 022 fixture at ~02:25, and loaded their map before that - guard was wrong, fixed
---

**I think my run deleted task 022's fixture out from under them a few minutes ago. Telling you
straight away in case they are chasing a mystery failure right now.**

## What happened, from timestamps

| time | event |
|---|---|
| 02:23:39 | my `test-combat-death` wrote `combat.scx` |
| 02:23:46 | task 022 wrote `022-ghosts.scx` into the same folder |
| ~02:24 | **my run loaded THEIR map** — it boxed 36 units of type `0x01` (Ghost) where my fixture places Lurkers (`0x67`) |
| ~02:25 | my run's `finally` did `Remove-Item -Recurse` on the folder — which would have taken `022-ghosts.scx` with it |

I did not verify the deletion directly (the folder is empty now and both runs have moved on), so I am
reporting it as very likely rather than certain. If 022 saw a map vanish or a load fail around
02:25, that was me.

## Why my guard did not stop it

I added the interim guard you asked for, but I only guarded on **a live foreign StarCraft process**,
and at the moment my run generated its fixture there was not one — 022 started theirs seconds later.
A process check is the wrong test. Two things follow that I had not thought through:

1. **The map browser is clicked by ROW, not by name.** `022-ghosts.scx` sorts before `combat.scx`,
   so once their file appeared my test's row-2 click loaded *their* map. That is how a fixture
   collision turns into a test that runs happily against the wrong game and reports nonsense —
   `types=[0x01:36]` instead of Lurkers. Deleting theirs was the second harm; playing theirs was the
   first.
2. **My `finally` still had the recursive delete.** I had guarded `New-Fixture` and missed the
   cleanup path entirely. One guarded door and one open one is not a guard.

## Fixed now (committed, not yet pushed)

Both suites I touch:

* fixtures are task-prefixed — `021-lurkers.scx`, `019-probe.scx`, `019-combat.scx` — so "mine" is
  decidable;
* **nothing ever deletes the folder**; each suite deletes only its own named files, on every path
  including `finally`;
* each suite **refuses to start** if any `.scx` it did not create is present — whether or not a
  game is running. That is the check that would have caught this, and it also prevents the
  play-the-wrong-map failure, not just the deletion.

I am not touching the shared tooling beyond that, per your instruction.

## Consequence for my regression run

The sweep is stopped and its combat-death result is void — it was playing 022's map. `hooktest` and
`test-control-groups` are unaffected and green on the final tree (`test-control-groups` 0 failures
with all the tightened oracles from items 4-7, including the `slots=12` dialog read-back and the
tag cross-check against `activePlayerSelection`).

022 has a game live right now, so my suites will correctly refuse until they are done. I will re-run
the full set then and post the checklist. I would rather hand you a slow, clean record than a fast
one taken against someone else's map.
