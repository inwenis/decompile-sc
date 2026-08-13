#Requires -Version 7
<#
Pester coverage for the two pieces of tools/plugin/drive-game.ps1 that are PURE LOGIC:
the map-browser listing model and the fixture-ownership registry.

Why these two and not the rest: every in-game defect this repo lost runs to on
2026-08-09 was one of them getting a row number or an owner wrong, and both are decidable
from a directory tree alone -- no game, no window, no GDI+. So they can be regression
tested here, in CI, instead of being re-discovered by whoever is bleeding next.

The listing expectations below are not invented: each mirrors a captured frame, cited in
the test name, so a change to the model has to argue with a photograph.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'tools' 'plugin' 'drive-game.ps1')

    function New-TestMapsTree {
        param([string[]]$BroodWarDirs = @(), [string[]]$FixtureFiles = @())
        $root = Join-Path ([IO.Path]::GetTempPath()) ("sc-browser-" + [Guid]::NewGuid().ToString('n'))
        $maps = Join-Path $root 'Maps'
        # The stock shape, as it is on disk in the working copy.
        foreach ($d in @('BroodWar', 'campaign', 'ladder', 'oldladder', 'replays', 'scenario')) {
            New-Item -ItemType Directory -Path (Join-Path $maps $d) -Force | Out-Null
        }
        foreach ($d in @('Allied', 'Ladder', 'WebMaps')) {
            New-Item -ItemType Directory -Path (Join-Path $maps "BroodWar\$d") -Force | Out-Null
        }
        foreach ($d in $BroodWarDirs) {
            New-Item -ItemType Directory -Path (Join-Path $maps "BroodWar\$d") -Force | Out-Null
        }
        # A couple of real stock names, so the file half of the ordering is exercised.
        foreach ($f in @('(2)Astral Balance.scm', '(2)Baby Steps.scm', '(2)Binary Burghs.scx')) {
            Set-Content -LiteralPath (Join-Path $maps "BroodWar\$f") -Value 'x'
        }
        foreach ($f in @('(1)Enslavers01.scm', '(1)Enslavers02a.scm', '(1)Enslavers02b.scm')) {
            Set-Content -LiteralPath (Join-Path $maps "campaign\$f") -Value 'x'
        }
        Set-Content -LiteralPath (Join-Path $maps '(2)Bottleneck.scm') -Value 'x'
        foreach ($f in $FixtureFiles) {
            $p = Join-Path $maps $f
            New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force | Out-Null
            Set-Content -LiteralPath $p -Value 'x'
        }
        [pscustomobject]@{ Root = $root; Maps = $maps }
    }
}

