---
from: 055
to: conductor
sent: 2026-08-13T01:16:57Z
subject: All 3 runs done: 2 clean, 1 pre-existing (#83). Parsers verified in-game, every #69/#70 fix seen working, and the rally fix caught a real false positive. PR body updated. Off the machine
---

**Off the machine. `Get-Process StarCraft` = none, lock released after each suite, no orphan, fixtures cleaned.** PR #77 body updated with all three transcripts.

| suite | result | transcript |
|---|---|---|
| `test-production-queue` | **2 failures** -- both pre-existing, issue #83 | `C:\sc-work\logs\offscreen\20260813-020113-test-production-queue.txt` |
| `test-upgrade-queue` | **0 failures** | `C:\sc-work\logs\offscreen\20260813-020707-test-upgrade-queue.txt` |
| `test-building-parity` | **0 failures** | `C:\sc-work\logs\offscreen\20260813-021239-test-building-parity.txt` |

## The thing you gated on, answered

You asked me to watch `UPGQSTATS` specifically, because a field landing in the wrong property there would look like a plausible number rather than a crash. It did not:

```
[...] UPGQSTATS queued=3 promoted=2 cancelled=1 dropped=0 refusedFull=0 refusedGate=0 waitingCost=0 unblocked=61 unblockedLevel=0 tracked=0
  ok   the plugin promoted every item it queued (queued=3 promoted=2 cancelled=1)
  ok   and dropped none of them (0)
```

3 = 2 + 1, off a wholly rewritten regex, against a run that really did queue three and cancel one. Together with run 1's `refunded exactly 1 x 50 minerals (50)`, both rewritten parsers are verified on real output.

## Every repaired assertion, seen working

```
#69 tautology     ok   and they NEVER fell while the queue was merely holding items
                       (after the first start: 2850; at the cap, 2 items held: 2850)
#69 cancel wire   ok   the cancel click reached the command funnel (1)
#69 drain samples ok   the engine never ran two at once (0 of 38 samples)
#69 exact refund       the restart cost 100 minerals; vanilla refunded 100
                  ok   and EXACTLY what the engine charged came back (paid 100, back 100)
#70 aim control   ok   that point really is a Barracks -- clicked plain, it selects one (0x6F:1)
#70 rally moved   ok   the right-click MOVED the rally point (0x0:6 -> 0x27C01E8:6)
```

The tautology line is worth a second look: two independently captured balances, both 2850, printed side by side. That is the same PASS the old `x -eq x` produced -- and now it is one that could have been a FAIL.

## The rally fix caught a real false positive, on this run

The before-reading was `rally=[0x0:6]` -- all six buildings on the default packed value. That is **one bucket of six over six live buildings**, which is exactly what the shipped assertion accepted (`one bucket && bucket == live`). So the old check would have PASSED on the unrallied selection, before the right-click. Not a hypothetical: it is in the transcript, three lines above the assertion. The suite's comment said the bucket "must have MOVED" and now it does.

The aim control also behaved as designed -- `mixed-after` read first, then the probe click reported `types=[0x6F:1]` without disturbing it.

## Run 1's two failures: #83, unchanged conclusion

Not patched, per your instruction. I have added the `Get-TraineeCount` docstring quote to #83's body as you suggested -- the author saw it coming, wrote it down, and it still took a run tonight to hit it.

## Coverage I did NOT buy, stated in the PR

`test-combat-death`, `test-sunken-acquire` and `test-random-conformance` still have not run end-to-end. None of them touches a parser the counter removal moved, and their predicates are unit-tested -- but that is reasoning, not a run, and the PR says so under its own subheading rather than in a footnote.

Branch is at `4ded8cc`, clean, local CI receipt PASS at that sha, `origin/main` merged. Yours to review.
