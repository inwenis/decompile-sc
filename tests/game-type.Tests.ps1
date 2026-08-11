#Requires -Version 7
<#
Pester coverage for the Game Type read (tools/plugin/drive-game.ps1) -- issue #29.

WHAT THIS REPLACES. Set-ScGameType used to prove a pick by fingerprinting the
map-information panel: pick a known OTHER entry, hash, pick the wanted one, require the
hash to differ. That oracle cannot separate "the pick did not take" from "the value was
already right" -- both leave the hashes equal -- and the combo remembers the last value
used on the machine, so "already right" is the common case. It was also the last reason
the harness raised the game window at all.

The value was readable the whole time. Task 027's active-dialog scan already walks the
engine's list and logs every control that carries text, and the Game Type combo's text IS
the selected entry's label.

The fixture below is a REAL DIALOGS line, copied verbatim out of
C:\sc-work\logs\034-widescreen-s2-ws.log, not one written to make these tests pass. It is
also the awkward case rather than the easy one: the Create screen carries THREE type-13
combos (game type, player name, race), so "find the combo" has to mean "find the one on
the Game Type label's row" and nothing weaker.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'tools' 'plugin' 'drive-game.ps1')

    # Verbatim from a live run, 2026-08-11 09:40:36. Wrapped for width only.
    $script:CREATE_LINE = @(
        "[2026-08-11 09:40:36.054] DIALOGS n=1  dlg='Create' rect=0,0,639,479",
        "ctrl='glue\create\pListMap2.pcx' rect=0,0,363,292 type=5 flags=0x60008",
        "ctrl='glue\create\pInfo.pcx' rect=400,0,639,332 type=5 flags=0x60008",
        "ctrl='Create' rect=40,68,175,87 type=9 flags=0x4008",
        "ctrl='BroodWar' rect=58,102,349,121 type=9 flags=0x818",
        "ctrl='Astral Balance' rect=410,58,599,107 type=10 flags=0x808",
        "ctrl='Map Size:.128x96' rect=418,242,589,261 type=9 flags=0x8",
        "ctrl='Tileset:.Space' rect=418,262,589,281 type=9 flags=0x8",
        "ctrl='Number of Players:.2' rect=418,282,589,301 type=9 flags=0x0",
        "ctrl='Human Slots:.2' rect=418,282,589,301 type=9 flags=0x8",
        "ctrl='Computer Slots:.0' rect=418,302,589,321 type=9 flags=0x8",
        "ctrl='o.O.k' rect=441,383,592,404 type=14 flags=0x2284218",
        "ctrl='c.C.ancel' rect=477,419,608,440 type=14 flags=0x2204258",
        "ctrl='Game Type' rect=58,262,169,281 type=9 flags=0x408",
        "ctrl='{0}' rect=180,261,351,277 type=13 flags=0x20020418",
        "ctrl='asdf' rect=33,315,182,331 type=13 flags=0x2002041A",
        "ctrl='Random' rect=193,315,342,331 type=13 flags=0x20020418"
    ) -join ' '

    function New-Log {
        param([string]$GameType = 'Use Map Settings', [string[]]$Extra = @())
        $p = Join-Path ([IO.Path]::GetTempPath()) ("sc-gt-" + [Guid]::NewGuid().ToString('n') + '.log')
        $lines = @('[2026-08-11 09:40:30.000] OBSERVER started') + $Extra +
                 @($script:CREATE_LINE -f $GameType)
        Set-Content -LiteralPath $p -Value $lines
        $p
    }
}

Describe 'Get-ScGameTypeControl reads the combo out of the dialog list' {

    It 'reports the selected entry by name' {
        $p = New-Log -GameType 'Use Map Settings'
        try { (Get-ScGameTypeControl -LogPath $p).Value | Should -Be 'Use Map Settings' }
        finally { Remove-Item $p -Force }
    }

    It 'TRACKS THE VALUE -- a different selection reads differently' {
        # The whole point. A read that returned the same string whatever the engine held
        # would be the pixel fingerprint's failure in a new costume.
        $p = New-Log -GameType 'Melee'
        try { (Get-ScGameTypeControl -LogPath $p).Value | Should -Be 'Melee' }
        finally { Remove-Item $p -Force }
    }

    It 'picks the combo on the Game Type ROW, not the player-name or race combo' {
        $p = New-Log -GameType 'Free For All'
        try {
            $c = Get-ScGameTypeControl -LogPath $p
            $c.Value | Should -Be 'Free For All'
            $c.Value | Should -Not -Be 'asdf'
            $c.Value | Should -Not -Be 'Random'
        }
        finally { Remove-Item $p -Force }
    }

    It "computes the click point from the control's own rect, not a fixed (265,268)" {
        # rect=180,261,351,277 on a dialog at origin 0,0 -> centre (266,269). The fixed
        # point this replaces was (265,268): one pixel out on both axes, inside a box 171
        # wide and 16 tall, which is exactly why nobody ever noticed it was a fixed point.
        $p = New-Log
        try {
            $c = Get-ScGameTypeControl -LogPath $p
            $c.ClickX | Should -Be 266
            $c.ClickY | Should -Be 269
        }
        finally { Remove-Item $p -Force }
    }

    It 'reports the map-information panel lines the engine is SHOWING, as corroboration' {
        # Under Use Map Settings the engine shows Human/Computer Slots (flag 0x8) and hides
        # Number of Players (0x0) -- the very difference the old fingerprint was hashing,
        # here as a fact rather than a digest.
        $p = New-Log
        try {
            $c = Get-ScGameTypeControl -LogPath $p
            $c.PanelShows | Should -Contain 'Human Slots'
            $c.PanelShows | Should -Contain 'Computer Slots'
            $c.PanelShows | Should -Not -Contain 'Number of Players'
        }
        finally { Remove-Item $p -Force }
    }

    It 'returns $null when the Create screen is not up, rather than guessing' {
        $p = Join-Path ([IO.Path]::GetTempPath()) ("sc-gt-" + [Guid]::NewGuid().ToString('n') + '.log')
        Set-Content -LiteralPath $p -Value @(
            "[2026-08-11 09:40:36.054] DIALOGS n=1  dlg='Tips_Dlg' rect=128,32,511,287 ctrl='o.O.K' rect=20,216,123,243 type=14 flags=0x8")
        try { Get-ScGameTypeControl -LogPath $p | Should -BeNullOrEmpty }
        finally { Remove-Item $p -Force }
    }

    It 'reads the NEWEST line, so a pick that changed the value is not read as stale' {
        # Get-ScDialogs takes the last DIALOGS line; the older one here says Melee.
        $stale = $script:CREATE_LINE -f 'Melee'
        $p = New-Log -GameType 'Use Map Settings' -Extra @($stale)
        try { (Get-ScGameTypeControl -LogPath $p).Value | Should -Be 'Use Map Settings' }
        finally { Remove-Item $p -Force }
    }
}

Describe 'Set-ScGameType index/name table' {
    It 'maps the indices this harness picks to the entries it expects' {
        # -Index 2 has meant "Use Map Settings" in eleven call sites for months, on the
        # strength of a frame read once in task 016. Now it is checked against what the
        # engine reports after the pick, so this table is load-bearing rather than a note.
        $script:ScGameTypeByIndex[0] | Should -Be 'Melee'
        $script:ScGameTypeByIndex[2] | Should -Be 'Use Map Settings'
    }
}
