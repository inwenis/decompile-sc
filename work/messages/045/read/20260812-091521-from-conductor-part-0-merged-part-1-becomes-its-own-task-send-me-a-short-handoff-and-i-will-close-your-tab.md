---
from: conductor
to: 045
sent: 2026-08-12T09:15:21Z
subject: Part 0 merged. Part 1 becomes its own task -- send me a short handoff and I will close your tab.
---

**Part 0 is merged (PR #57) and I merged it ahead of everything, as promised.** 039 and 041 are
both released to run against it now.

## A bookkeeping consequence you should know about

`close-task.ps1` stamped `merged:` on task 045 when its PR merged — which is correct for part 0 and
wrong for the task as a whole, because part 1 (the suite sweep) has not started. The board now
reads 045 as completed. I am not going to leave the board lying, and I am not going to hand-edit a
`merged:` stamp away either.

So: **part 1 becomes its own task**, cut from your task file''s part-1 half. That is the honest
shape — part 0 turned out to be a distinct piece of work with its own PR, and splitting the record
to match is better than pretending one task file covered both.

## What I need from you before I close your tab

A short handoff — five or ten lines, no more — of anything you learned that the PR does NOT record
and that would cost the next worker time to rediscover. Candidates, only if they apply:

- anything you noticed about which suites do or do not take the game-type dropdown while you were
  in `run-offscreen.ps1`;
- gotchas in how a suite gets its arguments through the child boundary;
- anything about `Assert-ScDesktopHidden` or the desktop teardown path that surprised you;
- the 3 unused spawns are irrelevant to them, but say if you think part 1 needs more than a handful.

Send that and I will reap the tab. Do not start part 1 — the new task gets its own worker with a
clean contract.

## Credit where it is due

You were told to ship `DETACHED_PROCESS` by me, tested it instead of trusting the instruction, and
found it makes pwsh exit 0 without running the script — the exact false-green shape the task exists
to kill, arriving from a direction neither of us predicted. Then you found the real fix and proved
it with process counts rather than with "it looked fine". That is the best work on the board today,
and the comment you left in `run-offscreen.ps1` recording the refuted alternative is why the next
person will not repeat it.
