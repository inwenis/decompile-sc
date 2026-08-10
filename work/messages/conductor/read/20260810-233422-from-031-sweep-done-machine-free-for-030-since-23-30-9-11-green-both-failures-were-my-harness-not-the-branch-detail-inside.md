---
from: 031
to: conductor
sent: 2026-08-10T23:34:22Z
subject: sweep done, machine free for 030 since 23:30. 9/11 green; BOTH failures were my harness, not the branch - detail inside
---

MACHINE IS FREE and has been since ~23:30 -- the last suite closed its game cleanly. I have launched nothing since and will not until you say go.

SWEEP: 9 of 11 exited 0. Both failures were caused by ME, not by the branch, and I would rather say so plainly than bury it.

1. `test-sunken-acquire` -- 1 failure, and it is the yield sentinel I told you about:
   `drive-game: ...00-t031 holds zz-031-yield-hold.scx, which this run did not create ... Refusing to start`
   My hold file landed DURING the suite's fourth arm instead of after it. So the failure is the fixture-ownership guard doing exactly its job, on my own foreign file. Nothing to do with the change under review, and honestly a good look for that guard: it refused rather than playing whatever was there.

2. `test-production-queue` -- 1 failure, and this one is a REAL latent race that my sweep script provoked:
   `FAIL a test step threw: The process cannot access the file 'C:\sc-work\logs\031\sweep\marker.txt' because it is being used by another process` (at Get-ProdQueue -> Set-Content on the marker)
   My sweep pointed eight suites at ONE log directory, and `marker.txt` lives beside the log, so they shared one marker file. But the collision itself is not about sharing between suites -- the plugin's observer thread polls that file four times a second while the driver writes it, and `Set-Content` and that read can collide inside a SINGLE run. It is rare and it just cost a run. NOT FIXED: it is `Get-ScWorldState`/`Get-ScUnitState` in drive-game.ps1, which four live tasks source, and you told me tonight is not the night to touch that machinery. A retry around the marker write is the fix and it is small; it goes in the PR as a finding with the stack trace, for whoever owns the next slot on that file.

3. `test-ability-in-combat` -- 4 failures, diagnosed in my last message: the fanout arm needed four takes, the suite stims again on every retake, the stim effect outlives a retake, so by take 4 all 36 already carried it and the did-it-fire delta read 0. Its own guard caught it. Also not the branch -- I compared the generated fixture's CHK bytes against the origin/main generator and they are identical.

So: 9 clean, 3 suites to re-run (`ability-in-combat`, `sunken-acquire`, `production-queue`) once the machine is mine again, with the sweep script fixed to give every suite its own log directory. `production-queue` has already passed twice tonight on this branch at 126.8s and 0 failures, so I expect all three; I will report whatever actually happens.

DONE WHILE YIELDED, no machine needed:
* ci-local PASS at 58c2bf5 -- parse-ps1, validate-json, pester 61/61, game-content-guard, compile-python, hooktest 0 failures. `ruff` NOT RUN as expected.
* I took the hooktest log-path fix you offered. `%TEMP%\scplugin-hooktest.log` is now `%TEMP%\scplugin-hooktest-<pid>.log`, and a caller that sets SCPLUGIN_LOG still wins. Verified: this run wrote `scplugin-hooktest-53252.log`. Committed separately (3c5fc33) so it can be reverted on its own if you would rather it went with the issue.
* Branch pushed, PR body written; I will open the PR after the three re-runs so its regression section is true rather than optimistic.
