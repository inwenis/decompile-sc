#Requires -Version 7
<#
Pester cases for tools/make_test_map.py's PTEx tech-state writer (task 026).

WHY THESE EXIST AT ALL. The generator wrote PTEx with a TECH-major index and read it
back with the same tech-major index, so its own validator confirmed its own mistake and
printed `PTEx: player 0 has researched 10(personnel-cloaking)` for a map on which player
0 had researched nothing. Every fixture that needed a tech other than Stim Packs was
silently wrong, and one of them cost tasks 022 and 023 the entire Ghost question.

A shared helper stops the write and the read drifting apart again, but it cannot prove
the convention -- both halves agreeing is exactly the failure that happened. So these
cases assert the LITERAL byte offsets that the engine's own applier dictates, taken from
its disassembly (0x004CB870: `SUB EBX,0x2c` per player, `MOV EAX,0x2c` down to 0 per
tech; research/command-card.md 6). They fail against the pre-026 indexing by
construction -- `ptexIndex(10, 0)` was 120 and has to be 10 -- and the tech-0/player-0
case is pinned separately because it is the one point where both conventions agree, and
therefore the reason nobody noticed.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $venv = Join-Path $script:RepoRoot '.venv/Scripts/python.exe'
    $script:Python = if (Test-Path -LiteralPath $venv) { $venv }
                     elseif (Get-Command python -ErrorAction SilentlyContinue) { 'python' }
                     else { $null }

    # Runs a snippet against the real module -- no reimplementation of the arithmetic
    # here, or the test would only prove the test.
    function Invoke-MapPy {
        param([string]$Snippet)
        $prelude = @(
            'import sys',
            "sys.path.insert(0, r'$(Join-Path $script:RepoRoot 'tools')')",
            'import make_test_map as m'
        ) -join "`n"
        $out = & $script:Python -c "$prelude`n$Snippet" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "python failed: $out" }
        ($out | Out-String).Trim()
    }
}

Describe 'make_test_map PTEx indexing' {
    BeforeEach {
        if (-not $script:Python) { Set-ItResult -Skipped -Because 'no python available' }
    }

    It 'is player-major: index = player * 44 + tech' {
        Invoke-MapPy 'print(m.ptex_index(0, 0), m.ptex_index(10, 0), m.ptex_index(0, 1), m.ptex_index(43, 11))' |
            Should -Be '0 10 44 527'
    }

    It 'puts Personnel Cloaking for player 0 at byte 10, not the old 120' {
        Invoke-MapPy 'print(m.ptex_index(10, 0))' | Should -Be '10'
    }

    It 'agrees with the old tech-major indexing at the two corner cells and nowhere else' {
        # Two fixed points, not one: the first cell and the last, since
        # t*12 + p == p*44 + t only for (0,0) and (43,11) -> 0 and 527. The first is the
        # whole reason the bug survived -- Stim Packs for the human slot is the one
        # fixture that could ever have worked, and it is the one every suite used.
        Invoke-MapPy @'
same = [(t, p) for t in range(m.PTEX_TECHS) for p in range(m.PTEX_PLAYERS)
        if m.ptex_index(t, p) == t * m.PTEX_PLAYERS + p]
print(same)
'@ | Should -Be '[(0, 0), (43, 11)]'
    }

    It 'never indexes outside one 528-byte sub-array' {
        Invoke-MapPy @'
n = m.PTEX_TECHS * m.PTEX_PLAYERS
bad = [(t, p) for t in range(m.PTEX_TECHS) for p in range(m.PTEX_PLAYERS)
       if not 0 <= m.ptex_index(t, p) < n]
print(len(bad), n)
'@ | Should -Be '0 528'
    }

    It 'covers every (tech, player) pair exactly once' {
        Invoke-MapPy @'
seen = {m.ptex_index(t, p) for t in range(m.PTEX_TECHS) for p in range(m.PTEX_PLAYERS)}
print(len(seen))
'@ | Should -Be '528'
    }
}

Describe 'make_test_map PTEx write/read round trip' {
    BeforeEach {
        if (-not $script:Python) { Set-ItResult -Skipped -Because 'no python available' }
    }

    It 'sets available, researched and clears usesDefault at the engine offsets' {
        # Asserted against literal offsets rather than against ptex_index, so a change
        # to the helper cannot quietly move the bytes and still pass.
        Invoke-MapPy @'
buf = bytes(m.PTEX_SIZE)
out = m.set_techs_researched(buf, [10], 0)
print(out[m.PTEX_OFF_PLAYER_AVAILABLE + 10],
      out[m.PTEX_OFF_PLAYER_RESEARCHED + 10],
      out[m.PTEX_OFF_USES_DEFAULT + 10],
      out[m.PTEX_OFF_PLAYER_RESEARCHED + 120])
'@ | Should -Be '1 1 0 0'
    }

    It 'grants the tech to the requested player and to no other' {
        Invoke-MapPy @'
buf = bytearray(m.PTEX_SIZE)
for i in range(m.PTEX_OFF_USES_DEFAULT, m.PTEX_SIZE):
    buf[i] = 1                      # every slot starts on the map-wide default
out = m.set_techs_researched(bytes(buf), [10], 0)
print([p for p in range(m.PTEX_PLAYERS) if 10 in m.read_techs_researched(out, p)])
'@ | Should -Be '[0]'
    }

    It 'refuses a PTEx of the wrong size rather than writing into it' {
        Invoke-MapPy @'
try:
    m.set_techs_researched(bytes(100), [0], 0)
    print("NO-RAISE")
except ValueError:
    print("raised")
'@ | Should -Be 'raised'
    }
}
