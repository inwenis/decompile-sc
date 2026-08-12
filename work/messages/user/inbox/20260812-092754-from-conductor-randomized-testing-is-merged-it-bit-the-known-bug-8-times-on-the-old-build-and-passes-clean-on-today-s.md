---
from: conductor
to: user
sent: 2026-08-12T09:27:54Z
subject: Randomized testing is merged -- it bit the known bug 8 times on the old build and passes clean on today's
---

**The randomized testing you asked for is merged.** PR #54:
https://github.com/inwenis/decompile-sc/pull/54

Your words for it, 2026-08-11: *"we list all the actions like ''building x'' then ''scheduled unit
a'' then ''12 times'' and we verify that it build 12 units and charged for 12."* That is what it
does, and it reads the answers out of the game''s own memory rather than out of our bookkeeping.

## It was proven by finding a real bug that we already knew about

The only honest way to show a bug-finder works is to point it at a build with a known bug and watch
it bite. Pointed at the commit BEFORE this week''s selection-array fix, seed 47:

| | teeth run (the broken build) | gate run (current main) |
|---|---|---|
| result | **FAIL 8 of 89** | **PASS 83 of 83** |
| what failed | 11 presses -> only 6 reached the engine; 1100 minerals due, 600 charged; queues capped at 5; the Train button vanished from the card | nothing |

That is your original complaint — *"can''t queue more than 5 units per building when multiple
buildings are selected"* — measured three independent ways at once, through two different input
paths (drag-box select and control-group recall). And it passes on today''s build.

## Two things it found out about ITSELF, which is why I trust it

1. It once reported **PASS 94 of 94 against the very build whose bug it was written to find.** Its
   own episodes had filled a building early, which kept every later burst below the engine''s
   5-slot limit — and below that limit a broken build and a correct one behave identically. It now
   COUNTS how many episodes actually reached the thing under test and prints that beside the
   verdict, with an explicit line saying a run that never got there cannot detect the bug whatever
   its verdict says.
2. It once printed **PASS 13 checks for a run that executed no test episodes at all** — an error
   unwound past the summary and the exit code was swallowed. A verdict that does not depend on
   finishing the work is not a verdict; it now says INCOMPLETE instead, and that guard has since
   caught three real aborts.

Both are written into the project rulebook as general rules, not as notes about this one harness.

The worker also caught two of its own failures being its own fault rather than the build''s, and
re-ran the whole comparison rather than publish a result with an asterisk. The version merged has
eight failures and every one of them belongs to the broken build.

## Where the rest stands

- **039** (your 5th-slot bug) now has the machine to itself for its last four runs, including the
  group-line before/after pictures.
- **049** just started: the sweep that produces the definitive list of which suites need to be
  visible on your screen and which do not.
