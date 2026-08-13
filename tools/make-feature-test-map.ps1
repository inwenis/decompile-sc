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

WHY --grid-spacing 128, NOT the generator's usual 160. A Command Center's footprint is
128x96 px (4x3 build tiles); 128 is the tightest uniform spacing (this generator uses
one spacing value for both axes) that keeps every building clear of its neighbours, so
it packs the 4x4 block into the smallest footprint the placement can support without
risking a silently-dropped unit. 160 (what task 038's fixture uses for 3 buildings)
left the 13-building block taller than the playable viewport, so a single drag could
only ever reach 12 of the 13 -- measured in game, not assumed: at 160, buildings=12
every time, from any single camera position. At 128 the block is short enough that ONE
drag, from a camera scrolled up slightly from the default spawn view, reads back
`buildings=13 selected=13` and the HUD row shows `13 units 1-12 (1/2)` -- confirmed
with the plugin's own read-back oracles, not inferred from geometry. Placement was
re-checked after tightening the spacing too: Get-ScWorldState reads back exactly 13
engine-side units with this spacing, so nothing silently failed to place.

REGENERATING. This needs no running game and takes under a second. Since task 067,
tools/deploy.ps1 runs it automatically as its last assembly step on every deploy:
the /MIR mirror correctly purges the previous copy (a destination-only file), and
the deploy immediately writes a fresh one that matches the build it just deployed --
so "the map is not in the list any more" should no longer happen. Running this
script by hand is still fine any time; same output, byte-for-byte.

.PARAMETER OutputPath
Where the .scx is written. Defaults to the user's own deployed play copy's
Maps\BroodWar\ folder -- not Maps\ itself -- because that is where Single Player >
Expansion > Play Custom's map browser OPENS (research/tools/plugin/drive-game.ps1,
Select-ScBrowserMap), so the map is on screen with no extra "Up One Level" click.

Filename starts with `!` on purpose. The deployed Maps\BroodWar\ folder holds every
stock ladder map (measured: 90 of them), sorted alphabetically after directories; a
name that sorts LAST (an earlier draft used `zz-`) landed at row 95 of a 6-row-visible
list, invisible without scrolling this repo's own automation cannot do. `!` (0x21)
sorts before every stock map's leading `(` (0x28), so the file is the first entry
after the folders -- row 6 in a fresh install, confirmed by driving the real browser.

Never committed to the repo (a .scm/.scx is game content -- AGENTS.md hard rule 1);
.gitignore blocks the default output path's extension regardless.

.PARAMETER TemplatePath
The stock ladder map this generator edits a copy of. Same template every suite in
this repo uses.

.EXAMPLE
./tools/make-feature-test-map.ps1

.EXAMPLE
./tools/make-feature-test-map.ps1 -OutputPath C:\sc-work\1161-base\Maps\BroodWar\!feature-test.scx
#>
[CmdletBinding()]
param(
    [string]$OutputPath = 'C:\sc-deploy\starcraft-modded\game\Maps\BroodWar\!feature-test.scx',
    [string]$TemplatePath = 'C:\sc-work\1161-base\Maps\BroodWar\Ladder\(2)Fading Realm.scx'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $repoRoot 'tools/make-test-map.ps1') `
    -UnitCount 13 -UnitType command-center -Player 0 -ClearPlayerUnits `
    -GridSpacing 128 -Race terran `
    -UnitBuildTime @('scv=240') `
    -StartingMinerals 8000 `
    -TemplatePath $TemplatePath -OutputPath $OutputPath

exit $LASTEXITCODE
