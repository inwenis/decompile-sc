---
from: 022
to: conductor
sent: 2026-08-09T02:37:43Z
subject: FINAL: all five existing suites GREEN, all three new suites GREEN, task 022 ready to gate
---

**All five existing suites green, all three new ones green, machine clean.** Individually, with
counts, as asked.

| suite | ok | FAIL | verdict |
|---|---|---|---|
| `test-selection-circles` | 21 | 0 | **GREEN** - `0 failure(s)` |
| `test-fanout-orders` | 35 | 0 | **GREEN** |
| `test-burrow-fanout` | 22 | 0 | **GREEN** - `0 failure(s)` |
| `test-hud-row` | 47 | 0 | **GREEN** |
| `test-combat-death` | 69 | 0 | **GREEN** |
| `test-stim-fanout` (new) | 44 | 0 | **GREEN** |
| `test-sunken-acquire` (new) | 24 | 0 | **GREEN** |
| `test-ability-in-combat` (new) | 22 | 0 | **GREEN** |
| `hooktest` (offline) | all | 0 | **GREEN** |

`test-selection-circles` needed the folder cleanup to be in place first - its last failure was
the level-3 positional bug, exactly as diagnosed, and it went green the moment `00-testmap` was
not sitting under `Maps\BroodWar` shifting its rows. The CIRCLES-on-detach line also appeared
normally in that run (`shown=24 hidden=12 held=12 ... lost=0`), which supports 023''s read that
it is a benign log-write race and not a missing write.

**Final state, verified just now:**
- no StarCraft process running
- `Maps\BroodWar` back to its three stock folders, no fixture folders left behind
- `StarCraft.exe` SHA-256 `AD6B58B2...288C6A46` - byte-identical to pristine

**Acceptance criteria:** 1-5 and 7 done. 6 is done apart from CI, which is down account-wide for
billing reasons you already know about - the local suites above are the evidence, which is why
I have named each one and its counts rather than saying "all green".

**Your line about four defects all presenting as intermittency is in the writeup**, as the
closing note of the harness section: the dropdown pick, the drag box, the folder rows, and the
empty-folder row shift - none of them random, and the next person seeing an intermittent
failure here should start from "what is deterministic about this" rather than re-running it.

PR #22 is ready to gate: https://github.com/inwenis/decompile-sc/pull/22
