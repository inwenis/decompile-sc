#Requires -Version 7
<#
Pester coverage for the contracts between tools/deploy.ps1, tools/package-release.ps1,
tools/plugin/sc-stage-runtime.ps1 and the rest of the repo: every helper
run-with-plugin.ps1 dot-sources is also staged, a redeploy leaves the feature-test map in
place, both installs stage through the one function, and the one launcher ships the wide
geometry. Offline: no game, no toolchain.

The staged install is self-contained -- sc-stage-runtime.ps1 copies run-with-plugin.ps1
and each of its helpers into <Dest>\plugin so the user's game keeps working after every
worktree on the machine has been pruned, and a player with only the zip has no repo at
all. The copy list is therefore a hand-maintained mirror of a dot-source list in another
file, with nothing tying the two together.

A helper missing from that mirror is invisible in this repo (every file is present),
invisible in CI (which never deploys), and lands on the user, whose double-clicked
shortcut runs `pwsh -WindowStyle Hidden` and so fails with no console to fail in.
#>

BeforeAll {
    $script:root      = Split-Path $PSScriptRoot -Parent
    $script:pluginDir = Join-Path $script:root 'tools/plugin'
    $script:runner    = Join-Path $script:pluginDir 'run-with-plugin.ps1'
    $script:deploy    = Join-Path $script:root 'tools/deploy.ps1'
    $script:package   = Join-Path $script:root 'tools/package-release.ps1'
    $script:stage     = Join-Path $script:pluginDir 'sc-stage-runtime.ps1'
    $script:launcherFile = Join-Path $script:pluginDir 'Launch-StarCraft-Modded.ps1'

    # `. (Join-Path $scriptDir 'sc-thing.ps1')` -> 'sc-thing.ps1'
    function Get-DotSourcedHelper {
        param([Parameter(Mandatory)][string]$Path)
        $text = Get-Content -Raw -LiteralPath $Path
        [regex]::Matches($text, "(?m)^\s*\.\s*\(Join-Path\s+\`$scriptDir\s+'([^']+)'\)") |
            ForEach-Object { $_.Groups[1].Value }
    }

    # The `$SC_RUNTIME_SCRIPTS = @( ... )` list in sc-stage-runtime.ps1, as names.
    function Get-StagedScript {
        $text = Get-Content -Raw -LiteralPath $script:stage
        $m = [regex]::Match($text, '(?s)\$SC_RUNTIME_SCRIPTS\s*=\s*@\((.*?)\)')
        if (-not $m.Success) { return @() }
        [regex]::Matches($m.Groups[1].Value, "'([^']+\.ps1)'") | ForEach-Object { $_.Groups[1].Value }
    }
}

Describe 'the staged plugin runtime carries every dependency it dot-sources' {

    It 'finds the dot-sourced helpers at all (the parse itself is proved positive)' {
        # An empty match list makes every assertion below vacuously true -- AGENTS.md
        # § "Oracles: absence and defect-era checks", applied to a test's own input.
        $helpers = @(Get-DotSourcedHelper -Path $script:runner)
        $helpers.Count | Should -BeGreaterThan 2
        $helpers | Should -Contain 'sc-canonical-path.ps1'
        $staged = @(Get-StagedScript)
        $staged.Count | Should -BeGreaterThan 2
        $staged | Should -Contain 'run-with-plugin.ps1'
    }

    It 'stages every helper run-with-plugin.ps1 dot-sources into <Dest>\plugin' {
        $staged = @(Get-StagedScript)
        foreach ($h in @(Get-DotSourcedHelper -Path $script:runner)) {
            $staged | Should -Contain $h -Because "sc-stage-runtime.ps1 must copy $h, or the launcher throws on a machine with no repo"
        }
    }

    It 'every dot-sourced helper actually exists on disk' {
        foreach ($h in @(Get-DotSourcedHelper -Path $script:runner)) {
            Test-Path -LiteralPath (Join-Path $script:pluginDir $h) |
                Should -BeTrue -Because "run-with-plugin.ps1 dot-sources $h"
        }
    }

    It 'deploy.ps1 and package-release.ps1 both stage and verify through the one function' {
        foreach ($f in $script:deploy, $script:package) {
            $t = Get-Content -Raw -LiteralPath $f
            $t | Should -Match "sc-stage-runtime\.ps1" -Because "$f must dot-source the stage file"
            $t | Should -Match 'Publish-ScPluginRuntime -Dest' -Because "$f must stage through the shared function"
            $t | Should -Match 'Test-ScPluginRuntime -Dest' -Because "$f must re-check what it staged"
        }
        # Two copies of the staging steps would drift; the deploy has none of its own left.
        $d = Get-Content -Raw -LiteralPath $script:deploy
        $d | Should -Not -Match 'launcherBody'
        $d | Should -Not -Match 'CNC_DDRAW_DLL_SHA256\s*='
    }
}

