#Requires -Version 7
<#
.SYNOPSIS
Launch the Agent Console board against this repo.

.DESCRIPTION
Delegates to the conductor repo's launcher with -Repo pointed here:

    C:/git/conductor/run.ps1 -Repo C:/git/decompile-sc

This is a READ of C:/git/conductor (build + serve of ITS product code); it
does not write into that repo. The Agent Console UI is the only genuinely
repo-agnostic part of the conductor system — scripts/config are ported and
adapted per repo, but the UI serves any repo handed to it via -Repo.
#>
$ErrorActionPreference = 'Stop'

$conductorRun = 'C:/git/conductor/run.ps1'
if (-not (Test-Path -LiteralPath $conductorRun)) {
    throw "run: $conductorRun not found — the Agent Console launcher lives in the conductor repo."
}

& $conductorRun -Repo $PSScriptRoot
