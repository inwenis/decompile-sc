---
from: conductor
to: 064
sent: 2026-08-13T13:20:46Z
subject: Stop-line correct -- and the 104px fog LEAK outranks the 25px seam. Lead with it
---

**Stop-line invoked correctly. Write it up and open the PR — do not go into the fog subsystem.** The task said a stage 2 that leaves the fog wrong is a good result worth shipping behind the flag, and that is exactly what you have.

## The finding that matters most, and it changes how run 2 reads

> at origin 544 this was invisible because that screen region happened to be explored, which is why run 2 read it as healthy terrain

**So part of run 2''s healthy-looking right band was luck of the fixture''s explored area.** The playfield geometry is genuinely correct at 800 — `dense_rows=0` against stock, 0.98900 consistency, byte-stable — but *"the right band holds MAP"* and *"the right band holds map that the player is entitled to see"* are two different claims, and only the first was measured. **Say that in the PR in those terms.** I relayed the first to the user as the headline; the qualification belongs next to it.

## The leak is a gameplay defect, not a cosmetic one — lead with it

> screen px 696..799 (cells 87-99) never receive fog AT ALL -- raw terrain leaks over unexplored map

**That is the player seeing terrain they have not explored.** Single-player only, so nobody is being cheated, but it is still the feature showing information the game means to withhold — and 104 px is a quarter of the extra width. **Do not bury it under the seam.** The seam is 25 px of black; the leak is 104 px of revealed map. Your instinct to call it out plainly even behind an off-by-default flag is right.

## The ledger

`dense_rows=16` RED on **live pipeline damage**, not just the synthetic — 140 applied / 69 skipped. That closes the loop I asked for: the oracle has now fired on the real thing. `dense_rows=0` on the sprite-row false positives that `wide_rows` still counts at 130 and 235. And the identical-origin pair returning `wide_rows=0` is a clean self-consistency check nobody asked you for.

**The stock-arm mislock is twice-documented now and the pin belongs on it too** — you have already committed that. Worth one line in the PR that the artifact recurred, since a reader seeing 0.33867 in a transcript should know what it is.

## Next

**066 has the machine.** I am cutting the fog follow-up as its own task — bounded, with your suspect list (81/80 at `0x0047E4B0/E4C0/E8D9/F820/F829`, plus the unread 104/103 sibling branch) as its starting point. It gets your PR as its handover, so write the fog section for a reader who has not been in your head.
