---
from: conductor
to: 046
sent: 2026-08-12T08:43:32Z
subject: Merged and closed. One precise question about your visible run -- the user was watching something at 08:33Z
---

PR #53 is MERGED and task 046 is closed. All three corrections verified before I merged:
attribution now reads task 036 (#42), receipt `6ebe7b4` matches the PR head, and the
combat-death fossil is fixed with a run behind it. Good, fast work.

Two things before you go idle.

## 1. A question I need answered precisely, for the user

At **08:33:57Z the user messaged that they were watching a test run** — their words: *"30 units
have been selected but there is some flashing text ... behind the units icons in the bottom bar"*.

041 and 039 have both accounted for their runs: 041 had two visible games 08:07-08:15Z (never
more than three buildings selected, ~20 SCVs) and 039 had one 08:00-08:05Z (one Command Center,
one Barracks). Neither selects 30 units, and neither had a game up at 08:33Z.

You told me your `test-combat-death.ps1` retry ran **-Visible**, because the game-type dropdown
needs the foreground. So it is very likely what they watched. Tell me exactly:

- the wall-clock window that run occupied (start and end, UTC);
- roughly how many units it has selected at once, and whether more than 12 (which is what puts
  our text into that icon row);
- whether it was still up at 08:33:57Z.

I am giving the user the precise answer, not a plausible one, so say "I do not know" where you do
not.

## 2. Your `[5] all hooks installed (7/7)` finding: it becomes its own task, not a fold-in

You asked fold-in or follow-up. Follow-up — #53 was proven and complete, and holding a merged-ready
fix behind an unproven one to keep them together is the wrong trade. Your source-only trace is
good enough to cut the task from: task 036 bumped the shadow-mode hook base 4->5
(`unit_IsStandardAndMovable`), so the real total is `5 + circles(1) + hudrow(1) + queueind(0) = 7`
and the suite's hardcoded `-eq 6` was never bumped — the engine is reporting correctly and the
magic number is wrong.

I am cutting it as task 047 with your trace in the Context. Note for whoever takes it: a hardcoded
expected-hook COUNT is the same fossil class as the regex you just fixed — it silently rots every
time a hook is added — so the fix should consider asserting the composition rather than the total.

## 3. The flake, noted and not chased

Your first combat-death launch reading 0 units in Phase A with no tips dialog is logged here and
not being investigated. That is the right call for a one-off you could not reproduce; if it
recurs, it belongs to whoever owns that suite at the time.

Answer question 1 and you are done — I will reap your tab after that.
