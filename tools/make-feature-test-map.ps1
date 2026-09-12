#Requires -Version 7
<#
.SYNOPSIS
Generate the feature-test map with tools/make_feature_test_map.py: a Use Map Settings sandbox
where the player owns a Terran, a Zerg and a Protoss base (every research building, supply to
spare, a mixed army each), starts on 50,000 minerals and gas, and has a passive enemy field to
attack. What to do on it: tools/feature-test-map-card.md. tools/deploy.ps1 runs this as its
last step, because its /MIR mirror purges a destination-only file like this one.

.PARAMETER OutputPath
Where the .scx goes. Default: the deployed copy's Maps\BroodWar\, the folder Play Custom's map
browser opens in; the leading `!` sorts it above the stock maps, right after the folders.
A .scm/.scx is game content and is never committed (AGENTS.md § "Hard rules").

.PARAMETER TemplatePath
The stock ladder map the sandbox is cut from (its settings, strings and ground tile).

.EXAMPLE
./tools/make-feature-test-map.ps1 -OutputPath 'C:\sc-work\1161-base\Maps\BroodWar\!feature-test.scx'
#>
[CmdletBinding()]
param(
    [string]$OutputPath = 'C:\sc-deploy\starcraft-modded\game\Maps\BroodWar\!feature-test.scx',
    [string]$TemplatePath = 'C:\sc-work\1161-base\Maps\BroodWar\Ladder\(2)Fading Realm.scx'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sc-python.ps1')
$resolved = Resolve-ScPython -RepoRoot (Split-Path -Parent $PSScriptRoot) -RequireModule 'richchk'
if (-not $resolved.Path) {
    throw "make-feature-test-map: no python that can import richchk (probed: $($resolved.Probed -join '; ')). Run ./setup-worktree.ps1."
}
& $resolved.Path (Join-Path $PSScriptRoot 'make_feature_test_map.py') --template $TemplatePath --output $OutputPath 2>&1 |
    Where-Object { "$_" -notmatch 'WARNING:StormLibFinder' }
exit $LASTEXITCODE
