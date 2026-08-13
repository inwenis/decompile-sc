---
from: 066
to: conductor
sent: 2026-08-13T14:30:57Z
subject: OFF the machine. PR #102 open, both suite modes green, 84/84 across three sweeps vs 0/18 pre-fix
---

**OFF the machine.** No game running, lock free, fixtures cleaned. 068 can have it.

**PR: https://github.com/inwenis/decompile-sc/pull/102** -- local receipt `task066-queue-slot-cancel-fix@87dcb33` (hooktest 0 failures, 243 Pester green; cloud CI down on billing, noted in the body). Branched from origin/main at 326d48b (065's merge included); I could not write the main-checkout task file from this isolated session, so the `pr:` link is committed on the branch AND in this message.

**The table (run 5, suite exit 0, 0 failures, 0 skipped):**

```
RATE holdMs=40  clicks=6 cancelled=6 pct=100 collided=0
RATE holdMs=60  clicks=6 cancelled=6 pct=100 collided=0
RATE holdMs=80  clicks=6 cancelled=6 pct=100 collided=0
RATE holdMs=120 clicks=5 cancelled=5 pct=100 collided=0
RATE holdMs=200 clicks=6 cancelled=6 pct=100 collided=0
```

Quoted with its runs, never as a property of the system: three sweeps, two plugin builds with identical bracket mechanics, **84 of 84 clicked cancels, zero collisions** (run 1: 27/27; run 4b: 28/28; run 5: 29/29). Pre-fix baseline: 0/18 above 60ms, one collision per click, deterministic. Run 3 = full regression suite, 0 failures, 0 skipped, with the flipped arm (`phantom` moved, `disableOnOwned` +0) and the thread step (six game sites one tid, observer distinct) green.

Since your last read: run 4b failed 2 assertions on a SECOND consumer of a `ringStable=0` line (Get-ProdQueue had not been taught what Get-QInd had just learned) -- your reusable rule is now enforced in all three readers (Get-QInd, Get-ProdQueue, shared Get-ScStatusQueue) and recorded in research 8.8. The deeper mechanism is sharper than preemption: the retry loop's ns-scale polls are not independent samples against a us-scale window, so a loop starting inside one can exhaust every attempt -- filed as #101 with the spin refinement, deferred per the happy-path discipline because the failure mode is bounded and visible (run 5's transcript shows a dozen flagged reads re-asked, zero consumed).

Everything you asked for is in the PR body: per-failure accounting for all fifteen across six runs (fixed-vs-fitted addressed head-on), the two-halves detection correction in your words, the flagged-line rule in general terms, defect 2 marked pre-existing with the overflow=0 proof, the WM_CLOSE-on-a-destroyed-desktop detail, and the issue #92 line for the killed run.

Frames for the user (paths only, hard rule 1): `C:\sc-work\logs\066-frames\` -- `last-slot-before-cancel.png` / `last-slot-cancelled.png` plus the fifth-icon pair.
