#Requires -Version 7
<#
.SYNOPSIS
End-to-end, UNATTENDED proof that an untargeted ABILITY fans out past the 12-unit
selection cap in the live game: generates a playable Use Map Settings map holding 36
Lurkers, boxes all of them, presses Burrow ONCE, and asserts that every one of the 36
is burrowed -- read out of each unit's own flags from inside the process.

.DESCRIPTION
The fixture is generated at run time by tools/make_test_map.py: generated maps are game
content and are never committed (AGENTS.md § "Hard rules"). Two properties of that
generator are what make this test possible at all (tools/README-test-map.md):

  * the human slot's SIDE must be an explicit race, not "User Selectable" -- otherwise
    StarCraft hands that slot the standard MELEE starting units even under Use Map
    Settings and never creates the map's own units;
  * TRIG must be empty -- otherwise the template's own triggers (a ladder map's melee
    triggers, a campaign map's mission objectives) end the game within seconds of loading.

Why the result cannot be faked: `burrowed` is counted over the plugin's SHADOW list --
all 36 units, not the 12 the engine holds -- from each unit's own CUnit+0xDC bit 0x10, so
36/36 is a claim about every unit's state and not about the picture or the largest bucket;
the map has no triggers, no enemy units and one unit-less computer slot, so nothing in the
game can burrow a Lurker except the command this test issues; and Burrow is innate to
Lurkers, so the map needs no tech state.

Driving recipe as in test-fanout-orders.ps1 (research/automated-testing-options.md §4.1):
posted Win32 messages in client coordinates, no synthetic OS input, focus not required,
window must not be minimised.

Frames are a DIAGNOSTIC only and land outside the repo -- they reproduce game artwork and
must never be committed.

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
    # Which folder under Maps\ the fixture is generated into. Concurrent workers share
    # this suite, so each points it at its own folder and nobody's row click can land on
    # anybody else's map.
    [string]$FixtureDir,
    # How long the map must sit there doing nothing. The failure this guards against
    # (a template's own victory/defeat triggers) fires within about seven seconds, so
    # two minutes is well past it; raise it to watch for a slower one.
    [int]$IdleSeconds = 120,
    [int]$UnitCount = 36,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')

. (Join-Path $scriptDir 'sc-suite.ps1')

$failures = 0
$step = 0

# Pinned ids, asserted rather than reported.
#   $LURKER_TYPE  units.dat 103. All one type on purpose: a MIXED selection is offered
#                 only the basic command card in game, with no ability button to press
#                 at all (research/command-opcodes.md §8).
#   $BURROW_CMD   the command id the Burrow button emits (research/data/command-opcodes.tsv:
#                 0x2C, len 2, handler 0x004C1FA0, LOOP selection shape, policy fanout).
#   $BURROW_KEY   'U', the Lurker command card's Burrow hotkey; a wrong key fails the run
#                 on "the key emitted 0x2C" rather than silently.
$LURKER_TYPE = '0x67'
$BURROW_CMD = '0x2C'
$BURROW_KEY = 0x55
$IDLE_ORDER = '0x03'

# The generated fixture. The map name is the suite's own: one suite, one name, so
# ownership is readable off the filename and "delete only your own file" stays decidable
# when two suites share a folder. With $env:AGENT_TASK set the folder resolves to THIS
# agent's own, so two concurrent runs of this suite cannot overwrite each other's fixture
# (AGENTS.md § "Test fixtures").
if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-testmap' -Suite 'burrow-fanout' }
$mapDir = $FixtureDir
$mapName = 'burrow-fanout.scx'
$mapPath = Join-Path $mapDir $mapName
$fixtures = New-ScFixtureRun -Dir $mapDir -Names @($mapName)

$markerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt'
function Get-ScState {
    param([string]$Tag, [int]$TimeoutSec = 15)
    Get-ScUnitState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec
}

