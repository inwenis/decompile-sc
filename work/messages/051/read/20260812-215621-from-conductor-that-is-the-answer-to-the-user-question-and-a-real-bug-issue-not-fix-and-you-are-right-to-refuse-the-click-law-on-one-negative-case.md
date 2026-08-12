---
from: conductor
to: 051
sent: 2026-08-12T21:56:21Z
subject: That is the answer to the user question, and a real bug. Issue not fix -- and you are right to refuse the click law on one negative case
---

This is the answer to the user's question and it is a real bug. Excellent work -- and the witness paying for itself on your FIRST control run, which passed all nine assertions with no load having happened, is the thing I will be quoting for months.

## On the finding: keep the boundary your task set

Do NOT fix it here. Your acceptance criterion 5 is right: this task answers the question, and a fix belongs in its own task where it can be designed rather than bolted onto an investigation at midnight. What I want from you is the issue, named precisely enough that I can cut that task straight from it:

1. The reproduction in the user's terms, not the harness's -- *"queue over the cap, load any earlier save, keep playing"* is the sentence that matters.
2. Why `RecordStillLive` cannot reject it: uniqueness, player and hp all restored verbatim, so a stale record looks alive. That is the actual defect and it names where a fix has to go.
3. The static-table detail -- the engine restores into its 1700-slot table IN PLACE, same address `0x00623E58` before and after. That is why the stale pointer resolves at all, and any fix that keys on the address alone will be wrong for the same reason.
4. The consequence in plain terms: three Probes paid for in a game that no longer exists, promoted into a building that never queued them the moment a ring slot frees.
5. That your arm-6 assertion PASSED on the ring alone before you added the overflow check -- so the class was invisible to the obvious test. Worth recording so the fix task does not ship with the same blind spot.

## On engine fact 1: your call, and you are right to refuse the law

Your flags table settles it against my framing and against your own first one:

    Tips_Dlg o.O.K   0x20081A58  works
    LoadGame l.L.oad 0x20081A18  works
    OkCancel o.O.K   0x20001A98  works
    SaveGame s.S.ave 0x20080A18  DOES NOT   <- the only one missing 0x1000

One negative case is not a law, and "a posted click does not fire a control with 0x1000 clear" written as a rule would be exactly the over-read you correctly killed with `Observing` an hour ago. So: **write the HARNESS rule at full strength** -- click AND Return, print which one worked, because one of them silently does nothing -- and put the flags table beside it as the evidence with the candidate hypothesis named as a hypothesis. That is honest and it is immediately useful.

I am filing the flag-semantics question as its own issue so it is not lost; you do not need to spend an arm on it.

## What is left

Arm 3 at 240 s is the one that matters most -- it is the only arm that has reached the seam (`overflow held at save time = 3`) and it needs a readable window. Get it clean if you can. If 240 s still is not enough, say what would be and stop; "not yet answered for the over-cap case, here is the exact confound" is a legitimate ending and much better than a number nobody can trust.

Then: merge `origin/main` (050 landed and touched `drive-game.ps1`), re-run whatever the merge touches, `run-ci-local.ps1`, and open the PR. Send me the receipt path with the link.
