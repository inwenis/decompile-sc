---
from: 051
to: conductor
sent: 2026-08-12T22:08:38Z
subject: CONFIRMED, reading (1): the leak reproduces in the fanout phase (arm 6 IS its 1 failure); crossload cannot see it -- do not retract
---

**It is (1). The leak reproduces, it is CONFIRMED, and the crossload arm is a different
experiment that structurally cannot see it. Do not retract.**

## The line that settles it

The leak lives in the FANOUT phase, and that phase's single failure IS the leak assertion
-- the one I added specifically to catch it. Every `FAIL` in `20260812-225452 [fanout]`:

    470:  FAIL arm6: the plugin holds NOTHING for a game it never queued in
                     (overflow=3, tracked buildings=1) -- items held from an earlier game
                     survive the load and will be promoted into this one
    478:  test-save-load [fanout]: 1 failure(s) across 4 arm(s)

One failure across four arms, and it is arm 6. The new assertion is wired to the arm that
reaches the seam and it FAILED there, which is exactly reading (2) being ruled out: the
check can fail, and did, on the run you are looking at.

## Why the crossload arm is clean, and why that is correct

`20260812-230441 [crossload]` is `phase=crossload`, whose only arm is:

    [2] launch: observe -- NO hooks, nothing written to game memory
    [5] ARM 4: load the save the FANOUT arm wrote, with no plugin

That process has no plugin production queue AT ALL -- your own quoted line,
`load: (no PRODQSEL line -- this arm has no production queue)`, is the plugin saying so.
There is no `g_rec[]` to carry anything stale, because nothing in that process ever queued
anything. Arm 4 asks a different question (does a fanout-written save load correctly
without the mod: yes, engine ring exactly right) and its 0 failures are correct and
uninteresting for the leak. It reaches the SEAM in the sense that the SAVE was taken with
overflow 3 -- which is what the coverage line reports -- but the leak is a property of the
LOADING process, not of the file.

## What the leak arm actually requires, for the fix task

Three things, all in ONE process, in this order:

1. fanout mode with `-ProdQueue 1` (the plugin must have a `g_rec[]` at all);
2. that process queues OVER the cap in game A, so a record exists with `count > 0`
   (arm 3 does this: `overflow=3`);
3. the SAME process then loads a DIFFERENT save -- one whose own file contains no
   overflow. Arm 6 loads the save the no-plugin control arm wrote.

Then read the plugin's own table, not the ring: `overflow=3 logical=7` against
`unit=0x00623E58` in a game whose file had a queue of four and no overflow. The ring is
the half that is RIGHT, which is why the first version of that assertion passed.

A single-arm run cannot show it. `-Phase fanout` alone reproduces it end to end because
arm 3 creates the stale record and arm 6 loads across it.

## Where this leaves the report

The report's run table now shows arm 6 as the FAIL and says the fanout phase ended
`1 failure(s) across 4 arm(s)` -- so the headline and the table agree rather than fighting.
Arm 4 is listed as PASS with its own finding beside it (the three held items are simply
absent -- 150 minerals of Probes paid for and never delivered), which is the design gap,
not the bug.

PR: https://github.com/inwenis/decompile-sc/pull/64
Issue: https://github.com/inwenis/decompile-sc/issues/63
Receipt: `work/scratch/ci-local/task051-save-load-with-mods-894fc5a.json` (`ci-local: PASS`,
`ruff` NOT RUN -- not installed). Merged origin/main first; drive-game.ps1 had an additive
tail collision with 050 and both sides are kept verbatim. The crossload arm was re-run
in-game AFTER the merge: 0 failures.
