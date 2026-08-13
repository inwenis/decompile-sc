#Requires -Version 7
<#
.SYNOPSIS
End-to-end, UNATTENDED proof of what an ability with a PER-UNIT COST does to a >12
selection: 36 Marines, 24 healthy and 12 pre-damaged, one Stim Pack keypress, and every
unit's effect state AND every unit's hit points read out of the process.

This is task 022's question 1, in the user's words: "if I apply steam to ferdinarines
will all of them get steam and will all of them have HP decreased".

.DESCRIPTION
Stim (command 0x36) is the sharpest available test because its cost is VISIBLE per unit
and its affordability gate is per unit. Read off this binary (research/ability-semantics.md
2), the handler 0x004C2F30 does, for every unit in the receiving player's selection:

    0x004C2F68  CMP dword ptr [ESI + 0x8],0xa00   ; hit points vs 10.0
    0x004C2F6F  JLE skip-this-unit                ; STRICTLY greater, or nothing happens
    0x004C2FD4  MOV EAX,0xa00                     ; the cost -- the same constant
    0x004C2FD9  MOV ECX,ESI
    0x004C2FDB  CALL 0x004797B0                   ; the damage primitive
    0x004C2FE0  MOV CL,byte ptr [ESI + 0x115]     ; the stim timer
    0x004C2FEC  MOV byte ptr [ESI + 0x115],0x25   ; ... set, if it was lower

So the prediction this test exists to check in the live engine, at 36 units:

  * all 24 units that can afford it gain the effect (CUnit+0x115 == 0x25) -- 24 > 12,
    so the engine's own capped selection cannot account for it;
  * all 24 of them pay, individually, 0xa00 (10 HP) each;
  * the 12 that cannot afford it gain nothing and pay nothing -- and the split falls on
    the HP line, not on the visible/overflow line, which is what says the ENGINE decided
    and not us;
  * pressing it repeatedly walks the payers down 0x2800 -> 0x1e00 -> 0x1400 -> 0xa00 and
    then STOPS, because at exactly 0xa00 the gate is false. Stim cannot kill.

WHY THE RESULT CANNOT BE FAKED

  1. Effect and cost are read PER UNIT from the plugin's WORLD scan -- one line per unit
     carrying hp and the stim timer TOGETHER, so the pairing is observed and not inferred
     from two histograms that happen to have matching totals.
  2. The counts are also taken over the fan-out's shadow list (all 36), and `visible=12`
     / `overflow=24` are asserted, so any count above twelve is unreachable without the
     fan-out.
  3. The map has no triggers, no enemy and one unit-less computer slot, and Terran units
     do not regenerate, so nothing in the game can move a Marine's hit points or stim
     timer except this keypress. The idle step demonstrates that rather than assuming it.
  4. The before-state is asserted, not assumed: 0 stimmed, and exactly two HP values.

The fixture is generated at run time and DELETED afterwards (AGENTS.md hard rule 1). It
needs two things no earlier fixture had, both added by task 022 to tools/make_test_map.py:
`--damaged-count` (a pre-damaged tail of the same block, so payers and non-payers sit in
ONE selection) and `--tech-researched` (PTEx; without it no unit on a generated map has
any ability that needs research, which is every ability with a per-unit cost).

.EXAMPLE
./tools/plugin/test-stim-fanout.ps1

.EXAMPLE
./tools/plugin/test-stim-fanout.ps1 -IdleSeconds 60 -KeepOpen
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogPath = 'C:\sc-work\logs\022\stim-fanout.log',
    [string]$ShotDir = 'C:\sc-work\logs\022\stim-frames',
    # Which folder under Maps\ the fixture is generated into; see test-burrow-fanout.ps1.
    # Default is what this suite has always used.
    [string]$FixtureDir,
    # Long enough to show nothing drifts on its own. Shorter than the burrow test's 120s
    # because THAT test had to prove a generated map does not end itself and this one
    # inherits that result from the same template -- what this step has to show is only
    # that hit points and stim timers are stationary, which they are or are not within
    # seconds.
    [int]$IdleSeconds = 30,
    [int]$UnitCount = 36,
    [int]$DamagedCount = 12,
    # 25% of a Marine's 40 hit points is 10 -- 0xa00, EXACTLY the gate constant. The gate
    # is `JLE skip`, so these must be skipped; one off-by-one in the engine (or in this
    # tool's reading of it) and they would stim instead. That is the point of choosing it.
    [int]$DamagedHpPercent = 25,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

