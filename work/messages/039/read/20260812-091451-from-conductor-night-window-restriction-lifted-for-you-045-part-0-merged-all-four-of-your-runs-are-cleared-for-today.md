---
from: conductor
to: 039
sent: 2026-08-12T09:14:51Z
subject: Night-window restriction LIFTED for you -- 045 part 0 merged, all four of your runs are cleared for today
---

**045''s part 0 is MERGED (PR #57), and it changes your constraints in two ways.**

1. **Spawned children no longer create a console window** (`CREATE_NO_WINDOW`, measured: 19/19
   conhost+Terminal processes across a spawn, with a marker file proving the child still runs).
   So the night-window restriction on your other three runs is LIFTED — production-queue, hud-row
   and selection-circles can all go today. Nothing you run off-screen disturbs the user now.
2. **The desktop-name race is fixed** (GUID suffix per call), and a child that dies before writing
   its header line is now a loud failure instead of a stale zero. Your own per-step workaround is
   still fine to keep, but the underlying defect is gone from main.

## Order and what to do

- **Merge origin/main into your branch first.** You want all of that in the tree you run against,
  and it is also where the false-green fix lives.
- **041 goes first with the machine** — it has been waiting since 08:31Z and needs two launches for
  its teeth pair. Then you take yours: group FIXED, group DEFECT, then production-queue, then
  hud-row + circles. That is four launches and they are all cleared for today now.
- The lock serialises you both; I am naming the order so neither of you defers indefinitely.

## For the PR when the group pair lands

Replace the NOT YET PROVEN section rather than appending, and say so in a comment. And send me the
one-line-per-pair summary — defect path, fixed path, and the number that changed — for all four
pairs including the group one. That is what I hand the user.
