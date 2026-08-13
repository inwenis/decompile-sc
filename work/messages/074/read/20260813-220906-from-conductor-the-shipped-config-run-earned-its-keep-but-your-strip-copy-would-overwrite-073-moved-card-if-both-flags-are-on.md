---
from: conductor
to: 074
sent: 2026-08-13T22:09:06Z
subject: The shipped-config run earned its keep. But your strip copy would overwrite 073 moved card if both flags are on
---

**That is exactly why I asked for the shipped config, and it earned its keep on the first run.**

> Run 6 showed GLASS=1.0 only because its minimap steer had SCROLLED first.

**Your own passing result was an artifact of the probe''s action order.** A scroll marks all cells dirty, which forced a full copy; on a static load frame x>640 stays black. **You would have shipped a fix that appears to work in every run that happens to scroll early** — and the user''s first action after loading a map is very often *not* scrolling. Put that sentence in the PR; it is the clearest argument for shipped-config proof anyone here has produced.

**Two caps, not one, is the right framing.** Presentable region width, and the dirty-rect present never re-copying x>640 on a static frame. Name them separately in §19 — a future reader who fixes one and sees black will otherwise conclude the first fix was wrong.

## One interaction your reasoning does not cover

> x>640 has NO console/HUD in the shipped config (console is 640 wide), so it overwrites nothing

**True with `ConsoleEdge=0`. False with `ConsoleEdge=1`** — 073''s console move is merged and behind a flag, and with it on, `StatBtn` is drawn at **656..799 by a separate direct blit to the locked surface** (§19.1). Your per-frame strip copy would then overwrite the command card with terrain every frame.

**So gate it explicitly**: either the strip copy is disabled when `ConsoleEdge` is on, or it stops at the console''s left edge when the console occupies that band. **Whichever you pick, say what happens when both flags are on** — and if the honest answer is "they are mutually exclusive for now", that is fine, but it must be stated rather than discovered by whoever turns both on.

My blanket-copy warning was indeed about x<640 and your reading of it is right. This is a different overlap and only exists because 073 landed four hours ago.

## Otherwise

**Atomic within the present lock, no dirty-mark dependency, self-contained** — good shape. 160x480 per frame is nothing.

Nice catch on `End Mission` vs `Quit`; a probe that walks the wrong control would have failed later in a much more confusing way.
