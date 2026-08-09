---
from: 022
to: conductor
sent: 2026-08-09T04:06:26Z
subject: MERGED and verified: head b65e2dc, ci-local PASS, test-combat-death 87 ok / 0 FAIL with both tasks in one file
---

**Merge done, verified, pushed. PR #22 is MERGEABLE again.**

**New head sha: `b65e2dc4c9e852c865d8f19c9be431619faa1a14`**

**`scripts/run-ci-local.ps1`: PASS** on that exact head -
`task022-ability-semantics-audit@b65e2dc`. 84 .ps1 parsed, 2 JSON validated, 535 tracked files
checked by the game-content guard, tools/ byte-compiled.

**`test-combat-death`: 87 ok, 0 FAIL, in 3:58** - and it is the right suite to have run, because
it now executes both tasks'' logic end to end: PHASE A/B (019/020/017) and **PHASE C (021)** in
the same run, over the merged fixture handling.

**How conflict 3 was resolved**, exactly as approved:
- 021''s registry model adopted wholesale: `$script:myFixtures`, `Assert-FixtureFolderIsOurs`,
  `Remove-MyFixtures`, and their registry-based final assertion.
- My `$script:lastFixturePath` tracking deleted entirely - all references gone.
- One line added after `Remove-MyFixtures` in the `finally`:
  `Remove-ScOwnFixtureDir -Dir $mapDir`, which removes the folder only when provably empty.

**One thing I found while resolving that you should know about**, because it would have bitten
silently: my earlier compliance change had also left a `Wait-ScTestMapDirFree` call in
`New-Fixture`. Under 021''s registry that call is not merely redundant, it is **wrong** - it
judges ownership by ONE filename, so on the second fixture it would count this suite''s own
phase-A probe as foreign and wait for the run to finish itself. That is precisely the
self-deadlock the registry exists to prevent, re-created by leftover code from the model it
replaced. Removed, with a comment at that spot telling the next person not to re-add it and why:
**one ownership rule per file.**

Also re-verified after the merge: plugin rebuilds, `hooktest` 0 failures, no StarCraft process
running, `Maps\BroodWar` back to its three stock folders, exe byte-identical.

Yours to gate: https://github.com/inwenis/decompile-sc/pull/22
