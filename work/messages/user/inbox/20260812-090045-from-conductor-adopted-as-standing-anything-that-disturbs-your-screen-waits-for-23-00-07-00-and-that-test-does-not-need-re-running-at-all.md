---
from: conductor
to: user
sent: 2026-08-12T09:00:45Z
subject: Adopted as standing: anything that disturbs your screen waits for 23:00-07:00 -- and that test does not need re-running at all
---

Good rule — adopted as standing. Two parts to the answer.

## 1. That specific test does not need to run again at all

The 50x loop was reproducing a race we already have fully diagnosed from 039''s evidence. I told
045 to stop chasing the reproduction and prove the FIX instead, which takes a handful of controlled
spawns rather than a hundred. And once the `DETACHED_PROCESS` change lands, those spawns create no
console at all — so there is nothing left to be annoyed by, night or day. Nothing is being deferred
because nothing disruptive remains queued.

## 2. Your rule is now the rule anyway

**Anything that disturbs your screen waits for the night window: 23:00-07:00 your time.** That
covers process-spawning loops, anything that must run `-Visible`, and any long stress run. During
the day a worker either runs it invisibly or asks me and I schedule it. I have told all four
workers.

The one thing I will still interrupt you with during the day: a single `-Visible` run when a suite
genuinely needs the game-type dropdown, which cannot work off-screen. Those are ~3 minutes and rare
— task 045 is producing the list of which suites actually need it. If you would rather those wait
for the night too, say so and they will.

## 3. Board, briefly

- **PR #55** (039 — your 5th-slot bug) is open. The Command Center and Barracks halves are proven
  in both arms with pictures; the group-line half is marked NOT YET PROVEN in the body, in those
  words, because its two attempts failed for a real reason. It will not read as done until it is.
- **PR #54** (041 — randomized testing) is pre-reviewed and one measurement away.
- 047 has the machine for a short run right now; 041 and 039 are next in that order.
