---
from: 062
to: conductor
sent: 2026-08-13T08:42:49Z
subject: Fixture table + redeploy-survival answer -- please relay to user
---

## Feature-to-fixture table

One map, one building type, one generator call. Every one of the 7 features the user
listed reduces to "select some subset of 13 pre-placed Command Centers and click."

| # | Feature | What it needs | How this map gives it |
|---|---|---|---|
| 1 | Over-cap production queue (8+) | 1 producing building, long build time, minerals | 13 Command Centers, one selected, Train x8+ |
| 2 | `+N` overflow indicator + 5th slot | same | same building, same clicks |
| 3 | Cancel-by-click incl. last slot (issue #061) | same | click Cancel on that building's card while queued |
| 4 | Group queue indicator | 2+ buildings of one type, selected as a group | select 2+ of the 13, Train (ProdFan fans it to all) |
| 5 | `>12`-unit paging row (issue #44: never tried on a BUILDING group) | 13+ units, one selection | select all 13 -- page 1 shows 1-12, page 2 shows unit 13 |
| 6 | Save/load | any state worth reloading | save mid-queue, reload, confirm the queue survived |
| 7 | Selection circles / building groups | whatever the suites already use | automatic on every click above -- no separate step |

Generator call (mirrors task 038's proven fixture -- `test-group-queue-over-five.ps1`
uses this exact shape for #1-4 already):

```
python tools/make_test_map.py \
  --unit-count 13 --unit-type command-center --player 0 --clear-player-units \
  --grid-spacing 160 --race terran \
  --unit-build-time scv=240 \
  --starting-minerals 8000 \
  --output <path, see below>
```

13, not e.g. 36: the point of #5 is "one past twelve," proven with the smallest number
that proves it -- and 13 Command Centers already gives #1-4 a group to select subsets
of. `scv=240` matches task 051's 240s Probe precedent -- long enough that the queue
sits still while the user looks, per the Context note that a 20s drain beats the user
to it.

Cut anything? Ability/tech features (Stim, Cloak, Burrow) and the combat/death variant
need a second unit type and a hostile force -- genuinely different setup, so per the
task's own "leave it out rather than contorting the map" they are NOT on this map. If
the user wants those too, that is a second, separate fixture map, not a bigger version
of this one.

## Where the map survives a redeploy -- the actual mechanics, read from deploy.ps1

`deploy.ps1`'s `/MIR` preserves exactly 5 things in `<DeployRoot>\game\`:
`characters\`, `save\`, `Maps\Replays\`, `maps\download\`, `SCScrnShot_*.pcx`. Everything
else under `Maps\` -- which is where a map has to live for the in-game browser to find it
at all (`Maps\` is the browser's own root; this repo's own automation notes it has no
`[Up One Level]` row, i.e. there is no drive-hopping out of that tree in the classic UI)
-- is wiped on every redeploy. `Maps\Replays\` is preserved but off-limits (task rule).
So: **nothing under the deploy tree survives a redeploy automatically**, and I'm not
going to make it by patching `deploy.ps1`'s preserved-set/robocopy exclusions -- that
script's own PURGED-section comment already flags custom-map survival as "worth a
follow-up task," on purpose, and it's a tripwire-laden shared script I'd rather not be
the one extending for a test-fixture's convenience.

What I'm doing instead: write it to
`C:\sc-deploy\starcraft-modded\game\Maps\zz-feature-test.scx` (loads exactly like any
other custom map, `zz-` keeps it easy to spot in the list), and the card's first line
says outright: *"not in the list? a redeploy wiped it -- run this one command, wait 2s,
refresh"* with the exact `make_test_map.py` invocation above. Regeneration needs no
running game and takes under a second. If you/the user would rather this survive with
zero manual steps, the real fix is a small additive step in `deploy.ps1` itself (write
the fixture after the mirror, same idempotent generator) -- say so and I'll scope that
as its own change instead of folding it in here.

Not launching anything until you clear it with 061. Machine-free note received.
