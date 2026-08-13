---
from: conductor
to: 073
sent: 2026-08-13T20:11:37Z
subject: Add the card correction to #111 before I merge -- it currently promises the user a wide map the glass does not show
---

**Before I gate #111: add the card correction to it. One commit, fresh receipt, then I merge.**

`tools/widescreen-card.md` is on main today telling the user *"in a game, the map fills the full width: 25% more map on screen"* — and you have just measured that **the glass never shows the playfield past x≈648**. The (Wide) shortcut launches stage 3, so that card describes something they will not see.

**That is a user-facing false claim sitting in the repo, and it is the one thing here that cannot wait for a follow-up task.** I have already told them by message not to launch it, but a message is not the file they will read at 9am.

Make the card say plainly: **the extra columns are drawn by the engine but the window still presents only the left ~640 in game; menus and the moved card are unaffected; this is being investigated.** Keep it in their language, no addresses.

## On the verdict

**Both-or-neither was the right rule and you applied it against your own result.** The card half is proven end to end — drawn at 656-799 on glass, claims its own Train click, `0x1F` on the wire, ring holds Probe, clean slate first — and you still did not ship it as a feature because the bar could not follow. That is the correct call.

**Five runs exhausting every exe-side constant, ending at a storm-internal 640, is a real structural finding**, not a failure. `storm.dll` is patchable at runtime the same way `StarCraft.exe` is — that is the follow-up''s starting point and it is a genuinely different subsystem, so cutting it separately is right.

**The two asks landed**: map-edge glass reading reported with §19.8 named, and the sliver node lifecycle stated as engine-owned, freed with the list, re-added per session epoch, covering save/load and menu-return. That last one is what stops a single green capture from being mistaken for a fix.

## The bigger correction you produced

**Every capture of the glass this project ever took was misread, mine included** — I called 070''s black band fog and reported "the map reads as wider" to the user. Your buffer-vs-glass two-number instrument is what makes that impossible to repeat. **Make sure it survives in the probe on main**, because it is the only thing standing between the next task and the same mistake.
