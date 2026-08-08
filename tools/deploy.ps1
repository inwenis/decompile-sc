#Requires -Version 7
<#
.SYNOPSIS
One-click deployed install of the modded StarCraft 1.16.1: builds the plugin from HEAD,
assembles a self-contained copy of the game + plugin at -DeployRoot, and creates/updates
a desktop shortcut that launches it windowed with the full feature set on -- no terminal,
no arguments.

.DESCRIPTION
Run this after every merge. It is idempotent: re-running overwrites the deployed version
cleanly (mirrors the game tree, overwrites the plugin binaries and launcher, re-saves the
shortcut).

What it does, in order:
  1. Guards -DeployRoot: refuses a target inside this repo, under C:\sc-install (hard
     rule: never write there), or under -SourceGameDir itself.
  2. Builds scplugin.dll + scinject.exe from the current checkout (tools/plugin/build.ps1
     -- already asserts both are PE32/x86 and fails the build otherwise).
  3. Mirrors -SourceGameDir (default the working copy, C:\sc-work\1161-base) into
     <DeployRoot>\game -- the same StarCraft.exe bytes, not a rebuild of anything.
  4. Copies the freshly built plugin binaries, plus run-with-plugin.ps1 and its
     check-game-windows.ps1 dependency, into <DeployRoot>\plugin -- so the deployed
     install does not depend on this repo (or this worktree, which is disposable)
     still existing on disk later. See "Design: self-contained, not a thin repo
     pointer" below.
  5. Writes <DeployRoot>\Launch-StarCraft-Modded.ps1, a launcher with zero parameters
     that calls the deployed copy of run-with-plugin.ps1 with the feature set baked in:
     -Mode fanout -InjectWindowedHelper WMode -Circles 1 -HudRow 1 (fanout + selection
     circles + HUD row paging, windowed). This is run-with-plugin.ps1's real working
     windowed recipe, not its deprecated/broken -Windowed switch -- see
     tools/plugin/README.md "Windowed mode: injected, not proxied".
  6. Creates/updates the desktop shortcut "StarCraft Modded.lnk", target
     "pwsh -WindowStyle Hidden -File <launcher>" so double-clicking shows the game and
     nothing else -- no console window.
  7. Verifies: deployed StarCraft.exe sha256 == source's, plugin DLL/EXE are newer than
     this run's start (proof they were actually rebuilt, not stale leftovers), the
     shortcut resolves to an existing target and launcher. Prints a one-line receipt.

Design: self-contained, not a thin repo pointer.
tools/plugin/run-with-plugin.ps1 already does everything the launcher needs (pristine-
install guard, injection, windowed helper, dialog health check) -- reimplementing that
here would be pure duplication risk for zero benefit. The question was only whether the
deployed launcher should call this repo's copy in place, or its own copy. A thin pointer
into the repo is fragile for this project specifically: worker worktrees (including the
one this task was built in) are disposable and get pruned after merge (AGENTS.md
"Conventions"), so a launcher baked with a worktree path would break the day its worktree
is cleaned up. Copying run-with-plugin.ps1 + check-game-windows.ps1 into the deploy tree
avoids that: the deployed install has everything it needs under one root and keeps
working even if every git worktree on the machine is deleted. The cost is that a deployed
install goes stale until the next ./tools/deploy.ps1 -- identical to how the plugin
binaries themselves already work, so it is not a new kind of staleness.

.PARAMETER DeployRoot
Where the self-contained install is assembled. Must not be inside this repo, under
C:\sc-install, or under -SourceGameDir.

.PARAMETER SourceGameDir
The pristine-verified working copy to deploy from. Never C:\sc-install (hard rule 1).

.PARAMETER ShortcutName
File name of the desktop shortcut.

.EXAMPLE
./tools/deploy.ps1
#>
[CmdletBinding()]
param(
    [string]$DeployRoot = 'C:\sc-deploy\starcraft-modded',
    [string]$SourceGameDir = 'C:\sc-work\1161-base',
    [string]$ShortcutName = 'StarCraft Modded.lnk'
)

$ErrorActionPreference = 'Stop'
$deployStart = Get-Date

$scriptDir = $PSScriptRoot
$repoRoot  = (Resolve-Path (Join-Path $scriptDir '..')).Path
$pluginDir = Join-Path $scriptDir 'plugin'

