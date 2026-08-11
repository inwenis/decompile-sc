#Requires -Version 7
<#
Pester coverage for the ONE contract between run-with-plugin.ps1 and tools/deploy.ps1:
every helper run-with-plugin.ps1 dot-sources must also be copied into the deploy tree.

WHY THIS EXISTS (issue #30, 2026-08-11). The deployed install is deliberately
self-contained -- deploy.ps1 copies run-with-plugin.ps1 and each of its helpers into
<DeployRoot>\plugin so the user's game keeps working after every worktree on the machine
has been pruned (tools/deploy.ps1, "Design: self-contained, not a thin repo pointer").
That makes the copy list a hand-maintained mirror of a dot-source list, in a different
file, with nothing tying the two together -- and issue #30 added a helper to one of them.

The failure mode is the worst shape available: it is invisible in this repo (where every
file is present), invisible in CI (which never deploys), and lands on the USER, whose
double-clicked shortcut runs `pwsh -WindowStyle Hidden` and therefore fails with no
console to fail in. Exactly the regression class run-with-plugin.ps1's -NoLaunchLock note
already records shipping once.

So: parse the dot-sources out of run-with-plugin.ps1 and require each one in deploy.ps1's
copy list. Offline, no game, no toolchain.
#>

BeforeAll {
    $script:pluginDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/plugin'
    $script:runner    = Join-Path $script:pluginDir 'run-with-plugin.ps1'
    $script:deploy    = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/deploy.ps1'

    # `. (Join-Path $scriptDir 'sc-thing.ps1')` -> 'sc-thing.ps1'
    function Get-DotSourcedHelper {
        param([Parameter(Mandatory)][string]$Path)
        $text = Get-Content -Raw -LiteralPath $Path
        [regex]::Matches($text, "(?m)^\s*\.\s*\(Join-Path\s+\`$scriptDir\s+'([^']+)'\)") |
            ForEach-Object { $_.Groups[1].Value }
    }
}

Describe 'the deployed plugin runtime carries every dependency it dot-sources' {

    It 'finds the dot-sourced helpers at all (the parse itself is proved positive)' {
        # An empty match list would make every assertion below vacuously true -- the
        # absence-assertion rule in AGENTS.md, applied to a test's own input.
        $helpers = @(Get-DotSourcedHelper -Path $script:runner)
        $helpers.Count | Should -BeGreaterThan 2
        $helpers | Should -Contain 'sc-canonical-path.ps1'
    }

    It 'copies every helper run-with-plugin.ps1 dot-sources into <DeployRoot>\plugin' {
        $deployText = Get-Content -Raw -LiteralPath $script:deploy
        foreach ($h in @(Get-DotSourcedHelper -Path $script:runner)) {
            $copied = $deployText -match [regex]::Escape("Join-Path `$pluginDir '$h'")
            $copied | Should -BeTrue -Because "deploy.ps1 must Copy-Item $h, or the deployed launcher throws on a machine with no repo"
        }
    }

    It 'every dot-sourced helper actually exists on disk' {
        foreach ($h in @(Get-DotSourcedHelper -Path $script:runner)) {
            Test-Path -LiteralPath (Join-Path $script:pluginDir $h) |
                Should -BeTrue -Because "run-with-plugin.ps1 dot-sources $h"
        }
    }
}
