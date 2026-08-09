---
from: conductor
to: user
sent: 2026-08-08T23:12:59Z
subject: bigger screen: queued as an investigation first - honest read on why this one is the hardest ask yet
---

Queued, and I want to set expectations before it starts, because this is a different order of difficulty from everything else on the list.

**What we already know from our own work:** 1.16.1 is built around a 640x480 screen, and that number is not incidental — it is baked into things we have already touched and documented. The HUD is a dialog of 44 controls positioned in 640x480 coordinates, loaded from a game asset. Our own circle-drawing code carries an on-screen bounds check against 640 and 480. The test suites click the minimap using 640x480 maths. Every one of those is a place that assumes the screen size.

**What "bigger like Remastered" could mean, cheapest to hardest:**

1. **A bigger WINDOW showing the same 640x480 image, scaled up.** We already ship the windowed helper that does something in this family. This is stretching, not more visible battlefield — probably not what you want, but it is nearly free and worth confirming you do or do not want it.
2. **More visible battlefield at a higher resolution.** This is the real ask, and it means changing what the engine renders: the viewport size, the tile-drawing loop, the HUD art and its layout, the minimap, and every piece of code that assumes 640x480 — including ours. Remastered achieved it by rewriting the renderer, with the original engine running underneath at its own scale.
3. **Somewhere in between** — e.g. a wider viewport with the stock HUD left alone. Whether that is possible at all is exactly what an investigation has to answer.

**So I am queuing it as an INVESTIGATION, not an implementation.** The deliverable is a map of how rendering and the viewport actually work in this binary, an honest verdict on which of the three above is achievable and at what cost, and a recommendation — the same two-stage shape as the HUD row task, where you saw the investigation pay for itself by finding the cheap route.

That is also the honest answer to "can we do it": I do not know yet, and anyone who tells you a number before mapping the renderer is guessing. What I can say is that our tooling for this is now good — we can drive the game, read its memory, generate test maps and capture frames unattended, which is exactly what a renderer investigation needs.

It goes after the queue I sent you. If you would rather pull it forward, say so — it is your game, and "I want a bigger screen" is a perfectly good reason to reorder.
