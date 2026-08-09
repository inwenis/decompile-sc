#Requires -Version 7
<#
.SYNOPSIS
Name the Ghost's Personnel Cloaking button -- and, if nothing names it, say WHY with a
control that separates "the input never reached the card" from "the ability was never on
the card in the first place".

.DESCRIPTION
THE QUESTION, inherited from task 022. That task could not drive Cloak. It reported that
`C` emits nothing even at full energy, and that clicking the bottom-left command-card slot
produced a frame reading "Select Target" -- i.e. that slot is a TARGETED ability
(Lockdown), so the click armed something and issued nothing. The underlying mechanism was
answered without it, but the user's original report was about a CLOAKED GHOST
specifically, so the unit itself is still unanswered.

WHAT THIS MEASURES. Every command the client sends goes through queueCommand, which the
plugin logs as `CMD id=0x.. len=.. bytes=[..]` (research/command-path.md 1). So a keypress
or a card click has exactly three possible outcomes, and all three are visible:

  * it emits a command -- the id names the ability (Personnel Cloaking is 0x21:
    research/ability-semantics.md 3, the handler that deducts energy and sets the
    secondary order to 0x6D);
  * it emits nothing and ARMS a targeted order -- no CMD line at press time, and the
    NEXT left-click issues one. Each step cancels with a right-click and records the
    key as "armed nothing", which is what task 022 saw for the slot it clicked;
  * it emits nothing at all.

FOUR ARMS, because a bare negative from one of them means nothing:

  A. every key A-Z against the whole >12 Ghost selection;
  B. every key A-Z against ONE Ghost. A >12 homogeneous selection is not obviously
     offered the same command card as a single unit (research/command-opcodes.md 8
     records that a MIXED selection gets only the basic card), so a negative on the block
     alone would not separate "the key is not a letter" from "this is not the ability
     card";
  C. all nine command-card slots, CLICKED. If no key names the ability, the button still
     can: a click on an untargeted ability emits its command there and then;
  D. THE CONTROL ARM, and the one that makes a negative worth reading. Arms A-C run on a
     fixture with Personnel Cloaking marked researched in PTEx; arm D runs the identical
     fixture WITHOUT the tech and fingerprints the same command-card rectangle. If the
     two cards are byte-identical then the researched fixture never put the ability on
     the card, and no amount of pressing keys at it was ever going to work -- the blocker
     is the FIXTURE, not the input path. If they differ, the ability is on the card and
     the blocker really is the input path.

Positive before negative (AGENTS.md, 2026-08-09): a bare "nothing emitted 0x21" is worth
nothing unless the same mechanism is shown WORKING, so the run also requires that some key
and some card slot emitted a basic-card command (Hold 0x2B / Stop 0x1A). Both are asserted
before the Cloak verdict is read.

.EXAMPLE
./tools/plugin/probe-ghost-cloak.ps1

.EXAMPLE
./tools/plugin/probe-ghost-cloak.ps1 -Keys C,D,E     # a shorter sweep while iterating
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogDir = 'C:\sc-work\logs\023',
    [string]$FixtureDir,
    [int]$UnitCount = 18,
    # A..Z. The command card's hotkeys are plain letters -- no modifier is involved, so
    # task 021's accelerator finding does not apply (drive-game.ps1 KNOWN LIMITS).
    [string[]]$Keys = @('A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
                        'Q','R','S','T','U','V','W','X','Y','Z'),
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

$failures = 0
function Assert-That {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "  ok   $What" }
    else { Write-Host "  FAIL $What $Detail"; $script:failures++ }
}

$CLOAK_CMD = '0x21'      # Personnel Cloaking (research/ability-semantics.md 3)
$GHOST_TYPE = 1

# The command card, in CLIENT coordinates. Read off a captured frame with the (+5,+32)
# window offset already subtracted -- the trap that made task 021 "fix" a coordinate that
# was correct (Save-ScWindowImage / Get-ScRegionFingerprint both take client coords and
# add the offset themselves). The three column centres and three row centres below are
# confirmed live: clicking (568,375) emits Stop and (568,418) emits Hold.
$CARD_COLS = @(523, 568, 613)
$CARD_ROWS = @(375, 418, 458)
$CARD_RECT = @{ X = 500; Y = 355; Width = 140; Height = 125 }

