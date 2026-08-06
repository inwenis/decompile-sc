#Requires -Version 7
<#
.SYNOPSIS
Launch the Agent Console board against this repo.

.DESCRIPTION
Delegates to the conductor repo's launcher with -Repo pointed here:

    C:/git/conductor/run.ps1 -Repo C:/git/decompile-sc

The conductor's run.ps1 (and the build.ps1 it may trigger) resolves npm's
package.json from the CALLER's cwd, so this wrapper Push-Locations into
C:/git/conductor for the duration of the call — no human or agent ever needs
to cd there by hand (that repo is a LIVE system; see AGENTS.md hard rule 5).
The launch builds/serves inside C:/git/conductor: on a missing dist/ it runs
`npm run build` there, writing that repo's OWN dist/dist-server build dirs —
it never touches its orchestration data, and it never writes into decompile-sc
beyond serving the console for it. This script is intended to be run by the
USER; agents in this repo never invoke anything under C:/git/conductor.
#>
$ErrorActionPreference = 'Stop'

$conductorRepo = 'C:/git/conductor'
$conductorRun = "$conductorRepo/run.ps1"
if (-not (Test-Path -LiteralPath $conductorRun)) {
    throw "run: $conductorRun not found — the Agent Console launcher lives in the conductor repo."
}

$repoHere = $PSScriptRoot
Push-Location $conductorRepo
try { & $conductorRun -Repo $repoHere }
finally { Pop-Location }
