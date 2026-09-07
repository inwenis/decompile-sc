#Requires -Version 7
<#
.SYNOPSIS
Name the Ghost's Personnel Cloaking button by reading the command card out of process
memory (dialog 0x0068C148, research/command-card.md), then drive the slot the read names.
.DESCRIPTION
Arms A/B: keys A-Z against the >12 selection and against one Ghost (a multi-select may
get a group card, research/command-opcodes.md 8). C: every card slot clicked at a centre
computed from the live dialog. D: the no-tech control fixture. E: the card read out of
memory on both fixtures -- the only arm whose answer needs no posted message to arrive.
.EXAMPLE
./tools/plugin/probe-ghost-cloak.ps1
.EXAMPLE
./tools/plugin/probe-ghost-cloak.ps1 -Keys C,D,E     # a shorter sweep while iterating
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogDir = 'C:\sc-work\logs\026',
    [string]$FixtureDir,
    [int]$UnitCount = 18,
    # Plain letters: card hotkeys carry no modifier, so the posted-modifier limit in
    # drive-game.ps1 (MODIFIER LIMIT) does not apply.
    [string[]]$Keys = @('A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
                        'Q','R','S','T','U','V','W','X','Y','Z'),
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

. (Join-Path $scriptDir 'sc-suite.ps1')

$failures = 0

$CLOAK_CMD = '0x21'      # Personnel Cloaking (research/ability-semantics.md 3)
$GHOST_TYPE = 1
# The Cloak button's action function is what NAMES a card slot as Cloak in the memory
# read -- byte-exact, not inferred from an icon or a position: 0x00423730 is
# `if (sendGate()) { buf = {0x21, shiftFlag}; queueCommand(buf, 2); }`, the id written
# at 0x00423748 (`MOV byte [EBP-4],0x21`) (research/command-card.md 4).
$CLOAK_ACTION = '00423730'
$DECLOAK_ACTION = '00423270'   # the same slot's other button; it sends 0x22
# The slot is a TOGGLE: the Ghost's buttonset holds both faces at slot 7 and the card
# draws whichever matches the portrait unit's state -- Cloak (act 0x00423730, icon 0x00FC)
# while visible, Decloak (act 0x00423270, icon 0x00FD) while cloaked. Do not name the slot
# by the Cloak action alone: a read taken after a sweep has already cloaked the Ghost shows
# the Decloak face and reads as "no Cloak button" -- a false negative from its own success.
$CLOAK_PAIR = @($CLOAK_ACTION, $DECLOAK_ACTION)
function Get-CloakSlots { param($Card) @($Card.Slots | Where-Object { $_.HasButton -and $_.Action -in $CLOAK_PAIR }) }
function Get-CloakFace  { param($Slot) $(if ($Slot.Action -eq $CLOAK_ACTION) { 'Cloak' } else { 'Decloak' }) }

# The command card in CLIENT coordinates: the (+5,+32) window offset is already
# subtracted, and Save-ScWindowImage / Get-ScRegionFingerprint add it themselves -- do not
# "fix" these by adding it again. Column and row centres are confirmed live: clicking
# (568,375) emits Stop and (568,418) emits Hold.
$CARD_COLS = @(523, 568, 613)
$CARD_ROWS = @(375, 418, 458)
$CARD_RECT = @{ X = 500; Y = 355; Width = 140; Height = 125 }

if (-not $FixtureDir) { $FixtureDir = Join-Path $GameDir 'Maps\BroodWar\00-t026' }
# Both fixtures declared together: ownership is per-RUN, so a suite that creates more than
# one file must name them all up front or its own second fixture reads as somebody else's
# and the run waits for itself (AGENTS.md § Test fixtures: one folder per task, one NAME
# per suite).
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
$cardNoTech = $null
$cardTech   = $null

