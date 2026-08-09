#Requires -Version 7
<#
.SYNOPSIS
End-to-end, UNATTENDED proof that an untargeted ABILITY fans out past the 12-unit
selection cap in the live game: generates a playable Use Map Settings map holding 36
Lurkers, boxes all of them, presses Burrow ONCE, and asserts that every one of the 36
is burrowed -- read out of each unit's own flags from inside the process.

This closes the half of task 015's acceptance criterion 3 that was waived for want of a
fixture (research/command-opcodes.md §8). Task 015 proved the untargeted-COMMAND path
live (Stop, Hold Position at 24 units) and the whole 19-id set byte-exact offline; the
untargeted-ability half needed a map no stock file could supply.

.DESCRIPTION
The fixture is generated at run time by tools/make_test_map.py and DELETED afterwards --
generated maps are game content and are never committed (AGENTS.md hard rule 1). Two
properties of that generator are what make this test possible at all, both root-caused by
task 016 and documented in tools/README-test-map.md:

  * the human slot's SIDE must be an explicit race, not the ladder template's
    "User Selectable" -- otherwise StarCraft hands that slot the standard MELEE starting
    units even under Use Map Settings and never creates the map's own units;
  * TRIG must be empty -- otherwise the template's own triggers (a ladder map's three
    standard melee triggers, a campaign map's mission objectives) end the game within
    seconds of loading.

WHY THE RESULT CANNOT BE FAKED:

  1. `burrowed` is counted over the plugin's SHADOW list -- all 36 units, not the 12 the
     engine holds -- from each unit's own CUnit+0xDC bit 0x10. 36/36 is a claim about
     every unit's state, not about the picture and not about the largest bucket.
  2. The engine holds twelve (`visible=12`, `overflow=24` is asserted). Twenty-four of
     the thirty-six are past the cap, so a burrow count above twelve is not reachable
     without the fan-out.
  3. The map has NO triggers, NO enemy units and one unit-less computer slot, so nothing
     in the game can burrow a Lurker except the command this test issues. The idle step
     demonstrates that directly: after 120 s of nothing happening the count is still 0/36.
  4. Burrow is innate to Lurkers -- no research -- so the map needs no tech state, and
     the before-state is asserted to be 0/36 rather than assumed.

Same driving recipe as test-fanout-orders.ps1 (task 012's D1,
research/automated-testing-options.md §4.1): posted Win32 messages in client
coordinates, no synthetic OS input, focus not required, window must not be minimised.

Frames are captured as a DIAGNOSTIC only and land outside the repo -- they reproduce game
artwork and must never be committed.

.EXAMPLE
./tools/plugin/test-burrow-fanout.ps1

.EXAMPLE
./tools/plugin/test-burrow-fanout.ps1 -IdleSeconds 300 -KeepOpen
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogPath = 'C:\sc-work\logs\016-burrow-fanout.log',
    [string]$ShotDir = 'C:\sc-work\logs\016-burrow-frames',
    # Which folder under Maps\ the fixture is generated into. More than one task runs
    # this suite, so it cannot be nailed to one task's folder -- a worker points it at
    # its own (`-FixtureDir <GameDir>\Maps\BroodWar\00-t023`) and nobody's row click can
    # land on anybody else's map. The default is what this suite has always used.
    [string]$FixtureDir,
    # How long the map must sit there doing nothing. The failure this guards against
    # (a template's own victory/defeat triggers) fired within about seven seconds, so
    # two minutes is well past it; raise it to watch for a slower one.
    [int]$IdleSeconds = 120,
    [int]$UnitCount = 36,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')

$failures = 0
$step = 0

# Pinned ids, asserted rather than reported.
#   $LURKER_TYPE  units.dat 103. The fixture is all one type on purpose: a MIXED
#                 selection is offered only the basic command card in game, with no
#                 ability button to press at all (research/command-opcodes.md §8).
#   $BURROW_CMD   the command id the Burrow button emits. Already in the fan-out set
#                 (research/data/command-opcodes.tsv: 0x2C, len 2, handler 0x004C1FA0,
#                 LOOP selection shape, policy fanout).
#   $BURROW_KEY   'U', the Lurker command card's Burrow hotkey. If it were the wrong
#                 key the run fails on "the key emitted 0x2C", not silently.
$LURKER_TYPE = '0x67'
$BURROW_CMD = '0x2C'
$BURROW_KEY = 0x55
$IDLE_ORDER = '0x03'