# "Every live unit is of exactly one type, and it is this one." Single-bucket on purpose:
# a histogram whose largest bucket is 20 of 36 says nothing about the other sixteen.
function Assert-ScAllOneType {
    param([string]$What, $State, [string]$ExpectedType)
    $only = @($State.Types.Keys)
    $ok = ($only.Count -eq 1) -and ($State.Types[$only[0]] -eq $State.Live) -and
          ($only[0] -eq $ExpectedType)
    Assert-That "$What`: all $($State.Live) units are $ExpectedType" $ok "(got $($State.TypesText))"
}

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
        # The fixture folder may be SHARED between workers and the map browser opens a ROW,
        # so a foreign .scx moves which map loads -- and a recursive delete here takes
        # another worker's fixture out from under its running game. Ownership is the
        # declared set above: wait for THEIRS to go, clear only OURS
        # (AGENTS.md § "Test fixtures").
        Wait-ScFixtureFolderFree -Run $fixtures
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount $UnitCount -UnitType lurker -Player 0 -OutputPath $mapPath 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
        # The generator's own structural validation is part of the contract: it is what
        # asserts the human slot is 0x06, the race is not "User Selectable", TRIG is empty,
        # and every other CHK section came across byte-for-byte from the template.
        Assert-That 'its structural validation passed' `
            (@($gen | Select-String -Pattern '^OK: ').Count -gt 0)
        Assert-That 'nothing can end the game on its own (TRIG is empty)' `
            (@($gen | Select-String -Pattern 'TRIG holds 0 byte').Count -gt 0)
        Assert-That 'the map differs from its template only where this tool meant it to' `
            (@($gen | Select-String -Pattern 'differs from the template ONLY in: OWNR SIDE UNIT TRIG FORC').Count -gt 0)
        # With the FORC "randomize start location" bit set, the human's player id is not
        # fixed: one of three otherwise-identical loads comes up as player 1, owning none
        # of the placed units. An intermittent failure is worse than a reliable one, so
        # the fixture must not leave the choice open.
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

        # Set the Game Type EXPLICITLY rather than trusting what the box shows: the combo
        # comes up carrying whatever this machine's profile last used, and a stale "Melee"
        # makes the map play as a melee game. Entry 2 of {Melee, Free For All, Use Map
        # Settings}; picking the wrong one fails the unit-type assertion below rather than
        # passing quietly (AGENTS.md § "Game Type / `Custom Type`").
        Set-ScGameType -Hwnd $hwnd -LogPath $LogPath -Index 2      # Use Map Settings, verified
        Shot 'lobby'

        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> mission briefing
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 10
        # Found in the engine's own dialog list and dismissed by ITS OWN OK button, then
        # asserted gone -- never a fixed point, never the registry (AGENTS.md § "Tips dialog").
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
        # Read from inside the process: the units in the FILE are the units in the GAME.
        # A melee start reports Drones, Larva and an Overlord here instead.
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
        # A template's own victory/defeat triggers end a generated map within seconds, so
        # this waits well past that and then proves the game is still there by BOXING
        # again -- a stale shadow list does not survive that, and an ended game reports n=0.
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
        # Precondition, asserted not assumed: one shared order across every live unit. No
        # arrival to confuse it with -- burrowing is not something a standing unit drifts
        # into.
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
        # The engine holds twelve and the other twenty-four sit past the cap, so a burrowed
        # count above twelve is not reachable without the fan-out.
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
catch { Write-ScStepFailure $_ 'a test step' }
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
        # Take the FOLDER away too when it is empty: an extra directory pushes the entries
        # below it down, and with six visible rows a pile of abandoned folders pushes a
        # target off the visible list entirely. Remove-ScOwnFixtureDir refuses a folder
        # with anything at all still in it.
        Remove-ScOwnFixtureDir -Dir $mapDir
    }
}

Write-Host ''
Write-Host '[final] the run must balance'
$left = if ($gamePid -gt 0) { Get-Process -Id $gamePid -ErrorAction SilentlyContinue } else { $null }
Assert-That 'the game process this test started is gone' ($KeepOpen -or $null -eq $left)
# This test's own fixture, not the folder: the folder is shared with other workers (see
# the note at the generation step).
Assert-That 'the generated map was cleaned up' ($KeepOpen -or -not (Test-Path -LiteralPath $mapPath))

$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-burrow-fanout: $failures failure(s)"
Write-Host "frames (diagnostic): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
