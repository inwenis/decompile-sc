#Requires -Version 7
<#
.SYNOPSIS
Launch StarCraft 1.16.1 from the disposable working copy with the task-008
read-only observer plugin injected.

.DESCRIPTION
The plugin is injected by scinject.exe (CreateProcess + CreateRemoteThread ->
LoadLibraryA). NOTHING is copied into the game directory by the plugin itself,
so "uninstall" is simply "launch StarCraft.exe directly instead of through this
script" -- see tools/plugin/README.md.

-Windowed is the separate, pre-existing windowed-mode recipe from
research/launch-baseline.md (WMode.dll copied in as ddraw.dll). It is the ONE
thing that does write into the game directory; -RemoveWindowed undoes it, and
tools/make-working-copy.ps1 -Force also purges it.

Hard rules this script respects: it only ever touches the working copy
(default C:\sc-work\1161-base), never C:\sc-install\Starcraft; and the log goes
to a path outside the repo (C:/sc-work/ is gitignored).

.EXAMPLE
./tools/plugin/run-with-plugin.ps1 -Build -Windowed

.EXAMPLE
./tools/plugin/run-with-plugin.ps1 -RemoveWindowed -NoLaunch
#>
[CmdletBinding()]
param(
    [string]$GameDir  = 'C:\sc-work\1161-base',
    [string]$BuildDir,
    [string]$LogPath  = 'C:\sc-work\logs\sc-plugin.log',
    [int]$PollMs      = 250,
    [int]$SettleMs    = 4000,
    [switch]$Build,
    [switch]$Windowed,
    [ValidateSet('none', 'WMode', 'WMode_Fix', 'both')]
    [string]$InjectWindowedHelper = 'none',
    [switch]$RemoveWindowed,
    [switch]$NoLaunch,
    [switch]$WaitForExit
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot  = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path

if ($GameDir -match '^\s*C:\\sc-install') {
    throw "run-with-plugin: refusing to touch the pristine install ($GameDir). Use the working copy."
}
if (-not (Test-Path -LiteralPath $GameDir)) {
    throw "run-with-plugin: game dir not found: $GameDir (create it with tools/make-working-copy.ps1)"
}

$ddraw = Join-Path $GameDir 'ddraw.dll'

if ($RemoveWindowed) {
    if (Test-Path -LiteralPath $ddraw) {
        Remove-Item -LiteralPath $ddraw -Force
        Write-Host "run-with-plugin: removed $ddraw (windowed-mode shim)"
    }
    else { Write-Host "run-with-plugin: no $ddraw present, nothing to remove" }
}

if ($Build) { & (Join-Path $scriptDir 'build.ps1') | Write-Host }

if (-not $BuildDir) { $BuildDir = Join-Path $repoRoot 'work/scratch/plugin-build' }
$dll = Join-Path $BuildDir 'scplugin.dll'
$inj = Join-Path $BuildDir 'scinject.exe'
foreach ($f in @($dll, $inj)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "run-with-plugin: missing $f -- run ./tools/plugin/build.ps1 first (or pass -Build)." }
}

if ($Windowed) {
    $wmode = Join-Path $GameDir 'WMode.dll'
    if (-not (Test-Path -LiteralPath $wmode)) { throw "run-with-plugin: $wmode not found; cannot enable windowed mode." }
    Copy-Item -LiteralPath $wmode -Destination $ddraw -Force
    Write-Host "run-with-plugin: windowed shim installed ($ddraw <- WMode.dll)"
}

if ($NoLaunch) { Write-Host 'run-with-plugin: -NoLaunch given, done.'; return }

$exe = Join-Path $GameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw "run-with-plugin: $exe not found" }

New-Item -ItemType Directory -Path (Split-Path $LogPath -Parent) -Force | Out-Null
$env:SCPLUGIN_LOG     = $LogPath
$env:SCPLUGIN_POLL_MS = "$PollMs"

Write-Host "run-with-plugin: log -> $LogPath (poll ${PollMs}ms)"

$injArgs = @($exe, $dll, '--wait-ms', "$SettleMs")

# The windowed-mode helpers have no export table, so they cannot be a ddraw proxy;
# they are injectable hook DLLs and must be in place before DirectDraw initialises.
# Hence --early-dll (injected while the process is still suspended).
if ($InjectWindowedHelper -ne 'none') {
    $helpers = switch ($InjectWindowedHelper) {
        'WMode'     { @('WMode.dll') }
        'WMode_Fix' { @('WMode_Fix.dll') }
        'both'      { @('WMode.dll', 'WMode_Fix.dll') }
    }
    foreach ($h in $helpers) {
        $hp = Join-Path $GameDir $h
        if (-not (Test-Path -LiteralPath $hp)) { throw "run-with-plugin: $hp not found" }
        $injArgs += @('--early-dll', $hp)
        Write-Host "run-with-plugin: will early-inject $hp"
    }
}

if (-not $WaitForExit) { $injArgs += '--no-wait-exit' }

& $inj @injArgs
$rc = $LASTEXITCODE
Write-Host "run-with-plugin: scinject exit=$rc"
if ($rc -ne 0) { throw "run-with-plugin: injection failed (exit $rc)" }

if (-not $WaitForExit) {
    # A launch can fail with the process still alive and a modal DirectDraw error
    # box on screen -- invisible to exit codes. Check from outside the process.
    Start-Sleep -Seconds 2
    & (Join-Path $scriptDir 'check-game-windows.ps1')
    if ($LASTEXITCODE -eq 1) {
        throw 'run-with-plugin: the game has an error dialog open — the launch is NOT healthy.'
    }
}
