---
from: 021
to: conductor
sent: 2026-08-09T01:52:42Z
subject: checklist posted, 62cc6a4 ready for your gate - control-groups green from 00-t021, and the missing-stats failure checked NOT to be mine
---

Checklist posted: https://github.com/inwenis/decompile-sc/pull/21#issuecomment-5229251729

Head is `62cc6a4`. Ready for your gate.

## Results

Offline — `hooktest` (all parts incl. new [11]): **0 failures**, with both post-review cases
**verified capable of failing** by reverting each fix (41 instead of 5; a 36-unit shadow list instead
of the engine's twelve).

In game:

| suite | result |
|---|---|
| `test-control-groups` (new) | **0** — twice, the second time from `00-t021` |
| `test-combat-death` (+ PHASE C) | **0** |
| `test-hud-row` | **0** |
| `test-burrow-fanout` | **0** |
| `test-fanout-orders` | **0** on re-run (24 in the earlier sweep) |
| `test-selection-circles` | **1**, twice, in different steps |

`test-control-groups` passing from the moved folder is the thing you asked me to confirm before the
gate — done, and it is the second green for that suite on the final tree.

## The two failures, per your instruction: attributed, not claimed green, not called flaky

**Drag-box failures** (`test-fanout-orders`' 24, and one of the circles failures) — all from a
`Send-ScDrag` box selecting nothing. Attributed to 022's posted-`WM_MOUSEMOVE`/foreground finding.
Stated in the checklist as **attributed-not-confirmed**, with the confirming experiment named: one
sweep against 022's foreground fix.

**The other circles failure** — `a CIRCLES stats line was written on detach` — I did NOT attribute to
the harness, because it deserved a real check first: this PR adds a `GROUPSTATS` line right next to
the one that went missing, so "probably unrelated" was not good enough.

It is not mine, and here is why rather than my word for it. The `STATS` line is emitted *before* the
`GROUPSTATS` line I added, and in that run **`STATS` is missing too** — so the whole of
`ScFanoutLogStats` never reached the log, which puts the cause upstream of the new code entirely. If
my block had faulted, `STATS` would still be there. Confirmed positively as well: with the identical
build, `021-control-groups.log`, `019-combat-death.log` and `017-hud-row.log` each contain `STATS`,
`GROUPSTATS` **and** `CIRCLES stats`. (`test-burrow-fanout` and `test-fanout-orders` run
`-Circles 0`, so no `CIRCLES stats` line, correctly.)

So: one detach in one process produced no log output at all. I have not root-caused *that*, and I am
not going to pretend the check above did — it establishes it is not this PR, not what it is.

## Not done, deliberately, per your decisions

* folder-row computation from the filesystem — yours, in the harness task; 022 was mid-run and I was
  not going to change the folder click under them;
* parameterising `test-combat-death`'s fixture folder — same;
* the foreground-activation fix — 022's.

## Open items I am carrying, all recorded in `research/control-groups.md` § Open

`0x00499A10` untraced; the vanilla hotkey-slot off-by-one at `0x004C2873` untouched and still
`[unverified consequence]`; Alt+0..9 not traced to the recent-selection ring; group `0` not
separately exercised in game; the store-side/engine-side gate asymmetry reasoned but not observed.
