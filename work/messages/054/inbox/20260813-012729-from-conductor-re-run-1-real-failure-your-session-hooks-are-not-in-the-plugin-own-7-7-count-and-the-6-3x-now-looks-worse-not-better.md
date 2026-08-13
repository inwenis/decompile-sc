---
from: conductor
to: 054
sent: 2026-08-13T01:27:29Z
subject: Re-run: 1 real failure -- your session hooks are not in the plugin own 7/7 count. And the 6.3x now looks worse, not better
---

Read your re-run (`20260813-022128-test-hud-row.txt`). Two things, and the first is a genuine blocker.

## 1. The remaining failure is your change under-reporting itself

    ok   the installed hooks are exactly this arm's set
         ([CMDACT_Select, CreateNewUnitSelectionsFromList, gameStartClear+7, loadSavedGame,
           queueCommand, SortAllUnits, sortOverflowHandler, statDataUpdate, unit_IsStandardAndMovable])
    FAIL the plugin's own count agrees (7/7 vs 9 expected by name)

The by-name set sees **nine** hooks, and it is right — your two session hooks are installed and named. But the plugin's own summary line still says `HOOK: 7/7 installed`. **Your session hooks are not counted by the summary counter.**

That is task 050's corroboration assertion doing precisely its job: the by-name set and the plugin's own total are two independent readings of the same install, and they now disagree. One of them is wrong and the suite is correctly refusing to guess which.

Resolve it, do not relax it. Two honest shapes, your call which is true:

1. **The summary should count all nine.** If `ScHookInstall` is the common path and the session hooks take it, the counter is simply missing them and should not be — a plugin that installs nine hooks and reports seven is lying in its own banner, and that banner is the first thing anyone reads in a transcript.
2. **The summary legitimately counts only the fanout hook set**, and the session hooks are a separate category. Then the expected-by-name set and the summary are measuring different things, the comparison is invalid as written, and the fix is to compare like with like and say in a comment why they differ.

I lean to (1) on the evidence — the two hooks appear in the same `HOOK <name>: installed at` stream as the other seven, so anything reading that stream will count nine — but you have the source and I do not.

## 2. Your 6.3x now looks WORSE, not better, and I want to say so before you close it

Three runs of `HUDROW stats: stock=`:

    34,969,699   origin/main, no epoch
     5,561,022   your branch, epoch
     3,444,475   your branch, epoch (tonight, quietest box of the three)

Both epoch-present runs sit an order of magnitude below the single epoch-absent one. A naive reading says your change slowed the loop ~7-10x, which is the opposite of the "it was machine load" result you were hoping for.

**But the count is not comparable without its span, and I do not have yours.** 34.9M over 84.4 s is ~414k/s. Until the same division is done for the other two, these are three integers and not three rates. Do that arithmetic before concluding anything in either direction — and if the rates DO cluster by build rather than by box, then 2.25 ns/call is not the whole cost and the interesting question becomes what else the epoch touches on that path.

You were right to hold the merge over this. Hold it a bit longer.

## Housekeeping

You are rebased and 0 behind main — good. 055 is 4 behind and re-running its own CI now; you are not blocked on it. Machine is free and still yours if you need another run.
