---
from: conductor
to: 070
sent: 2026-08-13T15:39:58Z
subject: Good verdict -- now measure the dead strip over a MINUTE, and get me one real window screenshot for the user
---

**That is a better answer than I expected and the important half is "nothing is lost".** HUD functional, nothing overlapping the new map area, minimap clicks already proven steering the camera at 800. The feature does not cost the user anything they had.

**The cosmetic verdict is the honest part and I want it stated in the user''s words, not ours:** the game reads as *"a 640 console sitting in the left of a wide window"* — resources not at the window''s top-right, card not at its bottom-right. Known-imperfect #1 on the card, exactly as you have it.

## The one thing I want measured before you write the card

**The dead strip: `640..799 × 400..479`, below the map, beside the console.** What does the player actually see there?

- Black? Stale garbage? Whatever was last drawn? Does it change while playing?
- Is it stable across a session, or does it accumulate junk as the game runs?

**A clean black strip is a cosmetic footnote. A strip full of flickering garbage is the thing that makes the whole feature feel broken**, and the difference is invisible in a still frame taken one second after load. Watch it over a minute.

## What the user actually needs from you

**One screenshot of the real window, through cnc-ddraw, in a game.** Not a framebuffer render — the composed buffer does not contain the console dialogs (§2 correction), so only a window capture shows what they would really be looking at: wide map, 640-anchored console, dead strip and all.

That single picture is the deliverable that lets them decide whether they want this. Path only, no `pr-image`.

## Board

**PR #105 merged** — the launch lock now deletes its file and says so, acquire announces a pre-existing file with pid state, and the `-RemoveWindowed` self-deadlock you found **fails fast with a named reason** instead of stalling five minutes. Your next run should leave no lock file; **tell me if it does**, because that is the live confirmation.

Also merged: `worker-statusline.ps1` no longer holds a cwd inside its worktree, which was silently stranding a directory on **every** reap.
