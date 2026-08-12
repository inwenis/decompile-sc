---
from: conductor
to: user
sent: 2026-08-11T10:46:39Z
subject: wider screen: the blocker is not what we thought, and there is a decision only you can make
---

# The real blocker turns out to be presentation, not the engine

Progress since my last note: the corruption I showed you is **fixed for the first two stages**, and the causes were all one family of mistake — arithmetic that encodes the old screen width without ever containing the number. The last one was hiding in a routine that is HANDED its buffer, so it never mentions it: fourteen offsets, of which exactly one spells 640, sitting over a thousand bytes from anything that names the screen.

Stage 3 (the playfield geometry itself) still renders wrong. The worker hit the stop-line I gave it — two failed fix attempts — and stopped to report rather than grind. That was the right call and I have told it to do one cheap 20-minute experiment to narrow down which group of ~120 changes is responsible, then stop regardless.

# But here is the thing that actually decides this

**Every frame this experiment has ever captured shows only the left 640 columns.** The windowing helper we launch through crops to 640 and always has. So even if the playfield rendered perfectly at 800 wide, **not one new pixel would reach your monitor through the current shortcut.** The extra columns have never been seen by anything, in any run.

So the blocker was never "can the engine draw a wider picture" — it can, that part works. It is "can anything show it to you".

# The decision, and it is yours because it touches your machine

The only presentation route that could actually display 800 columns is **true fullscreen** — the game`s own display mode, no helper. That means switching your 3840x2160 desktop to 800x600 while it runs.

**That rearranges your desktop icons, and Windows does not put them back.** The game does this in an ordinary stock fullscreen launch too, so it is not something we introduced — but it is your data, and a worker correctly refused to do it unattended.

Three ways forward, your pick:

1. **You run it yourself once**, so nothing surprises you, and tell me what you see. I will hand you the exact command.
2. **You say go and I run it** — with the honest caveat about the icons.
3. **We stop here.** Stages 0-1 are green and committed behind an off-by-default flag; the whole thing is written up as a measured account rather than an estimate. Nothing is lost if we return to it.

There is a fourth possibility I have not costed: finding or writing a different windowing helper that does not crop. That is a real option but it is a new piece of work, not a tweak.

My honest read: option 3 unless you actively want to see it, because even with fullscreen working you would be playing at 800x600 on a 4K monitor to gain 160 columns of map — and I do not yet know whether stage 3 can be made to render at all.
