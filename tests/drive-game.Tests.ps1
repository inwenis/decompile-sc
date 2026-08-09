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
