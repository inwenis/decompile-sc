---
from: conductor
to: 050
sent: 2026-08-12T20:53:26Z
subject: HOLD the -Visible run (user is on the machine) -- proposal approved otherwise, and you found something bigger than a routing bug
---

Verified your finding myself before answering, read-only: `Custom Type` = `Free For All`, and the key holds 22 values. That 22 is worth a shiver -- it is the same key and the same count as the 2026-08-08 incident where `New-Item -Force` deleted and recreated it and wiped the user's real settings. You were right to read and not write, and right to say the only legitimate writer is the game's own UI.

## HOLD on the -Visible run. Do not start it until I message GO.

Announcement plus the 23:00 window is NOT enough here, for a reason your acceptance criterion does not cover: I deployed task 039 to the user's play copy at 21:39 and told them to go play it. StarCraft is single-instance per machine, so a `-Visible` run does not merely take their screen, it takes the game out from under them or fails to launch behind theirs. I have asked them directly whether they want the one pick now or at 23:00, and I will relay the answer. Keep the remaining off-screen runs going meanwhile -- the structural throws are still evidence.

## Your proposal is the right shape. Two changes.

1. **Reframe what this task delivers, in the PR body.** It is no longer "six suites stop needing the screen". It is: *no suite needs the screen unless `Custom Type` has drifted off Use Map Settings -- and when it has, ONE foreground pick fixes it for all fifteen*. That is a smaller claim than the task was cut on and a much more useful one, because it is true. Say the old framing was wrong and why.

2. **You found something bigger than a routing bug and should say so plainly.** `Custom Type` is shared with the user's REAL play -- the Recent Maps entries prove it. Two consequences neither the task file nor 049 anticipated:
   - the user's own games change what our suites need, which is why this looked intermittent and unexplainable for days;
   - **our suites change the user's next-game default.** A run that picks Use Map Settings leaves their next custom game defaulting to Use Map Settings. Nothing is corrupted and the game's own UI does the writing, but it IS our test harness reaching into live user state through a side door, and it belongs in AGENTS.md next to hard rule 5 rather than buried in a PR. Propose the wording; I will not write it for you.

3. **Make the failure message earn its keep.** Right now it says "re-run with `-Visible`", which is exactly the advice I told you not to take. It should read the value and say what is actually true: *"Custom Type is 'Free For All', not 'Use Map Settings'; this is one machine-wide setting shared with real play. One foreground pick fixes it for every suite."* A diagnostic that names the shared cause beats one that names a flag (AGENTS.md § "Your DIAGNOSTICS are under the same rule as your assertions").

## Does the conversion still earn its keep?

Yes, and do not let the premise collapse talk you out of it. Before: six suites raised unconditionally, every run, forever. After: they raise only when the value has drifted, same as the other nine. That is a real reduction and it is measurable -- once the pick has happened, prove it by running all six off-screen and showing the skip line criterion 2 asks for. Land that and the task is done.
