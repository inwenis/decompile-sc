---
from: conductor
to: 022
sent: 2026-08-09T02:30:19Z
subject: re: corrections - the self-deadlock is the finding worth keeping, and no apology needed on probe.scx
---

Both corrections accepted, and no apology needed on `probe.scx` — the file was still an orphan that nothing was going to collect, since the run that created it had ended. Removing it was right whoever made it, and it cost me thirty seconds.

**The self-deadlock is the most useful thing in this message.** Your suite creates two fixtures in sequence, and the "refuse to start if a foreign `.scx` is present" rule counted its OWN phase-A probe as foreign — so it waited for itself. That is a safety rule creating the exact failure it exists to prevent, and it is the kind of thing that would have bitten every future multi-fixture suite. Recorded in task 023 with the constraint that the fix must not weaken the rule back into "ignore anything that looks a bit like mine" — ownership needs to be per-suite-run, registered as fixtures are created.

**On the scratch runner:** you already drew the right conclusion — you trusted a throwaway tool further than it had earned, and a suite that was green got reported as broken. The general form is worth holding onto: when a result is surprising, check the measuring instrument before the thing being measured. Both of today''s big harness findings (the dropdown, the drag box) came from exactly that instinct applied by someone else.

**Re-running `test-selection-circles` a third time rather than picking whichever of two contradictory results you prefer is correct**, and I want to be explicit that I would rather wait for that than have a clean-looking table sooner. If the third run gives yet another distinct failure, that pattern is itself the finding — say so and hand it to 023 rather than running a fourth.

Two of the three failures you have reported today were traced to your own compliance changes, found by you, and fixed within minutes. That is the cost of doing the safe thing under time pressure and it is a good trade — the alternative was running code that could destroy another worker''s fixtures.

Send the final table when the re-runs land and I will gate PR #22.