Describe 'map-browser listing model' {

    It 'sorts [Up One Level] AMONG the directories, not above them (016-frames\05-browse.png)' {
        # THE level-3 fact. The frame reads: [Allied] [Ladder] [Up One Level] [WebMaps].
        $t = New-TestMapsTree
        try {
            $l = Get-ScBrowserListing -Dir (Join-Path $t.Maps 'BroodWar') -MapsRoot $t.Maps
            $l.Entries[0..3].Name | Should -Be @('Allied', 'Ladder', 'Up One Level', 'WebMaps')
            ($l.Entries | Where-Object Kind -eq 'up').Row | Should -Be 3
            ($l.Entries | Where-Object Kind -eq 'up').Y | Should -Be 178
        } finally { Remove-Item -LiteralPath $t.Root -Recurse -Force }
    }

    It 'moves [Up One Level] down a row for every fixture folder that sorts before it' {
        # This IS the bug: an extra directory nobody else uses shifts the parent entry,
        # and test-selection-circles opened a folder instead of leaving BroodWar.
        $t = New-TestMapsTree -BroodWarDirs @('00-t021', '00-t022')
        try {
            $l = Get-ScBrowserListing -Dir (Join-Path $t.Maps 'BroodWar') -MapsRoot $t.Maps
            ($l.Entries | Where-Object Kind -eq 'up').Row | Should -Be 5
            (Get-ScBrowserEntry -Listing $l -Name '00-t022').Row | Should -Be 2
        } finally { Remove-Item -LiteralPath $t.Root -Recurse -Force }
    }

    It 'gives the maps root no parent entry, and does list BroodWar' {
        # A frame of this listing starts at [campaign], which was first read as "BroodWar
        # is excluded". It was a SCROLLED view -- the live probe that established
        # Sync-ScBrowserToTop showed entry 1 sitting above the visible window. A model
        # that silently drops a directory puts every row below it off by one, which is
        # the bug this file exists to catch, so it is pinned here.
        $t = New-TestMapsTree
        try {
            $l = Get-ScBrowserListing -Dir $t.Maps -MapsRoot $t.Maps
            $l.IsRoot | Should -BeTrue
            $l.Entries.Name | Should -Not -Contain 'Up One Level'
            $l.Entries[0..5].Name | Should -Be @('BroodWar', 'campaign', 'ladder', 'oldladder',
                                                 'replays', 'scenario')
        } finally { Remove-Item -LiteralPath $t.Root -Recurse -Force }
    }

    It 'puts (1)Enslavers02b.scm on row 4 (015-probe-scroll\02-campaign-listing.png)' {
        # The row the two campaign suites have always clicked, now derived rather than typed.
        $t = New-TestMapsTree
        try {
            $l = Get-ScBrowserListing -Dir (Join-Path $t.Maps 'campaign') -MapsRoot $t.Maps
            $e = Get-ScBrowserEntry -Listing $l -Name '(1)Enslavers02b.scm'
            $e.Row | Should -Be 4
            $e.Y | Should -Be 197
        } finally { Remove-Item -LiteralPath $t.Root -Recurse -Force }
    }

    It 'lists directories before map files and ignores non-map files' {
        $t = New-TestMapsTree -FixtureFiles @('BroodWar\00-t023\023-combat.scx',
                                              'BroodWar\00-t023\notes.txt')
        try {
            $l = Get-ScBrowserListing -Dir (Join-Path $t.Maps 'BroodWar\00-t023') -MapsRoot $t.Maps
            $l.Count | Should -Be 2
            $l.Entries[0].Name | Should -Be 'Up One Level'
            $l.Entries[1].Name | Should -Be '023-combat.scx'
            $l.Entries[1].Y | Should -Be 159
        } finally { Remove-Item -LiteralPath $t.Root -Recurse -Force }
    }

    It 'refuses a target below the six visible rows rather than clicking row 6' {
        $t = New-TestMapsTree -BroodWarDirs @('00-t001', '00-t002', '00-t003', '00-t004', '00-t005')
        try {
            $l = Get-ScBrowserListing -Dir (Join-Path $t.Maps 'BroodWar') -MapsRoot $t.Maps
            { Get-ScBrowserEntry -Listing $l -Name 'WebMaps' } |
                Should -Throw -ExpectedMessage '*only 6 rows are visible*'
        } finally { Remove-Item -LiteralPath $t.Root -Recurse -Force }
    }

    It 'names what IS in the listing when the wanted entry is not' {
        $t = New-TestMapsTree
        try {
            $l = Get-ScBrowserListing -Dir (Join-Path $t.Maps 'BroodWar') -MapsRoot $t.Maps
            { Get-ScBrowserEntry -Listing $l -Name '00-t023' } |
                Should -Throw -ExpectedMessage '*The browser shows:*'
        } finally { Remove-Item -LiteralPath $t.Root -Recurse -Force }
    }
}

