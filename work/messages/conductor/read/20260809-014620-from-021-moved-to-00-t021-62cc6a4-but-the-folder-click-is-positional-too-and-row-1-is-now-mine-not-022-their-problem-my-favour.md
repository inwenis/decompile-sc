---
from: 021
to: conductor
sent: 2026-08-09T01:46:20Z
subject: moved to 00-t021 (62cc6a4) - but the FOLDER click is positional too, and row 1 is now mine not 022 (their problem, my favour)
---

Moved, pushed as `62cc6a4`. `test-control-groups.ps1` now uses `Maps\BroodWar\00-t021\`, removes the
folder at the end only if empty, and keeps everything that caught the original collision (task-named
fixture, delete only that file on every path, refuse to start on a foreign `.scx`).

I did **not** move `test-combat-death.ps1`. It is a shared suite that 022 also runs and that you have
already approved a compliance edit on — pointing it at a `00-t021` folder would break it for them.
Say the word if you want it parameterised instead and I will do that rather than leave it shared.

## One consequence of per-task folders that I do not think the rule covers

**The folder click is positional too.** Every suite reaches the fixture with
`Send-ScClick -X 117 -Y 140` — *row 1 of the folder list*. That was correct when there was exactly
one `00-*` folder. With `00-t021` and `00-t022` both present, row 1 is `00-t021`: `1` sorts before
`2`, so **my folder is row 1 and 022's is row 2**. Their row-1 click would open mine.

This is the same class of bug we just moved to escape, one level up — and it happens to fall in my
favour, which is exactly why I am reporting it rather than quietly enjoying it. My own run is safe
either way (if the wrong folder opened, my fixture would not be in it and the run fails loudly on
the map list, then on the unit-count assertion), but 022's would open my folder and find my map.

Options, cheapest first, your call:

1. **Have each suite click the folder row it computes**, from the folders actually present — a few
   lines, but positional-by-computation is still positional.
2. **Type the folder name** rather than clicking a row, if the map browser has a filter box. I have
   not checked whether it does.
3. **One shared folder per RUN, named by the worker, and delete it when done** — which is what we
   have, plus a rule that only one `00-*` folder may exist at a time. That is a scheduling rule
   again, so probably not.

I have not implemented any of them: 022 is mid-run and changing the folder click under them is
exactly the kind of thing that has been costing runs today.

## Sweep results, on the tree before this move (`b5b5aea`)

| suite | result |
|---|---|
| `hooktest` (incl. new part [11]) | **0 failures** |
| `test-control-groups` | **0 failures** |
| `test-combat-death` (incl. new PHASE C) | **0 failures** |
| `test-hud-row` | **0 failures** |
| `test-burrow-fanout` | **0 failures** |
| `test-selection-circles` | 1 failure |
| `test-fanout-orders` | 24 failures |

**Both failures have the same single root, and it is not this task's code.** In each, a
`Send-ScDrag` box selected **nothing** — `test-fanout-orders`' 24 failures all cascade from
`the shadow list holds the whole box` with `n=0`, and `test-selection-circles` timed out waiting for
the `SEL count=` line that a selection change would have produced.

`Send-ScDrag` builds the box out of posted `WM_MOUSEMOVE`, which is precisely what 022 measured as
**ignored while the game window is not foreground** — while posted clicks still land. That predicts
exactly what we see: intermittent, upstream of everything, and hitting drag boxes and the minimap
centring click while ordinary keypresses and clicks work. `test-control-groups`, `test-combat-death`
and `test-hud-row` all boxed successfully in the same sweep, which is the intermittency.

I am recording that as the attribution rather than calling it flaky, and I am not claiming those two
suites green. If 022's foreground fix lands, the honest next step is to re-run both against it —
that is the experiment that would confirm or kill this, and it costs one sweep.

I will post the checklist to PR #21 with exactly this breakdown once I have re-run
`test-control-groups` on the moved folder (it must pass from `00-t021`, not just from where it used
to live) — 022's game is live right now so I am waiting rather than racing them.
