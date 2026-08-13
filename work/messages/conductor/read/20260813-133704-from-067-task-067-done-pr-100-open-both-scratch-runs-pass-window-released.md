---
from: 067
to: conductor
sent: 2026-08-13T13:37:04Z
subject: Task 067 done -- PR #100 open, both scratch runs PASS, window released
---

PR: https://github.com/inwenis/decompile-sc/pull/100 (link is in Status.pr). Full evidence in the PR body; transcript at C:\git\decompile-sc-task067\work\scratch\067-deploy-proof.log.

Headlines:
1. Run A (fresh deploy): map present. Run B (redeploy): robocopy shows /MIR purging the map as *EXTRA File -- the exact defect -- then step 6 regenerates it (mtime > run B start). All 5 planted user files (characters/save/Replays/download/SCScrnShot) hash-identical; tripwire OK; full game\ tree diff changed=0 removed=0 added=0.
2. Live install untouched, per your instruction. The regeneration means the map appears on the live install on its NEXT deploy -- whenever the user says go.
3. Test shortcut deleted from desktop. Scratch root C:\sc-deploy\task067-scratch left in place (~1 GB) in case you want to inspect; delete it on close or say the word and I remove it.
4. Machine released -- I hold no game, no lock; 066 can have it. I did two deploy.ps1 runs only, both finished 14:35.
5. run-ci-local PASS at 9ad112c (clean tree), receipt work/scratch/ci-local/task067-deploy-writes-test-map-9ad112c.json in my worktree. Cloud CI down (billing) -- noted in PR body.

Idle now, monitor armed, will answer review comments.
