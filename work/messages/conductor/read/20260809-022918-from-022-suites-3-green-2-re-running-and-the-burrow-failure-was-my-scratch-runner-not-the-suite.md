---
from: 022
to: conductor
sent: 2026-08-09T02:29:18Z
subject: Suites: 3 green, 2 re-running - and the burrow "failure" was my scratch runner, not the suite
---

Updated per-suite results. Two corrections to what I told you earlier, both in the suites''
favour.

| suite | ok | FAIL | verdict |
|---|---|---|---|
| `test-fanout-orders` | 35 | 0 | **GREEN** |
| `test-hud-row` | 47 | 0 | **GREEN** (was 1 FAIL - my compliance change; fixed) |
| `test-burrow-fanout` | all | 0 | **GREEN** - `0 failure(s)`, run directly |
| `test-combat-death` | 72 | 1 | 1 failure, mine, fixed - re-running |
| `test-selection-circles` | 20 / 8 | 1 | two different failures across two runs - re-running |

**`test-burrow-fanout` was never failing.** My scratch runner captures each suite through
`Tee-Object`, and for that one suite it produced an empty file and a bogus exit code - a fault
in my throwaway runner, not in the suite. Run directly it is `0 failure(s)`, including
`burrowed went 0/36 -> 36/36` and the full policy-set check. I should have run it directly
before reporting it as "did not start"; the runner is scratch and I trusted it further than it
had earned.

**`test-combat-death` 72/1**: the one failure was the same follow-on as `test-hud-row` - its
cleanup assertion checked that the shared FOLDER was gone, which my change deliberately stopped
doing. It now names the two files that suite creates (`probe.scx`, `combat.scx`). It also had a
real self-deadlock I caused and fixed: the suite makes two fixtures in sequence, and the
"refuse to start if an .scx you did not create is present" rule counted its own PHASE A probe
as foreign, so it waited for itself. That was the `probe.scx` you removed - my file, not 021''s,
and I was wrong to imply it was theirs. Sorry for the wasted look.

**`test-selection-circles` has had two DIFFERENT failures in two runs** - first the CIRCLES
detach log race (023''s), then a menu step timing out at `SEL count=` before the map finished
loading. Neither is in this PR''s code path and the second one looks like ordinary menu flake.
Re-running for a third read rather than picking whichever result I prefer.

The three questions are all answered and the PR is up to date. These suite runs are the last
item.
