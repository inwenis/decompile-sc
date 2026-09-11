#Requires -Version 7
<#
.SYNOPSIS
Build the plugin and pack everything a player needs into one zip: plugin\, the launcher,
its .cmd shim, the card, a README, and an empty game\ for their own 1.16.1 files.

.DESCRIPTION
The zip is the tree tools/deploy.ps1 assembles on this machine, minus the mirrored game
(never redistributed: AGENTS.md § "Hard rules") and minus the feature-test map (deploy
generates it into its own game tree; a player's game\ is theirs). Both scripts stage
through tools/plugin/sc-stage-runtime.ps1, so the zip and the desktop install carry the
same files. .github/workflows/release.yml runs this on a tag and attaches the zip to the
release; a run by hand produces the same file.

The 2x ini is written borderless (fullscreen=true, aspect kept): the monitor that plays is
not the one that packages, and borderless fits every screen. The README in the zip says
how to get a 2x window instead.

.PARAMETER OutDir
Where the staged tree and the zip land. Default work\scratch\release (gitignored).

.PARAMETER Version
Name suffix of the zip. Default: `git describe --tags --always`, plus +dirty when the
tree has uncommitted changes.

.EXAMPLE
./tools/package-release.ps1
./tools/package-release.ps1 -OutDir dist
#>
[CmdletBinding()]
param(
    [string]$OutDir,
    [string]$CncDdrawDir = 'C:\sc-work\cnc-ddraw\v7.1.0.0',
    [string]$Version
)
$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot  = (Resolve-Path (Join-Path $scriptDir '..')).Path
$pluginDir = Join-Path $scriptDir 'plugin'
. (Join-Path $pluginDir 'sc-stage-runtime.ps1')
. (Join-Path $pluginDir 'sc-build-id.ps1')

if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'work\scratch\release' }
if (-not $Version) {
    $Version = (& git -C $repoRoot describe --tags --always).Trim()
    if (& git -C $repoRoot status --porcelain) { $Version += '+dirty' }
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$OutDir  = (Resolve-Path -LiteralPath $OutDir).Path
$stage   = Join-Path $OutDir 'starcraft-modded'
$zipPath = Join-Path $OutDir "starcraft-modded-$Version.zip"
Write-Host "package: version=$Version"

Write-Host ''
Write-Host '== Building plugin (and running hooktest) =='
& (Join-Path $pluginDir 'build.ps1') -Test | Write-Host
if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "package: plugin build failed (exit $LASTEXITCODE)" }
$builtDll = Join-Path $repoRoot 'work\scratch\plugin-build\scplugin.dll'
$builtExe = Join-Path $repoRoot 'work\scratch\plugin-build\scinject.exe'

Write-Host ''
Write-Host "== Staging -> $stage =="
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Publish-ScPluginRuntime -Dest $stage -BuiltDll $builtDll -BuiltExe $builtExe -CncDdrawDir $CncDdrawDir -Borderless $true | Out-Null
Copy-Item -LiteralPath (Join-Path $scriptDir 'release-README.md') -Destination (Join-Path $stage 'README.md') -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination (Join-Path $stage 'LICENSE') -Force
# An empty directory does not survive a zip; the placeholder keeps game\ visible and says
# what goes in it.
$gameDir = Join-Path $stage 'game'
New-Item -ItemType Directory -Path $gameDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $gameDir 'PUT-YOUR-STARCRAFT-1.16.1-FILES-HERE.txt') -Encoding utf8 -Value @(
    'Copy the contents of your StarCraft: Brood War 1.16.1 folder into this folder:'
    'StarCraft.exe, storm.dll, the .mpq files, everything.'
    'A copy, not your only install: the launcher writes ddraw.dll here.'
    'Then double-click Launch-StarCraft-Modded.cmd one level up.'
)

Write-Host ''
Write-Host '== Verifying =='
Test-ScPluginRuntime -Dest $stage -Borderless $true
$stamp = Get-ScDllBuildStamp -Path (Join-Path $stage 'plugin\scplugin.dll')
if (-not $stamp) { throw 'package: the staged scplugin.dll carries no build stamp; rebuild with tools/plugin/build.ps1.' }
Write-Host "verify: staged scplugin.dll is build $($stamp.BuildId) src=$($stamp.SrcDigest) (read from the file)"

if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath
$archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
try { $entries = @($archive.Entries | ForEach-Object { $_.FullName }) } finally { $archive.Dispose() }
foreach ($must in 'plugin/scplugin.dll', 'plugin/scinject.exe', 'plugin/cnc-ddraw/ddraw.dll', 'Launch-StarCraft-Modded.cmd', 'Launch-StarCraft-Modded.ps1', 'README.md', 'game/PUT-YOUR-STARCRAFT-1.16.1-FILES-HERE.txt') {
    if ($entries -notcontains $must) { throw "package: $must missing from $zipPath (entries: $($entries -join ', '))" }
}
$sizeMb = [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 1)
Write-Host ''
Write-Host "package: OK version=$Version -> $zipPath ($sizeMb MB, $($entries.Count) entries)"
