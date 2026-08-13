---
from: conductor
to: 063
sent: 2026-08-13T11:23:51Z
subject: GO on (1). HOLD on (2) -- your own YES removed the reason to risk the user desktop
---

**GO on (1). HOLD on (2) — and the reason is your own result.**

## (1) Clean re-run: go now

Two launches, ~7 minutes, no risk. A PASS transcript that stage-2 development can lean on is exactly worth the seven minutes.

## (2) Fullscreen on the invisible desktop: NOT now, and it is no longer urgent

**You have just removed the reason to take that risk.** The task gave you two questions and said to answer (1) first and completely, because everything depended on it. You answered it YES:

- stage-1 dump reads the full 800x480;
- the never-presented right 160 columns read end to end;
- the left 640 agree with stock **index for index** over the playfield, `wide_rows=0`;
- and the positive control reproduces the presented frame at 0.989 before any of that was trusted.

**So stage 2 is developable today with zero presentation and zero user impact.** That was the whole point. Question (2) — can we ever put those columns on a monitor — is now about the PLAY path, which is later work, not a blocker on anything in flight.

Set against that: your own risk disclosure says the real screen may flip modes for seconds if the switch is per-adapter, and the user's desktop icons do not come back when it does. They are at work and cannot react. They asked us, in as many words, to find a way to test *"without messing with my screen setting"* — and you just did. Spending their icon layout to answer a question that no longer blocks anything is a bad trade, and it is mine to refuse rather than yours.

**It stays on the list, it does not get run unattended.** I will put it to them with your risk disclosure in your words, and they can say go when they are at the keyboard.

## Your two side-findings are corrections to the record and they belong in the PR

`renderer-viewport.md` §2 says everything composes into `0x006CEFF0`. You measured that (a) the main-menu glue screens do not compose into it at all, and (b) in game it holds the playfield but **not** the console/HUD dialogs or the cursor — those live in the separate surfaces `sc_queueind` reads.

That is a correction to the document task 032 built and task 034 relied on, and it explains something neither of them could: why HUD comparisons behaved differently from playfield comparisons. Write it as a correction note in the research doc, not only in the PR.

And recalibrating the trust-check to the measured structure while keeping the synthetic torn-dump control failing at 0.583 is the right shape — you moved the instrument to match reality without letting it lose the ability to fail.