if (-not $FixtureDir) { $FixtureDir = Join-Path $GameDir 'Maps\BroodWar\00-t023' }
# Two fixtures, declared together: the ownership rule is per-RUN, so a suite that creates
# more than one file must name them all up front or its own second fixture reads as
# somebody else's (the 2026-08-09 self-deadlock, AGENTS.md).
$mapName = 'ghost-cloak.scx'
$ctlName = 'ghost-nocloak.scx'
$mapPath = Join-Path $FixtureDir $mapName
$ctlPath = Join-Path $FixtureDir $ctlName
$fixtures = New-ScFixtureRun -Dir $FixtureDir -Names @($mapName, $ctlName)
$logPath = Join-Path $LogDir 'ghost-cloak.log'
$shotDir = Join-Path $LogDir 'ghost-cloak-frames'
$markerPath = Join-Path $LogDir 'marker.txt'
New-Item -ItemType Directory -Path $LogDir, $shotDir -Force | Out-Null
foreach ($p in @($logPath, $markerPath)) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }

$gamePid = 0
$launchLock = $null
$table = @(); $solo = @(); $card = @()
# The world state read AT THE MOMENT a press or click emitted 0x21, not after the sweep.
# Cloak is a TOGGLE and it drains energy, so a snapshot taken at the end of a 26-key sweep
# could deny a cloak that really happened.
$cloakProof = $null

# One Ghost fixture, generated and validated. Returns the generator's own output lines so
# the caller can assert on them rather than on this function's say-so.
function New-GhostFixture {
    param([string]$Path, [switch]$WithTech)
    # A HASHTABLE, not an array: splatting an array passes its elements POSITIONALLY, so
    # '-UnitCount' itself lands in the first positional parameter.
    $genArgs = @{ UnitCount = $UnitCount; UnitType = 'ghost'; Player = 0; Race = 'terran'
                  OutputPath = $Path }
    if ($WithTech) { $genArgs['TechResearched'] = 'personnel-cloaking' }
    $out = & (Join-Path $repoRoot 'tools/make-test-map.ps1') @genArgs 2>&1
    $out = @($out | Where-Object { "$_" -notmatch 'WARNING:StormLibFinder' })
    $out | ForEach-Object { Write-Host "       $_" }
    ,$out
}

