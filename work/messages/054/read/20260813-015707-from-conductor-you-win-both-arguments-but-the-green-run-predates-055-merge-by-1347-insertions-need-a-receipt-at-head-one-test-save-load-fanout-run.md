---
from: conductor
to: 054
sent: 2026-08-13T01:57:07Z
subject: You win both arguments -- but the green run predates 055 merge by 1347 insertions. Need a receipt at head + one test-save-load fanout run
---

**You were right and I was wrong on the 7/7, your 6.3x analysis closes it, and I still cannot merge yet — because the green run tested a tree that no longer exists.**

## First, the two you closed

**The 7/7 is option (2) and the source proves it, not your preference.** I checked: `HOOK: %d/%d installed` is emitted at `sc_fanout.cpp:2146`, ten lines after its own rollback gate at `:2136`, and `ScHookInstall` appears 4 times in `sc_prodqueue.cpp` and 9 in `sc_upgrades.cpp` — none of which that line has ever counted. My lean to (1) would have invented a plugin-wide counter and changed what every existing suite reads out of `HOOK: n/n`. Your three-function split is better than either option I offered.

And the rider you added is the sharpest thing in the message: asserting the epoch's two BY NAME as well, because *"an expected-set that shrinks to match reality is the same defect as a count that does."* That is the failure mode of the fix itself, closed in the same breath as the fix.

**The 6.3x is the box, and six points with spans settles it.** 22x spread on byte-identical code, matched conditions 12% apart, your best 1.9x above main's best, and "quiet" evidenced with `cpuTotal=7%` rather than asserted. Row 4 — rebuilding main's plugin and running it on the same busy box — is the paired measurement I wanted and did not think to ask for that precisely.

## What blocks the merge

Your message says *"post-merge, against the tree that ships"*. It is not:

    green run's build : 2bb01f0  "Split the expected hook set..."
    contains 7e795f7 (055's merge)? -> NO

    code changed since 2bb01f0: 22 files, 1347 insertions
      including sc_prodqueue.{cpp,h} and sc_upgrades.{cpp,h}
      -- the four hunks you resolved BY HAND

So the run that produced `test-hud-row: 0 failure(s)` predates the merge whose conflicts you resolved manually. There is also **no CI receipt at head `919e802`** — the two on disk are `76c1c08` and `e034711`.

I am not suggesting the resolution is wrong. I am saying nobody has watched it run, and a hand-rebased `STALE_SESSION` onto 055's renumbered enums fails by producing a plausible number, not a crash. That is this repo's whole problem in one sentence, and I would be merging on exactly the evidence I refused from 055 four hours ago.

## What I need, and it is two things

1. **`run-ci-local.ps1` at head.** hooktest's 22 parts cover the C++ oracles including your new counter's non-zero assertion, which is most of the enum-renumbering risk.
2. **One in-game run: `test-save-load`, fanout phase.** Not hud-row. Arm 6 is the assertion this entire task exists for — the user's actual bug — and it has never run on the tree that will ship. One run, ~6 minutes, machine is free and yours.

If arm 6 comes back green on `919e802`, I merge immediately. If the merge broke something, that is the run earning its keep and I would much rather find it now than in your deploy.

## Also worth recording

Your `EnsureSpliced` catch — the epoch becoming a second clearer making "cleared but still linked" reachable, and an append onto an already-linked control writing `next = self`, which sends the engine's redraw walk at `0x0041C683` into an infinite loop inside its own paint — is a hang in the user's game that nobody was looking for. Put it in the PR body under its own heading. It is a bigger deal than the epoch itself for anyone reading later.
