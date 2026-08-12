---
from: 041
to: conductor
sent: 2026-08-12T08:30:34Z
subject: INTERIM: gate green (93 checks, 0 fail, off-screen); teeth test still open and I am saying why
---

Interim, because the machine is contended and I do not want you sequencing blind. Nothing here
needs an answer.

## Where it stands

- **Harness is built, committed, and local CI is green** — `ci-local: PASS
  task041-randomized-conformance@c32ed3f` (only optional `ruff` skipped, not installed).
- **Gate run on current main: PASS, 93 checks, 0 failures, 6 of 6 episodes, 2:36 wall clock**,
  entirely OFF-SCREEN on 043's invisible desktop. All seven invariants asserted; one honest skip
  (INV-Q's surface half, because 039's `boxDiff` is not merged yet).
- **Teeth test: not yet demonstrated.** Two separate reasons, both mine, both now fixed or
  understood — details below. It is the one acceptance criterion still open, and I am re-running.

## The teeth test, honestly

My first teeth run against `59aa50b` with seed 20260812 came out **PASS 94/0 — against the very
build whose bug it was written to find.** That is the most dangerous possible result and it is
worth stating plainly rather than burying:

The run's own indicator episode filled one building to the plugin's cap. The headroom check then
clamped every later GROUP burst to two or three presses, and below the engine's five slots a
plugin with 038's bug behaves exactly like a correct one. So the seam was never reached, and
nothing in the output said so.

Two changes came out of that:

1. The coverage report now COUNTS the episodes that pushed a multi-building selection past the
   engine's five slots, and when that count is zero it says: *"A run that never does that CANNOT
   detect task 038's class of bug, whatever its verdict says."* That line is what would have told
   me in one second instead of one run.
2. The teeth test now uses **seed 47**, chosen offline from the plan generator (no game needed):
   its episode 1 is an 11-press burst across two buildings and episode 2 a 9-press group recall,
   both against empty queues. I picked it deliberately and I am saying so — it is not a seed that
   happened to work.

I did see the bug reproduce on an earlier teeth run, on 038's exact seam: `0x00623E58 went PAST
the engine's 5, and its ring is held at 4 (5)` in the two group episodes, plus the Train button
leaving the card entirely in one of them — the user's own symptom. That run is not my evidence
though, because a harness change had landed between it and its paired gate run, and I will not
publish a comparison whose two halves ran different code.

## Two things the harness found out about ITSELF, which is the point

- It printed `PASS 13 checks, 0 failures` for a run that threw right after its fixture step and
  executed NO episodes — the exit code swallowed by the transcript pipe. The verdict now depends
  on reaching the end of the episode loop: `INCOMPLETE`, never `PASS`, non-zero, episode count on
  the summary. It has since caught three real aborts, including today's wrong-map one.
- Posted HOTKEYS stopped being processed mid-run and stayed dead: `trainSeen` froze while three
  episodes pressed 22 more times, so every later episode failed INV-W/INV-M with "0 presses
  reached the funnel" — which reads exactly like the feature being broken. Posted CLICKS worked
  throughout. Train is now driven by clicking the card's own button, and a burst that produces
  ZERO commands while the button was enabled is reported as `INPUT` (a harness failure) rather
  than as an invariant failure.

## Machine

Heavily contended — I have queued behind four different workers' games in the last half hour
(pids 1980, 13628, 15640, 12388) and my current run is still waiting. I am waiting on the lock,
never killing. If you would rather I take a slot at a particular time, say so.

One hazard worth knowing about, since it cost me a run: my teeth launch loaded the WRONG MAP —
the browser row shifted under it (`[00-t041]` read at row 2 where it had been row 1) and the game
came up with zero player units. The fixture assertion caught it and the run went INCOMPLETE
rather than reporting anything about the build. That is the row-shift hazard AGENTS.md documents,
under concurrent fixture folders.
