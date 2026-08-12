---
from: conductor
to: user
sent: 2026-08-12T07:57:47Z
subject: Tests no longer touch your screen -- PR #52 merged, proven with you using the laptop through the run
---

## Your screen problem is fixed and merged

https://github.com/inwenis/decompile-sc/pull/52 — task 043, squash-merged into main.

A test run now happens on an invisible Windows desktop. Nothing reaches your monitor.

**The evidence I checked myself, rather than taking the worker's word:**

- `test-selection-circles.ps1`, unmodified, run twice — once off-screen, once visible.
  Assertion for assertion identical: same counts (3->2, 12/12, 12 vs 12, 12->11, 24 ordered),
  same circle coordinates (147,196), same final accounting (shown=24 hidden=12 held=12 lost=0).
- `watch-foreground.ps1` across the whole off-screen run: **"no StarCraft window was ever
  foreground"** — and the trace shows YOU working through it, Chrome then File Explorer then
  your terminal, uninterrupted. That is the proof that matters, and it is not self-reported:
  `C:\sc-work\logs\043\fg-offscreen.txt`.
- **It costs nothing:** 75.0 s off-screen vs 75.2 s visible, same suite, wall clock.
- `test-stim-fanout.ps1` — a different shape of suite, with fixture generation, a Game Type
  pick, keyboard input and 36 units — also ran off-screen with 0 failures.

One flag (`-Visible`) puts a run back on your screen when you want to watch, and it is the
same code path, not a separate mode.

## One real limit, measured rather than assumed

A **dropdown pick cannot work off-screen, ever.** Windows has exactly one foreground window and
it belongs to the desktop receiving your input, so a window on an invisible desktop can never
hold it. The game needs the foreground for its own `SetCapture` when a dropdown is held open.
The worker proved this properly: all three arms failed off-screen, including the control arm
that passes every time on the monitor.

In practice most suites never hit it, because the game-type combo usually already reads the
right value and the pick is skipped. When a pick IS needed the run stops and names the desktop
as the cause, pointing you at `-Visible` — it never silently runs a weaker test instead.

## Two follow-ups cut from what 043 found

1. **Task 045** — sweep every remaining suite off-screen and write the verdict per suite into
   the README, so "which suites take my screen" has one answer instead of being folklore.
   Queued behind the game lock, not started.
2. **Task 046** — `test-selection-circles` part [5] fails on clean `main` and has been failing
   for a while. 043 proved it pre-existing by running the suite on untouched main with its own
   build. Worth knowing: in the same run the shadow list, the circle count and the fan-out all
   agree on 24 boxed / 12 over-cap — three oracles agreeing with each other and disagreeing with
   the one log line this check reads. So the suspect is the diagnostic, not the feature.
   **Spawned, running now.** A permanently red line in a suite teaches everyone to ignore red
   lines, which is why it is worth a task.

## Board

039 (your 5th-slot bug) and 041 (randomized testing) both running; 041 has a game up right now.
043 finished and closed. CI still red on the billing error — I am merging on the local receipt
as you authorised, and saying so on each PR.
