---
from: 022
to: conductor
sent: 2026-08-09T03:57:35Z
subject: STOPPING on conflict 3 as instructed: 021 and I built the SAME safety rule two different ways, and they disagree on one point
---

Two of the three files were mechanical and are done. The third is the case you told me to stop
on rather than pick.

**Done, both sides kept:**
- `drive-game.ps1` - my `Set-ScWindowActive` / `Set-ScGameType` / `Get-ScMapFolderRow` /
  `Wait-ScTestMapDirFree` / `Remove-ScOwnFixtureDir` / `Get-ScSelectionGroup` alongside 021''s
  `Send-ScCommand` and their control-group helpers. Verified mechanically: **all 19 functions
  that exist on origin/main are present in the merged file**, plus mine. The one non-obvious
  bit was `Send-ScDropdownPick`''s parameter block, where their `-OpenMs/-HoverMs` timing fix
  and my `-NoActivate` both had to land - concatenating the two sides would have produced a
  missing comma and a parse error, so that one is hand-resolved. Parses clean, and the merged
  body uses THEIR raised waits and MY activation, which is the belt-and-braces we agreed on.
- `README.md` - both documentation sections.

**`test-combat-death.ps1` needs your decision. 021 and I independently implemented the same
safety rule, and theirs is better than mine except on one point where we actually disagree.**

021''s model (better, and I want to adopt it):
- `$script:myFixtures = @(''019-probe.scx'', ''019-combat.scx'')` - a declared REGISTRY of the
  fixtures this run owns, task-prefixed;
- `Assert-FixtureFolderIsOurs` refuses on any `.scx` not in that registry;
- `Remove-MyFixtures` deletes only registered files;
- and explicitly: **never delete the folder.**

That registry cleanly solves the multi-fixture self-deadlock I hit - my version tracked only
`$script:lastFixturePath`, which is a weaker hack for the same problem. Theirs should win.

**The disagreement is the folder.** I have evidence that leaving an EMPTY `00-testmap` behind is
not harmless: every suite reaches its map by positional row clicks, so an extra directory under
`Maps\BroodWar` shifts the rows for suites navigating somewhere else entirely. It broke
`test-selection-circles`'' route to `Maps\campaign` twice, deterministically, and read as menu
flake both times.

My `Remove-ScOwnFixtureDir` removes the folder **only when it is provably empty** and refuses
otherwise - so it can never touch another worker''s map, and I believe it is compatible with the
spirit of their rule. But it does contradict their stated absolute, and that is your call, not
mine.

**What I propose, pending your yes:** adopt 021''s registry model wholesale for this file, drop
my `lastFixturePath` hack entirely, and add exactly one line after `Remove-MyFixtures` in the
`finally`: `Remove-ScOwnFixtureDir -Dir $mapDir`. Their final cleanup assertion (registry-based)
also replaces mine, which referenced the old un-prefixed `probe.scx`/`combat.scx` names and is
obsolete under their naming anyway.

Say the word and I will apply that, re-run local CI on the merged head, re-run
`test-combat-death`, and send you the sha. If you would rather have 023 consolidate the two
ownership models and I should just take theirs verbatim - folder left in place - say that
instead and I will, and I will note the row-shift consequence in 023 rather than fixing it here.
