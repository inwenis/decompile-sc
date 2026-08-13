---
from: conductor
to: user
sent: 2026-08-13T08:30:20Z
subject: Confirmed both -- cutting the cancel bug and the test map as tasks. Nothing will launch while you play
---

Good — that is the first time either of those has been confirmed by a human rather than by an oracle I wrote. Thank you for actually clicking them.

## The cancel bug: I believe you, and it is ours

*"I can cancel a queue unit by clicking it, but it doesn't work if I click the last slot when it has our extra +x text."*

That is almost certainly a side effect of task 039's fix — the thing that made the fifth slot draw properly is the same thing now sitting where your click lands. Two candidates, and neither is a guess I want to ship: either our spliced control is swallowing the click before the engine's own hit-test sees it, or the slot's meaning changed under the cancel path so it maps to nothing.

**Do not work around it** — I would rather the worker sees exactly what you see. Cutting it as a task now.

There is a rule in our own AGENTS.md written by task 039 itself: *"a card slot changes meaning under you — re-read before every click."* It was about the drawing side. It appears to apply to the clicking side too, which nobody checked.

## The test map: yes, and it is a better idea than it looks

A map where you can exercise every feature in a minute is worth more than another automated suite, because you keep finding things the suites cannot. Cutting that as its own task.

One constraint it has to respect: hard rule 1 means the map file itself never goes in the repo. The repo already has fixture generators, so the deliverable is **a generator plus a one-page card** telling you what to click and what should happen — and the map lands somewhere you can load it, not in git.

I will ask you what you want on it once someone has scoped it, rather than guessing: over-cap queues, a >12 selection for the paging row, multiple buildings selected, upgrades, and a save to reload are the obvious candidates.

## While you play

Nothing of mine will launch StarCraft — it is single-instance and I am not taking it out from under you. Both tasks will do their reading and code work first and wait for my go before touching the machine. **Tell me when you are done playing** and I will let them in.
