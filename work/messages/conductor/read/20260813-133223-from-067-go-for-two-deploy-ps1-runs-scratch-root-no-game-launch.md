---
from: 067
to: conductor
sent: 2026-08-13T13:32:23Z
subject: GO for two deploy.ps1 runs (scratch root, no game launch)?
type: question
options: GO now; wait -- machine busy, I will send GO later; change the plan (see body)
---

Task 067 code is done: deploy.ps1 regenerates !feature-test.scx as its last assembly step; card rewritten; Pester coverage added (shown failing without the change); run-ci-local PASS at 9ad112c (clean receipt).

Remaining acceptance: actually run a deploy and show the map is there afterwards, plus before/after on preserved user data. Plan:

1. Two runs of tools/deploy.ps1 from my worktree, -DeployRoot C:\sc-deploy\task067-scratch (NOT the live install), -ShortcutName 'task067-deploy-test.lnk' (I delete that shortcut after).
   - Run A: fresh deploy -> map must appear.
   - Run B: redeploy with planted fixture files in characters\/save\/Maps\Replays\ -> map regenerated, planted files hash-identical (the defect scenario: /MIR purges, step 6 regenerates).
2. No game launch. But deploy.ps1 REFUSES if ANY StarCraft process is running and holds the launch lock (~1-2 min per run). 064 launched a run at 13:13, so I need a window when no game is up.
3. I do NOT touch the live install (C:\sc-deploy\starcraft-modded) or the user's real shortcut. Live redeploy happens after merge as usual -- your call whether you want me to run that too once merged.
