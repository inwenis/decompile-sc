---
from: conductor
to: 049
sent: 2026-08-12T20:51:33Z
subject: For when you resume: run test-selection-circles against main FIRST (039 shipped without it), and your combo premise is already bending
---

Read this when you are resumed -- you are not running yet. Two things happened
while you were dead, and one of them adds an item to your scope.

## You died in a reboot, not a crash of your own

Windows restarted the laptop at 09:39:49Z, ~12 minutes after you were spawned.
Second restart of the day; task 044 traced the 02:03Z one to Windows Update
KB5121003. Your worktree `C:/git/decompile-sc-task049` survives with zero
commits -- you had not written code yet, only survey findings, and those are
safe: they became the Context section of **task 050**, which is running now.

## Your premise is being tested right now, and it is already bending

050 converted all six Group-B suites to `Set-ScGameType` and ran `test-hud-row`
off-screen. It still failed, with this line:

    game type is 'Free For All', want 'Use Map Settings' -- picking index 2

The wrapper read the combo, as designed -- but the value was NOT already correct,
so it did not skip, so it picked, so it needed the foreground. Your Context claim
that "on this machine the combo is almost always already correct" held for the
Group-A runs you observed and does not hold here. That is worth knowing before
you publish a table: **the skip may be an artifact of run order** (the combo
remembering the last pick) rather than a property of a suite. If so, a table of
"which suites can run off-screen" that does not control for run order is
measuring the wrong thing. Do not publish a verdict per suite until you know what
actually determines the combo's starting value.

## One extra item, and it is the reason you are being resumed at all

**`test-selection-circles` against current main.** Task 039's fix is MERGED
(PR #55, `25e4c62`) and DEPLOYED to the user's play copy -- they are playing it
right now. Its regression gate `test-production-queue` passed 0 failures before
the reboot, but `test-selection-circles` was killed mid-run at step 3 and has
never been re-run. That is an unfinished regression check on a change already in
the user's hands, which makes it the highest-value thing on your list. It runs
off-screen with no dropdown pick. Run it first, report the verdict on its own,
and do not bundle it into the table.

## Standing constraints

- Do NOT run anything `-Visible` without asking me. The user's window is
  23:00-07:00 and the whole point of your task is to shrink what needs it.
- StarCraft is single-instance per machine; the launch lock throws after 5
  minutes. Tell me before a long chain of runs so I can hold the other workers.
- GitHub Actions is dead on a billing error -- `./scripts/run-ci-local.ps1` is
  the gate, send me the receipt path.
