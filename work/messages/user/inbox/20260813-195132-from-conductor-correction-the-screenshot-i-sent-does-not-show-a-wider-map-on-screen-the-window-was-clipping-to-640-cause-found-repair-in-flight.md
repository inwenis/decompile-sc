---
from: conductor
to: user
sent: 2026-08-13T19:51:32Z
subject: Correction: the screenshot I sent does NOT show a wider map on screen -- the window was clipping to 640. Cause found, repair in flight
---

**Correction, and it matters before you try it: I told you the screenshot showed the map filling the full width. It does not.**

I said of `drive-ingame-after.png`: *"The map genuinely reads as wider. Not a stretched 640 — more world on screen, minerals and units across the full width."*

**I re-opened it. The terrain ends at x≈648 and everything right of that is black, top to bottom.** I read that black band as unexplored fog, because a later capture from a different task genuinely was fog and I had that answer in my head. It was not fog.

## What is actually true

1. **The game really does draw 800 columns of map.** That part is measured and merged — the extra columns exist in the engine's framebuffer, correctly fogged, at every camera position.
2. **But the window has been showing only 640 of them.** Task 073 measured it directly this evening: the buffer holds the content at x≈748-782, the glass at those coordinates is black.
3. **Cause found**: the present path clips against a region built from a list that has exactly one entry — the console art, `(0,0,640,480)`. Nothing ever told it the screen got wider. Menus and dialogs escape it because they draw by a different route, which is why the menus and the moved command card looked right.
4. **Every earlier task measured the framebuffer, and the framebuffer was genuinely correct.** Only two captures ever looked at the actual window, and I misread both.

## Where that leaves it

073 is testing a repair right now — one extra entry in that list, added through the engine's own function. If it works, the map you see gets wider for the first time; if it does not, you would have launched the (Wide) shortcut and seen a black band on the right.

**Nothing is broken that was not already broken** — this has been true since the wide build was first assembled, and no shipped behaviour changed. What changed is that we now know.

**Do not try the (Wide) shortcut until I tell you 073's repair landed.** You would see the black band and reasonably conclude the whole thing does not work.

Everything else in my last message stands: fog correct, minimap and keyboard scrolling working, the console still 640-anchored, and clicking past x=640 still unverified.
