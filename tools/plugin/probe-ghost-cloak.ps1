#Requires -Version 7
<#
.SYNOPSIS
Name the Ghost's Personnel Cloaking button -- by READING THE COMMAND CARD OUT OF PROCESS
MEMORY, and then by driving the slot the read names.

.DESCRIPTION
THE QUESTION, inherited from task 022. That task could not drive Cloak. It reported that
`C` emits nothing even at full energy, and that clicking the bottom-left command-card slot
produced a frame reading "Select Target" -- i.e. that slot is a TARGETED ability
(Lockdown), so the click armed something and issued nothing. The underlying mechanism was
answered without it, but the user's original report was about a CLOAKED GHOST
specifically, so the unit itself is still unanswered.

WHAT TASK 026 ADDED, AND WHY IT IS THE ARM THAT SETTLES IT. Arms A-D below are all POSTED
INPUT, and posted input cannot separate "the button refused" from "the click missed" --
both leave the log empty. Arm E does not click: the plugin walks the card dialog
(0x0068C148) and reports, per slot, the control's visible/disabled flags and the Button
record behind it (research/command-card.md). Two things fall out of that read:

  * the ENABLED/GREYED bit, control+0x18 & 0x2. BOTH of the engine's input paths test it
    and refuse -- the mouse at 0x00459947 and the hotkey predicate at 0x004588C0 -- so a
    greyed button is silent to every key and every click by construction, which is the
    exact shape of the arms A-C negative;
  * the slot RECTANGLES, so arm C clicks a point COMPUTED from the live dialog instead of
    a coordinate read off a screenshot. That removes the "the click missed" confound that
    made task 022's reading of the bottom-left slot ambiguous in the first place.

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

  E. THE MEMORY READ (task 026), run on BOTH fixtures. No input at all: the card's own
     nine controls, their flags, and the Button record behind each. It names the Cloak
     slot, its ability, its conditionParam (the tech id) and its enabled/greyed state,
     and it is the only arm whose answer does not depend on a posted message arriving.

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
    [string]$LogDir = 'C:\sc-work\logs\026',
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
# The Ghost Cloak BUTTON's action function. This is what NAMES a card slot as Cloak in
# the memory read, and it is byte-exact rather than inferred: 0x00423730 is
# `if (sendGate()) { buf = {0x21, shiftFlag}; queueCommand(buf, 2); }`
# (research/command-card.md 4, listing at work/scratch/card/act-listing.tsv).
$CLOAK_ACTION = '00423730'
$DECLOAK_ACTION = '00423270'   # the same slot's other button; it sends 0x22
# THE SLOT IS A TOGGLE, and the read has to be written for that. The Ghost's buttonset
# holds BOTH faces at slot 7 and the card draws whichever matches the portrait unit's
# current state -- Cloak (act 0x00423730, icon 0x00FC) while it is visible, Decloak
# (act 0x00423270, icon 0x00FD) while it is cloaked. Measured on the 2026-08-09 run: the
# card read taken after the key sweep had already cloaked the Ghost showed the DECLOAK
# face, and a probe that named the slot by the Cloak action alone called that "no Cloak
# button on the card" -- a false negative produced by its own earlier success.
$CLOAK_PAIR = @($CLOAK_ACTION, $DECLOAK_ACTION)
function Get-CloakSlots { param($Card) @($Card.Slots | Where-Object { $_.HasButton -and $_.Action -in $CLOAK_PAIR }) }
function Get-CloakFace  { param($Slot) $(if ($Slot.Action -eq $CLOAK_ACTION) { 'Cloak' } else { 'Decloak' }) }

# The command card, in CLIENT coordinates. Read off a captured frame with the (+5,+32)
# window offset already subtracted -- the trap that made task 021 "fix" a coordinate that
# was correct (Save-ScWindowImage / Get-ScRegionFingerprint both take client coords and
# add the offset themselves). The three column centres and three row centres below are
# confirmed live: clicking (568,375) emits Stop and (568,418) emits Hold.
$CARD_COLS = @(523, 568, 613)
$CARD_ROWS = @(375, 418, 458)
$CARD_RECT = @{ X = 500; Y = 355; Width = 140; Height = 125 }

if (-not $FixtureDir) { $FixtureDir = Join-Path $GameDir 'Maps\BroodWar\00-t026' }
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
# Arm E: the two card read-backs, no-tech and with-tech.
$cardNoTech = $null
$cardTech   = $null

