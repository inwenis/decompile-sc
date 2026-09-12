#Requires -Version 7
<#
Pester coverage for the contracts between tools/deploy.ps1 and the rest of the repo:
every helper run-with-plugin.ps1 dot-sources is also copied into the deploy tree, a
redeploy leaves the feature-test map in place, and the one launcher ships the wide
geometry. Offline: no game, no toolchain.

The deployed install is self-contained -- deploy.ps1 copies run-with-plugin.ps1 and each
of its helpers into <DeployRoot>\plugin so the user's game keeps working after every
worktree on the machine has been pruned. The copy list is therefore a hand-maintained
mirror of a dot-source list in another file, with nothing tying the two together.

A helper missing from that mirror is invisible in this repo (every file is present),
invisible in CI (which never deploys), and lands on the user, whose double-clicked
shortcut runs `pwsh -WindowStyle Hidden` and so fails with no console to fail in.
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
        # An empty match list makes every assertion below vacuously true -- AGENTS.md
        # § "Oracles: absence and defect-era checks", applied to a test's own input.
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
    # tools/deploy.ps1 mirrors -SourceGameDir with /MIR and !feature-test.scx is a
    # destination-only file, so every redeploy purges it unless deploy.ps1 regenerates
    # the map as its last assembly step. These are static checks on the script text;
    # the live proof is an actual deploy run. Each check fails against a deploy.ps1
    # without the regeneration step, so the coverage is not vacuous.

    BeforeAll {
        $script:deployText = Get-Content -Raw -LiteralPath $script:deploy
        # The literal invocation form in deploy.ps1's code: a bare
        # 'make-feature-test-map.ps1' match is satisfied by its header comment alone.
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
        # Presence alone passes on a stale leftover, so deploy.ps1 checks freshness the
        # same way it does for the plugin binaries.
        $script:deployText.Contains('feature-test map missing after deploy') | Should -BeTrue
        $script:deployText.Contains('predates this deploy run -- the regeneration step did not actually write it') | Should -BeTrue
    }

    It 'the generator deploy.ps1 calls exists on disk' {
        Test-Path -LiteralPath (Join-Path (Split-Path $script:deploy -Parent) 'make-feature-test-map.ps1') |
            Should -BeTrue -Because 'deploy.ps1 invokes it by path at deploy time'
    }
}