# The generated fixture.
#
# THE NAME IS THE SUITE'S OWN, and that is not cosmetic: this suite and test-hud-row.ps1
# both used to generate `lurkers.scx`, which made "delete only your own file" undecidable
# between them and blocked a run outright when one held the other's file open (task 022,
# 2026-08-09). One suite, one name, so ownership is readable off the filename.
#
# No row is assumed from the folder name any more -- Select-ScBrowserMap computes every
# click from the filesystem and checks what opened (drive-game.ps1).
# Not a bare default any more: with $env:AGENT_TASK set this resolves to THIS
# agent's own folder, so two concurrent runs of this same suite cannot land in one
# folder and overwrite each other's identically-named fixture (task 023 review).
if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-testmap' }
$mapDir = $FixtureDir
$mapName = 'burrow-fanout.scx'
$mapPath = Join-Path $mapDir $mapName
$fixtures = New-ScFixtureRun -Dir $mapDir -Names @($mapName)

function Assert-That {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "  ok   $What" }
    else { Write-Host "  FAIL $What $Detail"; $script:failures++ }
}

function Step {
    param([string]$Name, [scriptblock]$Body)
    $script:step++
    Write-Host ''
    Write-Host ("[{0}] {1}" -f $script:step, $Name)
    & $Body
}

$markerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt'
function Get-ScState {
    param([string]$Tag, [int]$TimeoutSec = 15)
    Get-ScUnitState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec
}

# "Every live unit is of exactly one type, and it is this one." Single-bucket, like the
# order assertions in test-fanout-orders.ps1: a histogram whose largest bucket is 20 of
# 36 would say nothing about the other sixteen.
function Assert-ScAllOneType {
    param([string]$What, $State, [string]$ExpectedType)
    $only = @($State.Types.Keys)
    $ok = ($only.Count -eq 1) -and ($State.Types[$only[0]] -eq $State.Live) -and
          ($only[0] -eq $ExpectedType)
    Assert-That "$What`: all $($State.Live) units are $ExpectedType" $ok "(got $($State.TypesText))"
}

