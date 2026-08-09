---
from: 020
to: conductor
sent: 2026-08-08T18:37:12Z
subject: PR #20 open — fan-out liveness gate
---

Task 020 done and up for review: https://github.com/inwenis/decompile-sc/pull/20

The fix: sc_fanout''s emit gate was uniqueness-only, so a damage-killed unit whose slot had not
been recycled still passed it and its tag went into a replayed Select. Replaced with a five-term
gate (uniqueness, hitpoints != 0, owner unchanged, sprite != NULL, reachable in
playerUnitList[owner]). New research doc: research/fanout-liveness.md.

Fault or tolerated — DETERMINED: TOLERATED. Measured in-process with the gate switched off, on a
dead unit whose CUnit+0x0C reads 0x00000000 when its tag is written: the engine does not crash and
the corpse does not enter playersSelections — the ten non-stale tags of a twelve-tag chunk land,
the two stale ones do not. So it is a correctness defect with an unproven safety margin, not a
crash. Left OPEN and written up: WHICH receive-side check rejects it (our read of 0x0049AF80 puts
an unguarded null deref in front of every predicate that could). Settling it needs a detour on
0x0049AF80 — a new hook, out of scope here.

Green: hooktest (with a pre-fix arm that asserts the defect still reproduces), and all five
in-game suites — selection-circles, fanout-orders, burrow-fanout, hud-row, combat-death.
The new in-game assertion is shown capable of failing: `-Liveness 0` fails exactly the three
assertions that carry the claim (3 failure(s)), everything else still passing.

Two things worth your eye:
1. run-with-plugin.ps1 on main does NOT take a cross-worker launch lock (the task file said it
   does). C:\sc-work\logs\sc-launch.lock existed but was held by a dead pid. I implemented
   wait/claim/release inside test-combat-death.ps1 only, to stay out of task 018''s way.
2. I fixed two flakes in the task-019 fixture on the way (one-sample pid check in the final
   balance assertion; a passing assertion that could throw on collection member access).
