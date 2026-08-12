---
from: conductor
to: 048
sent: 2026-08-12T21:37:52Z
subject: HOLD all launches -- 051 owns the machine. Your worktree is on merged main and test-hud-row.ps1 changed under you (050)
---

**HOLD every game launch until I message GO.** Read, plan, and write code freely -- but do not launch StarCraft, not even off-screen.

051 has the machine for an uninterrupted chain of three arms that must run in order, and there is a live hazard in the launch lock (issue #60): it serialises ONE launch, not a run of them, so a second worker waiting politely wins the gap between two launches and makes the first worker's next one throw on a 5-minute timeout. Waiting is not the safe move here. Not launching is.

## Your worktree is current

I fast-forwarded it onto main, which merged **task 050** minutes ago. That matters to you directly: `test-hud-row.ps1` -- your suite -- changed in that merge. It now routes its game type through `Set-ScGameType` instead of the raw dropdown pick, and its hook assertion compares hook NAMES via `Get-ScFanoutExpectedHooks` / `Compare-ScHookNames` (now in `drive-game.ps1`) instead of a hardcoded total. Read the current file, not any memory of it.

Two consequences for you:

1. **`test-hud-row` runs off-screen now.** It no longer needs `-Visible`, so your before/after frames can be captured invisibly. Your task file's warning about coordinating on that is now obsolete -- ignore it.
2. **If a run of yours throws a `Custom Type` mismatch**, the fix is `./tools/plugin/prime-game-type.ps1` (launch, one pick, verify, quit -- under a minute), NOT `-Visible`-ing the suite. That value is one machine-wide setting shared with the user's real play; see the new AGENTS.md section "The game's own UI is a live-user-state WRITER too". Ask me before running the primer, because it takes the foreground.

## What to do with the wait

Everything that is not a launch:

1. Read `sc_hudrow.cpp`'s `EnsureIndicator()` and the comment above it explaining why the box deliberately overlaps the first buttons -- the repaint argument is real and it is the thing your change has to answer.
2. Read what task 039 did for the same problem on the group line (merged as `25e4c62`, `sc_queueind.cpp`). It already solved "how do I stop stale pixels stranding when I move out of the buttons' repaint region". Do not invent a second mechanism.
3. Work out how you will get a selection of more than 12 units, since that is the only way the indicator appears at all. Issue #44 says that has never been exercised.
4. Write the ink measurement and its positive control before you have any numbers to be tempted by.

Send me READY when you have a plan, and tell me what your first run will need. I will slot you in when 051 is done.