Describe 'log parsing' {

    It 'returns the engine twelve as twelve, not as one array holding twelve' {
        # The regression: Get-ScSelectionGroup ended in `,@(...)` and its caller wrapped
        # the call in `@(...)`, so $engine.Count read 1 and `-contains` matched nothing.
        # test-stim-fanout then failed two assertions about the engine's own selection
        # while the log in front of it held all twelve pointers -- a harness bug wearing
        # the costume of a finding.
        $log = Join-Path ([IO.Path]::GetTempPath()) ("sc-sel-" + [Guid]::NewGuid().ToString('n') + ".log")
        $ptrs = 0..11 | ForEach-Object { "[$_]=0x0062{0:X4}" -f (0x1000 + $_ * 0x150) }
        try {
            Set-Content -LiteralPath $log -Value @(
                '[2026-08-09 06:00:00.000] observer tick'
                "[2026-08-09 06:00:01.000]     clientSelectionGroup   $($ptrs -join ' ')"
                "[2026-08-09 06:00:01.002]     clientSelectionGroup2  $($ptrs -join ' ')"
            )
            $engine = @(Get-ScSelectionGroup -LogPath $log)
            $engine.Count | Should -Be 12
            $engine[0] | Should -Be '00621000'
            # The whole point of reading them: intersecting with Get-ScWorldState's units.
            $engine | Should -Contain '00621150'
        } finally { Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue }
    }

    It 'does not mistake clientSelectionGroup2 for clientSelectionGroup' {
        $log = Join-Path ([IO.Path]::GetTempPath()) ("sc-sel-" + [Guid]::NewGuid().ToString('n') + ".log")
        try {
            Set-Content -LiteralPath $log -Value @(
                '[2026-08-09 06:00:01.000]     clientSelectionGroup   [0]=0x00621000 [1]=0x00621150'
                '[2026-08-09 06:00:01.002]     clientSelectionGroup2  [0]=0x00AAAAAA [1]=0x00BBBBBB [2]=0x00CCCCCC'
            )
            @(Get-ScSelectionGroup -LogPath $log) | Should -Be @('00621000', '00621150')
        } finally { Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'fixture ownership registry' {

    BeforeEach {
        $script:tree = New-TestMapsTree
        $script:dir = Join-Path $script:tree.Maps 'BroodWar\00-t023'
        New-Item -ItemType Directory -Path $script:dir -Force | Out-Null
    }
    AfterEach { Remove-Item -LiteralPath $script:tree.Root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'does not call a suite OWN earlier fixture foreign (the 2026-08-09 self-deadlock)' {
        # test-combat-death creates a placement probe, then the combat map. The old
        # one-filename rule counted the probe as somebody else's and the suite waited
        # for itself.
        $run = New-ScFixtureRun -Dir $script:dir -Names @('combat-death-probe.scx', 'combat-death.scx')
        Set-Content -LiteralPath (Join-Path $script:dir 'combat-death-probe.scx') -Value 'x'
        Get-ScForeignFixture -Run $run | Should -BeNullOrEmpty
        { Assert-ScFixtureFolderMine -Run $run } | Should -Not -Throw
    }

    It 'still calls anything undeclared foreign, and refuses to start' {
        $run = New-ScFixtureRun -Dir $script:dir -Names @('combat-death.scx')
        Set-Content -LiteralPath (Join-Path $script:dir '022-ghosts.scx') -Value 'x'
        Get-ScForeignFixture -Run $run | Should -Be @('022-ghosts.scx')
        { Assert-ScFixtureFolderMine -Run $run } | Should -Throw -ExpectedMessage '*Refusing to start*'
    }

    It 'deletes only declared fixtures and leaves everything else alone' {
        $run = New-ScFixtureRun -Dir $script:dir -Names @('a.scx', 'b.scx')
        foreach ($n in @('a.scx', 'b.scx', 'someone-else.scx')) {
            Set-Content -LiteralPath (Join-Path $script:dir $n) -Value 'x'
        }
        Remove-ScOwnFixture -Run $run
        (Get-ChildItem -LiteralPath $script:dir).Name | Should -Be @('someone-else.scx')
    }

    It 'refuses to delete a name the run never declared' {
        $run = New-ScFixtureRun -Dir $script:dir -Names @('a.scx')
        { Remove-ScOwnFixture -Run $run -Names @('someone-else.scx') } |
            Should -Throw -ExpectedMessage "*not one of this run's declared fixtures*"
    }

    It 'refuses to launch a fixture the run never declared' {
        $run = New-ScFixtureRun -Dir $script:dir -Names @('a.scx')
        $p = Join-Path $script:dir 'undeclared.scx'
        Set-Content -LiteralPath $p -Value 'x'
        { Assert-ScFixtureStillMine -Run $run -MapPath $p } |
            Should -Throw -ExpectedMessage '*was never declared*'
    }

    It 'names the missing-own-fixture case separately from the collision case' {
        $run = New-ScFixtureRun -Dir $script:dir -Names @('a.scx')
        { Assert-ScFixtureStillMine -Run $run -MapPath (Join-Path $script:dir 'a.scx') } |
            Should -Throw -ExpectedMessage "*another worker's cleanup took it*"
    }

    It 'rejects a duplicate declaration' {
        { New-ScFixtureRun -Dir $script:dir -Names @('a.scx', 'a.scx') } |
            Should -Throw -ExpectedMessage '*duplicate fixture name*'
    }
}

Describe 'fixture folder default' {

    # THE HOLE THE REVIEW FOUND. Ownership keys on the declared NAME set, which separates
    # this suite from every other suite -- and not at all from ANOTHER RUN OF ITSELF. Two
    # concurrent runs of one suite with no -FixtureDir declare the same names in the same
    # folder, so neither sees the other as foreign and one overwrites the other's fixture.

    It 'keeps the suite historical folder when no agent is running (the by-hand case)' {
        Resolve-ScFixtureDir -GameDir 'C:\g' -Fallback '00-testmap' -Suite 'hud-row' -AgentTask '' |
            Should -Be 'C:\g\Maps\BroodWar\00-testmap'
        Resolve-ScFixtureDir -GameDir 'C:\g' -Fallback '00-testmap' -Suite 'hud-row' -AgentTask $null |
            Should -Be 'C:\g\Maps\BroodWar\00-testmap'
    }

    It 'gives a worker its OWN folder, so two runs of one suite cannot collide' {
        $a = Resolve-ScFixtureDir -GameDir 'C:\g' -Fallback '00-testmap' -Suite 'hud-row' -AgentTask '023'
        $b = Resolve-ScFixtureDir -GameDir 'C:\g' -Fallback '00-testmap' -Suite 'hud-row' -AgentTask '024'
        $a | Should -Be 'C:\g\Maps\BroodWar\00-t023-hud-row'
        $a | Should -Not -Be $b
    }

    It 'takes the task id from a suffixed AGENT_TASK (Enter-ScLaunchLock names them that way)' {
        Resolve-ScFixtureDir -GameDir 'C:\g' -Fallback '00-testmap' -Suite 'hud-row' -AgentTask '023-ghost-cloak' |
            Should -Be 'C:\g\Maps\BroodWar\00-t023-hud-row'
    }

    It 'never leaves a worker in ANOTHER task finished folder' {
        # test-control-groups defaulted to 00-t021 and three suites to 00-t022 -- the
        # folders of the tasks that wrote them, not of the task running them.
        foreach ($stale in @('00-t021', '00-t022')) {
            Resolve-ScFixtureDir -GameDir 'C:\g' -Fallback $stale -Suite 'hud-row' -AgentTask '023' |
                Should -Be 'C:\g\Maps\BroodWar\00-t023-hud-row'
        }
    }

    It 'falls back to a sanitised leaf for a non-numeric agent id' {
        Resolve-ScFixtureDir -GameDir 'C:\g' -Fallback '00-testmap' -Suite 'hud-row' -AgentTask 'probe/../x' |
            Should -Be 'C:\g\Maps\BroodWar\00-tprobex-hud-row'
    }

    # THE SECOND HOLE (task 059 / issue #80): two DIFFERENT suites of one task used to
    # collide, because the folder was keyed on task alone.
    It 'gives two suites of the SAME task two DIFFERENT folders, so they cannot collide' {
        $saveLoad = Resolve-ScFixtureDir -GameDir 'C:\g' -Fallback '00-t051' -Suite 'save-load' -AgentTask '054'
        $hudRow   = Resolve-ScFixtureDir -GameDir 'C:\g' -Fallback '00-testmap' -Suite 'hud-row' -AgentTask '054'
        $saveLoad | Should -Be 'C:\g\Maps\BroodWar\00-t054-save-load'
        $hudRow   | Should -Be 'C:\g\Maps\BroodWar\00-t054-hud-row'
        $saveLoad | Should -Not -Be $hudRow
    }

    It 'gives two PHASES of the SAME suite the SAME folder, so a multi-phase suite keeps its fixture' {
        $control = Resolve-ScFixtureDir -GameDir 'C:\g' -Fallback '00-t051' -Suite 'save-load' -AgentTask '054'
        $fanout  = Resolve-ScFixtureDir -GameDir 'C:\g' -Fallback '00-t051' -Suite 'save-load' -AgentTask '054'
        $control | Should -Be $fanout
    }
}

Describe 'fixture folder owner note (task 059 / issue #80)' {

    # The refusal/wait messages used to assert "another run" as fact, which sent two
    # readers hunting for a colliding worker that did not exist -- the file belonged to
    # the same task's OTHER suite. Now the folder is exclusive to one task+suite, so the
    # note can say precisely what the path proves and nothing it does not know.

    It 'names the owning task and suite for a task+suite-scoped folder' {
        $note = Get-ScFixtureFolderOwnerNote -Dir 'C:\g\Maps\BroodWar\00-t054-save-load'
        $note | Should -Match 'task 054'
        $note | Should -Match 'save-load'
        $note | Should -Match 'impossible'
    }

    It 'admits it cannot name an owner for a non-task+suite (shared/by-hand) folder' {
        $note = Get-ScFixtureFolderOwnerNote -Dir 'C:\g\Maps\BroodWar\00-testmap'
        $note | Should -Match 'cannot be determined'
    }

    It 'never asserts "another run" without evidence in the refusal message' {
        $dir = Join-Path $TestDrive 'Maps\BroodWar\00-t054-hud-row'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $dir 'save-load.scx') -Force | Out-Null
        $run = New-ScFixtureRun -Dir $dir -Names @('hud-row.scx')
        { Assert-ScFixtureFolderMine -Run $run } | Should -Throw -ExpectedMessage '*save-load.scx*'
        try { Assert-ScFixtureFolderMine -Run $run }
        catch {
            $_.Exception.Message | Should -Not -Match "another run's fixture"
            $_.Exception.Message | Should -Match "task 054's 'hud-row' runs only"
            $_.Exception.Message | Should -Match 'No liveness check'
        }
    }
}

# ---------------------------------------------------------------------------
# Get-ScCardState -- the command-card read-back parser (task 026)
#
# This one is here for a specific reason: an in-game run is the scarcest thing in this
# repo (they serialise on a machine-wide lock and, on 2026-08-09, on the user's own
# screen), and a parser that silently matches nothing turns a launch into a timeout and
# a wasted slot. The lines below are the exact printf shapes in sc_card.cpp, including
# the `%-7s` state padding and the ScLog timestamp prefix, so a change to either side
# has to break a test here rather than a run there.
# ---------------------------------------------------------------------------

Describe 'Get-ScCardState' {
    BeforeAll {
        # The label is "<tag>-<seq>" with a module-private counter, so the fixture log
        # carries every label the call could pick rather than guessing the seq.
        function New-CardLog {
            param([string]$Tag, [string[]]$Body)
            $path = Join-Path ([IO.Path]::GetTempPath()) ("sc-card-" + [Guid]::NewGuid().ToString('n') + ".log")
            $lines = foreach ($seq in 1..60) {
                foreach ($b in $Body) { "2026-08-09 21:00:00.000  " + ($b -replace '<L>', "$Tag-$seq") }
            }
            Set-Content -LiteralPath $path -Value $lines
            $path
        }

        # A Ghost card, verbatim in shape from the 2026-08-09 read-back.
        $script:GhostCardBody = @(
            'CARD [<L>] dialog=0x0068C148 root=0x0068C148 cardId=1 ovrSel=228 ovrSub=228 portrait=0x0059CE18 ptype=0x001 pset=1 penergy=51200 powner=0 set=(n=9 buttons=0x00517AB8) reason=8 rootrect=(500,358,639,479)'
            'CARD [<L>] slot=1 enabled ctrl=0x0AB10100 flags=0x00000009 icon=0x00E4 rect=(3,6,35,38) button=0x00517AB8 bslot=1 bicon=0x00E4 cond=0x004282D0 act=0x00424440 cparam=0 aparam=0 name=0x0298 dis=0x0000'
            'CARD [<L>] slot=6 hidden  ctrl=0x0AB10256 flags=0x00000001 icon=0xFFFF rect=(95,48,127,80) button=0x00000000 (no button record)'
            'CARD [<L>] slot=7 GREYED  ctrl=0x0AB102AC flags=0x0000000B icon=0x00FC rect=(3,90,35,122) button=0x00517B0C bslot=7 bicon=0x00FC cond=0x004293E0 act=0x00423730 cparam=10 aparam=10 name=0x0158 dis=0x0163'
            'CARD [<L>] tech p=0 available=[0 1 10 11] researched=[10]'
            'CARD [<L>] slots=9 shown=7 greyed=2'
        )
    }

    It 'parses the header, including the dialog origin' {
        $log = New-CardLog -Tag 'hdr' -Body $script:GhostCardBody
        try {
            $c = Get-ScCardState -LogPath $log -Tag 'hdr' `
                    -MarkerPath (Join-Path (Split-Path $log -Parent) 'marker.txt') -TimeoutSec 5
            $c.Ok | Should -BeTrue
            $c.CardId | Should -Be 1
            $c.OverrideSel | Should -Be 228
            $c.PortraitType | Should -Be 1
            $c.PortraitSet | Should -Be 1
            $c.SetCount | Should -Be 9
            $c.RootRect | Should -Be @(500, 358, 639, 479)
            $c.Shown | Should -Be 7
            $c.Greyed | Should -Be 2
        } finally { Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue }
    }

    It 'reads slot 7 as the greyed Cloak button, with its Button record' {
        $log = New-CardLog -Tag 'slot' -Body $script:GhostCardBody
        try {
            $c = Get-ScCardState -LogPath $log -Tag 'slot' `
                    -MarkerPath (Join-Path (Split-Path $log -Parent) 'marker.txt') -TimeoutSec 5
            $s = Get-ScCardSlot -Card $c -Slot 7
            $s.State     | Should -Be 'GREYED'
            $s.Visible   | Should -BeTrue
            $s.Disabled  | Should -BeTrue
            $s.Flags     | Should -Be 0xB
            $s.HasButton | Should -BeTrue
            $s.BSlot     | Should -Be 7
            # The two fields the whole task turns on: the action names the ability, the
            # conditionParam names the tech.
            $s.Action    | Should -Be '00423730'
            $s.CondParam | Should -Be 10
        } finally { Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue }
    }

    It 'distinguishes hidden from greyed, and a slot with no Button record' {
        $log = New-CardLog -Tag 'hid' -Body $script:GhostCardBody
        try {
            $c = Get-ScCardState -LogPath $log -Tag 'hid' `
                    -MarkerPath (Join-Path (Split-Path $log -Parent) 'marker.txt') -TimeoutSec 5
            $s6 = Get-ScCardSlot -Card $c -Slot 6
            $s6.Visible   | Should -BeFalse
            $s6.Disabled  | Should -BeFalse
            $s6.HasButton | Should -BeFalse
            (Get-ScCardSlot -Card $c -Slot 1).Disabled | Should -BeFalse
        } finally { Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue }
    }

    It 'parses the per-player tech state as id lists' {
        $log = New-CardLog -Tag 'tech' -Body $script:GhostCardBody
        try {
            $c = Get-ScCardState -LogPath $log -Tag 'tech' `
                    -MarkerPath (Join-Path (Split-Path $log -Parent) 'marker.txt') -TimeoutSec 5
            $c.TechPlayer     | Should -Be 0
            $c.TechAvailable  | Should -Be @(0, 1, 10, 11)
            $c.TechResearched | Should -Be @(10)
        } finally { Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue }
    }

    It 'computes a slot centre as dialog origin + control rect, never a constant' {
        $log = New-CardLog -Tag 'pt' -Body $script:GhostCardBody
        try {
            $c = Get-ScCardState -LogPath $log -Tag 'pt' `
                    -MarkerPath (Join-Path (Split-Path $log -Parent) 'marker.txt') -TimeoutSec 5
            $p = Get-ScCardSlotPoint -Card $c -Slot 7
            $p.X | Should -Be (500 + [math]::Floor((3 + 35) / 2))    # 519
            $p.Y | Should -Be (358 + [math]::Floor((90 + 122) / 2))  # 464
        } finally { Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue }
    }

    It 'reports not-ok rather than hanging when the process has no card' {
        $log = New-CardLog -Tag 'none' -Body @(
            'CARD [<L>] dialog=0 (no command card in this process state)')
        try {
            $c = Get-ScCardState -LogPath $log -Tag 'none' `
                    -MarkerPath (Join-Path (Split-Path $log -Parent) 'marker.txt') -TimeoutSec 5
            $c.Ok | Should -BeFalse
            $c.Slots.Count | Should -Be 0
        } finally { Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue }
    }

    It 'throws with the -CardScan hint when no CARD line ever arrives' {
        $log = New-CardLog -Tag 'quiet' -Body @('WORLD [<L>] p=7 units=0 recount=0 complete=1')
        try {
            { Get-ScCardState -LogPath $log -Tag 'quiet' `
                    -MarkerPath (Join-Path (Split-Path $log -Parent) 'marker.txt') -TimeoutSec 1 } |
                Should -Throw -ExpectedMessage '*-CardScan 1*'
        } finally { Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue }
    }
}
