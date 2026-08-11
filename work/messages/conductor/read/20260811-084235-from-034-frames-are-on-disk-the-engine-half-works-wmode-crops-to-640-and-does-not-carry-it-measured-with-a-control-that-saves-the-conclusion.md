---
from: 034
to: conductor
sent: 2026-08-11T08:42:35Z
subject: Frames are on disk. The engine half works; WMode CROPS to 640 and does not carry it — measured, with a control that saves the conclusion
---

**The two frames you asked for** (stage 2, same fixture map, same moment, gitignored diagnostic path, not committed, not through pr-image):

- `C:\sc-work\logs\034-frames\s2-widescreen-ingame.png`
- `C:\sc-work\logs\034-frames\s2-control-ingame.png`

Both are 640x480 client captures. Please still open them — but I can tell you what you will see, because I measured it structurally rather than looking:

**Verdict: CROP. WMode presents columns 0..639 of the 800-wide frame at 1:1.**

Evidence, no artwork reproduced, only counts:

| measurement | result | what it rules out |
| --- | --- | --- |
| client area, both arms | 640x480 | the helper does not FOLLOW the mode |
| HUD band y400..479 sampled, ws vs control | **98.9% identical pixels** | not SCALE — a 0.8x squeeze would move every HUD pixel |
| top strip y0..19 | **100% identical** | same |
| rightmost non-black column, both arms | x=639 of 640 (100%) | no black margin, so nothing was letterboxed |

So the extra 160 columns are composed into the framebuffer and thrown away at the blit. The feature is real in the engine and invisible on screen through this helper.

**A control saved me from a wrong conclusion, twice.** I also tried the other vector — WMode copied in as `ddraw.dll`, the research/launch-baseline.md recipe — and got a **"Direct Draw Error" modal box**. My first read was "the patch broke it". It did not: the **control arm (widescreen OFF, stock 640x480) throws the identical error**. That vector is simply not working on this machine today, in either arm, and says nothing about widescreen. I would have reported it as a widescreen failure without the second arm.

**And 800x600 is not the answer either.** I regenerated the whole table at 800x600 (the generator is parametric; it took one command) and re-ran. Same result: client 640x480, 95.3% identical, CROP. So it is not "the mode is non-standard" — the injected WMode presents 640x480 whatever it is asked for.

**The one presentation path left untested, and why I did not test it.** True fullscreen, no helper at all — the game's own `SetDisplayMode(800,600,8)`. It is the only route that could actually put 800 columns on the monitor. I stopped rather than run it unattended: it switches the user`s 3840x2160 desktop to 800x600, and a 4K -> 800x600 switch **rearranges desktop icons**, which is live user state and does not come back when the mode does (hard rule 5). launch-baseline measured a stock fullscreen launch switching the desktop, so the game does this normally — but that is the user`s call to make knowingly, not mine to make while they are at the machine. Say the word and I will run it, or hand them the command.

**Where that leaves the deliverable.** Stages 0-2 are complete and green (17/17, 126 rewrites, 0 refused, `test-widescreen.ps1 -Stage 2`). The blocker is not in the engine, not in the patch set, and not fixable from the plugin — it is a packed third-party DLL that presents 640x480. That answers research/renderer-viewport.md 10 item 2, which is the thing 032 left open.

Doing now: research doc update, report, PR. `run-ci-local.ps1` already passes (61 Pester, hooktest, game-content guard) on this branch.
