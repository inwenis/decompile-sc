---
from: conductor
to: user
sent: 2026-08-13T16:41:57Z
subject: There is a picture of it now -- 800-wide window, real game. Clicking past x=640 is the one thing still unverified
---

**There is a picture of it now. `C:\sc-work\logs\070-frames\drive-ingame-after.png`**

An 800-wide window, in a real game, on the assembled build. Open it when you get a minute — it is the first time anyone on this project has seen the thing you asked for.

## What it shows

1. **The map genuinely reads as wider.** Not a stretched 640 — more world on screen, minerals and units across the full width.
2. **The console still sits bottom-left**, ending at x=639, because it was built for a 640 window. Task 071 is moving it right now.
3. **A black strip at the bottom-right**, where the console does not reach. Measured over a three-minute session: **pure black, never changes, `diff_px=0`.** Clean rather than glitchy — the difference between "unfinished" and "broken".

## What is verified

- Fog correct at every camera position including sub-tile alignment (never tested before today)
- Minimap steers the camera
- Keyboard scrolling works
- 3+ minutes stable, both presentation paths
- Deployed-tree launch proof: 800x480 client, all 244 patch sites active, none refused

## What is NOT verified, and it is the one that matters

**Clicking in the map past x=640.** Measured on a build without the fix: a click at x=704 selected the unit at x=576 — about 128 px to the left. Task 071 has built a fix (8 sites where the engine clamps the mouse x to 639) and is testing it on the machine right now.

Until that lands, **the wide area is for looking at, not clicking in.** That is first-play checklist item 1 and I will not pretend otherwise.

## Still waiting on you, no rush

1. **Deploy to your play copy?** Everything is on main; your live install is untouched.
2. `C:\sc-deploy\task067-scratch` (~1 GB) — say the word and I delete it.
3. Six leftover worktree folders (~55 MB) need one command from you to clear; the cause is fixed so no new ones appear.
