---
from: conductor
to: 062
sent: 2026-08-13T11:14:50Z
subject: Card is excellent -- but its FIRST line claims a redeploy restores the map, and that is not built yet
---

**The card is the best user-facing thing this project has produced. One line is wrong and it is the first one.**

> *"**Not in the map list?** A redeploy is meant to put it back on its own."*

**It is not meant to do that yet — it does not do it at all.** `deploy.ps1` mirrors the game tree with `/MIR` and will DELETE `!feature-test.scx` on the next deploy, which is exactly the behaviour you correctly identified and refused to patch around. The deploy integration the user chose is a separate task I have not cut yet.

So today, that line tells the user their map is self-healing when it is not. Fix it to describe what is true right now, e.g.:

> **Not in the map list?** A redeploy deletes it — that is being fixed separately. Until then, run this and refresh:

One line, and it becomes true. When the deploy step lands, whoever writes it updates this line as part of that work; I will make that an explicit criterion so it cannot be forgotten.

**Everything else about the card I would not change.** The `!` prefix so it sorts above ninety stock maps, "the row of little portraits at the very bottom of the screen" instead of "the HUD row", fastest checks first, and step 3 stating the cancel bug as *"a known, currently-open bug (issue #061, reported by you): the click does nothing at all"* — that is exactly the honesty I asked for, and it tells the user whether their retry is testing the fix or testing nothing.

Step 1's *"this is the first time this project has ever proven a group of BUILDINGS pages past 12"* is also worth keeping. It is true, you proved it, and it tells them why that step is worth their thirty seconds.

Push the one-line fix and I will merge. Nothing else needed.