# One card read-back, printed slot by slot: the slot table is the measurement.
function Read-Card {
    param([string]$Tag)
    $c = Get-ScCardState -LogPath $logPath -Tag $Tag -MarkerPath $markerPath
    if (-not $c.Ok) { Write-Host "       [card:$Tag] no command card in this process state"; return $c }
    # The parentheses are load-bearing: `-f` binds tighter than `+`, so without them only
    # the second literal is formatted and the first half's placeholders print verbatim.
    Write-Host (("       [card:{0}] cardId={1} (portrait type=0x{2:X3} buttonset={3} energy={4}) " +
                 "buttons={5} shown={6} greyed={7} reason={8}") -f
                $Tag, $c.CardId, $c.PortraitType, $c.PortraitSet, $c.PortraitEnergy,
                $c.SetCount, $c.Shown, $c.Greyed, $c.Reason)
    Write-Host ("       [card:{0}] player {1} tech: available=[{2}] researched=[{3}]" -f `
                $Tag, $c.TechPlayer, ($c.TechAvailable -join ' '), ($c.TechResearched -join ' '))
    foreach ($s in ($c.Slots | Sort-Object Index)) {
        $btn = if ($s.HasButton) {
            "act=0x{0} cond=0x{1} cparam={2} name=0x{3:X4}" -f $s.Action, $s.Cond, $s.CondParam, $s.NameStr
        } else { '(no button)' }
        Write-Host ("       [card:{0}]   slot {1} {2,-7} icon=0x{3:X4} {4}" -f
                    $Tag, $s.Index, $s.State, $s.Icon, $btn)
    }
    $c
}
# The world state read AT THE MOMENT a press or click emitted 0x21: Cloak is a toggle and
# drains energy, so a snapshot taken after a 26-key sweep could deny a cloak that happened.
$cloakProof = $null

# Returns the generator's own output lines so the caller asserts on them, not on this
# function's say-so.
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

# Launch, walk the menus, load $MapPath; sets $script:gamePid and returns the window
# handle. Browser rows come from Select-ScBrowserMap, never a fixed row number.
function Start-GhostGame {
    param([string]$MapPath)
    Wait-ScNoGameRunning
    $script:launchLock = Enter-ScLaunchLock -TaskId '026-ghost-cloak'
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode fanout -WorldScan 1 -CardScan 1 -InjectWindowedHelper WMode -NoLaunchLock `
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
    Set-ScGameType -Hwnd $h -LogPath $logPath -Index 2
    Send-ScClick -Hwnd $h -X 516 -Y 393
    Start-Sleep -Seconds 6
    Send-ScClick -Hwnd $h -X 544 -Y 387
    Start-Sleep -Seconds 10
    # Dismissed by its OWN OK button and asserted gone -- never a fixed point, never the
    # registry (AGENTS.md § The in-game tips dialog is dismissed by ITS OWN button).
    Dismiss-ScTipsDialog -Hwnd $h -LogPath $logPath | Out-Null
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

# A card entry has two ways to produce no CMD line at press time: it did nothing, or it
# ARMED a targeted order ("Select Target") and is waiting. Cancelling with a right-click
# alone makes the two identical in the log, so every action is followed by a LEFT click on
# open ground: with something armed the click issues it and the id names the ability; with
# nothing armed a left click on terrain issues no command (the right button gives the move
# order), so the baseline is empty and any id here is signal.
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
    $ctlEngineSel = @(Get-ScSelectionGroup -LogPath $logPath)
    # The engine's selection, not the plugin's shadow -- see Select-One in [4]. They agree
    # here only because nothing has boxed a >12 group yet.
    Assert-That ("the control selection really is a single Ghost (engine={0}, shadow n={1})" -f `
                 $ctlEngineSel.Count, $ctlState.N) `
        ($ctlEngineSel.Count -eq 1 -and $ctlState.Types.ContainsKey('0x01'))
    $ctlCard = Get-ScRegionFingerprint -Hwnd $hwnd -X $CARD_RECT.X -Y $CARD_RECT.Y `
                   -Width $CARD_RECT.Width -Height $CARD_RECT.Height
    Write-Host "       command card WITHOUT the tech: $ctlCard"
    # Arm E, half one: the same card read out of memory, so [9]'s hash comparison can be
    # reconciled slot by slot.
    $cardNoTech = Read-Card -Tag 'card-no-tech'
    Assert-That 'the no-tech card was read out of process memory' ($cardNoTech.Ok)
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
    # ONE Ghost, clicked, verified against the ENGINE's own selection, retried.
    # `Get-ScUnitState`.N is NOT the engine's selection: it is the plugin's SHADOW group
    # (`n=18 live=18 visible=12 overflow=6`), and the shadow survives a single click that
    # replaces the client selection. Do not assert `N -eq 1`: it reads 18 while the engine's
    # `clientSelectionGroup` holds one entry -- two structures, one name; assert the
    # engine's (AGENTS.md § Assert the ENGINE'S OWN RESULT, not your bookkeeping).
    function Select-One {
        for ($i = 1; $i -le 4; $i++) {
            Send-ScClick -Hwnd $hwnd -X 315 -Y 180 | Out-Null
            Start-Sleep -Milliseconds 700
            if (@(Get-ScSelectionGroup -LogPath $logPath).Count -eq 1) { return }
        }
    }
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
            # Right-click cancels whatever is still armed (with nothing armed it is a move
            # order to where the block already is); then reselect, because the ability and
            # the ground click above may both have changed the selection.
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
    # The >12 block's card, read out of memory: the multi-select card resolver (0x00458BC0)
    # can substitute a group card, and then no ability button is on this card at all.
    # This is also the CANONICAL read: taken before any input, so the toggle is unflipped
    # and slot 7 shows its Cloak face. Every later read is of a card this probe has changed.
    $cardBoxed = Read-Card -Tag 'card-boxed'
    $boxedCloak = @(Get-CloakSlots $cardBoxed) | Select-Object -First 1
    Assert-That 'the untouched card carries the Cloak button' ($null -ne $boxedCloak)
    if ($boxedCloak) {
        Write-Host ("       BEFORE ANY INPUT: slot {0} is showing its {1} face and is {2}" -f `
                    $boxedCloak.Index, (Get-CloakFace $boxedCloak), $boxedCloak.State)
        Assert-That 'and before any input it is showing the CLOAK face, not Decloak' `
            ($boxedCloak.Action -eq $CLOAK_ACTION) "(action 0x$($boxedCloak.Action))"
        Assert-That 'and with Personnel Cloaking researched it is ENABLED' (-not $boxedCloak.Disabled) `
            "(state=$($boxedCloak.State); a greyed button here means the fixture never granted the tech)"
        Assert-That 'the ENGINE agrees the fixture researched Personnel Cloaking (tech 10)' `
            (@($cardBoxed.TechResearched) -contains 10) `
            "(engine says [$(@($cardBoxed.TechResearched) -join ' ')])"
    }

    Write-Host ''
    Write-Host "[5] sweep A: the whole $UnitCount-Ghost selection"
    # NO @() here: Invoke-KeySweep returns `,$rows`, and wrapping that again builds a
    # ONE-element array holding the 26-row array -- [8] then prints a single row whose Key
    # is the whole alphabet and whose commands are every id concatenated, so which key fired
    # Cloak is unreadable. A property of the leading comma, not of that function.
    $table = Invoke-KeySweep -What 'many' -Reselect { Select-Block }

    Write-Host ''
    Write-Host '[6] sweep B: ONE Ghost, same keys'
    Select-One
    $engineSel = @(Get-ScSelectionGroup -LogPath $logPath)
    $one = Get-ScUnitState -LogPath $logPath -Tag 'single' -MarkerPath $markerPath
    # The ENGINE's selection is the claim, so it is what is asserted. The plugin's shadow
    # size is printed beside it because the two differing is normal -- see Select-One.
    Assert-That ("the ENGINE is holding exactly one unit (engine={0}, plugin shadow n={1})" -f `
                 $engineSel.Count, $one.N) ($engineSel.Count -eq 1) `
        "(engine holds: $($engineSel -join ' '))"
    Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $shotDir '02-single.png') -FullWindow | Out-Null

    # THE COMPARISON THE WHOLE NEGATIVE RESTS ON, taken on the same selection size as the
    # control arm so the only difference between the two frames is the PTEx byte.
    $techCard = Get-ScRegionFingerprint -Hwnd $hwnd -X $CARD_RECT.X -Y $CARD_RECT.Y `
                    -Width $CARD_RECT.Width -Height $CARD_RECT.Height
    Write-Host "       command card WITH the tech:    $techCard"

    Write-Host ''
    Write-Host '[6b] ARM E: the command card, READ OUT OF PROCESS MEMORY (one Ghost, tech researched)'
    $cardTech = Read-Card -Tag 'card-tech'
    Assert-That 'the with-tech card was read out of process memory' ($cardTech.Ok)
    Assert-That 'the card resolved to the Ghost''s own buttonset, not a group card' `
        ($cardTech.CardId -eq $cardTech.PortraitSet -and $cardTech.OverrideSel -eq 228 -and
         $cardTech.OverrideSub -eq 228) `
        "(cardId=$($cardTech.CardId) pset=$($cardTech.PortraitSet) ovrSel=$($cardTech.OverrideSel) ovrSub=$($cardTech.OverrideSub))"

    # Either face of the toggle names the slot ($CLOAK_PAIR). Which face is showing is
    # REPORTED, not required: the sweeps above have very likely cloaked the Ghost and
    # flipped it, and that flip is itself evidence the ability fired.
    $cloakSlots = @(Get-CloakSlots $cardTech)
    Assert-That 'exactly one card slot carries the Cloak toggle (0x00423730 / 0x00423270)' `
        ($cloakSlots.Count -eq 1) "(found $($cloakSlots.Count))"
    $cloak = $cloakSlots | Select-Object -First 1
    if ($cloak) {
        Write-Host (("       THE GHOST'S CLOAK BUTTON IS CARD SLOT {0}: showing its {5} face, {1}, " +
                     "icon 0x{2:X4}, conditionParam {3} (Personnel Cloaking), condition 0x{4}") -f
                    $cloak.Index, $cloak.State, $cloak.Icon, $cloak.CondParam, $cloak.Cond,
                    (Get-CloakFace $cloak))
        if ($boxedCloak) {
            Assert-That 'and it is the same slot the untouched card named' `
                ($cloak.Index -eq $boxedCloak.Index) "(now $($cloak.Index), was $($boxedCloak.Index))"
        }
        Assert-That 'and its conditionParam is Personnel Cloaking (tech 10)' ($cloak.CondParam -eq 10) `
            "(cparam=$($cloak.CondParam))"

        # The tech changes the STATE, not the presence: the button sits in the Ghost's
        # buttonset unconditionally, and research decides whether the condition returns
        # 1 (enabled) or -1 (greyed). Both fixtures carry the same button in the same slot.
        $ctlCloak = @($cardNoTech.Slots | Where-Object { $_.HasButton -and $_.Action -eq $CLOAK_ACTION }) |
                    Select-Object -First 1
        Assert-That 'the Cloak button is on the card with OR without the tech (it is the STATE that research changes)' `
            ($null -ne $ctlCloak) '(no-tech card carried no Cloak button)'
        if ($ctlCloak) {
            Write-Host "       no-tech card, same slot $($ctlCloak.Index): $($ctlCloak.State)"
            Assert-That 'without the tech it is greyed' ($ctlCloak.Disabled) "($($ctlCloak.State))"
        }

        # The fixture check, in the engine's own memory rather than in the generator's
        # read-back of its own write (a tool that verifies its own write verifies nothing).
        $researched = @($cardTech.TechResearched)
        Write-Host "       player $($cardTech.TechPlayer) researched techs, per the engine: [$($researched -join ' ')]"
        Assert-That 'the ENGINE agrees the fixture researched Personnel Cloaking (tech 10)' `
            ($researched -contains 10) `
            "(engine says [$($researched -join ' ')]; if 10 is missing the fixture never granted it and the grey is a FIXTURE bug, not an engine one)"
        Assert-That 'and with it researched, the Cloak button is ENABLED' (-not $cloak.Disabled) `
            "(state=$($cloak.State))"
    }

    $solo = Invoke-KeySweep -What 'one ' -Reselect { Select-One }   # no @() -- see [5]

    Write-Host ''
    Write-Host '[7] sweep C: the nine command-card slots, clicked at COMPUTED centres'
    Select-One
    # Each point is the live control's own rect plus the dialog origin (Get-ScCardSlotPoint),
    # so a slot that emits nothing emitted nothing at the place the engine itself hit-tests.
    $cardGeom = Read-Card -Tag 'card-slots'
    foreach ($slotNo in 1..9) {
        $s = Get-ScCardSlot -Card $cardGeom -Slot $slotNo
        if (-not $s) { Write-Host "       [card] slot $slotNo not present in the dialog"; continue }
        $p = Get-ScCardSlotPoint -Card $cardGeom -Slot $slotNo
        $mark = Get-ScLogLineCount -LogPath $logPath
        Send-ScClick -Hwnd $hwnd -X $p.X -Y $p.Y -SettleMs 700
        $ids = @(Get-EmittedIds -Mark $mark)
        $armed = @(Get-ArmedIds)
        $card += [pscustomobject]@{ Key = "slot $slotNo ($($p.X),$($p.Y)) $($s.State)"
                                    Commands = ($ids -join ' '); Armed = ($armed -join ' ')
                                    Slot = $slotNo; State = $s.State
                                    Action = $(if ($s.HasButton) { $s.Action } else { '' }) }
        Write-Host ("       [card] slot {0} {1,-7} ({2},{3}) -> {4}{5}" -f $slotNo, $s.State,
                    $p.X, $p.Y,
                    $(if ($ids.Count) { $ids -join ' ' } else { '(nothing)' }),
                    $(if ($armed.Count) { "   then a target click issued $($armed -join ' ')" } else { '' }))
        if (($ids + $armed) -contains $CLOAK_CMD -and -not $cloakProof) {
            $cloakProof = Get-ScUnitState -LogPath $logPath -Tag "cloaked-slot$slotNo" -MarkerPath $markerPath
            Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $shotDir '03-cloaked.png') -FullWindow | Out-Null
        }
        Send-ScClick -Hwnd $hwnd -X 315 -Y 180 -Right     # cancel anything it armed
        Start-Sleep -Milliseconds 400
        Select-One
    }

    Write-Host ''
    Write-Host '[8] the answer'
    # An action counts whether it issued a command outright or armed one that the follow-up
    # target click issued: both are "this input reached that ability", only the timing differs.
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

    # Positive first (AGENTS.md § Absence assertions must first be proved positive): both
    # input paths must be shown WORKING before "neither emitted Cloak" means anything.
    # Hold (0x2B) and Stop (0x1A) are basic-card commands present on every unit's card.
    $keyBasic  = @(@($table) + @($solo) | Where-Object { (Get-AllIds $_) -match '0x2B|0x1A' })
    $cardBasic = @($card | Where-Object { (Get-AllIds $_) -match '0x2B|0x1A' })
    Assert-That 'the KEY path works -- a key emitted a basic-card command' ($keyBasic.Count -gt 0) `
        "(from: $(@($keyBasic | ForEach-Object { $_.Key }) -join ', '))"
    Assert-That 'the CLICK path works -- a card slot emitted a basic-card command' ($cardBasic.Count -gt 0) `
        "(from: $(@($cardBasic | ForEach-Object { $_.Key }) -join ', '))"

    Write-Host ''
    Write-Host '[9] the two fingerprints, kept as corroboration and NOT as the oracle'
    Write-Host "       no tech: $ctlCard"
    Write-Host "       tech:    $techCard"
    # AGENTS.md § Read a dialog's CONTENT from memory; never hash its pixels. A differing
    # hash here does not mean the tech drew a different card: it answers only "did any pixel
    # change", and the two frames differ partly because the Ghost is CLOAKED by this point,
    # i.e. because of what this probe did. The slot tables say WHICH slot, in which state.
    Write-Host ('       (a difference here means only "some pixel changed". The slot tables above are ' +
                'the measurement; these two lines are kept so the old comparison stays visible.)')
    if ($ctlCard -eq $techCard) {
        Write-Host '       identical -- which on its own would still say nothing either way.'
    }

    if ($hit.Count -ge 1) {
        $named = @($hit | ForEach-Object { $_.Key })
        Write-Host "       THE GHOST'S CLOAK IS: $($named -join ', ')"
        # Positive proof it really cloaked, not merely that a command id went out.
        Assert-That 'the world state at the moment it fired was captured' ($null -ne $cloakProof)
        if ($cloakProof) {
            Assert-That 'and it put the unit into the cloak secondary order (0x6D)' `
                ($cloakProof.Orders2.ContainsKey('0x6D')) "($($cloakProof.Line))"
        }
    }

    Write-Host ''
    Write-Host '[10] the verdict, reconciled against the memory read'
    # Arms A-C can only report silence; arm E says which silence it was, and the two must
    # agree. The verdict is a JOINT statement about the read and the input, and it fails
    # if they disagree in either direction.
    $cloakState = if ($cloak) { $cloak.State } else { 'unknown' }
    Write-Host "       the memory read says the Cloak button (slot $(if ($cloak) { $cloak.Index } else { '?' })) is: $cloakState"

    # The negative needs a positive beside it in EVERY branch: some enabled slot on this very
    # card must have fired, or a run where the whole click path was broken reads as a finding.
    $liveSlot = @($card | Where-Object { $_.State -eq 'enabled' -and
                                         -not [string]::IsNullOrWhiteSpace((Get-AllIds $_)) })
    Assert-That 'an ENABLED slot on the same card did fire (the paired positive)' `
        ($liveSlot.Count -gt 0) "(none of $($card.Count) slots)"

    $techOk = @($cardTech.TechResearched) -contains 10

    if ($cloak -and $cloak.Disabled -and -not $techOk) {
        # A FIXTURE bug, not an engine one: PTEx never granted the tech, so the requirement
        # interpreter's researched test fails and the button is greyed. The run has already
        # failed above on the researched assertion; this only names it.
        Write-Host '       => THE FIXTURE DID NOT GRANT THE TECH. The engine does not consider'
        Write-Host '          Personnel Cloaking researched for this player, so the condition returns'
        Write-Host '          -1 and the card greys the button. Nothing about the input path is'
        Write-Host '          implicated, and nothing about a real cloaked Ghost is established.'
    }
    elseif ($cloak -and $cloak.Disabled) {
        # Researched and STILL greyed would be a genuine engine finding. Both input paths
        # test the greyed bit (control+0x18 & 0x2) and refuse -- 0x00459947 for the mouse,
        # 0x004588C0 for the hotkey -- so silence is the only thing arms A-C can produce;
        # checked here as a prediction rather than excused as an outcome.
        $slotClick = @($card | Where-Object { $_.Slot -eq $cloak.Index })
        Assert-That 'a click on the greyed Cloak slot emitted nothing, as the disabled bit predicts' `
            ($slotClick.Count -eq 1 -and [string]::IsNullOrWhiteSpace((Get-AllIds $slotClick[0]))) `
            "($($slotClick | ForEach-Object { Get-AllIds $_ }))"
        Assert-That 'and no key A-Z reached it either, for the same reason' ($hit.Count -eq 0)
        Write-Host '       => RESEARCHED AND STILL GREYED. That is an engine rule, not a fixture'
        Write-Host "          artefact. Refuse reason at read time: $($cardTech.Reason)."
    }
    elseif ($cloak -and $cloak.Visible) {
        # ENABLED. The click went to the control's own rect, so nothing emitted is a real
        # anomaly rather than an aiming problem.
        Assert-That "the ENABLED Cloak slot put Personnel Cloaking ($CLOAK_CMD) on the wire" `
            ($hit.Count -ge 1) `
            "(the memory read says slot $($cloak.Index) is enabled and the click was aimed at its own rect, so this is no longer an aiming problem)"

        # BOTH paths, named: the disabled bit gags mouse and keyboard together, so with it
        # clear both must work, each asserted separately so "one of them fired" cannot stand
        # in for the pair. EITHER FACE counts: slot 7 is a toggle, so which command a press
        # emits depends on whether the Ghost is cloaked when this arm reaches it, and the
        # earlier arms decide that. Measured across two runs: the same slot click emitted
        # 0x21 in one and 0x22 in the other purely because sweep B's `C` left the unit in a
        # different state. Do not require 0x21 specifically -- that fails the run where it
        # worked, the same self-inflicted false negative as the card read ($CLOAK_PAIR).
        $TOGGLE_CMDS = '0x21|0x22'
        $slotRow = @($card | Where-Object { $_.Slot -eq $cloak.Index })
        $slotIds = @($slotRow | ForEach-Object { Get-AllIds $_ }) -join ' '
        Assert-That "the CLICK path issued the ability -- card slot $($cloak.Index) emitted $slotIds" `
            ($slotRow.Count -eq 1 -and $slotIds -match $TOGGLE_CMDS) `
            "(slot rows: $(@($card | ForEach-Object { "$($_.Slot)=$(Get-AllIds $_)" }) -join ' '))"
        $keyHit = @(@($table) + @($solo) | Where-Object { (Get-AllIds $_) -match $TOGGLE_CMDS })
        Assert-That "the KEY path issued it too -- key(s) $(@($keyHit | ForEach-Object { $_.Key }) -join ',') emitted the ability" `
            ($keyHit.Count -ge 1) `
            '(task 022 swept A-Z and got nothing; that sweep ran against a GREYED button, and the hotkey predicate 0x004588C0 refuses one)'

        # The toggle, round-tripped: seeing BOTH ids in one run proves the pair is one button
        # in two states, not two unrelated buttons sharing a slot. Asserted over the whole
        # run, not one arm, because which arm sees which face is not fixed.
        $allIds = @(@($table) + @($solo) + @($card) | ForEach-Object { Get-AllIds $_ }) -join ' '
        Assert-That 'and both faces of the toggle reached the wire in this run (0x21 and 0x22)' `
            (($allIds -match '0x21') -and ($allIds -match '0x22')) "(ids seen: $allIds)"
    }
    else {
        Assert-That 'the Cloak button is on the card at all' ($null -ne $cloak) `
            '(no card slot carried the Cloak action; the Ghost buttonset holds one unconditionally)'
    }
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