# --- guard: refuse a dangerous -DeployRoot ----------------------------------
# Simple GetFullPath prefix checks are enough here (unlike run-with-plugin.ps1's
# device-prefix/8.3/junction-proof canonicalisation): DeployRoot is a fresh
# directory of our own making, not an existing tree we copy into/delete from
# based on a spoofable spelling. What matters is catching an honest mistake --
# a typo'd -DeployRoot landing inside the repo or under C:\sc-install.
function Get-SimpleFullPath {
    param([string]$Path)
    [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Test-UnderOrEqual {
    param([string]$Candidate, [string]$Root)
    $c = Get-SimpleFullPath $Candidate
    $r = Get-SimpleFullPath $Root
    return ($c -ieq $r) -or $c.StartsWith("$r\", [StringComparison]::OrdinalIgnoreCase)
}

$deployRootFull = Get-SimpleFullPath $DeployRoot
foreach ($protected in @(
    @{ Path = $repoRoot;       Label = 'this repo' }
    @{ Path = 'C:\sc-install'; Label = 'the pristine install (hard rule 1)' }
    @{ Path = $SourceGameDir;  Label = '-SourceGameDir itself' }
)) {
    if (Test-UnderOrEqual -Candidate $deployRootFull -Root $protected.Path) {
        throw "deploy: refusing -DeployRoot '$deployRootFull' -- it is inside/under $($protected.Label) ('$($protected.Path)')."
    }
}

if (-not (Test-Path -LiteralPath $SourceGameDir)) {
    throw "deploy: -SourceGameDir not found: $SourceGameDir (create it with tools/make-working-copy.ps1)"
}
$sourceExe = Join-Path $SourceGameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $sourceExe)) {
    throw "deploy: $sourceExe not found -- is -SourceGameDir a real working copy?"
}

# --- version receipt ---------------------------------------------------------
$gitSha = (& git -C $repoRoot rev-parse --short HEAD).Trim()
$dirty  = [bool](& git -C $repoRoot status --porcelain)
if ($dirty) {
    Write-Warning 'deploy: working tree has uncommitted changes -- deploying whatever is on disk, not a clean HEAD checkout.'
}
$version = "$gitSha$(if ($dirty) { '+dirty' })"
$dateStamp = $deployStart.ToString('yyyy-MM-dd')

Write-Host "deploy: version=$version date=$dateStamp"
Write-Host "deploy: source game dir  $SourceGameDir"
Write-Host "deploy: deploy root      $deployRootFull"

# --- 1. build the plugin from HEAD -------------------------------------------
Write-Host ''
Write-Host '== Building plugin from current checkout =='
& (Join-Path $scriptDir 'plugin\build.ps1') | Write-Host
if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "deploy: plugin build failed (exit $LASTEXITCODE)" }

$builtDll = Join-Path $repoRoot 'work\scratch\plugin-build\scplugin.dll'
$builtExe = Join-Path $repoRoot 'work\scratch\plugin-build\scinject.exe'
foreach ($f in @($builtDll, $builtExe)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "deploy: expected build output missing: $f" }
    if ((Get-Item -LiteralPath $f).LastWriteTime -lt $deployStart) {
        throw "deploy: $f is older than this deploy run -- build did not actually refresh it."
    }
}
Write-Host 'build: OK, both artifacts newer than this deploy run'

# --- 2. mirror the game tree --------------------------------------------------
Write-Host ''
Write-Host "== Mirroring $SourceGameDir -> $deployRootFull\game =="
$gameDeployDir = Join-Path $deployRootFull 'game'
New-Item -ItemType Directory -Path $deployRootFull -Force | Out-Null
$robocopyArgs = @(
    $SourceGameDir, $gameDeployDir,
    '/MIR',         # deploy dir is ours alone; a true mirror is what keeps re-runs idempotent
    '/COPY:DAT', '/R:2', '/W:2', '/NFL', '/NDL', '/NP'
)
& robocopy @robocopyArgs | Out-Host
if ($LASTEXITCODE -ge 8) { throw "deploy: robocopy failed with exit code $LASTEXITCODE" }
Write-Host "robocopy exit code $LASTEXITCODE (success)"