$failures = 0
$step = 0

# Pinned constants, asserted rather than reported.
$MARINE_TYPE = 0x00        # units.dat 0 (richchk UnitId 'Terran Marine')
$STIM_CMD = '0x36'
$STIM_KEY = 0x54           # 'T', the Marine command card's Stim Pack hotkey
$IDLE_ORDER = '0x03'
$STIM_COST = 0xa00         # research/ability-semantics.md 2 -- gate AND cost
$STIM_TIMER = 0x25
$MARINE_MAX_HP = 0x2800    # 40 HP in the engine's 1/256 fixed point; asserted below,
                           # not assumed -- the before-state read is what establishes it

# A FIXTURE FOLDER OF ITS OWN, not the shared 00-testmap: sharing one means two workers
# can pick each other's maps, which happened twice during task 022, once in each
# direction. No row is assumed from the name -- Select-ScBrowserMap computes every click
# from the filesystem and verifies what opened.
# Not a bare default any more: with $env:AGENT_TASK set this resolves to THIS
# agent's own folder, so two concurrent runs of this same suite cannot land in one
# folder and overwrite each other's identically-named fixture (task 023 review).
if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t022' -Suite 'stim-fanout' }
$mapDir = $FixtureDir
$mapName = 'stim-fanout.scx'
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
function Get-ScState { param([string]$Tag, [int]$TimeoutSec = 15)
    Get-ScUnitState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec }
function Get-World { param([string]$Tag, [int]$TimeoutSec = 20)
    Get-ScWorldState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec }

# The player's Marines, out of the engine's own unit list. Player 0 by construction.
function Get-Marines { param($World) @($World.Units | Where-Object { $_.Type -eq $MARINE_TYPE -and $_.Player -eq 0 }) }

