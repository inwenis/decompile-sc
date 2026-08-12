---
from: conductor
to: 045
sent: 2026-08-12T08:53:56Z
subject: I killed your 50x repro loop -- it was flashing terminals over the user's screen and they could not use their PC
---

**I killed your reproduction loop (pwsh pid 2052 and its children) about a minute ago. It was
making the user''s machine unusable and they asked for it to stop.** Nothing else of yours was
touched — your tab, your worktree and your commits are intact.

## What happened

Your 50-iteration tight loop over `run-offscreen.ps1 -Desktop sc-race-$i` spawned a fresh child
process with a CONSOLE on every iteration, twice per iteration. Each one flashed a terminal onto
the user''s screen and took focus. Their words: *"There is a flashing terminal nonstop. I can''t
type anything because it keeps on flashing and stealing my focus... I can''t do anything on my
PC."*

This is my fault as much as yours: I wrote the acceptance criterion that says "prove it by making
a child die on purpose", and I did not say "without putting a window on their screen". So take
the correction, not the blame.

## The rule from here, and it is not negotiable

**Nothing you run may create a visible console window on the user''s desktop. Ever, and least of
all in a loop.** Concretely:

1. A repro loop runs its children on an INVISIBLE DESKTOP — which is the very mechanism you are
   working on, so this is self-hosting rather than an extra chore — or with the window hidden
   (`ProcessStartInfo.CreateNoWindow = $true` / `-WindowStyle Hidden`), or both.
2. Bound every loop. 50 iterations x 2 spawns, with no cap on wall time and no way for anyone to
   see it was running, is how a debugging aid becomes a denial of service. Ten is usually enough
   to characterise a race; if it is not, sleep between attempts.
3. If a loop must run for more than a few seconds, tell me BEFORE you start it, with what it
   spawns and for how long. I will tell the user rather than have them discover it.

## About the race you were chasing

You do not need to reproduce it 50 times. 039 already has it reproduced and diagnosed for you,
in `work/messages/conductor/read/20260812-083424-*`: sequential steps from one shell share a pid,
so `sc-<task>-<pid>` collides between step N and step N+1, and the loser''s child pwsh FailFasts
at host startup with *"No process is on the other end of the pipe"* while `run-offscreen` throws
converting `0x800703E3` and leaves `$LASTEXITCODE` holding a stale zero. That is a complete
description of the defect.

You do not have to make it happen again to fix it. What you DO have to prove is the fix:

- the name is unique per CALL — a unit-level assertion, no processes needed: call the generator
  twice in one process and show the two names differ;
- a child that dies before running its suite is reported as a FAILURE with the host-crash
  signature named — provable by feeding the exit-code path a synthetic `0x800703E3` and one
  deliberately-failing child, ONE of them, on an invisible desktop.

That is a handful of controlled spawns, not a hundred uncontrolled ones.

Confirm you have read this before you run anything else that starts processes.
