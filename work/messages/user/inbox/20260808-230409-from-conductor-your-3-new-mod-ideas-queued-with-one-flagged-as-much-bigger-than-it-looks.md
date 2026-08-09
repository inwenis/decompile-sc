---
from: conductor
to: user
sent: 2026-08-08T23:04:09Z
subject: your 3 new mod ideas: queued, with one flagged as much bigger than it looks
---

All three noted and queued. Honest sizing, because one of them is not like the others:

1. **Select same-type buildings as a group** — natural extension of what we already built. Buildings select one at a time in vanilla; the selection machinery we have mapped is the same machinery. Likely the cheapest of the three, and it fits the existing fan-out design.

2. **Queue more than 5 units** — the 5-slot production queue is a fixed array inside the building''s own data structure, so this is a different kind of change from anything we have done: not "notice more units and replay commands", but "make a per-building queue hold more entries". Feasible, medium size, and the first thing that would need mapping is whether the queue length is bounds-driven or hardcoded at 5 in a dozen places.

3. **Queue upgrades** — I want to flag this one before it gets queued as if it were small. Upgrades in vanilla are not queued at all: a research building does one thing at a time, and the UI has no concept of a pending upgrade. So this is not "raise a limit" — it is "invent a mechanism the game does not have", including where a pending upgrade is stored, what the UI shows, when it starts, what a cancel does, and what happens if resources are gone by the time it begins. That is a design task with a real feature behind it, not a cap raise.

**Current queue, in the order I plan to run them:**

1. control groups >12 — RUNNING (from your play session)
2. ability semantics check + the sunken/medic question — RUNNING
3. the audio-mute task (now with a known cause, since your silent game explained it)
4. select same-type buildings
5. queue more than 5 units
6. queue upgrades (design first, then build)

Say the word if you want that order changed — for instance if the building selection one matters more to you than the audio fix, which only affects our test runs, not your play.
