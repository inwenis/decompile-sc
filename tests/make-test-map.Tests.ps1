#Requires -Version 7
<#
Pester cases for tools/make_test_map.py's PTEx tech-state writer.

The generator writes PTEx and reads it back through one shared helper, so both halves
agreeing proves nothing: a tech-major index on both sides reports `PTEx: player 0 has
researched 10(personnel-cloaking)` for a map on which player 0 has researched nothing.

So these cases assert the LITERAL byte offsets the engine's own applier dictates, taken
from its disassembly (0x004CB870: `SUB EBX,0x2c` per player, `MOV EAX,0x2c` down to 0
per tech; research/command-card.md 6). Player-major is the convention: `ptex_index(10, 0)`
must be 10, not the tech-major 120.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    # Resolve-ScPython finds the main checkout's .venv from a worktree and rejects any
    # interpreter that cannot import richchk: a bare `python` from PATH has no richchk in
    # a fresh worktree, so these cases would FAIL for a reason unrelated to the code under
    # test instead of SKIPPING with the real reason.
    . (Join-Path $script:RepoRoot 'tools/sc-python.ps1')
    $resolved = Resolve-ScPython -RepoRoot $script:RepoRoot -RequireModule 'richchk'
    $script:Python = $resolved.Path
    $script:PythonSkipReason = if (-not $resolved.Path) {
        "no python that can import richchk (issue #97 environment gap): $($resolved.Probed -join '; ')"
    }

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
        # richchk's StormLib loader warns to stderr on every archive it opens. Dropped by
        # name, and only by name, and only below the exit-code check above -- so a snippet
        # that really fails still throws with its full, unfiltered output.
        $out = @($out | Where-Object { "$_" -notmatch 'StormLibFinder' })
        # Out-String joins with the platform's newline, so a multi-line expectation
        # written with `n in this file would never match on Windows, however right the
        # snippet is.
        (($out | Out-String).Trim()) -replace "`r`n", "`n"
    }
}

Describe 'make_test_map PTEx indexing' {
    BeforeEach {
        if (-not $script:Python) { Set-ItResult -Skipped -Because $script:PythonSkipReason }
    }

    It 'is player-major: index = player * 44 + tech' {
        Invoke-MapPy 'print(m.ptex_index(0, 0), m.ptex_index(10, 0), m.ptex_index(0, 1), m.ptex_index(43, 11))' |
            Should -Be '0 10 44 527'
    }

    It 'puts Personnel Cloaking for player 0 at byte 10, not the old 120' {
        Invoke-MapPy 'print(m.ptex_index(10, 0))' | Should -Be '10'
    }

    It 'agrees with the old tech-major indexing at the two corner cells and nowhere else' {
        # Two fixed points, not one: t*12 + p == p*44 + t only for (0,0) and (43,11).
        # (0,0) is Stim Packs for the human slot -- the one cell every suite touches, and
        # so the one cell where a tech-major index passes unnoticed.
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
        if (-not $script:Python) { Set-ItResult -Skipped -Because $script:PythonSkipReason }
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

<#
UNIx, the map's own unit-settings override.

The layout is NOT taken from prose. It is pinned against the two things that can
contradict it: the section's real size, and the real stats of units anyone can check by
hand. If an offset drifts, `Marine has 40 hit points` stops being true and the case below
says so -- a generator that verifies its own write with its own indexing verifies nothing.

None of this proves the ENGINE reads these bytes. That is
tools/plugin/probe-unit-settings.ps1's job, in a running game.
#>
Describe 'make_test_map UNIx layout' {
    BeforeEach {
        if (-not $script:Python) { Set-ItResult -Skipped -Because $script:PythonSkipReason }
    }

    It 'is the Brood War 228-unit, 130-weapon layout: 4168 bytes' {
        Invoke-MapPy 'print(m.UNIX_SIZE, m.UNIX_UNITS, m.UNIX_WEAPONS)' | Should -Be '4168 228 130'
    }

    It 'puts each array where the size arithmetic requires' {
        Invoke-MapPy @'
print(m.UNIX_OFF_USE_DEFAULT, m.UNIX_OFF_HIT_POINTS, m.UNIX_OFF_SHIELD_POINTS,
      m.UNIX_OFF_ARMOR, m.UNIX_OFF_BUILD_TIME, m.UNIX_OFF_MINERAL_COST,
      m.UNIX_OFF_GAS_COST, m.UNIX_OFF_STRING_NUMBER, m.UNIX_OFF_BASE_DAMAGE,
      m.UNIX_OFF_UPGRADE_DAMAGE)
'@ | Should -Be '0 228 1140 1596 1824 2280 2736 3192 3648 3908'
    }

    It 'stores build time as GAME SECONDS x 15 and hit points x 256' {
        Invoke-MapPy 'print(m.BUILD_TIME_PER_GAME_SECOND, m.HP_FIXED_POINT)' | Should -Be '15 256'
    }

    # THE CASE THAT WOULD CATCH A WRONG OFFSET. Decoding a section this tool never wrote
    # and getting five units' real, publicly-known stats back is what makes the layout a
    # reading rather than a guess.
    It 'decodes the Brood War template to the real stats of five units' {
        $template = 'C:\decompile-sc-data\sc-work\1161-base\Maps\BroodWar\Ladder\(2)Fading Realm.scx'
        if (-not (Test-Path -LiteralPath $template)) {
            Set-ItResult -Skipped -Because 'the template map is not on this machine'
        }
        Invoke-MapPy @"
from pathlib import Path
s = m.parse_chk_sections(m.read_chk_bytes(Path(r'$template')))
u = s[m.find_section(s, 'UNIx')].payload
print(len(u))
for name in ('marine', 'scv', 'command-center', 'supply-depot', 'barracks'):
    i = m.resolve_unit_id(name)
    e = m.read_unit_settings(u, [i])[i]
    print(name, e['max-hp'], e['build-time'], e['mineral-cost'])
"@ | Should -Be (@(
            '4168',
            'marine 40 24 50',
            'scv 60 20 50',
            'command-center 1500 120 400',
            'supply-depot 500 40 100',
            'barracks 1000 80 150'
        ) -join "`n")
    }
}

