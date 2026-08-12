---
from: 038
to: conductor
sent: 2026-08-12T01:24:56Z
subject: Task 038 ready for review - PR #47 (and CI is blocked on GitHub billing)
---

PR: https://github.com/inwenis/decompile-sc/pull/47 (link is in Status.pr)

**Cause, and it is one read.** `sc_prodqueue` decided which building a Train command was for by
reading `activePlayerSelection` (0x006284B8). The engine's own gate reads the OTHER array:
`getActivePlayerNextSelection` (0x0049A850) walks `playersSelections` (0x006284E8), row
`activePlayerId`. The two abut (0x006284B8 + 12*4 == 0x006284E8) and agree whenever ONE building
is selected -- so every suite passed. A fanned-out Select+Train pair is exactly where they
disagree: the simulation holds one building, the client still holds the group. The plugin
answered "no single building" for every replayed Train, held nothing back, all rings hit five,
and the client stopped sending.

**Measured at queueCommand, 3 Command Centers, 9 presses:**
- before: 5 of 9 on the wire; rings 5/5/5, overflow 0; 750 minerals (15 units)
- after: 9 of 9 on the wire; each building ring 4 + overflow 5 = 9; 27 units; 1350 minerals,
  charged by the engine, once each; plugin mineralsSpent=0; cancel refunded exactly 50.

**Tests**
- `tools/plugin/test-group-queue-over-five.ps1` (new, the first suite running task 025 and task
  030 in one game): 16 failures on main, 0 with the fix.
- hooktest part [15] gains the selection read with the two arrays disagreeing: 3 failures against
  main's reading, 0 with the fix.
- `test-production-queue.ps1` (task 025, criterion 3): 0 failures.
- Frames stay on the gitignored path (hard rule 1): `C:\sc-work\logs\038\group-queue-frames\`;
  log `C:\sc-work\logs\038\group-queue-over-five.log`. Wire traces are in the PR body as text.

**Two things for you**

1. **CI cannot run on this repo right now** -- the check failed with "The job was not started
   because recent account payments have failed or your spending limit needs to be increased"
   (run 31553441612), not on anything in the diff. `merge-task.ps1` gates on checks green, so it
   will refuse this PR until that is sorted. I ran every CI step locally instead: 98 .ps1 files
   parse, 2 JSON files valid, 0 tracked game-content/oversized files, `compileall tools` clean,
   plus `build.ps1 -Test` (hooktest 0 failures).
2. **`sc_upgrades.cpp` has the same wrong reading** in its own `SoleSelectedUnit` (task 029). It
   is LATENT -- no upgrade command is fanned out and the client will not offer an upgrade button
   for a multi-building selection, so the two arrays cannot disagree there today. I left it alone
   rather than change a shipped feature whose own suite this task cannot re-run; it is worth a
   small follow-up task. `research/production-queue.md` §10.5 records it.

I am idle now (no game running, launch lock released).
