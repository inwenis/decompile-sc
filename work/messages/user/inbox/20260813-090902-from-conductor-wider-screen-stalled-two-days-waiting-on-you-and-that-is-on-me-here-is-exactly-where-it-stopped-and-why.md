---
from: conductor
to: user
sent: 2026-08-13T09:09:02Z
subject: Wider screen: stalled two days waiting on you, and that is on me. Here is exactly where it stopped and why
type: question
options: Option 3 -- stop here, it is written up (recommended); Option 4 -- cost a non-cropping windowing helper as a task; Option 1 -- give me the command, I will run fullscreen myself; Option 2 -- you run fullscreen, I accept the icon shuffle
---

**Honest answer: it has not progressed since 2026-08-11, because it is waiting on you — and I should have re-raised that rather than letting it sit for two days.**

I asked you a question about it at 10:46Z on the 11th and you never answered. That is not a complaint; a question that gets parked is the asker's problem to chase, and I did not.

## Where it actually stands

Task 034 executed the plan and **merged as a measured account, not a feature** (PR #43, 11 Aug). The result:

| stage | what it is | result |
| --- | --- | --- |
| 0 | display mode | **passes** |
| 1 | the framebuffer itself | **passes** — 800x480, picture indistinguishable from control |
| 2 | the playfield geometry | **fails** — reads back perfect, frame is wrecked. Bisected, left broken, reported |

The engine *can* compose a wider frame. The descriptor and every layer rect prove it: layer 5 sits at (0,0) 800x400 with its draw callback intact.

## The finding that reordered everything

**`WMode.dll` — the windowing helper your shortcut launches through — presents 640 columns whatever it is asked for.** Measured in two arms, 800x480 and 800x600: the window came back 650x517 both times, at every stage.

So **every frame this experiment has ever captured shows only the left 640 columns.** The extra 160 have never been seen by anything, in any run. Even a perfect stage 2 would put zero new pixels on your monitor through the current launcher.

That is why it stopped. The blocker was never *"can the engine draw it"*. It is *"can anything show it to you"*.

## The decision that is still open, restated

The only presentation route that displays 800 columns is **true fullscreen, no helper** — which switches your 3840x2160 desktop to a small mode while the game runs, and **Windows does not put your desktop icons back**. Stock StarCraft does this too, so it is not something we introduced, but it is your data and a worker correctly refused to do it unattended.

1. **You run it once yourself** — I hand you the exact command, nothing surprises you.
2. **You say go and I run it**, icons caveat accepted.
3. **We stop here.** Stages 0-1 are committed behind an off-by-default flag; nothing is lost.
4. **Find or write a windowing helper that does not crop.** Real option, but new work, not a tweak — and nobody has costed it.

My read has not changed: **option 3**, unless you actively want to see it. Even with fullscreen working you would be playing at 800x600 on a 4K monitor to gain 160 columns of map, and stage 2 still does not render.

But option 4 is the one I would revisit if you want this feature rather than the experiment — it is the only path that ends with you playing wider without giving up your desktop, and *"nobody has costed it"* is a gap I can close with a task rather than a guess.
