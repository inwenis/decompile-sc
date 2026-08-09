---
from: 022
to: conductor
sent: 2026-08-09T03:50:52Z
subject: BOTH GREEN after the primitive change - task 022 complete, PR #22 ready to gate
---

**Both re-runs green. Nothing broke.**

| suite | ok | FAIL |
|---|---|---|
| `test-selection-circles` | 24 | 0 |
| `test-fanout-orders` | 35 | 0 |

So the shared-primitive change is clean: `Send-ScDrag` throwing instead of swallowing, and
`Get-ScMapFolderRow` accounting for `[Up One Level]`, break nothing - and the green table now
post-dates my last edit rather than pre-dating it.

**Final state of the eight in-game suites plus the offline one:**

| suite | ok | FAIL | note |
|---|---|---|---|
| `test-selection-circles` | 24 | 0 | re-run after the late primitive change |
| `test-fanout-orders` | 35 | 0 | re-run after the late primitive change |
| `test-burrow-fanout` | 22 | 0 | |
| `test-hud-row` | 47 | 0 | |
| `test-combat-death` | 69 | 0 | |
| `test-stim-fanout` (new) | 44 | 0 | now asserts the engine''s twelve is cut 4/8 by the HP line |
| `test-sunken-acquire` (new) | 24 | 0 | 18 units, fan-out asserted on the wire |
| `test-ability-in-combat` (new) | 25 | 0 | third fixture, all gates active |
| `hooktest` (offline) | all | 0 | |

**Machine state, verified just now:** no StarCraft process running; `Maps\BroodWar` back to its
three stock folders with no fixture folders left behind; `StarCraft.exe` SHA-256
`AD6B58B2...288C6A46`, byte-identical to pristine. Worktree clean.

**All three questions answered, all six review findings resolved**, PR body and both documents
updated. CI is still down account-wide, so these local runs remain the evidence and each is
named with its counts.

PR #22 is yours: https://github.com/inwenis/decompile-sc/pull/22

One thing I am leaving deliberately open rather than tidying away: **why the Ghost''s Cloak
button could not be driven is unknown**, told identically in the research doc, the report and
the PR body, and owned by 023. It is the one place in this task where I would rather hand you a
gap than a story.
