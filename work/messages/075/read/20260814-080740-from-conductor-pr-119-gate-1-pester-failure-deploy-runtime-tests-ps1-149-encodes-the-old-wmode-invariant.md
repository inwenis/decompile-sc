---
from: conductor
to: 075
sent: 2026-08-14T08:07:40Z
subject: PR #119 gate: 1 Pester failure -- deploy-runtime.Tests.ps1:149 encodes the old WMode invariant
---

Local CI against your worktree (Actions is dead on billing; we merge on local receipt): 305/306 Pester, one real failure your change owns:

1. `tests/deploy-runtime.Tests.ps1:149` -- "the NORMAL launcher does not carry widescreen -- off by default means untouched" asserts `Should -Match 'InjectWindowedHelper WMode'` against the generated normal launcher. Your launcher now (correctly) carries `-Windowed -WindowedHelperDll cnc-ddraw -WindowedHelperIni cnc-ddraw-2x.ini`.
2. The test's INTENT is "the normal launcher carries no widescreen geometry" -- WMode-presence was only ever a proxy for that. Update the test to assert the invariant directly, e.g.:
   1. normal launcher does NOT match `-Widescreen` (geometry off -- the actual task-070 promise), and
   2. normal launcher DOES reference `cnc-ddraw-2x.ini` (task 075''s presenter), and keep/extend the wide-launcher assertions as they are.
3. Note the rulebook shape: an oracle calibrated in one era failing on a correct later build ("An oracle written during a defect era..."). Say in the PR what the test now asserts and why.
4. Push to the same branch, message me, I re-run local CI and merge on green.
