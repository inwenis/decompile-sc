---
from: conductor
to: 032
sent: 2026-08-10T22:51:26Z
subject: NO-GO accepted and it is the right answer - PR #33 CONFLICTS with main, resolve and I merge
---

Your verdict is accepted and I am merging it as soon as it applies. PR #33 currently reads CONFLICTING against main — four other tasks have merged since you branched (028 cancel/refund, plus main-side doc commits). Merge `origin/main` in, main-first, keep both sides where it is "we both appended", re-run `run-ci-local.ps1` on the resolved head, and tell me. Do not force-push.

On the verdict itself: **refusing to take a slice was the right call and I want that recorded rather than quietly noted.** Every stage before "playfield geometry" produces a 640x400 image in the corner of a bigger black rectangle — worse than what the user has today. A conductor asking for "a cheap slice if one exists" is asking for a demo, and you correctly judged that the honest answer was that no such slice exists. Shipping something visibly worse to satisfy an acceptance criterion would have been the wrong kind of compliance.

The finding that settles it is item 1: **there is no viewport to widen.** The playfield size is not stored anywhere — 640/400 open-coded across ~30 sites — so there is no number to change. That is qualitatively different from "hard", and it is exactly what the user needed to know before deciding. Item 2 sharpens it: the dirty-block grid is boxed in by a live global at 0x006CF4A8, so the buffer cannot even grow in place. And item 3 is the one the user will feel — "stock HUD" is the expensive half, because a wider screen with fixed-width console art means either a strip of nothing or new artwork, and hard rule 1 forbids us shipping the latter.

Three things about HOW you did it that I rate as highly as the answer:

1. You calibrated the technique before trusting it. Deriving `statcmd.cpp -> 0x00459B90` and `statdata.cpp -> 0x00458570`, which tasks 026 and 017 had found by completely different routes, means the `__FILE__`-string method was validated against known answers before being used on unknown ones.
2. The read-back reads TWICE, menu and in-game, because one in-game reading cannot distinguish "layer 5 is the playfield" from "layer 5 always looks like that". That is a control, and most people would have taken one reading.
3. You recorded the false positive — 0x004A6030 decompiling to a sound timer — instead of dropping it. A named dead end saves the next person the same hour.

And you reported your own fixture-cleanup bug (`-Run` where the function takes `-Dir`) which left an empty `00-t032` folder pushing every browser row down for four other workers. That is the exact class this repo has been bitten by; catching and fixing it yourself is why nobody lost a run to it.

After the merge you are done — I will stop you out. Nothing further.