# Launch, walk the menus, load $MapPath, and leave exactly one Ghost selected. Returns the
# game pid and window handle. Every browser click inside is computed from the filesystem
# by Select-ScBrowserMap -- no fixed rows anywhere in this file.
function Start-GhostGame {
    param([string]$MapPath)
    Wait-ScNoGameRunning
    $script:launchLock = Enter-ScLaunchLock -TaskId '023-ghost-cloak'
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode fanout -WorldScan 1 -InjectWindowedHelper WMode -NoLaunchLock `
        -GameDir $GameDir -LogPath $logPath 6>&1 | ForEach-Object {
            Write-Host "       $_"
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $script:gamePid) { throw 'probe: could not parse the game pid from scinject output.' }
    $h = Get-ScGameWindow -ProcessId $script:gamePid

    Start-Sleep -Seconds 2
    Send-ScClick -Hwnd $h -X 215 -Y 119
    Send-ScClick -Hwnd $h -X 373 -Y 300
    Start-Sleep -Seconds 1
    Send-ScClick -Hwnd $h -X 75  -Y 111
    Send-ScClick -Hwnd $h -X 516 -Y 392
    Start-Sleep -Seconds 2
    Send-ScClick -Hwnd $h -X 327 -Y 415
    Start-Sleep -Seconds 2
    Assert-ScFixtureStillMine -Run $fixtures -MapPath $MapPath
    Select-ScBrowserMap -Hwnd $h -GameDir $GameDir -MapPath $MapPath | Out-Null
    Set-ScGameType -Hwnd $h -Index 2
    Send-ScClick -Hwnd $h -X 516 -Y 393
    Start-Sleep -Seconds 6
    Send-ScClick -Hwnd $h -X 544 -Y 387
    Start-Sleep -Seconds 10
    Send-ScClick -Hwnd $h -X 200 -Y 261
    Start-Sleep -Seconds 3
    $h
}

function Stop-GhostGame {
    if ($script:gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $script:gamePid | Write-Host }
        catch { Write-Host "  FAIL close-game: $($_.Exception.Message)"; $script:failures++ }
        Start-Sleep -Seconds 2
        $script:gamePid = 0
    }
    if ($script:launchLock) { Exit-ScLaunchLock -Lock $script:launchLock; $script:launchLock = $null }
}

# The CMD ids a single action put on the wire, minus the per-frame sync command.
function Get-EmittedIds {
    param([int]$Mark)
    @(Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue | Select-Object -Skip $Mark |
      Select-String -Pattern 'CMD id=(0x[0-9A-F]{2})' |
      ForEach-Object { $_.Matches[0].Groups[1].Value } |
      Where-Object { $_ -ne '0x37' } |
      Select-Object -Unique)
}

# THE SECOND HALF OF THE MEASUREMENT, and the one an earlier version of this probe was
# missing. A command-card entry has two ways to produce no CMD line at press time: it did
# nothing, or it ARMED a targeted order and is waiting for a target -- which is exactly
# what task 022 saw ("Select Target"). Cancelling with a right-click, as this probe used
# to, makes those two cases identical in the log.
#
# So every action is followed by a LEFT click on open ground. With something armed, that
# click issues it and the id names the ability. With nothing armed, a left click on
# terrain issues no command at all (it is the right button that gives a move order), so
# the baseline is empty and any id here is signal, not noise.
function Get-ArmedIds {
    param([int]$X = 200, [int]$Y = 120)
    $mark = Get-ScLogLineCount -LogPath $logPath
    Send-ScClick -Hwnd $hwnd -X $X -Y $Y -SettleMs 600
    @(Get-EmittedIds -Mark $mark)
}

try {
    Write-Host ''
    Write-Host '[1] the CONTROL fixture: the same Ghosts with NO tech researched'
    # Once, before ANY fixture exists. It clears this run's own leftovers, so calling it
    # again between the two arms would delete the control map this run had just made.
    Wait-ScFixtureFolderFree -Run $fixtures
    $ctlGen = New-GhostFixture -Path $ctlPath
    Assert-That 'the control generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
    Assert-That 'and it wrote NO PTEx research -- that is what makes it a control' `
        (@($ctlGen | Select-String -Pattern 'PTEx: player 0 has researched').Count -eq 0)

    Write-Host ''
    Write-Host '[2] control arm: one Ghost, and a fingerprint of its command card'
    $hwnd = Start-GhostGame -MapPath $ctlPath
    Send-ScClick -Hwnd $hwnd -X 315 -Y 180
    Start-Sleep -Milliseconds 800
    $ctlState = Get-ScUnitState -LogPath $logPath -Tag 'control-single' -MarkerPath $markerPath
    Assert-That "the control selection really is a single Ghost (n=$($ctlState.N))" `
        ($ctlState.N -eq 1 -and $ctlState.Types.ContainsKey('0x01'))
    $ctlCard = Get-ScRegionFingerprint -Hwnd $hwnd -X $CARD_RECT.X -Y $CARD_RECT.Y `
                   -Width $CARD_RECT.Width -Height $CARD_RECT.Height
    Write-Host "       command card WITHOUT the tech: $ctlCard"
    Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $shotDir '00-card-no-tech.png') -FullWindow | Out-Null
    Stop-GhostGame

    Write-Host ''
    Write-Host "[3] fixture: $UnitCount Ghosts, Personnel Cloaking researched, full energy"
    $gen = New-GhostFixture -Path $mapPath -WithTech
    Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
    # Without this the button is not on the card and every key emits nothing, which would
    # make "the key is not C" unfalsifiable.
    Assert-That 'Personnel Cloaking is marked researched for the human slot' `
        (@($gen | Select-String -Pattern 'PTEx: player 0 has researched 10\(personnel-cloaking\)').Count -gt 0)

    Write-Host ''
    Write-Host '[4] launch and box the Ghosts'
    $hwnd = Start-GhostGame -MapPath $mapPath

    function Select-Block { Send-ScDrag -Hwnd $hwnd -X1 115 -Y1 25 -X2 515 -Y2 330 -Steps 16 }
    function Select-One   { Send-ScClick -Hwnd $hwnd -X 315 -Y 180 }
    # One key at a time, and what it put on the wire. Returns the table.
    function Invoke-KeySweep {
        param([string]$What, [scriptblock]$Reselect)
        $rows = @()
        foreach ($k in $Keys) {
            $vk = [int][char]$k.ToUpperInvariant()
            $mark = Get-ScLogLineCount -LogPath $logPath
            Send-ScKey -Hwnd $hwnd -VirtualKey $vk -SettleMs 700
            # @() at the CALL SITE, and unrolled inside the function -- the combination
            # that works. A key that emits nothing returns $null, and $null.Count throws.
            $ids = @(Get-EmittedIds -Mark $mark)
            $armed = @(Get-ArmedIds)
            $rows += [pscustomobject]@{ Key = $k; Commands = ($ids -join ' '); Armed = ($armed -join ' ') }
            Write-Host ("       [{0}] {1} -> {2}{3}" -f $What, $k,
                        $(if ($ids.Count) { $ids -join ' ' } else { '(nothing)' }),
                        $(if ($armed.Count) { "   then a target click issued $($armed -join ' ')" } else { '' }))
            if (($ids + $armed) -contains $CLOAK_CMD -and -not $script:cloakProof) {
                $script:cloakProof = Get-ScUnitState -LogPath $logPath -Tag "cloaked-$k" -MarkerPath $markerPath
            }
            # Right-click cancels whatever is still armed; with nothing armed it is a move
            # order to where the block already is. Then reselect, because both the ability
            # and the ground click above may have changed the selection.
            Send-ScClick -Hwnd $hwnd -X 315 -Y 180 -Right
            Start-Sleep -Milliseconds 400
            & $Reselect
        }
        ,$rows
    }

    Select-Block
    $state = Get-ScUnitState -LogPath $logPath -Tag 'boxed' -MarkerPath $markerPath
    Assert-That "the box holds the $UnitCount Ghosts ($($state.N))" ($state.N -eq $UnitCount)
    Assert-That 'and they really are Ghosts' ($state.Types.ContainsKey('0x01'))
    Assert-That 'none is cloaked before the sweep' `
        (-not $state.Orders2.ContainsKey('0x6D')) "($($state.Line))"
    Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $shotDir '01-boxed.png') -FullWindow | Out-Null

    Write-Host ''
    Write-Host "[5] sweep A: the whole $UnitCount-Ghost selection"
    $table = @(Invoke-KeySweep -What 'many' -Reselect { Select-Block })

    Write-Host ''
    Write-Host '[6] sweep B: ONE Ghost, same keys'
    Select-One
    $one = Get-ScUnitState -LogPath $logPath -Tag 'single' -MarkerPath $markerPath
    Assert-That "the single-unit selection really is one unit (n=$($one.N))" ($one.N -eq 1)
    Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $shotDir '02-single.png') -FullWindow | Out-Null

    # THE COMPARISON THE WHOLE NEGATIVE RESTS ON, taken on the same selection size as the
    # control arm so the only difference between the two frames is the PTEx byte.
    $techCard = Get-ScRegionFingerprint -Hwnd $hwnd -X $CARD_RECT.X -Y $CARD_RECT.Y `
                    -Width $CARD_RECT.Width -Height $CARD_RECT.Height
    Write-Host "       command card WITH the tech:    $techCard"

    $solo = @(Invoke-KeySweep -What 'one ' -Reselect { Select-One })

    Write-Host ''
    Write-Host '[7] sweep C: the nine command-card slots, clicked'
    $slotNames = @('top-left','top-mid','top-right','mid-left','mid-mid','mid-right',
                   'bottom-left','bottom-mid','bottom-right')
    Select-One
    $i = 0
    foreach ($cy in $CARD_ROWS) {
        foreach ($cx in $CARD_COLS) {
            $name = $slotNames[$i]; $i++
            $mark = Get-ScLogLineCount -LogPath $logPath
            Send-ScClick -Hwnd $hwnd -X $cx -Y $cy -SettleMs 700
            $ids = @(Get-EmittedIds -Mark $mark)
            $armed = @(Get-ArmedIds)
            $card += [pscustomobject]@{ Key = "$name ($cx,$cy)"; Commands = ($ids -join ' ')
                                        Armed = ($armed -join ' ') }
            Write-Host ("       [card] {0,-12} ({1},{2}) -> {3}{4}" -f $name, $cx, $cy,
                        $(if ($ids.Count) { $ids -join ' ' } else { '(nothing)' }),
                        $(if ($armed.Count) { "   then a target click issued $($armed -join ' ')" } else { '' }))
            if (($ids + $armed) -contains $CLOAK_CMD -and -not $cloakProof) {
                $cloakProof = Get-ScUnitState -LogPath $logPath -Tag "cloaked-$name" -MarkerPath $markerPath
                Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $shotDir '03-cloaked.png') -FullWindow | Out-Null
            }
            Send-ScClick -Hwnd $hwnd -X 315 -Y 180 -Right     # cancel anything it armed
            Start-Sleep -Milliseconds 400
            Select-One
        }
    }

    Write-Host ''
    Write-Host '[8] the answer'
    # An action counts as having produced a command whether it issued one outright or
    # armed one that the follow-up target click then issued. Both are "this input reached
    # that ability"; only the timing differs.
    function Get-AllIds { param($Row) "$($Row.Commands) $($Row.Armed)".Trim() }
    foreach ($row in @(@{ N = "$UnitCount Ghosts"; T = $table }, @{ N = '1 Ghost'; T = $solo },
                       @{ N = 'card slots'; T = $card })) {
        $emitted = @($row.T | Where-Object { -not [string]::IsNullOrWhiteSpace((Get-AllIds $_)) } |
                     ForEach-Object { "$($_.Key)=$(Get-AllIds $_)" })
        $what = if ($emitted.Count -gt 0) { $emitted -join '; ' } else { 'NONE' }
        Write-Host ("       {0,-12} emitted: {1}" -f $row.N, $what)
    }
    $all = @($table) + @($solo) + @($card)
    $hit = @($all | Where-Object { (Get-AllIds $_) -match [regex]::Escape($CLOAK_CMD) })

    # POSITIVE FIRST (AGENTS.md, 2026-08-09): both input paths have to be shown WORKING
    # before "neither emitted Cloak" is worth anything. Hold (0x2B) and Stop (0x1A) are
    # basic-card commands present on every unit's card.
    $keyBasic  = @(@($table) + @($solo) | Where-Object { (Get-AllIds $_) -match '0x2B|0x1A' })
    $cardBasic = @($card | Where-Object { (Get-AllIds $_) -match '0x2B|0x1A' })
    Assert-That 'the KEY path works -- a key emitted a basic-card command' ($keyBasic.Count -gt 0) `
        "(from: $(@($keyBasic | ForEach-Object { $_.Key }) -join ', '))"
    Assert-That 'the CLICK path works -- a card slot emitted a basic-card command' ($cardBasic.Count -gt 0) `
        "(from: $(@($cardBasic | ForEach-Object { $_.Key }) -join ', '))"

    Write-Host ''
    Write-Host '[9] the control: did the tech change the command card at all?'
    Write-Host "       no tech: $ctlCard"
    Write-Host "       tech:    $techCard"
    $cardChanged = ($ctlCard -ne $techCard)
    if ($cardChanged) {
        Write-Host '       the researched fixture DOES draw a different command card, so the'
        Write-Host '       ability is on the card and a key/click that emits nothing is an'
        Write-Host '       INPUT-path result.'
    } else {
        Write-Host '       the two cards are IDENTICAL. The researched fixture put nothing new'
        Write-Host '       on the card, so no key and no click could ever have issued Cloak on'
        Write-Host '       it -- the blocker is the FIXTURE, not the input path.'
    }

    if ($hit.Count -ge 1) {
        $named = @($hit | ForEach-Object { $_.Key })
        Write-Host "       THE GHOST'S CLOAK IS: $($named -join ', ')"
        # Positive proof it really cloaked, not merely that a command id went out -- read
        # at the moment it fired, because cloak is a toggle and it drains energy.
        Assert-That 'the world state at the moment it fired was captured' ($null -ne $cloakProof)
        if ($cloakProof) {
            Assert-That 'and it put the unit into the cloak secondary order (0x6D)' `
                ($cloakProof.Orders2.ContainsKey('0x6D')) "($($cloakProof.Line))"
        }
    }
    # The verdict, stated so that the run FAILS while the question is open. A probe that
    # exits 0 on "nothing found" is a probe nobody re-runs.
    Assert-That "something emitted Personnel Cloaking ($CLOAK_CMD)" ($hit.Count -ge 1) `
        "(nothing did: no key A-Z at either selection size, and no card slot -- neither on the press itself nor on the target click that follows it; the command card $(if ($cardChanged) { 'DID' } else { 'did NOT' }) change when the tech was researched)"
}
catch {
    Write-Host "  FAIL the probe threw: $($_.Exception.Message)"
    Write-Host "       $($_.InvocationInfo.PositionMessage)"
    $failures++
}
finally {
    if (-not $KeepOpen) { Stop-GhostGame }
    elseif ($launchLock) { Exit-ScLaunchLock -Lock $launchLock }
    if (-not $KeepOpen) {
        Remove-ScOwnFixture -Run $fixtures
        Remove-ScOwnFixtureDir -Dir $FixtureDir
    }
}

Write-Host ''
Write-Host "probe-ghost-cloak: $failures failure(s)"
exit ($failures -gt 0 ? 1 : 0)