Describe 'make_test_map UNIx write/read round trip' {
    BeforeEach {
        if (-not $script:Python) { Set-ItResult -Skipped -Because $script:PythonSkipReason }
    }

    It 'writes the build time at the engine offset, scaled, for the right unit only' {
        Invoke-MapPy @'
import struct
buf = bytearray(m.UNIX_SIZE)
out = m.set_unit_settings(bytes(buf), {"build-time": [(7, 1)]})
at7 = struct.unpack_from("<H", out, m.UNIX_OFF_BUILD_TIME + 2 * 7)[0]
at6 = struct.unpack_from("<H", out, m.UNIX_OFF_BUILD_TIME + 2 * 6)[0]
at8 = struct.unpack_from("<H", out, m.UNIX_OFF_BUILD_TIME + 2 * 8)[0]
print(at7, at6, at8)
'@ | Should -Be '15 0 0'
    }

    # usesDefault is the byte that decides whether ANY override is read. This is the
    # exact shape of the PTEx `playerUsesDefault` bug: right numbers, dead section.
    It 'clears usesDefault for every unit it touches, and for no other' {
        Invoke-MapPy @'
buf = bytearray(b"\x01" * m.UNIX_SIZE)
out = m.set_unit_settings(bytes(buf), {"build-time": [(7, 1)], "max-hp": [(0, 25)]})
print([i for i in range(m.UNIX_UNITS) if out[m.UNIX_OFF_USE_DEFAULT + i] == 0])
'@ | Should -Be '[0, 7]'
    }

    It 'reads back what it wrote, in the caller units rather than raw' {
        Invoke-MapPy @'
buf = bytearray(m.UNIX_SIZE)
out = m.set_unit_settings(bytes(buf), {
    "build-time": [(7, 3)], "max-hp": [(7, 60)], "mineral-cost": [(7, 0)],
    "gas-cost": [(7, 7)], "armor": [(7, 2)], "shields": [(7, 9)]})
e = m.read_unit_settings(out, [7])[7]
print(e["build-time"], e["max-hp"], e["mineral-cost"], e["gas-cost"], e["armor"],
      e["shields"], e["uses-default"])
'@ | Should -Be '3 60 0 7 2 9 0'
    }

    It 'leaves every other unit in the section alone' {
        Invoke-MapPy @'
src = bytes(range(256)) * (m.UNIX_SIZE // 256) + bytes(m.UNIX_SIZE % 256)
out = m.set_unit_settings(src, {"build-time": [(7, 1)]})
diff = [i for i in range(m.UNIX_SIZE) if src[i] != out[i]]
print(diff)
'@ | Should -Be "[$([int]0 + 7), $((1824) + 14), $((1824) + 15)]"
    }

    It 'refuses a UNIx of the wrong size rather than writing into it' {
        Invoke-MapPy @'
try:
    m.set_unit_settings(bytes(100), {"build-time": [(7, 1)]})
    print("NO-RAISE")
except ValueError:
    print("raised")
'@ | Should -Be 'raised'
    }

    # Not a range check -- a refusal to ship a fixture whose behaviour nobody has looked
    # at. Zero is a legal u16; what the engine's production tick does with it is unknown.
    It 'refuses a ZERO build time, while allowing zero everywhere else' {
        Invoke-MapPy @'
try:
    m.set_unit_settings(bytes(m.UNIX_SIZE), {"build-time": [(7, 0)]})
    print("build-time NO-RAISE")
except ValueError:
    print("build-time raised")
m.set_unit_settings(bytes(m.UNIX_SIZE), {"mineral-cost": [(7, 0)], "armor": [(7, 0)]})
print("others fine")
'@ | Should -Be "build-time raised`nothers fine"
    }

    It 'refuses a value the field cannot hold rather than truncating it' {
        Invoke-MapPy @'
for field, value in (("build-time", 5000), ("armor", 300), ("max-hp", -1)):
    try:
        m.set_unit_settings(bytes(m.UNIX_SIZE), {field: [(7, value)]})
        print(field, "NO-RAISE")
    except ValueError:
        print(field, "raised")
'@ | Should -Be "build-time raised`narmor raised`nmax-hp raised"
    }

    It 'parses TYPE=VALUE by name and by raw units.dat id, and refuses junk' {
        Invoke-MapPy @'
print(m.parse_unit_setting("scv=1"), m.parse_unit_setting(" 7 = 20 "))
for bad in ("scv", "nosuchunit=1", "scv=fast"):
    try:
        m.parse_unit_setting(bad)
        print(bad, "NO-RAISE")
    except ValueError:
        print(bad, "raised")
'@ | Should -Be "(7, 1) (7, 20)`nscv raised`nnosuchunit=1 raised`nscv=fast raised"
    }
}

<#
make-test-map.ps1's OWN failure behaviour.

Every suite captures the wrapper's output and checks for the file later, so a wrapper
that merely propagates the generator's exit code lets a failed generation scroll past as
a warning, and the first LOUD message is drive-game blaming another worker for a file
nobody wrote. So a failed or empty generation THROWS at the generation step, naming what
happened. These cases drive the wrapper through -Python (a stub interpreter): no venv,
no richchk, no template map needed.
#>
Describe 'make-test-map.ps1 refuses at generation instead of failing downstream' {
    BeforeAll {
        $script:tmp = Join-Path ([IO.Path]::GetTempPath()) "mtm-tests-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $script:tmp | Out-Null
        $script:wrapper = Join-Path $script:RepoRoot 'tools/make-test-map.ps1'
        # A python that dies: prints a traceback shape to stderr, exits 3, writes nothing.
        $script:failPy = Join-Path $script:tmp 'fail-python.cmd'
        Set-Content -LiteralPath $script:failPy -Value "@echo off`r`necho Traceback (most recent call last): fake richchk import error 1>&2`r`nexit /b 3"
        # A python that lies: exits 0 without writing the output file.
        $script:silentPy = Join-Path $script:tmp 'silent-python.cmd'
        Set-Content -LiteralPath $script:silentPy -Value "@echo off`r`nexit /b 0"
    }
    AfterAll {
        if ($script:tmp -and (Test-Path -LiteralPath $script:tmp)) {
            Remove-Item -LiteralPath $script:tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'throws when the generator exits non-zero, carrying its output in the message' {
        $out = Join-Path $script:tmp 'never-written.scx'
        $thrown = $null
        try { & $script:wrapper -Python $script:failPy -OutputPath $out *> $null }
        catch { $thrown = $_.Exception.Message }
        $thrown | Should -Not -BeNullOrEmpty
        $thrown | Should -Match 'generation FAILED'
        $thrown | Should -Match 'python exit 3'
        # The traceback must survive INSIDE the throw: a caller assigning
        # `$gen = & ... 2>&1` loses its capture when the statement aborts.
        $thrown | Should -Match 'Traceback'
        Test-Path -LiteralPath $out | Should -BeFalse
    }

    It 'throws when the generator exits 0 but delivered no map (a green exit is not a map)' {
        $out = Join-Path $script:tmp 'also-never-written.scx'
        $thrown = $null
        try { & $script:wrapper -Python $script:silentPy -OutputPath $out *> $null }
        catch { $thrown = $_.Exception.Message }
        $thrown | Should -Not -BeNullOrEmpty
        $thrown | Should -Match 'no map exists'
        $thrown | Should -Match 'do not launch'
    }
}