# --- on-disk binary, BEFORE anything runs --------------------------------------
$exePath = Join-Path $GameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $exePath)) { throw "test: $exePath not found." }
$hashBefore = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "[0] StarCraft.exe SHA-256 before: $hashBefore"
$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
Assert-That 'the working copy starts out byte-identical to pristine 1.16.1' `
    ($hashBefore -eq $PRISTINE_SHA256) "(got $hashBefore)"

if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }
New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null

$gamePid = 0
$hwnd = [IntPtr]::Zero
$shotN = 0
function Shot([string]$tag) {
    if ($script:hwnd -eq [IntPtr]::Zero) { return }
    $script:shotN++
    Save-ScWindowImage -Hwnd $script:hwnd -Path (Join-Path $ShotDir ("{0:d2}-{1}.png" -f $script:shotN, $tag)) -FullWindow | Out-Null
}

try {
    Step "generate the fixture: $UnitCount Lurkers, Use Map Settings, no triggers" {
        # AGENTS.md rule 4 (task 022): the fixture folder may be SHARED between workers and
        # the map browser opens a ROW, so a foreign .scx moves which map loads -- and a
        # recursive delete here takes another worker's fixture out from under its running
        # game. Ownership is the declared set above, so this waits for THEIRS to go and
        # clears only OURS.
        Wait-ScFixtureFolderFree -Run $fixtures
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount $UnitCount -UnitType lurker -Player 0 -OutputPath $mapPath 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
        # The generator's own structural validation is part of the contract, not decoration:
        # it is what asserts the human slot is 0x06, the race is not "User Selectable", TRIG
        # is empty, and every other CHK section came across byte-for-byte from the template.
        Assert-That 'its structural validation passed' `
            (@($gen | Select-String -Pattern '^OK: ').Count -gt 0)
        Assert-That 'nothing can end the game on its own (TRIG is empty)' `
            (@($gen | Select-String -Pattern 'TRIG holds 0 byte').Count -gt 0)
        Assert-That 'the map differs from its template only where this tool meant it to' `
            (@($gen | Select-String -Pattern 'differs from the template ONLY in: OWNR SIDE UNIT TRIG FORC').Count -gt 0)
        # With the FORC "randomize start location" bit set, the human's player id is not
        # fixed: one of three otherwise-identical in-game loads came up as player 1,
        # owning none of the placed units. An intermittent failure is worse than a
        # reliable one, so the fixture must not leave the choice open.
        Assert-That "the human's player id is not left to the engine to pick" `
            (@($gen | Select-String -Pattern 'no force randomises start locations').Count -gt 0)
    }

    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode fanout -Circles 0 -HudRow 0 -InjectWindowedHelper WMode `
        -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step "menus: Single Player -> Expansion -> Play Custom -> $mapName" {
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
        Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # StarCraft: Brood War (Expansion)
        Start-Sleep -Seconds 1
        Send-ScClick -Hwnd $hwnd -X 75  -Y 111        # first entry in the Registry list
        Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 327 -Y 415        # Play Custom -- opens in Maps\BroodWar
        Start-Sleep -Seconds 2
        # LAST CHECK BEFORE THE ROW IS CLICKED, not only at generate time: the folder can
        # be added to in between, and every row below the addition moves.
        Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null

        # Set the Game Type EXPLICITLY rather than trusting what the box shows. The combo
        # comes up carrying whatever this machine's profile last used, and a stale "Melee"
        # would make the map play as a melee game -- which is the failure task 015 hit and
        # spent a whole task chasing. Entry 2 of {Melee, Free For All, Use Map Settings};
        # picking the wrong one fails the unit-type assertion below rather than passing
        # quietly. (SC's dropdowns are press-and-hold: see Send-ScDropdownPick.)
        Send-ScDropdownPick -Hwnd $hwnd -X 265 -Y 268 -Index 2
        Shot 'lobby'

        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> mission briefing
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 10
        # The tips dialog is found in the engine's own dialog list and dismissed by ITS OWN
        # OK button, then asserted gone (task 027) -- never a fixed point, never the registry.
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
        Shot 'in-game'
    }

    Step "the map spawned exactly the $UnitCount placed Lurkers, and nothing else" {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScDrag -Hwnd $hwnd -X1 10 -Y1 10 -X2 630 -Y2 340 -Steps 20
        Start-Sleep -Seconds 2
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        Assert-That 'the shadow list holds the whole box' `
            (@($lines | Select-String -Pattern 'SHADOW captured: (\d+) units').Count -gt 0)

        $script:boxed = Get-ScState 'boxed'
        # This is acceptance criterion 2 read from inside the process: the units in the
        # FILE are the units in the GAME. A melee start would report Drones, Larva and an
        # Overlord here -- which is exactly what it did report before the SIDE fix.
        Assert-That "the box holds all $UnitCount placed units ($($boxed.N))" ($boxed.N -eq $UnitCount)
        Assert-ScAllOneType 'the spawned units' $boxed $LURKER_TYPE
        Assert-That "the engine itself still holds only twelve ($($boxed.Visible))" ($boxed.Visible -eq 12)
        Assert-That "the rest are beyond the cap ($($boxed.Overflow))" `
            ($boxed.Overflow -eq $UnitCount - 12)
        Assert-That "not one of them is burrowed yet ($($boxed.Burrowed)/$($boxed.BurrowedOf))" `
            ($boxed.Burrowed -eq 0 -and $boxed.BurrowedOf -eq $UnitCount)
        Write-Host "       $($boxed.Line)"
        Shot 'boxed'
    }

    Step "the mission does not end itself: ${IdleSeconds}s of nothing" {
        # The other half of criterion 2. A generated map used to end within about seven
        # seconds on its template's own victory/defeat triggers; this waits well past that
        # and then proves the game is still there by BOXING again -- a stale shadow list
        # would not survive that, and a game that had ended reports n=0.
        Start-Sleep -Seconds $IdleSeconds
        Assert-That 'the game process is still alive' `
            ($null -ne (Get-Process -Id $gamePid -ErrorAction SilentlyContinue))
        Send-ScDrag -Hwnd $hwnd -X1 10 -Y1 10 -X2 630 -Y2 340 -Steps 20
        Start-Sleep -Seconds 2
        $idle = Get-ScState 'idle'
        Assert-That "the mission is still running after ${IdleSeconds}s ($($idle.Live) units alive)" `
            ($idle.Live -eq $UnitCount)
        Assert-ScAllOneType "after ${IdleSeconds}s" $idle $LURKER_TYPE
        # Nothing drifted on its own -- which is what makes the 0 -> 36 step below
        # attributable to the keypress and to nothing else in the game.
        Assert-That "and still not one of them has burrowed on its own ($($idle.Burrowed)/$($idle.BurrowedOf))" `
            ($idle.Burrowed -eq 0)
        Write-Host "       $($idle.Line)"
        $script:before = $idle
        Shot 'after-idle'
    }

    Step "Burrow ($BURROW_CMD), an UNTARGETED ABILITY, reaches every unit" {
        # Precondition, asserted not assumed: one shared order across every live unit, and
        # nobody burrowed. There is no arrival to confuse this with -- the units have been
        # standing still for two minutes and burrowing is not something a unit drifts into.
        $only = @($before.Orders.Keys)
        Assert-That "every unit shares ONE order before the keypress (must be $IDLE_ORDER)" `
            ($only.Count -eq 1 -and $only[0] -eq $IDLE_ORDER -and $before.Orders[$only[0]] -eq $before.Live) `
            "(got $($before.Line))"

        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScKey -Hwnd $hwnd -VirtualKey $BURROW_KEY
        Start-Sleep -Seconds 4
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)

        Assert-That "the key emitted $BURROW_CMD" `
            (@($lines | Select-String -Pattern "CMD id=$BURROW_CMD ").Count -gt 0)
        $start = @($lines | Select-String -Pattern "FANOUT start: cmd=$BURROW_CMD .* units=(\d+)")
        Assert-That 'it was fanned out' ($start.Count -gt 0)
        if ($start.Count -gt 0) {
            $u = [int]([regex]::Match($start[-1].Line, 'units=(\d+)').Groups[1].Value)
            Assert-That "more than twelve units were commanded ($u)" ($u -gt 12)
            Assert-That "every placed unit was commanded ($u of $UnitCount)" ($u -eq $UnitCount)
        }
        Assert-That 'every chunk went out' `
            (@($lines | Select-String -Pattern 'FANOUT done').Count -gt 0)

        $after = Get-ScState 'burrowed'
        Assert-That "nobody died on the way ($($before.Live) -> $($after.Live))" `
            ($after.Live -eq $before.Live)
        # THE ASSERTION THIS WHOLE TEST EXISTS FOR: every unit of a >12 selection is
        # burrowed, counted one unit at a time out of the engine's own flags.
        Assert-That "burrowed went $($before.Burrowed)/$($before.BurrowedOf) -> $($after.Burrowed)/$($after.BurrowedOf)" `
            ($after.Burrowed -eq $after.BurrowedOf -and $after.BurrowedOf -eq $UnitCount)
        Assert-That "and that is more than the twelve the engine holds ($($after.Burrowed))" `
            ($after.Burrowed -gt 12)
        Write-Host "       $($after.Line)"
        Shot 'after-burrow'
    }

    Step 'the run never fanned out anything outside the policy set' {
        $allowed = @('0x14', '0x15', '0x1A', '0x1B', '0x1C', '0x1D', '0x1E', '0x21',
                     '0x22', '0x25', '0x26', '0x28', '0x2A', '0x2B', '0x2C', '0x2D',
                     '0x2E', '0x36', '0x5A')
        $ids = @(Get-Content -LiteralPath $LogPath |
                 Select-String -Pattern 'FANOUT start: cmd=(0x[0-9A-F]{2})' |
                 ForEach-Object { [regex]::Match($_.Line, 'cmd=(0x[0-9A-F]{2})').Groups[1].Value } |
                 Sort-Object -Unique)
        Write-Host "       ids fanned out this run: $($ids -join ' ')"
        $stray = @($ids | Where-Object { $allowed -notcontains $_ })
        Assert-That 'every fanned-out id is in the policy set' ($stray.Count -eq 0) `
            ($stray.Count -gt 0 ? "(stray: $($stray -join ' '))" : '')
    }
}
catch {
    Write-Host "  FAIL a test step threw: $($_.Exception.Message)"
    Write-Host "       $($_.ScriptStackTrace)"
    $failures++
}
finally {
    if (-not $KeepOpen -and $gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch {
            Write-Host "  FAIL close-game could not shut the game down: $($_.Exception.Message)"
            $failures++
        }
        Start-Sleep -Seconds 2
    }
    elseif (-not $KeepOpen) {
        Write-Host '  FAIL no pid was ever parsed, so nothing could be closed'
        $failures++
    }
    # The fixture is game content: it is generated for the run and never survives it.
    if (-not $KeepOpen -and (Test-Path -LiteralPath $mapDir)) {
        Remove-ScOwnFixture -Run $fixtures
        # And take the FOLDER away too when it is empty. Leaving an empty one behind is
        # not harmless even now that rows are computed: an extra directory pushes the
        # entries below it down, and with six visible rows a pile of abandoned folders
        # eventually pushes a target off the visible list entirely.
        # Remove-ScOwnFixtureDir refuses if anything at all is still in it.
        Remove-ScOwnFixtureDir -Dir $mapDir
    }
}

Write-Host ''
Write-Host '[final] the run must balance'
$left = if ($gamePid -gt 0) { Get-Process -Id $gamePid -ErrorAction SilentlyContinue } else { $null }
Assert-That 'the game process this test started is gone' ($KeepOpen -or $null -eq $left)
# This test's own fixture, not the folder: the folder is shared with other workers and
# this suite no longer removes it (AGENTS.md rule 4 -- see the note at the generation step).
Assert-That 'the generated map was cleaned up' ($KeepOpen -or -not (Test-Path -LiteralPath $mapPath))

$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-burrow-fanout: $failures failure(s)"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
