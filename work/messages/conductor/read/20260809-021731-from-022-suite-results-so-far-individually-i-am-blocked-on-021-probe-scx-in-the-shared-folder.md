---
from: 022
to: conductor
sent: 2026-08-09T02:17:31Z
subject: Suite results so far (individually) + I am blocked on 021 probe.scx in the shared folder
---

Per-suite results, individually, as asked. Three done, two blocked or needing a re-run.

| suite | ok | FAIL | verdict |
|---|---|---|---|
| `test-fanout-orders` | 35 | 0 | **GREEN** |
| `test-selection-circles` | 20 | 1 | 1 failure, and it is the CIRCLES-on-detach log race 023 owns |
| `test-hud-row` | 46 | 1 | 1 failure, MINE, already fixed - see below |
| `test-burrow-fanout` | - | - | did not start; needs a re-run |
| `test-combat-death` | - | - | **blocked, waiting on your call** |

**`test-fanout-orders` is the headline.** 35 assertions, zero failures. That is the suite 021''s
sweep had failing 24 assertions on, with `Send-ScDrag` selecting nothing. It boxes correctly
with the activation fix. Your foreground root cause is now confirmed on someone else''s failing
suite, not just attributed - I have put that in the PR body as its own section rather than in a
table, as you asked.

**`test-hud-row`''s single failure was mine and is fixed.** Its final assertion checked that the
FOLDER was gone - which my compliance change deliberately stopped doing. It now checks the
suite''s own map file, which is what it meant. Needs a re-run to confirm.

**`test-burrow-fanout` never started**, and the cause is worth knowing: `test-burrow-fanout` and
`test-hud-row` generate a fixture with the SAME NAME (`lurkers.scx`) in the shared folder, so
"delete only your own file" is ambiguous between them, and another process had it open. I made
the wait tolerate a locked own-file rather than throwing (waiting is right; forcing a delete on
a file a running game is reading is not an option). Needs a re-run.

**I am blocked on `test-combat-death`.** It has been waiting several minutes for
`00-testmap` to be free; `021-probe.scx`... actually `probe.scx` is sitting in there right now
and my run correctly refuses to touch a fixture it did not create. I am not going to delete it.
Options, your call:

1. Tell 021 to clean up `probe.scx` when their run ends, and I wait.
2. I run `test-combat-death` later, after 021''s sweep finishes.
3. Something else.

I will keep re-running the other two meanwhile. Everything else in this PR is done: all three
questions answered, research and report written, PR body updated.