# One card read-back, printed slot by slot. The print is the point as much as the
# object is: this is the first time anything in this repo can say what the command
# card HOLDS rather than what it looks like.
function Read-Card {
    param([string]$Tag)
    $c = Get-ScCardState -LogPath $logPath -Tag $Tag -MarkerPath $markerPath
    if (-not $c.Ok) { Write-Host "       [card:$Tag] no command card in this process state"; return $c }
    # The parentheses are load-bearing: `-f` binds tighter than `+`, so a format string
    # built by concatenating two literals formats only the SECOND half and prints the
    # first half's placeholders verbatim.
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
    Set-ScGameType -Hwnd $h -Index 2
    Send-ScClick -Hwnd $h -X 516 -Y 393
    Start-Sleep -Seconds 6
    Send-ScClick -Hwnd $h -X 544 -Y 387
    Start-Sleep -Seconds 10
    # The tips dialog is found in the engine's own dialog list and dismissed by ITS OWN
    # OK button, then asserted gone (task 027) -- never a fixed point, never the registry.
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
    $ctlEngineSel = @(Get-ScSelectionGroup -LogPath $logPath)
    # The engine's selection, not the plugin's shadow -- see Select-One in [4]. Here they
    # happen to agree (nothing has boxed a >12 group yet in this arm), which is precisely
    # why the difference went unnoticed until a run where they did not.
    Assert-That ("the control selection really is a single Ghost (engine={0}, shadow n={1})" -f `
                 $ctlEngineSel.Count, $ctlState.N) `
        ($ctlEngineSel.Count -eq 1 -and $ctlState.Types.ContainsKey('0x01'))
    $ctlCard = Get-ScRegionFingerprint -Hwnd $hwnd -X $CARD_RECT.X -Y $CARD_RECT.Y `
                   -Width $CARD_RECT.Width -Height $CARD_RECT.Height
    Write-Host "       command card WITHOUT the tech: $ctlCard"
    # ARM E, half one: the same card, read out of memory. This is what makes the
    # fingerprint comparison in [9] mean something specific -- a hash that differs
    # says "something changed", a slot table says WHICH SLOT and HOW.
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
    # ONE Ghost -- clicked, then VERIFIED AGAINST THE ENGINE'S OWN SELECTION, and retried.
    #
    # `Get-ScUnitState`.N is NOT the engine's selection. It is the plugin's SHADOW group:
    # the same line reads `n=18 live=18 visible=12 overflow=6`, and the shadow survives a
    # single click that replaces the client selection. Asserting `N -eq 1` therefore asked
    # the wrong structure -- on the 2026-08-09 run it read 18 while the observer's own
    # `clientSelectionGroup [0]=0x006237C8` (one entry, no more) showed the click had done
    # exactly what was intended. Same class as the Get-ScSelectionGroup defect task 023
    # found: two structures, one name, and the assertion pointed at whichever was handy.
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
    # The >12 block's card, read out of memory. Worth having on its own: the mixed /
    # multi-select card resolver (0x00458BC0) can substitute a group card, and if it
    # did, no ability button would be on this card at all.
    #
    # THIS IS ALSO THE CANONICAL READ, and the reason it is kept: it is taken BEFORE any
    # input in this run, so the toggle has not been flipped and slot 7 is showing its
    # Cloak face. Every later read is of a card whose state this probe has itself changed.
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
    # NO @() HERE. Invoke-KeySweep already returns its array unrolled-proof (`,$rows`), and
    # wrapping it again builds a ONE-element array holding the 26-row array. Measured on the
    # 2026-08-09 run: the summary in [8] then printed a single row whose Key was the whole
    # alphabet and whose commands were every id concatenated -- so which key fired Cloak was
    # unreadable, and every per-row count was 1. Same trap test-ability-in-combat.ps1
    # documents for Get-Mine; it is a property of the leading comma, not of that function.
    $table = Invoke-KeySweep -What 'many' -Reselect { Select-Block }

    Write-Host ''
    Write-Host '[6] sweep B: ONE Ghost, same keys'
    Select-One
    $engineSel = @(Get-ScSelectionGroup -LogPath $logPath)
    $one = Get-ScUnitState -LogPath $logPath -Tag 'single' -MarkerPath $markerPath
    # The ENGINE's selection is the claim being made here, so it is the thing asserted.
    # The plugin's shadow size is printed next to it because the two differing is normal
    # and used to look like a failure -- see Select-One.
    Assert-That ("the ENGINE is holding exactly one unit (engine={0}, plugin shadow n={1})" -f `
                 $engineSel.Count, $one.N) ($engineSel.Count -eq 1) `
        "(engine holds: $($engineSel -join ' '))"
    Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $shotDir '02-single.png') -FullWindow | Out-Null

    # THE COMPARISON THE WHOLE NEGATIVE RESTS ON, taken on the same selection size as the
    # control arm so the only difference between the two frames is the PTEx byte.
    $techCard = Get-ScRegionFingerprint -Hwnd $hwnd -X $CARD_RECT.X -Y $CARD_RECT.Y `
                    -Width $CARD_RECT.Width -Height $CARD_RECT.Height
    Write-Host "       command card WITH the tech:    $techCard"

    # ===================== ARM E, THE ONE THAT SETTLES IT =====================
    Write-Host ''
    Write-Host '[6b] ARM E: the command card, READ OUT OF PROCESS MEMORY (one Ghost, tech researched)'
    $cardTech = Read-Card -Tag 'card-tech'
    Assert-That 'the with-tech card was read out of process memory' ($cardTech.Ok)
    Assert-That 'the card resolved to the Ghost''s own buttonset, not a group card' `
        ($cardTech.CardId -eq $cardTech.PortraitSet -and $cardTech.OverrideSel -eq 228 -and
         $cardTech.OverrideSub -eq 228) `
        "(cardId=$($cardTech.CardId) pset=$($cardTech.PortraitSet) ovrSel=$($cardTech.OverrideSel) ovrSub=$($cardTech.OverrideSub))"

    # THE NAMING. A card slot IS Cloak when its Button's action is the one that builds
    # command 0x21 -- read out of the binary byte for byte at 0x00423748
    # (`MOV byte [EBP-4],0x21`), not inferred from an icon or a position.
    # Either face of the toggle names the slot. Which one is showing is REPORTED rather
    # than required, because by this point the sweeps above have very likely cloaked the
    # Ghost and flipped it -- and that flip is itself evidence the ability fired.
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

        # WHAT THE TECH IS SUPPOSED TO CHANGE, and it is the STATE, not the presence.
        # The button sits in the Ghost's buttonset unconditionally; research decides
        # whether the condition returns 1 (enabled) or -1 (greyed). Task 023 compared a
        # PIXEL HASH of the card region here and concluded from two differing hashes
        # that the tech had changed the card. It had not: the slot tables are identical.
        # A frame hash is not an oracle for card content -- the slot table is.
        $ctlCloak = @($cardNoTech.Slots | Where-Object { $_.HasButton -and $_.Action -eq $CLOAK_ACTION }) |
                    Select-Object -First 1
        Assert-That 'the Cloak button is on the card with OR without the tech (it is the STATE that research changes)' `
            ($null -ne $ctlCloak) '(no-tech card carried no Cloak button)'
        if ($ctlCloak) {
            Write-Host "       no-tech card, same slot $($ctlCloak.Index): $($ctlCloak.State)"
            Assert-That 'without the tech it is greyed' ($ctlCloak.Disabled) "($($ctlCloak.State))"
        }

        # THE FIXTURE CHECK the user's observation demanded, done in the engine's own
        # memory rather than in the generator's read-back of its own write.
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
    # Never a hardcoded slot centre again. Each point is the live control's own rect
    # plus the dialog's origin (Get-ScCardSlotPoint) -- so a slot that emits nothing
    # emitted nothing at the place the engine itself hit-tests.
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
    Write-Host '[9] the two fingerprints, kept as corroboration and NOT as the oracle'
    Write-Host "       no tech: $ctlCard"
    Write-Host "       tech:    $techCard"
    # AGENTS.md, 2026-08-09: read a dialog's content from memory, never hash its pixels.
    # Task 023 concluded from exactly this pair of hashes that the researched fixture "drew
    # a different command card", and the slot tables above show what a hash cannot: WHICH
    # slot, and in which state. A hash answers "did any pixel change", which is a different
    # question -- and here the two cards differ partly because the Ghost is CLOAKED by this
    # point, i.e. because of what this probe did, not because of the tech.
    Write-Host ('       (a difference here means only "some pixel changed". The slot tables above are ' +
                'the measurement; these two lines are kept so the old comparison stays visible.)')
    if ($ctlCard -eq $techCard) {
        Write-Host '       identical -- which on its own would still say nothing either way.'
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

    Write-Host ''
    Write-Host '[10] the verdict, reconciled against the memory read'
    # THE POINT OF TASK 026. Arms A-C can only report silence. Arm E says which of the
    # two silences it was, and the two must agree -- so the verdict is a JOINT statement
    # about the read and the input, and it fails if they disagree in either direction.
    $cloakState = if ($cloak) { $cloak.State } else { 'unknown' }
    Write-Host "       the memory read says the Cloak button (slot $(if ($cloak) { $cloak.Index } else { '?' })) is: $cloakState"

    # The negative needs a positive next to it in EVERY branch: some slot on this very
    # card must be enabled and must have fired, or "greyed slots are silent" is untested
    # and a run where the whole click path was broken would read like a finding.
    $liveSlot = @($card | Where-Object { $_.State -eq 'enabled' -and
                                         -not [string]::IsNullOrWhiteSpace((Get-AllIds $_)) })
    Assert-That 'an ENABLED slot on the same card did fire (the paired positive)' `
        ($liveSlot.Count -gt 0) "(none of $($card.Count) slots)"

    $techOk = @($cardTech.TechResearched) -contains 10

    if ($cloak -and $cloak.Disabled -and -not $techOk) {
        # The 2026-08-09 state, and a FIXTURE bug, not an engine one: PTEx never granted
        # the tech, so the requirement interpreter's researched test fails and the button
        # is greyed. The run fails above on the researched assertion; this only names it.
        Write-Host '       => THE FIXTURE DID NOT GRANT THE TECH. The engine does not consider'
        Write-Host '          Personnel Cloaking researched for this player, so the condition returns'
        Write-Host '          -1 and the card greys the button. Nothing about the input path is'
        Write-Host '          implicated, and nothing about a real cloaked Ghost is established.'
    }
    elseif ($cloak -and $cloak.Disabled) {
        # Researched and STILL greyed -- that would be a genuine engine finding. Both
        # input paths test control+0x18 & 0x2 and refuse (0x00459947 for the mouse,
        # 0x004588C0 for the hotkey), so silence is the only thing arms A-C could have
        # produced -- checked here as a prediction rather than excused as an outcome.
        $slotClick = @($card | Where-Object { $_.Slot -eq $cloak.Index })
        Assert-That 'a click on the greyed Cloak slot emitted nothing, as the disabled bit predicts' `
            ($slotClick.Count -eq 1 -and [string]::IsNullOrWhiteSpace((Get-AllIds $slotClick[0]))) `
            "($($slotClick | ForEach-Object { Get-AllIds $_ }))"
        Assert-That 'and no key A-Z reached it either, for the same reason' ($hit.Count -eq 0)
        Write-Host '       => RESEARCHED AND STILL GREYED. That is an engine rule, not a fixture'
        Write-Host "          artefact. Refuse reason at read time: $($cardTech.Reason)."
    }
    elseif ($cloak -and $cloak.Visible) {
        # ENABLED. The click went to the control's own rect, so nothing emitted is now a
        # real anomaly rather than an aiming problem.
        Assert-That "the ENABLED Cloak slot put Personnel Cloaking ($CLOAK_CMD) on the wire" `
            ($hit.Count -ge 1) `
            "(the memory read says slot $($cloak.Index) is enabled and the click was aimed at its own rect, so this is no longer an aiming problem)"

        # BOTH PATHS, NAMED. The whole point of the disabled bit is that it gags the mouse
        # and the keyboard together; with the bit clear both must work, and each is asserted
        # separately so "one of them fired" cannot stand in for the pair.
        #
        # EITHER FACE COUNTS, and it has to. Slot 7 is a toggle, so which command a press
        # emits depends on whether the Ghost happens to be cloaked when this arm reaches it
        # -- and the earlier arms in this very probe decide that. Measured across two runs:
        # the same slot click emitted 0x21 in one and 0x22 in the other, purely because
        # sweep B's `C` had left the unit in a different state. Requiring 0x21 specifically
        # made the probe fail on the run where it worked, which is the same self-inflicted
        # false negative the toggle already caused once in the card read (see $CLOAK_PAIR).
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

        # THE TOGGLE, ROUND-TRIPPED. Seeing BOTH ids somewhere in one run is what proves
        # the pair really is one button in two states rather than two unrelated buttons
        # that happen to share a slot -- and it is asserted over the whole run, not over
        # one arm, precisely because which arm sees which face is not fixed.
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
