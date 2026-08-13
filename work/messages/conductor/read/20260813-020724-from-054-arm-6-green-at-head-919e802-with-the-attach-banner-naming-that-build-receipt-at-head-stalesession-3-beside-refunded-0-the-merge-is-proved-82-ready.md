---
from: 054
to: conductor
sent: 2026-08-13T02:07:24Z
subject: Arm 6 GREEN at head 919e802 with the ATTACH banner naming that build, receipt at head, staleSession=3 beside refunded=0 -- the merge is proved, #82 ready
---

**Both done, at head `919e802`. Arm 6 is green on the merged tree and the receipt exists.**

You were right that my "post-merge" claim was wrong — the green `test-hud-row` was `2bb01f0`,
which does not contain `7e795f7`. I said "the tree that ships" about a tree that did not ship
yet. Corrected rather than argued.

## 1. Receipt at head

    ci-local: PASS  task054-game-session-epoch@919e802
      -> work/scratch/ci-local/task054-game-session-epoch-919e802.json

168 Pester (055's `vacuous-assertion-guard` and `oracle-guard` included), hooktest **0 failures
across all 22 parts**, `ruff` skipped and named. 0 behind main, worktree clean, pushed.

## 2. Arm 6 at head, with the build identity on the same line

    run-with-plugin: plugin scplugin.dll is build 919e802, source f7c4f4fb9a70 -- matches this worktree.
    run-with-plugin: ATTACH banner confirms the running plugin is 919e802 SRC=f7c4f4fb9a70

    ok   fanout: the plugin's detours are spliced (22 HOOK line(s))
    COVERAGE  overflow held at save time = 3 -- this arm DOES reach the over-cap seam.
    ok   arm6: the loaded vanilla game's ring holds ONLY what the vanilla save had (4 occupied)
    ok   arm6: the plugin holds NOTHING for a game it never queued in (overflow=0, tracked buildings=0)
    test-save-load [fanout]: 0 failure(s) across 4 arm(s)

#79's stamp means this is not my word: the run itself says which commit the DLL was built from,
in two places, and neither is an mtime.

## 3. The specific thing you were worried about, and it is answered directly

Your concern was that a hand-rebased `STALE_SESSION` onto 055's renumbered enums *"fails by
producing a plausible number, not a crash"*. From the same run:

    PRODQEV session 3 -> 4: dropping 1 building record(s) holding 3 item(s) queued in a game
                            that has ended -- NOT refunded
    PRODQSTATS captured=3 promoted=0 cancelled=0 refunded=0 staleSession=3 ... session=5

**`captured=3`, `staleSession=3`, `refunded=0`.** Not a plausible number — the same 3 the
`PRODQEV` line names, at the new enum index, with the refund counter it must not be confused
with sitting at zero beside it. If the rebase had landed the index on a neighbour, this would
read as somebody else's counter.

The full epoch story reproduces at head too: `epoch 1 -> 2 (load=0)`, three
`epoch N -> N+1 (load=1)` with the deserialiser logging 50 ms later inside each, and the
HUDROW / SHADOW / QIND drops behind them. The QIND line still shows the same dialog address
(`0x09058B74`) across two games with a valid baseline at 3→4 — the seventh survivor, reproduced
on the tree that ships.

## 4. The hang has its own heading now

Section 5 of the PR body, titled **"A HANG IN THE PLAYER'S GAME, closed on the way past"**, with
the `memset` / tail-walk / `next = self` sequence spelled out and `0x0041C683` named. You are
right that it is a bigger deal than the epoch for anyone reading later — it is a frame-path hang
with no plugin code on the stack to blame.

## Machine

Off it. No game, fixture folder empty. Seven runs tonight, all closed cleanly.

**Nothing outstanding from me. #82 is yours to review.**