# "Every one of these units, individually." A histogram assertion can be satisfied by the
# wrong units; this one names the predicate and counts the units that fail it.
function Assert-Every {
    param([string]$What, $Items, [scriptblock]$Predicate, [scriptblock]$Describe)
    $bad = @($Items | Where-Object { -not (& $Predicate $_) })
    $detail = if ($bad.Count -gt 0) { "(offenders: " + (($bad | Select-Object -First 6 | ForEach-Object { & $Describe $_ }) -join ' ') + ")" } else { '' }
    Assert-That "$What (all $($Items.Count))" ($Items.Count -gt 0 -and $bad.Count -eq 0) $detail
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
$launchLock = $null
function Shot([string]$tag) {
    if ($script:hwnd -eq [IntPtr]::Zero) { return }
    $script:shotN++
    Save-ScWindowImage -Hwnd $script:hwnd -Path (Join-Path $ShotDir ("{0:d2}-{1}.png" -f $script:shotN, $tag)) -FullWindow | Out-Null
}

try {
    Step "generate the fixture: $UnitCount Marines, the last $DamagedCount pre-damaged, Stim researched" {
        # Possibly several workers: wait rather than delete, and never take the folder
        # out from under a running game (see Wait-ScFixtureFolderFree -- task 022 hit
        # exactly that collision live).
        Wait-ScFixtureFolderFree -Run $fixtures
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount $UnitCount -UnitType marine -Player 0 `
            -DamagedCount $DamagedCount -DamagedHp $DamagedHpPercent `
            -TechResearched stim-packs -OutputPath $mapPath 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
        Assert-That 'its structural validation passed' `
            (@($gen | Select-String -Pattern '^OK: ').Count -gt 0)
        Assert-That 'nothing can end the game on its own (TRIG is empty)' `
            (@($gen | Select-String -Pattern 'TRIG holds 0 byte').Count -gt 0)
        # Without this the Marines have no Stim button at all and the run would fail
        # several minutes later on "the key emitted nothing", far from the cause.
        Assert-That 'Stim Packs is marked researched for the human slot' `
            (@($gen | Select-String -Pattern 'PTEx: player 0 has researched 0\(stim-packs\)').Count -gt 0)
        Assert-That "the pre-damaged tail is in the map file ($DamagedCount at $DamagedHpPercent%)" `
            (@($gen | Select-String -Pattern "the LAST $DamagedCount are pre-damaged to $DamagedHpPercent%").Count -gt 0)
        Assert-That 'the map differs from its template only where this tool meant it to' `
            (@($gen | Select-String -Pattern 'differs from the template ONLY in: OWNR SIDE UNIT TRIG FORC PTEx').Count -gt 0)
    }

    # Single-instance game, and the launch lock is normally released as soon as the
    # launch is done -- which does not protect a game that is still alive. Wait for the
    # machine, then hold the lock for this run's whole lifetime.
    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '022-stim-fanout'
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode fanout -Circles 0 -HudRow 0 -WorldScan 1 -InjectWindowedHelper WMode -NoLaunchLock `
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
        # Every row from the filesystem, and the opened folder verified before the map row
        # is clicked. Task 022 computed the FOLDER row here and left the MAP row hardcoded
        # at 159; that half was the original incident (a foreign .scx sorting before ours).
        Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null
        Set-ScGameType -Hwnd $hwnd -LogPath $logPath -Index 2      # Use Map Settings, verified (see Set-ScGameType)
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

    Step "the map spawned exactly $UnitCount Marines, in two hit-point groups" {
        Send-ScDrag -Hwnd $hwnd -X1 10 -Y1 10 -X2 630 -Y2 340 -Steps 20
        Start-Sleep -Seconds 2

        $w = Get-World 'boxed'
        $marines = Get-Marines $w
        Assert-That "the engine's own unit list holds $UnitCount Marines for player 0 ($($marines.Count))" `
            ($marines.Count -eq $UnitCount)
        # The scan is taken from the observer thread, so it says out loud whether the
        # sample was torn rather than leaving a short list to be mistaken for a death.
        Assert-That 'the world scan of player 0 was not taken mid-edit' `
            ($w.Counts[0].Units -eq $w.Counts[0].Recount -and $w.Counts[0].Complete -eq 1) `
            "(units=$($w.Counts[0].Units) recount=$($w.Counts[0].Recount) complete=$($w.Counts[0].Complete))"

        $healthy = @($marines | Where-Object { $_.Hp -gt $STIM_COST })
        $poor    = @($marines | Where-Object { $_.Hp -le $STIM_COST })
        Assert-That "$($UnitCount - $DamagedCount) Marines can afford the 0x$('{0:x}' -f $STIM_COST) cost ($($healthy.Count))" `
            ($healthy.Count -eq $UnitCount - $DamagedCount)
        Assert-That "$DamagedCount cannot ($($poor.Count))" ($poor.Count -eq $DamagedCount)
        Assert-Every 'the healthy Marines are at full hit points' $healthy `
            { param($u) $u.Hp -eq $MARINE_MAX_HP } { param($u) "hp=$($u.Hp)" }
        # THE BOUNDARY. 25% of 40 is exactly 10, and 10 is exactly the gate constant --
        # so these units sit ON the gate, where `JLE` and a hypothetical `JL` disagree.
        Assert-Every "the pre-damaged Marines sit exactly ON the gate (hp == 0x$('{0:x}' -f $STIM_COST))" $poor `
            { param($u) $u.Hp -eq $STIM_COST } { param($u) "hp=$($u.Hp)" }
        Assert-Every 'not one Marine is stimmed yet' $marines `
            { param($u) $u.Stim -eq 0 } { param($u) "stim=$($u.Stim)" }

        $script:boxed = Get-ScState 'boxed'
        Assert-That "the box holds all $UnitCount ($($boxed.N))" ($boxed.N -eq $UnitCount)
        Assert-That "the engine itself still holds only twelve ($($boxed.Visible))" ($boxed.Visible -eq 12)
        Assert-That "the rest are beyond the cap ($($boxed.Overflow))" ($boxed.Overflow -eq $UnitCount - 12)
        Assert-That "the shadow list agrees nobody is stimmed ($($boxed.Stimmed)/$($boxed.StimmedOf))" `
            ($boxed.Stimmed -eq 0 -and $boxed.StimmedOf -eq $UnitCount)
        Write-Host "       $($boxed.Line)"
        Shot 'boxed'
    }

    Step "nothing drifts on its own: ${IdleSeconds}s of no input" {
        Start-Sleep -Seconds $IdleSeconds
        Assert-That 'the game process is still alive' `
            ($null -ne (Get-Process -Id $gamePid -ErrorAction SilentlyContinue))
        $w = Get-World 'idle'
        $marines = Get-Marines $w
        Assert-That "still $UnitCount Marines after ${IdleSeconds}s ($($marines.Count))" ($marines.Count -eq $UnitCount)
        # Terran units do not regenerate, which is why this fixture uses Marines: a Zerg
        # unit would drift back over the gate while the test watched.
        Assert-Every 'no Marine gained or lost hit points on its own' $marines `
            { param($u) $u.Hp -eq $MARINE_MAX_HP -or $u.Hp -eq $STIM_COST } { param($u) "hp=$($u.Hp)" }
        Assert-Every 'and none stimmed on its own' $marines `
            { param($u) $u.Stim -eq 0 } { param($u) "stim=$($u.Stim)" }
        Shot 'after-idle'
    }

    # The whole question, one keypress at a time. Each press must reach every unit that
    # can pay, and each press must cost each of them exactly 0xa00 -- so the expected
    # hit points of a payer after N presses is 0x2800 - N*0xa00, and after three presses
    # they are ON the gate and a fourth press must do nothing at all.
    $script:pressN = 0
    function Invoke-Stim {
        param([string]$Tag, [int]$PayerHpAfter)
        $script:pressN++
        $payerCount = $UnitCount - $DamagedCount
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScKey -Hwnd $hwnd -VirtualKey $STIM_KEY
        # Short on purpose. CUnit+0x115 is a countdown, so the effect has to be read
        # while it is still running; the cost (hit points) is permanent and could be read
        # at any time, but both come off the same scan.
        Start-Sleep -Seconds 2
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)

        Assert-That "press $script:pressN`: the key emitted $STIM_CMD" `
            (@($lines | Select-String -Pattern "CMD id=$STIM_CMD ").Count -gt 0)
        $start = @($lines | Select-String -Pattern "FANOUT start: cmd=$STIM_CMD .* units=(\d+)")
        Assert-That "press $script:pressN`: it was fanned out" ($start.Count -gt 0)
        if ($start.Count -gt 0) {
            $u = [int]([regex]::Match($start[-1].Line, 'units=(\d+)').Groups[1].Value)
            Assert-That "press $script:pressN`: every placed unit was commanded ($u of $UnitCount)" ($u -eq $UnitCount)
        }
        Assert-That "press $script:pressN`: every chunk went out" `
            (@($lines | Select-String -Pattern 'FANOUT done').Count -gt 0)

        $w = Get-World $Tag
        $marines = Get-Marines $w
        Assert-That "press $script:pressN`: nobody died ($($marines.Count) Marines)" ($marines.Count -eq $UnitCount)

        # Split the group by the EFFECT and then assert the COST on each side. Splitting
        # by hit points instead would stop working at the third press, where both groups
        # are at 0xa00 and only the stim timer still tells them apart.
        $stimmed = @($marines | Where-Object { $_.Stim -gt 0 })
        $notStimmed = @($marines | Where-Object { $_.Stim -eq 0 })

        Assert-That "press $script:pressN`: exactly $payerCount units carry the stim effect ($($stimmed.Count))" `
            ($stimmed.Count -eq $payerCount) `
            "(hp/stim seen: $((($marines | ForEach-Object { "$($_.Hp)/$($_.Stim)" }) | Sort-Object -Unique) -join ' '))"
        Assert-That "press $script:pressN`: that is more than the twelve the engine holds" `
            ($stimmed.Count -gt 12)
        Assert-Every ("press {0}: every stimmed unit has paid {0} x 0x{1:x} (hp == 0x{2:x})" -f `
                      $script:pressN, $STIM_COST, $PayerHpAfter) $stimmed `
            { param($u) $u.Hp -eq $PayerHpAfter } { param($u) "hp=$($u.Hp) stim=$($u.Stim)" }
        Assert-That "press $script:pressN`: exactly $DamagedCount units carry no effect ($($notStimmed.Count))" `
            ($notStimmed.Count -eq $DamagedCount)
        Assert-Every "press $script:pressN`: and not one of them has paid anything (hp still 0x$('{0:x}' -f $STIM_COST))" `
            $notStimmed { param($u) $u.Hp -eq $STIM_COST } { param($u) "hp=$($u.Hp) stim=$($u.Stim)" }
        Assert-That "press $script:pressN`: no timer exceeds the handler's own 0x$('{0:x}' -f $STIM_TIMER)" `
            (@($stimmed | Where-Object { $_.Stim -gt $STIM_TIMER }).Count -eq 0)

        $s = Get-ScState $Tag
        Assert-That "press $script:pressN`: the shadow list agrees ($($s.Stimmed)/$($s.StimmedOf) stimmed)" `
            ($s.Stimmed -eq $payerCount)
        Write-Host "       $($s.Line)"
        Shot $Tag
    }

    Step 'Stim (0x36) once: every unit that can afford it gains the effect AND pays' {
        # Precondition, asserted not assumed: one shared order across every live unit.
        $only = @($boxed.Orders.Keys)
        Assert-That "every unit shares ONE order before the keypress (must be $IDLE_ORDER)" `
            ($only.Count -eq 1 -and $only[0] -eq $IDLE_ORDER -and $boxed.Orders[$only[0]] -eq $boxed.Live) `
            "(got $($boxed.Line))"
        Invoke-Stim -Tag 'stim-1' -PayerHpAfter ($MARINE_MAX_HP - $STIM_COST)

        # THE REASON THE SPLIT IS THE ENGINE'S, measured rather than asserted by layout.
        #
        # An earlier version of this test claimed the pre-damaged tail landed outside the
        # engine's twelve, so that a fan-out-side decision would have produced a different
        # count. Cross-referencing the pointers showed that was simply untrue of the run:
        # the engine held 8 damaged units and 4 healthy ones. The real evidence is better,
        # and it is a set comparison rather than a story about layout:
        #
        #   * the set that gained the effect is EXACTLY the set that could afford it;
        #   * that set is NOT the set beyond the cap -- they differ;
        #   * and the engine's own twelve is itself split by the hit-point line, carrying
        #     both units that stimmed and units that did not.
        #
        # No partition along the visible/overflow line can do that: it would have to take
        # all twelve of the engine's units or none of them.
        $engine = @(Get-ScSelectionGroup -LogPath $LogPath)
        Assert-That "the engine's own selection was readable ($($engine.Count) slots)" ($engine.Count -eq 12)
        $w = Get-World 'split'
        $marines = @(Get-Marines $w)
        $stimmed = @($marines | Where-Object { $_.Stim -gt 0 })
        $notStimmed = @($marines | Where-Object { $_.Stim -eq 0 })
        $visibleStimmed = @($stimmed | Where-Object { $engine -contains $_.Unit })
        $visibleNot = @($notStimmed | Where-Object { $engine -contains $_.Unit })
        Write-Host ("       of the engine's twelve: {0} stimmed, {1} not; of the {2} beyond the cap: {3} stimmed" -f `
            $visibleStimmed.Count, $visibleNot.Count, ($marines.Count - $engine.Count),
            ($stimmed.Count - $visibleStimmed.Count))
        Assert-That 'the engine own twelve is SPLIT by the hit-point line, not taken whole' `
            ($visibleStimmed.Count -gt 0 -and $visibleNot.Count -gt 0) `
            "(stimmed $($visibleStimmed.Count), not $($visibleNot.Count) -- if either were 0 the split could also be read as following the cap)"
        Assert-That 'and units beyond the cap gained the effect too' `
            (($stimmed.Count - $visibleStimmed.Count) -gt 0)
    }

    Step 'Stim again: the cost is paid AGAIN, per unit, and the effect does not stack' {
        Invoke-Stim -Tag 'stim-2' -PayerHpAfter ($MARINE_MAX_HP - 2 * $STIM_COST)
    }

    Step 'Stim a third time: the payers land exactly ON the gate' {
        Invoke-Stim -Tag 'stim-3' -PayerHpAfter ($MARINE_MAX_HP - 3 * $STIM_COST)
    }

    Step 'Stim a fourth time: nothing happens at all, on either side of the wire' {
        # 0x2800 - 3*0xa00 == 0xa00, and the receive-side gate is strictly greater, so
        # this press must be inert. This is the assertion that separates `JLE` from `JL`,
        # and it is the one that says stim can never kill the unit that pays.
        #
        # It also caught something the static reading did not predict: the press emits
        # NO COMMAND. The receive-side gate in 0x004C2F30 is not the only one -- with
        # every selected unit sitting on 0xa00 the client's own command card refuses to
        # issue the ability, so the fourth keypress does not even reach the wire. Both
        # halves are asserted, because "no command" and "a command that did nothing" are
        # different facts about the engine and only one of them is true.
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScKey -Hwnd $hwnd -VirtualKey $STIM_KEY
        Start-Sleep -Seconds 3
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        Assert-That "the key emitted NO $STIM_CMD -- the client refuses once nothing selected can pay" `
            (@($lines | Select-String -Pattern "CMD id=$STIM_CMD ").Count -eq 0)
        Assert-That 'and nothing was fanned out for it either' `
            (@($lines | Select-String -Pattern "FANOUT start: cmd=$STIM_CMD").Count -eq 0)

        $w = Get-World 'stim-4'
        $marines = Get-Marines $w
        Assert-That "still $UnitCount Marines -- stim did not kill anybody ($($marines.Count))" `
            ($marines.Count -eq $UnitCount)
        Assert-Every 'every Marine is now on the gate and none went below it' $marines `
            { param($u) $u.Hp -eq $STIM_COST } { param($u) "hp=$($u.Hp)" }
        Shot 'stim-4'
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
    if (-not $KeepOpen) { Remove-ScOwnFixture -Run $fixtures }
    # An empty folder of ours left behind still pushes every entry below it down a row,
    # and only six are visible, so it goes too -- but only if it is empty, and only ours.
    Remove-ScOwnFixtureDir -Dir $mapDir
    if ($launchLock) { Exit-ScLaunchLock -Lock $launchLock; $launchLock = $null }
}

Write-Host ''
Write-Host '[final] the run must balance'
$left = if ($gamePid -gt 0) { Get-Process -Id $gamePid -ErrorAction SilentlyContinue } else { $null }
Assert-That 'the game process this test started is gone' ($KeepOpen -or $null -eq $left)
Assert-That 'the generated map was cleaned up' ($KeepOpen -or -not (Test-Path -LiteralPath $mapPath))

$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-stim-fanout: $failures failure(s)"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
