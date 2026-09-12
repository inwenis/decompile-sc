#Requires -Version 7
<#
.SYNOPSIS
Stage and zip what a player needs: the launcher, plugin\ (built dll + exe, pinned
cnc-ddraw, its ini), a README, and an empty game\ for their own 1.16.1 files.

.DESCRIPTION
Builds nothing and fetches nothing: run ./build.ps1 (or build.ps1 -Test) and
setup-onetime.ps1 first. .github/workflows/release.yml runs this on a tag; a run by
hand produces the same zip under work\scratch\release (gitignored).

.EXAMPLE
./tools/package-release.ps1 -Version v1.0
#>
[CmdletBinding()]
param(
    [string]$OutDir,
    [string]$CncDdrawDll = 'C:\sc-work\cnc-ddraw\v7.1.0.0\ddraw.dll',
    [string]$Version
)
$ErrorActionPreference = 'Stop'
$repoRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pluginDir = Join-Path $PSScriptRoot 'plugin'
$buildDir  = Join-Path $repoRoot 'work\scratch\plugin-build'
if (-not $OutDir)  { $OutDir = Join-Path $repoRoot 'work\scratch\release' }
if (-not $Version) { $Version = (& git -C $repoRoot describe --tags --always).Trim() }

foreach ($f in @((Join-Path $buildDir 'scplugin.dll'), (Join-Path $buildDir 'scinject.exe'), $CncDdrawDll)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "package: missing $f (run ./build.ps1 and ./setup-onetime.ps1 first)" }
}

$stage = Join-Path $OutDir 'starcraft-modded'
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $stage 'plugin\cnc-ddraw'), (Join-Path $stage 'game') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $buildDir 'scplugin.dll'), (Join-Path $buildDir 'scinject.exe') -Destination (Join-Path $stage 'plugin')
Copy-Item -LiteralPath $CncDdrawDll -Destination (Join-Path $stage 'plugin\cnc-ddraw\ddraw.dll')
Copy-Item -LiteralPath (Join-Path $pluginDir 'cnc-ddraw-release.ini') -Destination (Join-Path $stage 'plugin')
Copy-Item -LiteralPath (Join-Path $pluginDir 'Launch-StarCraft-Modded.cmd') -Destination $stage
Copy-Item -LiteralPath (Join-Path $pluginDir 'release-README.txt') -Destination (Join-Path $stage 'README.txt')
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination $stage
# An empty directory does not survive a zip; the placeholder keeps game\ visible.
Set-Content -LiteralPath (Join-Path $stage 'game\PUT-YOUR-STARCRAFT-1.16.1-FILES-HERE.txt') -Encoding ascii -Value @(
    'Copy the contents of your StarCraft: Brood War 1.16.1 folder into this folder:'
    'StarCraft.exe, storm.dll, the .mpq files, everything. A copy, not your only install.'
    'Then double-click Launch-StarCraft-Modded.cmd one level up.'
)

$zipPath = Join-Path $OutDir "starcraft-modded-$Version.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath

$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
try { $entries = @($zip.Entries | ForEach-Object { $_.FullName }) } finally { $zip.Dispose() }
foreach ($must in 'Launch-StarCraft-Modded.cmd', 'README.txt', 'plugin/scplugin.dll', 'plugin/scinject.exe',
                  'plugin/cnc-ddraw/ddraw.dll', 'plugin/cnc-ddraw-release.ini', 'game/PUT-YOUR-STARCRAFT-1.16.1-FILES-HERE.txt') {
    if ($entries -notcontains $must) { throw "package: $must missing from $zipPath (entries: $($entries -join ', '))" }
}
Write-Host "package: OK $zipPath ($([math]::Round((Get-Item -LiteralPath $zipPath).Length / 1KB)) KB, $($entries.Count) entries)"