Describe 'the one launcher ships the wide geometry at 2x (one shortcut, 2026-09-06)' {
    # The deploy ships ONE launcher and one shortcut, and it carries the extended
    # viewport; a separate "Wide" launcher off by default is the shape these checks
    # forbid, and each fails against a two-launcher deploy.ps1, so none is vacuous.

    BeforeAll {
        $script:deployText = Get-Content -Raw -LiteralPath $script:deploy
        $lb = [regex]::Match($script:deployText, "(?s)\`$launcherBody = @'(.*?)'@")
        $script:launcher = $lb.Success ? $lb.Groups[1].Value : ''
    }

    It 'the launcher body is findable (the parse itself is proved positive)' {
        $script:launcher.Length | Should -BeGreaterThan 100
    }

    It 'there is exactly ONE launcher body and no wide launcher left' {
        ([regex]::Matches($script:deployText, "(?m)^\`$\w*[lL]auncherBody = @'")).Count | Should -Be 1
        $script:deployText | Should -Not -Match 'wideLauncherBody'
        $script:deployText | Should -Not -Match 'WideShortcutName'
    }

    It 'the launcher turns the assembled widescreen on: stage 3 + storm widen + cnc-ddraw' {
        $script:launcher | Should -Match '-Widescreen 1'
        $script:launcher | Should -Match '-WidescreenStage 3'
        # The ARGUMENT lines -- stage, geometry and storm, each backtick-continued -- not
        # the launcher's own header comment, which also says "-StormPresent widen" and so
        # satisfies a plain substring match.
        $script:launcher | Should -Match '-WidescreenStage 3 `\s*\r?\n\s*-Geometry __GEOMETRY__ `\s*\r?\n\s*-StormPresent widen `' -Because 'issue #113: run-with-plugin.ps1 exported its old default 0 verbatim, so the DLL auto-arm never fired and the deployed wide game showed a black right band; the launcher must pass the buffer->glass copy as an argument'
        # The template carries a placeholder; deploy fills it from -Geometry before writing.
        $script:deployText.Contains('.Replace(''__GEOMETRY__'', $Geometry)') | Should -BeTrue -Because 'the launcher must name the preset the 2x ini was generated for'
        $script:launcher | Should -Match 'cnc-ddraw\\ddraw\.dll'
        $script:launcher | Should -Not -Match 'InjectWindowedHelper' -Because 'WMode presents 640 columns whatever it is asked; the wide path must use the cnc-ddraw proxy'
    }

    It 'the launcher keeps the full feature set (it is the same game, wider)' {
        foreach ($flag in '-Mode fanout', '-Sound', '-NoLaunchLock', '-NoForegroundRestore',
                          '-Circles 1', '-HudRow 1', '-ProdQueue 1', '-ProdFan 1',
                          '-UpgradeQueue 1', '-QueueIndicator 1', '-MenuCentre 1') {
            $script:launcher.Contains($flag) | Should -BeTrue -Because "the launcher must not silently drop $flag"
        }
    }

    It 'the launcher presents through cnc-ddraw with the 2x/lock ini, generated at 2x the plugin geometry' {
        $script:launcher | Should -Match 'cnc-ddraw-2x\.ini'
        # The ini is the committed file with width/height rewritten to 2x the preset's screen.
        $script:deployText.Contains('Get-ScWideGeometry -Geometry $Geometry') | Should -BeTrue -Because 'the ini must be sized from the preset the launcher names'
        $script:deployText | Should -Match '\^width=\\d\+'
        $script:deployText.Contains('does not carry width=') | Should -BeTrue -Because 'the verify step must read the ini that actually shipped'
    }

    It 'the geometry reader deploy and the suites share resolves every preset the DLL lists' {
        . (Join-Path $script:pluginDir 'sc-geometry.ps1')
        $listed = Get-Content -Raw -LiteralPath (Join-Path $script:pluginDir 'src/sc_screen_presets.h')
        $names = @([regex]::Matches($listed, '&SC_WS_GEOM_(\d+x\d+)') | ForEach-Object { $_.Groups[1].Value })
        $names.Count | Should -BeGreaterThan 0 -Because 'an empty list would pass every check below unexamined'
        foreach ($n in $names) {
            $g = Get-ScWideGeometry -Geometry $n
            "$($g.W)x$($g.H)" | Should -Be $n -Because "the $n table's own SC_WS_SCREEN_W/H"
            "$($g.StockW)x$($g.StockH)" | Should -Be '640x480' -Because 'the stock screen, from the hand-written record header'
        }
        { Get-ScWideGeometry -Geometry '1280x800' } | Should -Throw '*presets: *1280x880*'
    }

    It 'falls back to borderless full screen when 2x does not fit the primary monitor (the 2x-height step)' {
        # 1280x880 x2 = 2560x1760 does not fit a 1920x1080 monitor, so deploy flips the
        # ini to cnc-ddraw borderless (fullscreen=true) with the aspect kept (maintas),
        # rather than a window bigger than the screen.
        $script:deployText | Should -Match 'PrimaryScreen'
        $script:deployText | Should -Match '\$fits2x'
        $script:deployText | Should -Match "fullscreen=false', 'fullscreen=true'"
        $script:deployText | Should -Match 'maintas=true'
        $script:deployText | Should -Match 'must be borderless' -Because 'the verify step must confirm the fallback actually shipped'
    }

    It 'a leftover Wide launcher and shortcut from an earlier deploy are removed' {
        $script:deployText.Contains("Launch-StarCraft-Modded-Wide.ps1") | Should -BeTrue
        $script:deployText.Contains("StarCraft Modded (Wide).lnk") | Should -BeTrue
        $script:deployText | Should -Match 'Remove-Item -LiteralPath \$staleWideShortcut'
    }

    It 'deploy stages cnc-ddraw only through its own sha256 pin' {
        $script:deployText | Should -Match '\$CNC_DDRAW_DLL_SHA256\s*=\s*''[0-9a-f]{64}'''
        $script:deployText.Contains('cnc-ddraw ddraw.dll SHA256 MISMATCH') |
            Should -BeTrue -Because 'an unvouched helper DLL must be a hard stop, not a warning'
        $script:deployText.Contains('staged cnc-ddraw hash mismatch after copy') |
            Should -BeTrue -Because 'the verify step must re-check the copy that actually shipped'
    }

    It 'deploy copies cnc-ddraw.ini beside the deployed run-with-plugin.ps1' {
        # run-with-plugin.ps1 reads cnc-ddraw.ini from ITS OWN directory; in the
        # deploy tree that is plugin\, or the helper runs unconfigured.
        $script:deployText.Contains("Join-Path `$pluginDeployDir 'cnc-ddraw.ini'") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:pluginDir 'cnc-ddraw.ini') |
            Should -BeTrue -Because 'deploy copies it from tools/plugin at deploy time'
    }

    It 'the card deploy copies exists on disk and mentions the one action' {
        $card = Join-Path (Split-Path $script:deploy -Parent) 'widescreen-card.md'
        Test-Path -LiteralPath $card | Should -BeTrue
        (Get-Content -Raw -LiteralPath $card) | Should -Match 'double-click \*\*StarCraft Modded\*\*'
    }

    It '-NoShortcut skips the desktop entirely (scratch deploys must not touch it)' {
        $script:deployText.Contains('shortcuts SKIPPED (-NoShortcut)') | Should -BeTrue
        $gateAt = $script:deployText.IndexOf('if ($NoShortcut) {')
        $lnkAt = $script:deployText.IndexOf('$lnk.Save()')
        $staleAt = $script:deployText.IndexOf('$staleWideShortcut = ')
        $gateAt | Should -BeGreaterThan -1
        $lnkAt | Should -BeGreaterThan $gateAt -Because 'the shortcut write must sit behind the -NoShortcut gate'
        $staleAt | Should -BeGreaterThan $gateAt -Because 'a scratch deploy must not delete anything on the desktop either'
    }
}
