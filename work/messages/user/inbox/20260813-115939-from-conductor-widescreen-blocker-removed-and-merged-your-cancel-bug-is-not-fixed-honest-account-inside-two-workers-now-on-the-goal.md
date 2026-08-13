---
from: conductor
to: user
sent: 2026-08-13T11:59:39Z
subject: Widescreen blocker removed and merged; your cancel bug is NOT fixed (honest account inside); two workers now on the goal
---

**The widescreen blocker is gone, and one of your two bugs is not fixed. Both in detail below.**

## 1. We can now see the whole frame the game draws — merged

PR #94: https://github.com/inwenis/decompile-sc/pull/94

Task 034 gave up on widescreen last time because *"every frame this task has ever captured shows only the left 640 columns"*. That turned out to be a property of the camera, not the game. 063 read the engine''s own framebuffer instead of screenshotting the window, and captured an **800-wide in-game frame** — the extra 160 columns nobody had ever seen.

Why that matters to you: **the wide view is now developable and testable without ever touching your screen settings.** That was the whole thing standing in the way.

## 2. Two new workers, both aimed straight at your goal

| task | what it does | why it alone is not enough |
|---|---|---|
| **064** | make the engine DRAW map into the extra 160 columns | today they are blank |
| **065** | get more than 640 columns onto your monitor in a window | today `WMode.dll` crops them off |

You need both. They are running in parallel and neither waits on the other.

## 3. Your cancel bug is NOT fixed — and I would rather say so plainly

PR #95: https://github.com/inwenis/decompile-sc/pull/95 — **a diagnosis, not a fix.**

1. We know the mechanism: our own `+N` drawing makes the engine disable that slot, which destroys your click before the button-up can act on it.
2. The obvious fix — put the click back — was built, measured, and **it made things worse**: it left the button permanently held down. Reverted.
3. The real discovery: **this is a race, and every result this project has reported on it, including "we reproduced it", was a single coin flip.** The bug''s own test harness won the race sometimes and lost it others.
4. Your clicks are probably slower than the test harness''s 60ms, which would explain why it fails reliably for you and only sometimes for us. 061 is measuring that right now — clicks at 40/60/80/120/200ms.

Nothing shipped that changes what you see. The bug is still there.

## 4. Nothing needs you right now

The fullscreen question I was going to ask you has mostly answered itself: **your adapter has no 800x480 mode at all** (measured — 132 mode entries). So the fullscreen route was never going to give the wide view anyway, and the windowed route is the one that matters. No decision needed from you.
