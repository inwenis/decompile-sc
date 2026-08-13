---
from: 054
to: conductor
sent: 2026-08-13T01:02:04Z
subject: PR #82 open, local CI PASS at 76c1c08, all six criteria met -- but hold the merge until one hud-row re-run answers a number I have not explained
---

**PR: https://github.com/inwenis/decompile-sc/pull/82** — task file's `pr:` line updated.

Local CI **PASS** at `76c1c08`, rebased onto #75 so the receipt carries 053's new fields:
`work/scratch/ci-local/task054-game-session-epoch-76c1c08.json` (95 Pester passed, hooktest 0
failures, 22 parts; `ruff` skipped and named).

## Acceptance criteria

| # | criterion | state |
|---|---|---|
| 1 | arm 6 FAIL→PASS, run and shown | met — the A/B, both runs tonight |
| 2 | all six #67 siblings adopted or a measured reason | met — all six adopted, plus a seventh |
| 3 | epoch bumps on BOTH a new game and a load, from a real run | met — `SESSION start ... (load=0)` and `(load=1)` |
| 4 | a test that fails without the epoch for a sibling other than `sc_prodqueue` | met — 23 failures across six modules with the epoch pinned |
| 5 | no per-frame cost in the run's own timing lines; say what was measured | met — and I say what I refuse to claim |
| 6 | `run-ci-local.ps1` PASS, PR opened | met |

## The seventh survivor, and it was measured

`sc_queueind` invalidates its dialog splice and its **screen baseline** only on
`root != g_dialog` — two heap addresses. The engine builds the same dialogs in the same order
every game, and my run caught it doing exactly that:

    QIND session 2 -> 3: forgetting dialog 0x08F48B74, the splice (0) and the box baseline (0)
    QIND session 3 -> 4: forgetting dialog 0x08F48B74, the splice (1) and the box baseline (1)

Same address across three games, and at 3→4 with a **valid baseline** behind it. Without the
epoch, `ScQueueIndBoxDiff` — the oracle task 039 built because an ink count cannot answer "did
OUR pixels land" — diffs this game's surface against another game's, and fails by producing a
**plausible number** rather than by reading zero. Nothing the player sees is wrong; it is an
oracle that can lie, which is the reason to fix it rather than a reason not to.

Your 1-of-4 measurement is in the PR with your framing — "not a hole I introduced",
`CMDACT_Select` and `unit_IsStandardAndMovable` named, and the point that
*"observe: NOT ONE hook is installed"* would have passed on main today with `CMDACT_Select`
spliced.

## One thing still open, and it is mine not yours

I still owe **one ~6 minute slot** for a `test-hud-row` re-run against the corrected hook
allowlist. Behind 055 is fine.

It carries one question I want answered rather than assumed. The two hud-row runs had identical
84.4 s spans and dispatcher counts 6.3x apart (34,969,699 vs 5,561,022). I have said in the PR
that this is a free-running busy loop measuring spare CPU and not a cost instrument, and the
direct measurement backs that — the whole mechanism is 2.25 ns/call, bounded at under 0.3% of
one core at the highest rate seen. **But I have not proved the 6.3x is machine load rather than
my change.** If the re-run comes back near 400k on a quiet box, it was load and the matter is
closed. If it comes back near 66k again, the number means something I have not explained and I
will chase it before asking you to merge.

So: PR is open and reviewable now, but do not merge until I confirm that re-run. I will message
you either way.
