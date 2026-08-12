---
from: 039
to: conductor
sent: 2026-08-12T08:40:58Z
subject: Yes -- ONE of my runs was visible, 08:00-08:05Z, and it was not what they watched. Plus the group phase now answers "why is it flashing"
---

## 1. Were any of my runs on their monitor? Yes, exactly one, and here is the full list

Checked per run rather than from memory (`invisible desktop` created / `scinject: launched` /
`launching onto the desktop` in each console log):

| run | game launched | where |
| --- | ------------- | ----- |
| defect barracks probe, 08:00:28-08:05:12Z | yes, pid 5528 | **VISIBLE DESKTOP** |
| defect frames, 08:14-08:18Z | yes, pid 13628 | off-screen |
| defect frames (arm-aware), 08:26-08:27Z | yes, pid 15640 | off-screen |
| fixed frames, 08:28-08:30Z | yes | off-screen |
| fixed prodqueue, 08:29Z | **no game** -- host crashed first | n/a |
| fixed group, 08:29-08:32Z | **no game** -- I stopped it while it queued | n/a |

So: **one run of mine was on their screen, 08:00-08:05Z**, and the cause is mundane -- I
launched the probe directly before I had merged 043's off-screen path into my branch. Every run
since 08:14Z went to an invisible desktop.

**It was not what they watched.** They described "30 units have been selected" at 08:33Z; my
fixture is one Command Center and one Barracks, it never has 30 of anything, and by 08:33Z I had
no game running at all. A 36-unit selection is `test-selection-circles`/`test-hud-row` shaped --
somebody else, and worth finding, because if that run was visible the same gap exists in
whatever launched it.

## 2. "Why is it flashing" -- I think their sentence contains the mechanism, and it is not
   list re-ordering

A HEAD-spliced control does not lose every frame. It loses every frame in which the engine
repaints something that overlaps it, and the pane only repaints what is DIRTY -- so in frames
where the wireframe buttons are not redrawn, our text from the previous frame survives on the
surface. Alternation, at whatever rate the row happens to redraw. That is "appearing in front
and behind" without anything re-ordering the child list, and it is consistent with my
`boxDiff=0`: my samples happened to land on frames the row had repainted.

I am not asserting that from an armchair -- the group phase I just wrote measures it.

## 3. The group phase, now in my own probe rather than borrowed from the group suite

My fixture already holds two producing buildings, so I do not need
`test-group-production`'s four Command Centers to get a group line. It queues 3 at the Command
Center and 3 at the Barracks, clicks one and SHIFT-clicks the other (the engine's own way of
adding to a selection), then **reads the same state six times, ~700 ms apart, and prints every
boxDiff**, because "it drew once" and "it draws on every frame" are different claims and only
the second one is a fix. Two frames come out of the middle of that sampling.

The assertions, per arm:

    fixed   the line is BELOW the row on every sample (top vs the LIVE lowest button edge,
            read from the QINDDLG dump, ids 33..44 -- never a constant), AND boxDiff > 0 in
            ALL six samples
    defect  the line is ON the row in every sample, and the count of samples in which it put
            bytes on the screen is REPORTED rather than asserted -- that count is the
            flickering, quantified

So your question 2 gets a number instead of an opinion: six of six means it wins every frame we
sampled; anything less and I will say so plainly and not close defect 2.

## 4. Their "another place" ask

My read: the band below the row IS a change of place, not just of order -- it is a strip the
multi-select layout leaves empty, outside every one of the twelve button rects, measured off
those rects every frame and REFUSED (draw nothing) when it does not fit. The before/after pair
plus the six samples will settle whether that satisfies them. If the after frame still looks
contested I will say so and propose somewhere else rather than declare victory.

## 5. Where I am while held

Local CI **PASS** on `c81c429` (77 Pester, hooktest 0 failures; ruff not installed, reported as
NOT RUN). One thing worth knowing: `run-ci-local.ps1` from the MAIN checkout fails 20 tests with
`ModuleNotFoundError: No module named 'richchk'` -- `C:\git\decompile-sc\.venv` does not have it
while my worktree's does. Not my change and not blocking me, but if you gate anything from the
main checkout you will see 20 red that are pure environment.

Ready to run the moment you release me; group pair first, as you said.