# --- 3. copy the plugin runtime (self-contained, see .DESCRIPTION) -----------
Write-Host ''
Write-Host "== Assembling plugin runtime -> $deployRootFull\plugin =="
$pluginDeployDir = Join-Path $deployRootFull 'plugin'
New-Item -ItemType Directory -Path $pluginDeployDir -Force | Out-Null
Copy-Item -LiteralPath $builtDll -Destination (Join-Path $pluginDeployDir 'scplugin.dll') -Force
Copy-Item -LiteralPath $builtExe -Destination (Join-Path $pluginDeployDir 'scinject.exe') -Force
Copy-Item -LiteralPath (Join-Path $pluginDir 'run-with-plugin.ps1')     -Destination (Join-Path $pluginDeployDir 'run-with-plugin.ps1')     -Force
Copy-Item -LiteralPath (Join-Path $pluginDir 'check-game-windows.ps1') -Destination (Join-Path $pluginDeployDir 'check-game-windows.ps1') -Force
Write-Host 'plugin runtime copied: scplugin.dll, scinject.exe, run-with-plugin.ps1, check-game-windows.ps1'

# --- 4. write the zero-argument launcher --------------------------------------
$launcherPath = Join-Path $deployRootFull 'Launch-StarCraft-Modded.ps1'
$launcherBody = @'
#Requires -Version 7
<#
Deployed launcher -- no arguments. Generated by tools/deploy.ps1; re-run that to refresh
this file rather than editing it by hand. Baked feature set: fan-out + selection circles
+ HUD row paging, windowed. See tools/README-deploy.md for the debug/off-switch one-liner.
#>
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
& (Join-Path $here 'plugin\run-with-plugin.ps1') `
    -GameDir  (Join-Path $here 'game') `
    -BuildDir (Join-Path $here 'plugin') `
    -LogPath  (Join-Path $here 'logs\sc-plugin.log') `
    -Mode fanout `
    -InjectWindowedHelper WMode `
    -Circles 1 `
    -HudRow 1
'@
Set-Content -LiteralPath $launcherPath -Value $launcherBody -Encoding utf8NoBOM
Write-Host ''
Write-Host "launcher written: $launcherPath"

# --- 5. desktop shortcut -------------------------------------------------------
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop $ShortcutName
$pwshExe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
if (-not $pwshExe) { $pwshExe = Join-Path $PSHOME 'pwsh.exe' }
if (-not (Test-Path -LiteralPath $pwshExe)) { throw "deploy: could not resolve pwsh.exe (looked at $pwshExe)" }

$deployedExe = Join-Path $gameDeployDir 'StarCraft.exe'
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($shortcutPath)
$lnk.TargetPath = $pwshExe
$lnk.Arguments = "-WindowStyle Hidden -File `"$launcherPath`""
$lnk.WorkingDirectory = $deployRootFull
$lnk.IconLocation = "$deployedExe,0"
$lnk.Description = 'StarCraft 1.16.1, modded (fan-out select-past-12 + circles + HUD row), windowed'
$lnk.Save()
Write-Host "shortcut written: $shortcutPath"

# --- 6. verify -------------------------------------------------------------
Write-Host ''
Write-Host '== Verifying =='

$srcHash = (Get-FileHash -LiteralPath $sourceExe -Algorithm SHA256).Hash
$dstHash = (Get-FileHash -LiteralPath $deployedExe -Algorithm SHA256).Hash
if ($srcHash -ne $dstHash) {
    throw "deploy: deployed StarCraft.exe hash MISMATCH`n  source:   $srcHash`n  deployed: $dstHash"
}
Write-Host "verify: StarCraft.exe sha256 OK ($dstHash)"

foreach ($f in @((Join-Path $pluginDeployDir 'scplugin.dll'), (Join-Path $pluginDeployDir 'scinject.exe'))) {
    if ((Get-Item -LiteralPath $f).LastWriteTime -lt $deployStart) {
        throw "deploy: $f predates this deploy run -- not freshly built."
    }
}
Write-Host 'verify: plugin binaries are freshly built from this run'

if (-not (Test-Path -LiteralPath $shortcutPath)) { throw "deploy: shortcut was not written: $shortcutPath" }
$resolved = $shell.CreateShortcut($shortcutPath)
if ($resolved.TargetPath -ne $pwshExe) { throw "deploy: shortcut target mismatch: $($resolved.TargetPath)" }
if ($resolved.Arguments -notmatch [Regex]::Escape($launcherPath)) { throw "deploy: shortcut arguments do not reference the launcher: $($resolved.Arguments)" }
if (-not (Test-Path -LiteralPath $launcherPath)) { throw "deploy: shortcut points at a launcher that does not exist: $launcherPath" }
Write-Host "verify: shortcut resolves ($shortcutPath -> $pwshExe $($resolved.Arguments))"

Write-Host ''
Write-Host "deploy: OK  version=$version  date=$dateStamp  -> $deployRootFull"
Write-Host "deploy: shortcut -> $shortcutPath"
exit 0
