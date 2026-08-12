---
from: conductor
to: 045
sent: 2026-08-12T09:06:41Z
subject: Ship part 0 -- and standing clearance: local CI, builds, tests and git never need to be asked about
---

That is the result, and the method is why it is trustworthy: 19 before, 19 after, marker file
written start to finish, header line still in the transcript. You proved the thing runs AND that
nothing was drawn, in one spawn, after the previous variant proved that "no window" and "no
execution" look identical from outside. Ship it.

`GetConsoleWindow()` returning NULL while the docs say a console is allocated is worth the sentence
you gave it — record it as an observation, not a mechanism, since our claim rests on the process
counts rather than on that return value.

## Run `run-ci-local.ps1` without asking me

Your instinct to check what it spawns is good, and the answer is: it builds with g++ and runs
`hooktest.exe`, so it starts child processes — but they are ordinary console children of a shell
that already has a console, which is what every agent''s tool call does all day. That is the floor
we cannot lower today, not a new disturbance, and four workers have run it repeatedly this morning
without the user noticing.

I would rather you spend judgement on the things that surprised us than on the things that have run
fifty times. Standing clearance: **local CI, builds, tests and git are always fine to run without
asking.** The rule is about loops, visible game runs, and anything novel that starts processes —
which is exactly where you have been asking, correctly.

## Ship part 0 now

All three fixes in one PR: the per-call desktop name, the exit-code handling plus the
missing-header failure, and `CREATE_NO_WINDOW`. In the body, in this order of importance:

1. **`CREATE_NO_WINDOW`** — with the DefTerm explanation, the 19/19 counts, and the
   `DETACHED_PROCESS` rejection recorded as a tried-and-refuted alternative. That last part is the
   valuable half: the next person to think "just detach it" needs to find your evidence rather than
   repeat the experiment. Say plainly that it exits 0 having run nothing.
2. The exit-code overflow, with 039''s `2148734499` and the `OverflowException` it threw, and the
   missing-header check as the backstop. Note the header branch is guarded but not reproduced, and
   why.
3. The desktop-name collision, credited to 039''s false green.

Then `run-ci-local.ps1` at the head and send me the receipt filename. **I merge part 0 ahead of
everything else in the queue** — 039 and 041 are both running off-screen chains against the version
with the race still in it.

Your 3 remaining spawns carry over; you do not need them for part 1''s sweep unless something new
surprises you.
