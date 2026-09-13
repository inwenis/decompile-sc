#Requires -Version 7
<#
.SYNOPSIS
Generate the two sandbox maps. tools/make_feature_test_map.py writes the feature-test map: a
Use Map Settings sandbox where the player owns a Terran, a Zerg and a Protoss base (every
research building, supply to spare, a mixed army each), starts on 50,000 minerals and gas, and
has a passive enemy field to attack. tools/make_battle_map.py writes !battle.scx beside it: two
big mixed-race armies facing each other, for screenshots. What to do on them:
tools/feature-test-map-card.md. tools/deploy.ps1 runs this as its last step, because its /MIR
mirror purges destination-only files like these.

.PARAMETER OutputPath
Where the feature-test .scx goes; !battle.scx goes into the same folder. Default: the deployed
copy's Maps\BroodWar\, the folder Play Custom's map browser opens in; the leading `!` sorts them
above the stock maps, right after the folders.
A .scm/.scx is game content and is never committed (AGENTS.md § "Hard rules").

.PARAMETER TemplatePath
The stock ladder map the sandboxes are cut from (its settings and strings).

.EXAMPLE
./tools/make-feature-test-map.ps1 -OutputPath 'C:\decompile-sc-data\sc-work\1161-base\Maps\BroodWar\!feature-test.scx'
#>
[CmdletBinding()]
param(
    [string]$OutputPath = 'C:\decompile-sc-data\sc-deploy\starcraft-modded\game\Maps\BroodWar\!feature-test.scx',
    [string]$TemplatePath = 'C:\decompile-sc-data\sc-work\1161-base\Maps\BroodWar\Ladder\(2)Fading Realm.scx'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sc-python.ps1')
$resolved = Resolve-ScPython -RepoRoot (Split-Path -Parent $PSScriptRoot) -RequireModule 'richchk'
if (-not $resolved.Path) {
    throw "make-feature-test-map: no python that can import richchk (probed: $($resolved.Probed -join '; ')). Run ./setup-worktree.ps1."
}
$battlePath = Join-Path (Split-Path -Parent $OutputPath) '!battle.scx'
foreach ($map in @(@('make_feature_test_map.py', $OutputPath), @('make_battle_map.py', $battlePath))) {
    & $resolved.Path (Join-Path $PSScriptRoot $map[0]) --template $TemplatePath --output $map[1] 2>&1 |
        Where-Object { "$_" -notmatch 'WARNING:StormLibFinder' }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
exit 0
