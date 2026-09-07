#Requires -Version 7
<#
.SYNOPSIS
Generate the feature-test map: one saved single-player map that exercises over-cap
production queueing, the +N overflow indicator, the fifth slot, cancel-by-click
(including the last slot), the group queue indicator, the >12-unit paging row on a
BUILDING group, and save/load -- all from one selection of pre-placed Command Centers.

.DESCRIPTION
Fixed-parameter wrapper around tools/make-test-map.ps1 (itself a wrapper around
tools/make_test_map.py, the deterministic raw-CHK patcher): no flags to remember, and
the same bytes out of every run.

13 Command Centers and nothing else. 13 is the smallest count that proves "one past
twelve" for the paging row, and the same block doubles as the group-queue-indicator
fixture (select 2+) and the over-cap/cancel fixture (select 1). A Command Center needs
no prerequisite building and trains SCVs for 50 minerals and no gas, so the whole map
runs on one unit type and one resource.

`--unit-build-time scv=240` is 240 game seconds (~168 real seconds). Every feature
here is one the user must LOOK at, and a queue that drains in 20 seconds is gone
before the +N indicator can be read.

`--starting-minerals 8000` affords 8 deep at all 13 buildings through the group Train
fan-out (13 x 50 x 8 = 5200) with headroom for a curious extra click, and reads as
"not almost out" at a glance on the resource read-out.

No --enemy-count: none of these features need a hostile force. The ability/tech and
combat-death variants stay out -- they need a second unit type and hostile units,
which is a different fixture, not a bigger version of this one.

`--grid-spacing 128`, not the generator's usual 160. A Command Center footprint is
128x96 px (4x3 build tiles) and this generator uses one spacing value for both axes,
so 128 is the tightest uniform spacing that keeps every building clear of its
neighbours. Do not raise it to 160: measured in game, the 13-building block is then
taller than the playable viewport and a single drag reads back buildings=12 from any
camera position. At 128 one drag (camera scrolled slightly up from the default spawn
view) reads back `buildings=13 selected=13` with the HUD row `13 units 1-12 (1/2)`,
and Get-ScWorldState reports 13 engine-side units, so nothing silently failed to place.

Regenerating needs no running game and takes under a second. tools/deploy.ps1 runs
this as its last assembly step because the map is destination-only and deploy's /MIR
mirror purges it, so it has to be rewritten after that mirror, never before -- which
also keeps the deployed map matching the deployed build. Running it by hand gives the
same bytes.

.PARAMETER OutputPath
Where the .scx is written. Defaults to the deployed play copy's Maps\BroodWar\ folder
-- not Maps\ itself -- because that is where Single Player > Expansion > Play Custom's
map browser opens (research/tools/plugin/drive-game.ps1, Select-ScBrowserMap), so the
map is on screen with no extra "Up One Level" click.

The leading `!` is load-bearing. That folder holds every stock ladder map (measured:
90 of them), sorted alphabetically after directories, and only 6 rows are visible
without scrolling this repo's automation cannot do. `!` (0x21) sorts before every
stock map's leading `(` (0x28), so the file is the first entry after the folders --
row 6 in a fresh install, confirmed by driving the real browser. Do not pick a name
that sorts last (`zz-`): it lands at row 95, invisible.

A .scm/.scx is game content and is never committed (AGENTS.md § "Hard rules");
.gitignore blocks the default output path's extension regardless.

.PARAMETER TemplatePath
The stock ladder map this generator edits a copy of; the same template every suite in
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
