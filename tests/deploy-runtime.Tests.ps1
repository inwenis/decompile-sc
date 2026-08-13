#Requires -Version 7
<#
Pester coverage for the contracts between tools/deploy.ps1 and the rest of the repo:
(1) every helper run-with-plugin.ps1 dot-sources must also be copied into the deploy
tree, and (2) a redeploy must leave the feature-test map in place (task 067).

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

Describe 'a redeploy leaves the feature-test map in place (task 067)' {
    # tools/deploy.ps1 mirrors -SourceGameDir with /MIR, and !feature-test.scx is a
    # destination-only file -- so every redeploy purges it, and until task 067 the
    # user had to know to re-run the generator from a terminal. The fix regenerates
    # the map as deploy.ps1's last assembly step. These are static checks on the
    # script text (offline, no game, no toolchain -- same shape as the block above);
    # the live proof is an actual deploy run. Every one of them fails on the pre-067
    # deploy.ps1, so the coverage is not vacuous.

    BeforeAll {
        $script:deployText = Get-Content -Raw -LiteralPath $script:deploy
        # The literal invocation form in deploy.ps1's code -- NOT a bare
        # 'make-feature-test-map.ps1' match, which the header comment would satisfy
        # on its own (the absence-assertion rule: match the thing that does the work).
        $script:genInvocation = "& (Join-Path `$scriptDir 'make-feature-test-map.ps1')"
    }

    It 'deploy.ps1 actually invokes the feature-test map generator' {
        $script:deployText.Contains($script:genInvocation) |
            Should -BeTrue -Because 'without the regeneration step, /MIR deletes the map on every redeploy'
    }

    It 'pins the output into the deployed game tree, not the generator''s default' {
        # make-feature-test-map.ps1 DEFAULTS to the user's live install at
        # C:\sc-deploy\starcraft-modded; deploy.ps1 must pin -OutputPath under its own
        # $gameDeployDir or a -DeployRoot override would write the map into the wrong tree.
        $script:deployText.Contains("Join-Path `$gameDeployDir 'Maps\BroodWar\!feature-test.scx'") |
            Should -BeTrue -Because 'the map must land in THIS deploy''s game tree for any -DeployRoot'
    }

    It 'regenerates AFTER the mirror -- /MIR would purge a map generated before it' {
        $mirrorAt = $script:deployText.IndexOf('& robocopy @robocopyArgs')
        $genAt    = $script:deployText.IndexOf($script:genInvocation)
        $mirrorAt | Should -BeGreaterThan -1 -Because 'the mirror invocation itself must be findable for this ordering check to mean anything'
        $genAt    | Should -BeGreaterThan $mirrorAt -Because 'a map generated before /MIR runs is deleted by it'
    }

    It 'the verify step requires the map to exist AND to be from this run' {
        # Presence alone would pass on a stale leftover; deploy.ps1 checks freshness
        # the same way it does for the plugin binaries.
        $script:deployText.Contains('feature-test map missing after deploy') | Should -BeTrue
        $script:deployText.Contains('predates this deploy run -- the regeneration step did not actually write it') | Should -BeTrue
    }

    It 'the generator deploy.ps1 calls exists on disk' {
        Test-Path -LiteralPath (Join-Path (Split-Path $script:deploy -Parent) 'make-feature-test-map.ps1') |
            Should -BeTrue -Because 'deploy.ps1 invokes it by path at deploy time'
    }
}
