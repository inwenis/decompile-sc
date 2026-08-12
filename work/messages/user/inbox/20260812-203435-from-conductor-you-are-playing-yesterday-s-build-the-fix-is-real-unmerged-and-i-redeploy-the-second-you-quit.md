---
from: conductor
to: user
sent: 2026-08-12T20:34:35Z
subject: You are playing yesterday's build -- the fix is real, unmerged, and I redeploy the second you quit
---

Short version: **the bug you are looking at right now is real, and it is already fixed — you are
just not running the fixed build.** I proved that rather than assuming it. Details below, then
what I am doing about it, then your save/load question.

## 1. Why you still see "the 5 turns into a 2"

The plugin your game loaded at 21:27 is this file:

    C:\sc-deploy\starcraft-modded\plugin\scplugin.dll
    SHA-256 B646C6A6BAA212C742A4AEA7BEEB9092E75FE11127DCFB7D198F0AD5E2CEC416
    built  2026-08-12 02:37:20

That is **byte-identical** to the build in the main checkout, and the fix has never been on main —
it is on branch `task039-queue-indicator-corruption`, whose build is a different file entirely
(`96964B9F…`, built 10:15). The fix commit landed at **02:33**; that deploy ran at **02:37** but
built from main, four minutes too early and from the wrong tree.

So: nothing regressed, and the fix is not disproven. It was never in your hands.

Same answer for your other half — *"no indication of how many i queued"*. The "+N" overflow text is
the other half of the same PR. Measured on the defect build: **0 bytes drawn**. On the fixed build:
**33**. You are seeing exactly what the before-picture shows.

## 2. What I am doing now

1. PR #55 has the fix, is mergeable, and its one real regression gate — `test-production-queue` —
   finished with **0 failures** before the laptop went down. I am reviewing it and merging tonight.
2. GitHub Actions is still dead on the billing error (the job fails in 2 seconds with no steps), so
   the merge goes through on a local CI receipt, as you authorised.
3. **I will redeploy the moment you quit the game** — not before. `deploy.ps1` refuses while
   StarCraft is running, and I am not touching your machine while you play. When you are done,
   quit and I will have the fixed build in place within a minute or two. Then the fifth slot draws
   a proper icon with its slot number, and the queue count appears.

## 3. Your save/load question — honest answer: unknown, and I am not guessing

Nobody has ever tested it with the mods active. There are two save-test logs on disk from 08 Aug,
but both ran in `observe` mode — the plugin was reading memory and writing nothing. Your play build
runs `fanout` mode, which patches game memory in-process. Whether a save written under that comes
back correctly has never been checked.

That matters more than usual because the plugin fans out commands and rewrites parts of the
production queue, and a save file records unit and queue state. So it is a genuine open question,
not a formality. I have cut it as its own task and it will be tested properly — with your saves
untouched; the deploy already excludes `save\`, `characters\` and `Replays\` from every mirror.

## 4. About the laptop dying

It was Windows again, not us. It restarted at **09:39:49Z** this morning — the second restart of the
day; task 044 traced the 02:03Z one to Windows Update KB5121003. Nothing was lost: every worktree,
both open PRs and all the before/after pictures survived. No orphaned StarCraft, no stuck lock.

## 5. One thing I got wrong earlier

I asked you this morning whether to take your screen for three minutes tonight for the last
regression check. Skip that question — I have since routed it around: task 050 converts the six
suites that force a visible window so they stop needing one at all. You should not have to hand
over your monitor for a test again.
