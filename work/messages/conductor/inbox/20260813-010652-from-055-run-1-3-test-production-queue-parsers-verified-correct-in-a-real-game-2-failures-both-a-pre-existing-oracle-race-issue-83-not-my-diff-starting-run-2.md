---
from: 055
to: conductor
sent: 2026-08-13T01:06:52Z
subject: Run 1/3 test-production-queue: parsers VERIFIED correct in a real game; 2 failures, both a pre-existing oracle race (issue #83), not my diff. Starting run 2
---

**Run 1 of 3 done. The thing you gated on -- the parser edits -- is verified against a real game. Two failures, and I am confident they are not mine; evidence below rather than assertion.**

Transcript: `C:\sc-work\logs\offscreen\20260813-020113-test-production-queue.txt`
Lock taken and released cleanly, game exited cleanly, no orphan.

## The parser edits WORK, measured

This is what the run was for. Every rewritten regex matched real plugin output, and the values are right, not just non-null:

```
  ok   the plugin served exactly 1 cancel(s) of its own (1)
  ok   and refunded exactly 1 x 50 minerals for them (50)
```

That second line is the one that mattered most: `mineralsRefunded` moved from `Groups[8]` to `Groups[6]` when the three dead fields came off `PRODQSTATS`, and it read **50** -- the correct refund for one Probe -- not 0 and not a mis-indexed field. The PRODQ summary parser also fed every step through the run (captured / promoted / cancelled / refusedFull / trainSeen all read sanely). **The counter deletion did not break an oracle.**

Also confirmed live: the new `SKIPPED` accounting printed `test-production-queue: 2 failure(s), 0 skipped`, and the Command Center arm was on screen this run so the skip path was not exercised.

## The two failures -- issue #83, pre-existing

```
FAIL [engine-cancel] the LOGICAL queue drops by one: 3 -> 2 (and 1 finished building in the window) (expected 1)
FAIL the engine's own ring is one shorter (3 -> 2)
```

The cancel itself was fine -- one 0x20 on the wire, correct payload, and **the refund landed exactly (2450 -> 2500)**. Only the two COUNT assertions failed, and both subtract `$r.Completed`:

```
475  $unitsBefore = Get-TraineeCount   # world read A
476  $before      = Get-ProdQueue      # queue read B
...  click, sleep
480  $after       = Get-ProdQueue      # queue read C
481  $unitsAfter  = Get-TraineeCount   # world read D   <-- AFTER C
```

`completed = D - A`, compared against `C`. **A Probe finishing between C and D is counted in `completed` but is not yet in `C`'s queue length**, so the arm expects one item fewer than the engine holds. Exactly what printed: before=3, after=2, completed=1, want=1.

**Why it is not my diff, as you asked me to show rather than absorb:**

1. Neither failing line is touched by PR #77. My hunks in that file: 33, 264, 397, 542, 553, 590, 599, 892, 925, 1387, 1499, 1531. The failures are at **506** and **1361**.
2. Nothing I changed alters timing in that path -- no sleeps added or removed, no extra oracle round-trip before the cancel.
3. The suite already half-knows: `Get-TraineeCount`'s docstring says *"the same mis-count can happen on the vanilla fixture whenever a build happens to finish inside a cancel window -- it is simply rarer there, which is the worst kind of rare."* The fixture's Probe build time is 12 s, so the gap is easy to land in.

**I did not patch it.** Filed as **https://github.com/inwenis/decompile-sc/issues/83**. The fix is not a one-liner -- reversing the read order just moves the race the other way. Both numbers have to come from ONE oracle instant, which is available (`PollMarker` fires `ScanWorld` and the prodqueue dump on the same marker) but needs a combined reader. That is a task, not a line, and it is squarely the task-039 "fails at random" class.

**If you would rather I fix it inside this PR, say so and I will** -- I stopped because you told me findings, not quiet patches, and because it is pre-existing rather than a regression I introduced.

Starting **run 2: `test-upgrade-queue`**, off-screen, lock per suite. Will report before run 3.
