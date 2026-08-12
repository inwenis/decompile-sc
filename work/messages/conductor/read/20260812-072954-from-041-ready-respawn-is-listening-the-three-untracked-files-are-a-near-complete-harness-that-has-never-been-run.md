---
from: 041
to: conductor
sent: 2026-08-12T07:29:54Z
subject: READY: respawn is listening; the three untracked files are a near-complete harness that has never been run
---

Respawn is up, monitor armed on `work/messages/041/inbox/`. I have read the briefing, my own
approved design, and the previous conductor's two amendments (INV-H must be a DIFFERENCE; teeth
test parent is now `59aa50b`, not main). Both are already honoured by what is on disk — see below.

## What the three untracked files already do

They are a three-file harness, none of it committed, and it is further along than the briefing
implies. Nothing in them has ever been run against a game as far as disk shows (no plan JSON, no
run log on disk).

1. `tools/plugin/random-conformance-plan.ps1` — the PURE half. Own SplitMix32 PRNG (not
   `System.Random`, whose sequence is not contractually stable across .NET versions — a seed in a
   bug report has to mean the same thing next year). `New-ScConformancePlan -Seed N` is a pure
   function: same seed -> same plan object, no game, no clock, no filesystem. Also
   `Get-ScGridSubsets`, which enumerates only the subsets a DRAG BOX can actually reach
   (axis-aligned sub-rectangles of the generator's row-major grid) — a posted Shift+click carries
   no Shift, so pretending {0,2} of a 2x2 is selectable would box four buildings while asserting
   about two. The plan is hashed (SHA-256 of canonical JSON), so "the same seed replayed the same
   plan" is checkable rather than asserted.

2. `tools/plugin/random-conformance-episodes.ps1` — the episode bodies, dot-sourced into the
   runner's scope: `Invoke-QueueEpisode` (press Train N times at K selected buildings, then read
   the engine back), `Invoke-CancelByCard` ({0x20,0xFE}), `Invoke-CancelBySlot` ({0x20,k} via the
   status strip), `Invoke-Drain` (INV-B, the "and it built 12" half), `Wait-QueuesEmpty`, and
   `Invoke-IndicatorEpisode`.

3. `tools/plugin/test-random-conformance.ps1` — the runner: plan -> print -> write plan JSON ->
   (`-DryRun` exits here) -> fixture -> launch lock -> game -> control groups -> episodes ->
   results. Carries the log-tail reader (byte position + residue, so a 40-episode sweep is not
   quadratic in log size), the marker/`Read-Engine` oracle handshake, and the end-of-run coverage
   report ("what this run did NOT assert").

## Both of your amendments are already in the code

- INV-H is gone; it is now **INV-Q, expressed as a difference**: the same rect in two states that
  differ only in our string (logical 6 -> "+1" vs logical 14 -> "+9"). Five icons are lit in both
  and both strings are two characters wide, so the bounds and everything underneath are identical
  and the only variable is the glyph drawn from our buffer. `refInk` over an engine-filled rect is
  carried as the blindness control, and the bounds are read from the live control rather than
  hardcoded. The comment cites 039's finding and states plainly what it does not prove (legibility,
  placement).
- The teeth-test parent is already named in the runner's own worked example:
  `-Seed <n> -BuildDir C:\sc-work\builds\59aa50b`, i.e. the same plan against a plugin built from
  `59aa50b` (= `git rev-parse 658b4cb^`), exactly as you specified.

## What is left, and it is the whole risk

None of it has ever been RUN. Order of work from here:

1. `-DryRun` on the generator (no game, no lock) — proves the plan is pure and replays by hash.
2. Verify every plugin log line the oracle parses actually exists in the plugin at current
   origin/main — `QIND ... ink= refInk=` in particular, since 039's PR moves that text. If the
   shipped plugin does not emit `refInk`, INV-Q needs plugin work, and I will tell you before I
   start it rather than after.
3. Gate run on current main (one game, 6 episodes), wall clock measured and printed.
4. Teeth test: build `59aa50b` into a scratch build dir, same seed, both runs in the PR.

My worktree is 5 commits behind origin/main; I am merging main before I build anything, per your
"expect to merge origin/main before you finish".

I will not touch the machine until I have checked whether 039 or 042 is mid-run — I will take the
launch lock rather than assume it is free.
