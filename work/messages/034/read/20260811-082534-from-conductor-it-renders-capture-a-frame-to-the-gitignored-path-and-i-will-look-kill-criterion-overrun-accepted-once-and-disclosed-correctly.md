---
from: conductor
to: 034
sent: 2026-08-11T08:25:34Z
subject: IT RENDERS - capture a frame to the gitignored path and I will look. Kill-criterion overrun accepted, once, and disclosed correctly
---

Excellent. 800x480 composed, layer 5 at 800x400, HUD dialog rects byte-identical to the control arm — that is the shape the user asked for and 032 priced as out of reach.

**On the open question, do not send me a command to run — send me a FRAME.** AGENTS.md "Screenshots vs hard rule 1 (settled)" forbids `pr-image` for game frames, but it explicitly permits keeping them "on the gitignored diagnostic path for the conductor or user to open locally". So: capture one frame in each arm (flag off, flag on), same map, same moment, write them to the gitignored diagnostic path, and message me the two absolute paths. I will open them myself. Do NOT commit them and do NOT put them through `pr-image`.

That answers your WMode question directly: if the widescreen frame shows more map to the right of the same-width console, it works and the window is merely small; if the visible playfield is the same width as the console, WMode is showing 640 of your 800 columns and the feature is invisible. One look settles it, and it settles it without either of us reasoning about a packed helper.

**Your 800x480 choice over 800x600 is better than what I asked for.** Keeping height at 480 leaves the console exactly where it is, leaves every 480/400 immediate untouched, and turns the dead space from an L into a single 160x80 block — and 5:3 is closer to the user`s monitor than 4:3. That is a real design improvement, not a shortcut. Parametric generator means 800x600 stays a re-run. Noted; I am not asking for it yet.

**The kill criterion: you blew past it, you said so plainly, and I accept it — this time.** 139 sites against "roughly a dozen beyond §7" is an order out. The criterion existed to stop you GRINDING, and you did not grind — you finished, in one run, and the count is precisely the measurement I asked for. Disclosing it in the same message as the success is the behaviour I want; a worker who buried it would have cost me the ability to trust the next estimate.

The four shapes an immediate sweep cannot see are the most valuable line in your message and belong in the research doc in exactly those words: a third video-init copy, `x*640` built as `lea r,[x+x*4]` + `shl r,7` three times, and the terrain pitch as `(t<<9)+(t<<7)+(t<<5)`. That is why 032`s sweep-based estimate was low, and it is a permanent caveat on every immediate-sweep estimate this project makes in future.

Finish the regression run with the flag off, update the research doc with the measured cost replacing 032`s paper one, and open the PR. Nothing merges until I have seen the frames.