Describe 'a redeploy leaves the feature-test map in place' {
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

Describe 'the one launcher ships the wide geometry at 2x' {
    # ONE launcher and one shortcut, carrying the extended viewport; a separate "Wide"
    # launcher off by default is the shape these checks forbid, and each fails against a
    # two-launcher tree, so none is vacuous.

    BeforeAll {
        $script:deployText = Get-Content -Raw -LiteralPath $script:deploy
        $script:stageText  = Get-Content -Raw -LiteralPath $script:stage
        $script:launcher   = (Test-Path -LiteralPath $script:launcherFile) ? (Get-Content -Raw -LiteralPath $script:launcherFile) : ''
    }

    It 'the launcher file exists and is staged (the parse itself is proved positive)' {
        $script:launcher.Length | Should -BeGreaterThan 100
        $script:stageText | Should -Match "'Launch-StarCraft-Modded\.ps1', 'Launch-StarCraft-Modded\.cmd'"
        Test-Path -LiteralPath (Join-Path $script:pluginDir 'Launch-StarCraft-Modded.cmd') | Should -BeTrue
    }

    It 'there is exactly ONE launcher and no wide launcher left' {
        $script:deployText | Should -Not -Match 'wideLauncherBody'
        $script:deployText | Should -Not -Match 'WideShortcutName'
        Test-Path -LiteralPath (Join-Path $script:pluginDir 'Launch-StarCraft-Modded-Wide.ps1') | Should -BeFalse
    }

    It 'the launcher turns the assembled widescreen on: stage 3 + storm widen + cnc-ddraw' {
        $script:launcher | Should -Match '-Widescreen 1'
        $script:launcher | Should -Match '-WidescreenStage 3'
        # The ARGUMENT lines -- stage and storm, each backtick-continued -- not the
        # launcher's own header comment, which also says "-StormPresent widen" and so
        # satisfies a plain substring match.
        $script:launcher | Should -Match '-WidescreenStage 3 `\s*\r?\n\s*-StormPresent widen `' -Because 'run-with-plugin.ps1 exports its default 0 verbatim, so the DLL auto-arm never fires and the wide game shows a black right band; the launcher must pass the buffer->glass copy as an argument'
        $script:launcher | Should -Match 'cnc-ddraw\\ddraw\.dll'
        $script:launcher | Should -Not -Match 'InjectWindowedHelper' -Because 'WMode presents 640 columns whatever it is asked; the wide path must use the cnc-ddraw proxy'
    }

    It 'the launcher keeps the full feature set (it is the same game, wider)' {
        foreach ($flag in '-Mode fanout', '-Sound', '-NoLaunchLock', '-NoForegroundRestore',
                          '-Circles 1', '-HudRow 1', '-ProdQueue 1', '-ProdFan 1',
                          '-UpgradeQueue 1', '-QueueIndicator 1') {
            $script:launcher.Contains($flag) | Should -BeTrue -Because "the launcher must not silently drop $flag"
        }
    }

    It 'the launcher refuses a game that is not the 1.16.1 the plugin was derived from' {
        # The pin is make-working-copy.ps1's; the launcher must carry the same bytes.
        $wc = Get-Content -Raw -LiteralPath (Join-Path $script:root 'tools/make-working-copy.ps1')
        $m = [regex]::Match($wc, "'StarCraft\.exe'\s*=\s*'([0-9A-F]{64})'")
        $m.Success | Should -BeTrue -Because 'the working-copy fingerprint is the reference'
        $script:launcher.Contains($m.Groups[1].Value) | Should -BeTrue -Because 'a wrong build would be patched in the wrong places'
        $script:launcher | Should -Match 'Get-FileHash -LiteralPath \$exe'
    }

    It 'the launcher presents through cnc-ddraw with the 2x/lock ini, generated at 2x the plugin geometry' {
        $script:launcher | Should -Match 'cnc-ddraw-2x\.ini'
        # The ini is the committed file with width/height rewritten to 2x SC_WS_SCREEN_W/H.
        $script:stageText | Should -Match 'SC_WS_SCREEN_W'
        $script:stageText | Should -Match '\^width=\\d\+'
        $script:stageText.Contains('does not carry width=') | Should -BeTrue -Because 'the verify step must read the ini that actually shipped'
    }

    It 'deploy falls back to borderless when 2x does not fit the primary monitor; the zip is always borderless' {
        # 1280x880 x2 = 2560x1760 does not fit a 1920x1080 monitor, so deploy asks for
        # cnc-ddraw borderless (fullscreen=true) with the aspect kept (maintas), rather
        # than a window bigger than the screen. The zip cannot know the player's monitor.
        $script:deployText | Should -Match 'PrimaryScreen'
        $script:deployText | Should -Match '-Borderless \(-not \$fits2x\)'
        $script:stageText | Should -Match "fullscreen=false', 'fullscreen=true'"
        $script:stageText | Should -Match 'maintas=true'
        $script:stageText | Should -Match 'must be borderless' -Because 'the verify step must confirm the fallback actually shipped'
        (Get-Content -Raw -LiteralPath $script:package) | Should -Match '-Borderless \$true'
    }

    It 'a leftover Wide launcher and shortcut from an earlier deploy are removed' {
        $script:deployText.Contains("Launch-StarCraft-Modded-Wide.ps1") | Should -BeTrue
        $script:deployText.Contains("StarCraft Modded (Wide).lnk") | Should -BeTrue
        $script:deployText | Should -Match 'Remove-Item -LiteralPath \$staleWideShortcut'
    }

    It 'cnc-ddraw is staged only through its own sha256 pin' {
        $script:stageText | Should -Match '\$CNC_DDRAW_DLL_SHA256\s*=\s*''[0-9a-f]{64}'''
        $script:stageText.Contains('cnc-ddraw ddraw.dll SHA256 MISMATCH') |
            Should -BeTrue -Because 'an unvouched helper DLL must be a hard stop, not a warning'
        $script:stageText.Contains('staged cnc-ddraw hash mismatch after copy') |
            Should -BeTrue -Because 'the verify step must re-check the copy that actually shipped'
    }

    It 'cnc-ddraw.ini is staged beside the staged run-with-plugin.ps1' {
        # run-with-plugin.ps1 reads cnc-ddraw.ini from ITS OWN directory; in the staged
        # tree that is plugin\, or the helper runs unconfigured.
        $script:stageText.Contains("Join-Path `$pluginDest 'cnc-ddraw.ini'") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:pluginDir 'cnc-ddraw.ini') |
            Should -BeTrue -Because 'it is copied from tools/plugin at stage time'
    }

    It 'the card the stage copies exists on disk and mentions the one action' {
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
