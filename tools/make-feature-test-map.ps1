#Requires -Version 7
<#
.SYNOPSIS
Generate the feature-test map (task 062): one saved single-player map the user can
load to exercise over-cap production queueing, the +N overflow indicator, the fifth
slot, cancel-by-click (including the last slot), the group queue indicator, the
>12-unit paging row on a BUILDING group (issue #44 -- never exercised before this),
and save/load -- all from one selection of pre-placed Command Centers.

.DESCRIPTION
Thin, FIXED-parameter wrapper around tools/make-test-map.ps1 (itself a wrapper around
tools/make_test_map.py, the deterministic raw-CHK patcher). No flags to remember and
none exposed: this is the one command that reproduces work/reports/062-feature-test-map.md's
fixture table, byte-for-byte, every time it is run.

WHY 13 COMMAND CENTERS, AND NOTHING ELSE ON THE MAP.

13, not some rounder number: the point of the paging-row feature is "one past twelve",
proved with the smallest count that proves it. Selecting all 13 is also the first time
a BUILDING group has ever crossed the 12-unit cap in this project (issue #44 -- every
earlier >12 fixture used mobile units). The same 13 double as the group-queue-indicator
fixture (select any 2+) and the over-cap/cancel fixture (select just 1) -- one block
covers four of the seven features the user asked to exercise.

Command Center: no prerequisite building, produces SCVs (50 minerals, no gas), and is
the same building type task 038's proven fixture (test-group-queue-over-five.ps1) uses
for the identical over-cap + group-queue claim -- this map's generator call is that
suite's genArgs shape, just with -UnitCount raised from 3 to 13 and no combat.

`--unit-build-time scv=240`: 240 GAME seconds (~168 real seconds), the same number
task 051 chose for the Probe. The point of every one of these features is that the
user LOOKS at it -- a queue that drains in 20 seconds is gone before they can read the
+N indicator, which is the whole reason this flag exists (tools/make_test_map.py's own
header, and this task's Context).

`--starting-minerals 8000`, no gas (SCV costs none): affords 8+ deep at all 13
buildings through the group Train fan-out (13 x 50 x 8 = 5200) with headroom for a
curious extra click, and 8000 an easy number to recognise as "not almost out" on the
resource read-out while poking around.

No --enemy-count: none of the seven features need a hostile force, and per the task's
own guidance ("if a feature needs a fundamentally different setup, say so and leave it
out"), the ability/tech and combat-death variants are NOT folded into this map -- they
would need a second unit type and hostile units, which is a different fixture, not a
bigger version of this one.

REGENERATING. This needs no running game and takes under a second. It is also the fix
for "the map is not in the list any more": tools/deploy.ps1's /MIR wipes everything
under Maps\ (outside Maps\Replays\, which is off-limits to this task) on every
redeploy, so nothing under the deploy tree survives a redeploy on its own. Re-run this
script, wait a couple of seconds, refresh the in-game map browser.

.PARAMETER OutputPath
Where the .scx is written. Defaults to the user's own deployed play copy's
Maps\BroodWar\ folder -- not Maps\ itself -- because that is where Single Player >
Expansion > Play Custom's map browser OPENS (research/tools/plugin/drive-game.ps1,
Select-ScBrowserMap), so the map is on screen with no extra "Up One Level" click.
Never committed to the repo (a .scm/.scx is game content -- AGENTS.md hard rule 1);
.gitignore blocks the default output path's extension regardless.

.PARAMETER TemplatePath
The stock ladder map this generator edits a copy of. Same template every suite in
this repo uses.

.EXAMPLE
./tools/make-feature-test-map.ps1

.EXAMPLE
./tools/make-feature-test-map.ps1 -OutputPath C:\sc-work\1161-base\Maps\BroodWar\zz-feature-test.scx
#>
[CmdletBinding()]
param(
    [string]$OutputPath = 'C:\sc-deploy\starcraft-modded\game\Maps\BroodWar\zz-feature-test.scx',
    [string]$TemplatePath = 'C:\sc-work\1161-base\Maps\BroodWar\Ladder\(2)Fading Realm.scx'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $repoRoot 'tools/make-test-map.ps1') `
    -UnitCount 13 -UnitType command-center -Player 0 -ClearPlayerUnits `
    -GridSpacing 160 -Race terran `
    -UnitBuildTime @('scv=240') `
    -StartingMinerals 8000 `
    -TemplatePath $TemplatePath -OutputPath $OutputPath

exit $LASTEXITCODE
