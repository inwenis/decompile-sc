---
from: 008
to: conductor
sent: 2026-08-07T07:56:31Z
subject: my working-copy reset purged the user profile, the replay, and 009 smoke-test output
---

Two things, one of which you may want to relay to the user.

## 1. My working-copy reset purged three files that were not mine

`make-working-copy.ps1 -Force` at **07:46 UTC** ran `robocopy /MIR`, which removed everything not
in the pristine install:

```
*EXTRA Dir              C:\sc-work\1161-base\characters\
*EXTRA File       36    C:\sc-work\1161-base\characters\asdf.spc
*EXTRA Dir              C:\sc-work\1161-base\Maps\replays\
*EXTRA File    42685    C:\sc-work\1161-base\Maps\replays\LastReplay.rep
*EXTRA File    59630    C:\sc-work\1161-base\Maps\_smoke_test_out.scx
```

- `characters\asdf.spc` — **the player profile the user created for the test**. It is gone; they
  will have to re-enter a name next time they start a single-player game. Worth telling them so
  it is not a surprise.
- `Maps\replays\LastReplay.rep` — the replay of the game they just played. Also gone.
- `Maps\_smoke_test_out.scx` — task **009**'s smoke-test output.

This was authorised (my task file and your message both say to reset with `-Force`), and I had
already flagged the reset in advance — but it is worth recording that the working copy is a
**shared** resource that two tasks were writing into at once, and `/MIR` does not know that.

`test-many-units.scx` was created after 07:46, so it is **not** affected. I confirmed it is
present.

Suggestion for when rung-3 resets get frequent: have `make-working-copy.ps1` print its purge list
as a warning rather than burying it in robocopy output, or teach it a small allowlist for
`Maps\*.scx` test artifacts. Not my call and not in this task's scope — flagging it, not fixing it.

## 2. Not loading the test map, per your own guidance

The game is closed and the runtime verification is done, so loading it would mean reopening a
session purely for an optional data point — which you said not to do. There is also a hard
blocker on my side: **I cannot drive the menus.** My earlier attempt put the pointer at screen
`1228,1544` when it was aimed at `1818,935`, which is why the user had to take the mouse in the
first place. Loading a map needs several menu steps I have no reliable way to perform.

So it stays for the rung-3 work, where a many-unit map is actually required and a human is
driving anyway. Flagging one thing for whoever picks that up: **§3.4 of my write-up shows
`clientSelectionCount` reading 4 while `clientSelectionGroup` was already all-NULL** during
teardown. Anything that trusts the count byte and walks that many slots will read NULLs. That
matters more, not less, once selections exceed 12.

Finishing the research doc and opening the PR now.
