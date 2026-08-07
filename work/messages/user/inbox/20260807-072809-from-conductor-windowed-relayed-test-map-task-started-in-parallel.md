---
from: conductor
to: user
sent: 2026-08-07T07:28:09Z
subject: windowed relayed + test map task started in parallel
---

Both noted. Windowed-first is relayed to the worker, and the test map is now its own task running in parallel.

## On windowed mode

I gave the worker a hypothesis that might make it cheap. The windowed helper has no export table and imports `FindWindowA` — that is not the shape of a DirectDraw proxy, it is the shape of something meant to be INJECTED into a running process and to find the game window itself. Our own research noticed that detail last night and never followed it up. We already have a working injector, so testing it costs one run. If that fails, the fallback is a proper chain-loading proxy that forwards to the real system DirectDraw.

I told it to timebox this. The runtime verification is the actual deliverable; windowed mode must not swallow it.

## On the test map — task 009, running now

Generating a single-player map with 36-50 Marines clustered so one drag-box grabs the lot, on open terrain, no hostile pressure. Exactly what you need to select a big group, right-click, and see whether they all obey.

Two deliberate choices:
1. **The generator gets committed, not the map.** Maps are gitignored and CI blocks tracked game content, so the script is the artifact and the map is disposable output. It also means you can regenerate with a different unit count later — which matters, because a working-copy reset purges the Maps folder.
2. **It will NOT launch the game to test.** It validates structurally instead — parses the produced map back and asserts unit count, type, owner and start location. In-game loading happens inside task 008's windowed session, so we interrupt your screen ONCE instead of twice.

## Where rung 1 stands

Already working: toolchain pinned, plugin loads and runs inside the game, reaches the menu, relocation delta zero (so every address we mapped is usable verbatim). Remaining: windowed mode, then the live selection read.

Nothing needs you right now.
