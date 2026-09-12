#Requires -Version 7
<#
.SYNOPSIS
ONE Train press with SEVERAL production buildings selected: is Train on the card, how many
0x1F reach the wire, which buildings' own queues (CUnit+0x98) gain an item, and what was paid.
.DESCRIPTION
Arms: baseline (SCPLUGIN_PRODFAN=0, stock: 0 commands, 0 buildings gain), feature (=1: every
building gains one, N x cost paid by the ENGINE), cap (one building filled to the engine's five,
then the group pressed once). All arms share steps, oracles and a positive control. Fixture: N
Command Centers on a map with no hostiles and one resource trigger -- a Command Center supplies
its own SCVs, so supply-block cannot explain a zero. Numbers: research/group-production.md 6.
.EXAMPLE
./tools/plugin/test-group-production.ps1 -Arm baseline
.EXAMPLE
./tools/plugin/test-group-production.ps1 -Arm feature -Buildings 4
#>
[CmdletBinding()]
param(
    [ValidateSet('baseline', 'feature', 'cap')][string]$Arm = 'feature',
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogPath,
    [string]$ShotDir = 'C:\sc-work\logs\030\group-production-frames',
    [string]$FixtureDir,
    # How many production buildings the box selects. 4 is enough to make "one" and "all"
    # unmistakably different numbers and still fits one screen at the spacing below.
    [int]$Buildings = 4,
    [int]$StartingMinerals = 3000,
    [int]$StartingGas = 0,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

. (Join-Path $scriptDir 'sc-suite.ps1')

if (-not $LogPath) { $LogPath = "C:\sc-work\logs\030\group-production-$Arm.log" }

$failures = 0
$step = 0

# Pinned constants, asserted rather than reported.
$CC_TYPE    = 106         # units.dat 106, richchk UnitId 'Terran Command Center'
$SCV_TYPE   = 7           # units.dat 7,   richchk UnitId 'Terran SCV'
$SCV_COST   = 50          # minerals
$TRAIN_KEY  = 0x53        # 'S', the Command Center card's Train SCV hotkey
$TRAIN_CMD  = '0x1F'      # research/data/command-opcodes.tsv
$QUEUE_EMPTY = 0xE4       # research/production-queue.md 2.4
$ENGINE_SLOTS = 5         # the engine's own ring, research/production-queue.md 2.3
# Build-menu button table 0x005172C0: every Train record carries condition 0x00428E60 and
# action 0x004234B0, the 0x1F emitter itself, which is what names the slot here. The condition
# returns 0 when clientSelectionCount > 1 -- stock's missing button (research/group-production.md 3).
$TRAIN_ACTION = '004234b0'
$TRAIN_COND   = '00428e60'

if ($Buildings -lt 2) { throw 'test: -Buildings must be at least 2, or there is no group.' }

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t030' -Suite 'group-production' }
$mapDir = $FixtureDir
$mapName = 'group-production.scx'
$mapPath = Join-Path $mapDir $mapName
$fixtures = New-ScFixtureRun -Dir $mapDir -Names @($mapName)

$markerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt'
function Get-World { param([string]$Tag, [int]$TimeoutSec = 20)
    Get-ScWorldState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec }

# Same marker handshake as Get-ScWorldState. Waits for the `PRODFAN [label] buildings=`
# summary line, which the plugin writes LAST and unconditionally: the whole answer has landed,
# and an empty answer is still an answer. Returns one row per SELECTED building with that
# building's own five queue slots, plus the card's Train slot from the same marker -- "the
# button was dark" and "nothing queued" are then two readings of one instant.
$script:fanSeq = 0
function Get-ProdFan {
    param([string]$Tag, [int]$TimeoutSec = 20)
    $script:fanSeq++
    $label = "pf-$Tag-$script:fanSeq"
    Set-ScMarker -MarkerPath $markerPath -Label $label
    $esc = [regex]::Escape($label)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $all = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue)
        $lines = @($all | Select-String -Pattern "PRODFAN \[$esc\]")
        $summary = @($lines | Select-String -Pattern 'buildings=')
        if ($summary.Count -gt 0) {
            $out = [pscustomobject]@{
                Label = $label; Buildings = 0; Selected = 0; Visible = 0; SimSlots = 0
                ClientCount = 0; TotalQueued = 0; Minerals = 0; Gas = 0; Enabled = 0
                Fanned = 0; Refused = 0; Reached = 0; Lit = 0
                Rows = @(); Card = $null; CardLines = @()
                Lines = @($lines | ForEach-Object { $_.Line })
            }
            foreach ($l in $lines) {
                $m = [regex]::Match($l.Line,
                    'PRODFAN \[[^\]]+\] i=(\d+)/(\d+) unit=0x([0-9A-Fa-f]+) type=0x([0-9A-Fa-f]+) player=(\d+) head=(\d+) engineLen=(-?\d+) engine=\[([^\]]*)\] buildState=(\d+) buildUnit=0x([0-9A-Fa-f]+)(.*)$')
                if ($m.Success) {
                    $out.Rows += [pscustomobject]@{
                        Index = [int]$m.Groups[1].Value
                        Unit = $m.Groups[3].Value
                        Type = [Convert]::ToInt32($m.Groups[4].Value, 16)
                        Player = [int]$m.Groups[5].Value
                        Head = [int]$m.Groups[6].Value
                        EngineLen = [int]$m.Groups[7].Value
                        Engine = @($m.Groups[8].Value -split ',' |
                                   Where-Object { $_ -match '^0x' } |
                                   ForEach-Object { [Convert]::ToInt32(($_ -replace '^0x'), 16) })
                        BuildState = [int]$m.Groups[9].Value
                        BuildUnit = $m.Groups[10].Value
                        Stale = ($m.Groups[11].Value -match 'STALE')
                    }
                    continue
                }
                $s = [regex]::Match($l.Line,
                    'buildings=(\d+) selected=(\d+) visible=(\d+) simSlots=(-?\d+) clientCount=(\d+) totalQueued=(\d+) minerals=(\d+) gas=(\d+) enabled=(\d+) fanned=(\d+) refused=(\d+) reached=(\d+) lit=(\d+)')
                if ($s.Success) {
                    $out.Buildings = [int]$s.Groups[1].Value
                    $out.Selected = [int]$s.Groups[2].Value
                    $out.Visible = [int]$s.Groups[3].Value
                    $out.SimSlots = [int]$s.Groups[4].Value
                    $out.ClientCount = [int]$s.Groups[5].Value
                    $out.TotalQueued = [int]$s.Groups[6].Value
                    $out.Minerals = [int]$s.Groups[7].Value
                    $out.Gas = [int]$s.Groups[8].Value
                    $out.Enabled = [int]$s.Groups[9].Value
                    $out.Fanned = [int]$s.Groups[10].Value
                    $out.Refused = [int]$s.Groups[11].Value
                    $out.Reached = [int]$s.Groups[12].Value
                    $out.Lit = [int]$s.Groups[13].Value
                }
            }
            # The Train slot is named by its action pointer, not by the layout's slot index.
            $cardLines = @($all | Select-String -Pattern "CARD \[$esc\] slot=")
            $out.CardLines = @($cardLines | ForEach-Object { $_.Line })
            foreach ($c in $cardLines) {
                $cm = [regex]::Match($c.Line,
                    'slot=(\d+) (\S+) .*cond=0x([0-9A-Fa-f]+) act=0x([0-9A-Fa-f]+)')
                if ($cm.Success -and $cm.Groups[4].Value.ToLower() -eq $TRAIN_ACTION) {
                    $out.Card = [pscustomobject]@{
                        Slot = [int]$cm.Groups[1].Value
                        State = $cm.Groups[2].Value
                        Cond = $cm.Groups[3].Value.ToLower()
                        Act = $cm.Groups[4].Value.ToLower()
                    }
                }
            }
            return $out
        }
        Start-Sleep -Milliseconds 250
    }
    throw "test: no PRODFAN answer for marker '$label' within ${TimeoutSec}s (log: $LogPath)."
}

# Slot by slot, not by length: a length can be right with the wrong type in the wrong slot.
function Assert-Queue {
    param([string]$What, $Row, [int]$WantLen, [int]$WantType = 0)
    if ($null -eq $Row) { Assert-That "$What has a queue reading at all" $false; return }
    $eng = ($Row.Engine | ForEach-Object { '0x{0:x}' -f $_ }) -join ','
    Assert-That "$What holds $WantLen item(s), read from its own CUnit+0x98 ($($Row.EngineLen))" `
        ($Row.EngineLen -eq $WantLen) "(engine=[$eng])"
    if ($WantLen -gt 0 -and $WantType -gt 0) {
        $occupied = @($Row.Engine | Where-Object { $_ -ne $QUEUE_EMPTY })
        $bad = @($occupied | Where-Object { $_ -ne $WantType })
        Assert-That "$What's queued item(s) are all unit type 0x$('{0:x}' -f $WantType)" `
            ($bad.Count -eq 0) "(engine=[$eng])"
    }
    Assert-That "$What's shadow entry is not stale" (-not $Row.Stale)
}

# Box exactly these units by map position, camera centred on them first: a full-screen drag
# boxes whatever else is on the map, and the fixture's buildings must be named, not hoped for.
function Select-ScUnitsByMap {
    param(
        [Parameter(Mandatory)][object[]]$Units,
        [Parameter(Mandatory)][int]$TileX,
        [Parameter(Mandatory)][int]$TileY,
        [string]$Tag = 'aim',
        [int]$Margin = 24,
        [int]$MapW = 128, [int]$MapH = 96,
        # Skip the minimap centring and the world scan, reusing the viewport last read. Only
        # safe when nothing has moved the camera since. The point is SPEED: a one-second
        # re-box instead of four can be the difference between a building still at its
        # queue cap and one that has finished a unit in the meantime.
        [switch]$Reuse
    )
    if ($Reuse -and $script:lastScreen) {
        $w = [pscustomobject]@{ Screen = $script:lastScreen; Units = $Units }
    } else {
        $p = Get-ScMinimapPoint -MapTilesW $MapW -MapTilesH $MapH -TileX $TileX -TileY $TileY
        Send-ScClick -Hwnd $script:hwnd -X $p.X -Y $p.Y
        Start-Sleep -Milliseconds 800
        $w = Get-ScWorldState -LogPath $script:LogPath -Tag $Tag -MarkerPath $script:markerPath
        if (-not $w.Screen) { throw 'test: the plugin did not report the viewport origin.' }
        $script:lastScreen = $w.Screen
    }
    $x1 = ($Units | Measure-Object X -Minimum).Minimum - $w.Screen.Left - $Margin
    $x2 = ($Units | Measure-Object X -Maximum).Maximum - $w.Screen.Left + $Margin
    $y1 = ($Units | Measure-Object Y -Minimum).Minimum - $w.Screen.Top  - $Margin
    $y2 = ($Units | Measure-Object Y -Maximum).Maximum - $w.Screen.Top  + $Margin
    if ($x1 -lt 4 -or $y1 -lt 4 -or $x2 -gt 636 -or $y2 -gt 340) {
        Write-Host "       (block at client [$x1,$y1]-[$x2,$y2] is not fully on the battlefield)"
        return $false
    }
    # Name any foreign unit inside the rect. A neutral MINERAL FIELD (type=0x0B2 player=11)
    # sharing the box is a non-movable type too, so the building group would happily grow a
    # group of THOSE -- a failure that says what it is beats a wrong count three steps later.
    $mineSet = @{}
    foreach ($u in $Units) { $mineSet[$u.Unit] = $true }
    $intruders = @($w.Units | Where-Object {
        -not $mineSet.ContainsKey($_.Unit) -and
        ($_.X - $w.Screen.Left) -ge $x1 -and ($_.X - $w.Screen.Left) -le $x2 -and
        ($_.Y - $w.Screen.Top)  -ge $y1 -and ($_.Y - $w.Screen.Top)  -le $y2
    })
    if ($intruders.Count -gt 0) {
        Write-Host "       (WARNING: $($intruders.Count) unit(s) not in the block fall inside this rect: $(($intruders | ForEach-Object { 'p{0}/0x{1:x}' -f $_.Owner, $_.Type }) -join ' '))"
    } else {
        Write-Host '       (nothing but the block itself falls inside the rect)'
    }
    Write-Host "       (boxing client [$x1,$y1]-[$x2,$y2]; viewport at map ($($w.Screen.Left),$($w.Screen.Top)))"
    Send-ScDrag -Hwnd $script:hwnd -X1 $x1 -Y1 $y1 -X2 $x2 -Y2 $y2 -Steps 20
    Start-Sleep -Seconds 2
    return $true
}

# --- on-disk binary, BEFORE anything runs --------------------------------------
$exePath = Join-Path $GameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $exePath)) { throw "test: $exePath not found." }
$hashBefore = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "[0] arm=$Arm  StarCraft.exe SHA-256 before: $hashBefore"
$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
Assert-That 'the working copy starts out byte-identical to pristine 1.16.1' `
    ($hashBefore -eq $PRISTINE_SHA256) "(got $hashBefore)"

New-Item -ItemType Directory -Path (Split-Path $LogPath -Parent) -Force | Out-Null
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
    Save-ScWindowImage -Hwnd $script:hwnd -Path (Join-Path $ShotDir ("{0}-{1:d2}-{2}.png" -f $Arm, $script:shotN, $tag)) -FullWindow | Out-Null
}

try {
    Step "generate the fixture: $Buildings Command Centers, $StartingMinerals minerals" {
        Wait-ScFixtureFolderFree -Run $fixtures
        # 160 px (5 tiles) apart: a Command Center is 4x3 tiles, so this clears it with a
        # tile to spare, and $Buildings of them still fit one screen's battlefield for one drag box.
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount $Buildings -UnitType command-center -Player 0 -ClearPlayerUnits `
            -GridSpacing 160 -StartingMinerals $StartingMinerals -StartingGas $StartingGas `
            -OutputPath $mapPath 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
        Assert-That 'its structural validation passed' `
            (@($gen | Select-String -Pattern '^OK: ').Count -gt 0)
        Assert-That 'the map differs from its template only where this tool meant it to' `
            (@($gen | Select-String -Pattern 'differs from the template ONLY in: OWNR SIDE UNIT TRIG FORC').Count -gt 0)
    }

    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId "030-group-production-$Arm"
    # -Mode fanout: the building group that lets one box select all $Buildings lives in the
    # fan-out. -CardScan 1: "is Train lit" is answered by reading the card, never a frame
    # (AGENTS.md § Read a dialog's CONTENT from memory; never hash its pixels). -ProdQueue 0:
    # the over-cap feature is a different question and its detours would put unrelated
    # machinery in the picture; the engine's own five slots are all this measures.
    $prodFan = ($Arm -eq 'baseline') ? '0' : '1'
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode fanout -LogCommands 1 -Circles 0 -HudRow 0 -WorldScan 1 -CardScan 1 `
        -BuildingGroups 1 -ProdQueue 0 -ProdFan $prodFan -QueueIndicator 1 `
        -InjectWindowedHelper WMode -NoLaunchLock `
        -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step "the plugin came up in the $Arm configuration" {
        $cfg = @(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'PRODFAN: (ENABLED|disabled)')
        Assert-That 'the plugin reported its group-production state at all' ($cfg.Count -gt 0)
        $want = ($Arm -eq 'baseline') ? 'disabled' : 'ENABLED'
        Assert-That "and it reports itself $want" `
            (@($cfg | Select-String -Pattern "PRODFAN: $want").Count -gt 0) `
            "(got: $(($cfg | ForEach-Object { $_.Line }) -join ' | '))"
        # queueCommand (0x00485BD0) is the engine's outgoing-command funnel (AGENTS.md § A
        # player-input feature is unproven until the wire has been watched). Asserted positively
        # so that a later 'no 0x1F reached the wire' means something (AGENTS.md § Absence
        # assertions must first be proved positive).
        $hooks = @(Get-Content -LiteralPath $LogPath |
                   Select-String -Pattern 'HOOK queueCommand: installed at')
        Assert-That 'the command funnel is hooked, so every command this game sends is logged' `
            ($hooks.Count -ge 1) "(got $($hooks.Count))"
    }

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
        Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null
        Set-ScGameType -Hwnd $hwnd -LogPath $logPath -Index 2      # Use Map Settings, verified
        Shot 'lobby'
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> mission briefing
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 10
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
        Shot 'in-game'
    }

    Step "the map spawned exactly $Buildings Command Centers and nothing else" {
        $w = Get-World 'spawned'
        $mine = @($w.Units | Where-Object { $_.Player -eq 0 })
        $ccs = @($mine | Where-Object { $_.Type -eq $CC_TYPE })
        Assert-That "player 0 owns exactly $Buildings Command Centers ($($ccs.Count))" `
            ($ccs.Count -eq $Buildings)
        Assert-That "and owns nothing else ($($mine.Count) unit(s) total)" `
            ($mine.Count -eq $Buildings) `
            "(types seen: $((($mine | ForEach-Object { '0x{0:x}' -f $_.Type }) | Sort-Object -Unique) -join ' '))"
        Assert-That 'the world scan of player 0 was not taken mid-edit' `
            ($w.Counts[0].Units -eq $w.Counts[0].Recount -and $w.Counts[0].Complete -eq 1) `
            "(units=$($w.Counts[0].Units) recount=$($w.Counts[0].Recount) complete=$($w.Counts[0].Complete))"
        $script:ccs = $ccs
        if ($ccs.Count -gt 0) {
            $script:ccTile = [pscustomobject]@{
                X = [int]((($ccs | Measure-Object X -Average).Average) / 32)
                Y = [int]((($ccs | Measure-Object Y -Average).Average) / 32)
            }
            Write-Host "       the block is centred on tile ($($script:ccTile.X),$($script:ccTile.Y))"
        }
    }

    # The `cap` arm skips everything below and runs its own short sequence: a Command Center
    # finishes an SCV in about ten seconds, and a finished SCV standing among the buildings
    # makes any later drag box select the SCV instead of the group (SortAllUnits keeps movable
    # units and discards buildings, research/building-groups.md 2.2). So the cap case is
    # measured in a game where nothing has finished yet.
    if ($Arm -ne 'cap') {

    Step "box all $Buildings of them -- one selection, $Buildings buildings" {
        $aimed = Select-ScUnitsByMap -Units $script:ccs -TileX $script:ccTile.X -TileY $script:ccTile.Y -Tag 'aim-group'
        Assert-That 'the block is on screen and was boxed' $aimed
        $f = Get-ProdFan 'group-before'
        Write-Host "       $($f.Lines | Where-Object { $_ -match 'buildings=' } | Select-Object -First 1)"
        Assert-That "the selection holds all $Buildings buildings ($($f.Buildings))" `
            ($f.Buildings -eq $Buildings)
        Assert-That "the simulation holds ONE at a time (simSlots=$($f.SimSlots))" `
            ($f.SimSlots -eq 1)
        $wrongType = @($f.Rows | Where-Object { $_.Type -ne $CC_TYPE })
        Assert-That 'every selected unit is a Command Center' ($wrongType.Count -eq 0)
        $wrongOwner = @($f.Rows | Where-Object { $_.Player -ne 0 })
        Assert-That 'and every one is the human player 0' ($wrongOwner.Count -eq 0)

        # Every queue is read and asserted EMPTY before anything is pressed, so a later 1
        # cannot be something already there, and the oracle answers "0" before it is trusted
        # to answer "1".
        for ($i = 0; $i -lt $f.Rows.Count; $i++) {
            Assert-Queue "building $i (before)" $f.Rows[$i] 0
        }
        Assert-That "nothing is queued anywhere yet (totalQueued=$($f.TotalQueued))" `
            ($f.TotalQueued -eq 0)
        Assert-That "the player still has all $StartingMinerals minerals ($($f.Minerals))" `
            ($f.Minerals -eq $StartingMinerals)
        $script:mineralsBefore = $f.Minerals

        # 0x0059723D is named `clientSelectionCount` from the instruction that gates the
        # button on it; asserting it against a known count makes the name a reading, not a label.
        Assert-That "the engine's own client selection count reads $Buildings ($($f.ClientCount))" `
            ($f.ClientCount -eq $Buildings)

        if ($f.Card) {
            Write-Host "       Train button: slot=$($f.Card.Slot) state=$($f.Card.State) cond=0x$($f.Card.Cond) act=0x$($f.Card.Act)"
            Assert-That 'the Train slot found on the card is the one whose condition is 0x00428E60' `
                ($f.Card.Cond -eq $TRAIN_COND) "(got 0x$($f.Card.Cond))"
            $script:cardGroup = $f.Card.State
        } else {
            Write-Host "       Train button: NOT PRESENT on the card with $Buildings buildings selected"
            Write-Host "       (card slots seen: $($f.CardLines.Count))"
            $script:cardGroup = 'absent'
        }
        if ($Arm -eq 'feature') {
            # The whole client half of the feature, in one assertion: without it there is
            # no button, so no command, so nothing for the fan-out to fan out.
            Assert-That 'the Train button is DRAWN and enabled for the group' `
                ($null -ne $f.Card -and $f.Card.State -eq 'enabled') "(state: $($script:cardGroup))"
            # The addon buttons share condition 0x00428E60; lit, they would look live and do
            # nothing, because nothing fans 0x35 out. Asserted by action pointer, meaningful
            # only because the positive half above found a button by the same means.
            $addons = @($f.CardLines | Where-Object { $_ -match 'act=0x00423d10' })
            Assert-That 'and the two addon buttons on the same condition stay off the card' `
                ($addons.Count -eq 0) "(found $($addons.Count))"
        } else {
            Assert-That 'stock: the Train button is absent for a multi-building selection' `
                ($null -eq $f.Card)
        }
        Shot 'group-selected'
    }

    Step 'ONE Train press, with the whole group selected' {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScKey -Hwnd $hwnd -VirtualKey $TRAIN_KEY
        Start-Sleep -Seconds 3
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $cmds = @($lines | Select-String -Pattern "CMD id=$TRAIN_CMD ")
        $script:groupCmds = $cmds.Count
        Write-Host "       $($cmds.Count) Train command(s) reached the funnel:"
        $cmds | ForEach-Object { Write-Host "         $($_.Line)" }
        $fan = @($lines | Select-String -Pattern 'FANOUT (start|done|defer): ')
        $fan | ForEach-Object { Write-Host "         $($_.Line)" }

        if ($Arm -eq 'feature') {
            # `CMD id=` is logged inside the queueCommand DETOUR; the fan-out emits its pairs
            # through the TRAMPOLINE, so replayed commands never pass the logger. One press
            # shows exactly ONE `CMD id=0x1F` (the player's own, then suppressed) plus a
            # FANOUT plan naming the pairs sent in its place. Do not assert $Buildings CMD
            # lines: that fails a working feature.
            Assert-That "the player's ONE Train command reached the funnel ($($cmds.Count))" `
                ($cmds.Count -eq 1)
            $start = @($fan | Select-String -Pattern 'FANOUT start: cmd=0x1F')
            Assert-That 'and it was fanned out rather than passed through' ($start.Count -eq 1) `
                "(FANOUT lines: $($fan.Count))"
            if ($start.Count -eq 1) {
                $m = [regex]::Match($start[0].Line,
                    'units=(\d+) \(visible (\d+) \+ overflow (\d+)\) slots=(\d+) -> (\d+) Select\+order pairs')
                Assert-That 'the plan is parseable' $m.Success "($($start[0].Line))"
                if ($m.Success) {
                    Assert-That "the plan covers all $Buildings buildings ($($m.Groups[1].Value))" `
                        ([int]$m.Groups[1].Value -eq $Buildings)
                    # cmdrecvTrain (0x004C1C20) acts only when the selection holds exactly one
                    # unit (research/group-production.md 4), so the plan must be one per chunk.
                    Assert-That "at ONE building per chunk, which is what cmdrecvTrain's single-unit gate wants (slots=$($m.Groups[4].Value))" `
                        ([int]$m.Groups[4].Value -eq 1)
                    Assert-That "so $Buildings Select+order pairs go out ($($m.Groups[5].Value))" `
                        ([int]$m.Groups[5].Value -eq $Buildings)
                }
            }
            # A deferred tail would queue the rest behind the next command, and the queue
            # reads below would then measure a half-finished plan rather than the feature.
            $done = @($fan | Select-String -Pattern "FANOUT done: $Buildings/$Buildings chunks")
            Assert-That "and every chunk was emitted in this turn, none deferred ($($done.Count))" `
                ($done.Count -eq 1)
            $script:groupCmds = "1 press -> 1 command -> $Buildings Select+order pairs"
        } else {
            Write-Host "       (baseline: this is the measurement, not an assertion)"
        }
        Shot 'group-trained'
    }

    Step "read EVERY building's queue from its own memory" {
        $f = Get-ProdFan 'group-after'
        Write-Host "       $($f.Lines | Where-Object { $_ -match 'buildings=' } | Select-Object -First 1)"
        $f.Rows | ForEach-Object {
            Write-Host ("         i={0} unit=0x{1} engineLen={2} engine=[{3}]" -f `
                $_.Index, $_.Unit, $_.EngineLen, (($_.Engine | ForEach-Object { '0x{0:x}' -f $_ }) -join ','))
        }
        Assert-That "all $Buildings buildings are still in the reading ($($f.Buildings))" `
            ($f.Buildings -eq $Buildings)

        $want = ($Arm -eq 'feature') ? 1 : 0
        for ($i = 0; $i -lt $f.Rows.Count; $i++) {
            Assert-Queue "building $i (after one click)" $f.Rows[$i] $want $SCV_TYPE
        }
        $expectTotal = $want * $Buildings
        Assert-That "$expectTotal item(s) are queued across the group in total ($($f.TotalQueued))" `
            ($f.TotalQueued -eq $expectTotal)

        # Money reconciled from the resource globals in BOTH directions: the expected spend is
        # derived from what the buildings' own memory says queued, not from what was clicked.
        $expectMinerals = $script:mineralsBefore - $expectTotal * $SCV_COST
        Assert-That "minerals are down by exactly $expectTotal x $SCV_COST and no more ($($f.Minerals))" `
            ($f.Minerals -eq $expectMinerals) "(expected $expectMinerals)"
        Assert-That 'nothing was paid for that did not queue' `
            (($script:mineralsBefore - $f.Minerals) -eq ($f.TotalQueued * $SCV_COST)) `
            "(paid $($script:mineralsBefore - $f.Minerals) for $($f.TotalQueued) item(s))"

        # A building with an incomplete unit at CUnit+0xEC is one drawing a production
        # progress bar. The status area draws only the primary selection's queue, so this
        # is the measurement of whether all N are visibly working.
        $script:producing = @($f.Rows | Where-Object { $_.BuildUnit -ne '00000000' }).Count
        Write-Host "       buildings with a unit under construction (CUnit+0xEC): $($script:producing) of $($f.Buildings)"

        if ($Arm -eq 'feature') {
            Assert-That "the plugin counted one fan-out reaching $Buildings buildings (fanned=$($f.Fanned) reached=$($f.Reached))" `
                ($f.Fanned -eq 1 -and $f.Reached -eq $Buildings)
            Assert-That "all $Buildings buildings are actually building something ($($script:producing))" `
                ($script:producing -eq $Buildings)
        } else {
            Assert-That 'the plugin fanned nothing out, because the feature is off' `
                ($f.Fanned -eq 0) "(fanned=$($f.Fanned))"
        }
        $script:groupQueued = $f.TotalQueued
        $script:mineralsAfterGroup = $f.Minerals

        # The queue indicator is the ONLY thing on screen that says the click reached more
        # than one building: with N selected the engine takes its multi-select branch -- no
        # production strip, the wireframe row instead, ONE queue for the whole group -- so the
        # indicator reports how many selected buildings are queueing and how many items they
        # hold. Read back through the control's own pszText pointer, never the module's buffer.
        $qi = @(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'QIND \[') |
              Select-Object -Last 1
        if ($qi) {
            Write-Host "       $($qi.Line)"
            # Named groups, not positional: a field inserted into the log line shifts every
            # positional group after it without failing -- bldgs silently reads out of queued.
            $m = [regex]::Match($qi.Line,
                'mode=(?<mode>\d+) linked=(?<linked>\d+) visible=(?<visible>\d+) ' +
                'text="(?<text>[^"]*)" ' +
                'bounds=\((?<left>-?\d+),(?<top>-?\d+),(?<right>-?\d+),(?<bottom>-?\d+)\) ' +
                'ink=(?<ink>-?\d+) refInk=(?<refInk>-?\d+) refId=(?<refId>-?\d+) ' +
                'surfInk=(?<surfInk>-?\d+) slotDiff=(?<slotDiff>-?\d+) boxDiff=(?<boxDiff>-?\d+) ' +
                'fontH=(?<fontH>\d+).* bldgs=(?<bldgs>\d+) queued=(?<queued>\d+)')
            Assert-That 'the indicator read-back line parsed' ($m.Success) "($($qi.Line))"
            if ($m.Success) {
                $mode = [int]$m.Groups['mode'].Value
                $boxL = [int]$m.Groups['left'].Value
                $boxT = [int]$m.Groups['top'].Value
                $boxW = [int]$m.Groups['right'].Value - $boxL
                $boxH = [int]$m.Groups['bottom'].Value - $boxT
                $ink = [int]$m.Groups['ink'].Value
                $refInk = [int]$m.Groups['refInk'].Value
                $surfInk = [int]$m.Groups['surfInk'].Value
                $boxDiff = [int]$m.Groups['boxDiff'].Value
                $fontH = [int]$m.Groups['fontH'].Value
                $bldgs = [int]$m.Groups['bldgs'].Value
                $queued = [int]$m.Groups['queued'].Value
                if ($Arm -eq 'feature') {
                    Assert-That "it is in GROUP mode (2), not the single-building one ($mode)" `
                        ($mode -eq 2)
                    Assert-That "it names all $Buildings queueing buildings ($bldgs)" `
                        ($bldgs -eq $Buildings)
                    Assert-That "and the $expectTotal items they hold between them ($queued)" `
                        ($queued -eq $expectTotal)
                    Assert-That "the control is linked and the ENGINE's visible bit is set" `
                        ($m.Groups['linked'].Value -eq '1' -and $m.Groups['visible'].Value -eq '1')
                    Assert-That "its text says so in words (`"$($m.Groups['text'].Value)`")" `
                        ($m.Groups['text'].Value -eq "$Buildings bldgs  $expectTotal queued")
                    # Every assertion above passes for a TRUNCATED line -- a clipped string is
                    # still ink. Measured: "4 bldgs  4 queued" in a box 22 px wide, clamped to
                    # the wireframe button it anchors to. 5 px/char is a conservative floor.
                    $need = $m.Groups['text'].Value.Length * 5
                    Assert-That "and its box is wide enough to draw all of it ($boxW px for $need)" `
                        ($boxW -ge $need)
                    # The line belongs in the band BELOW the icon row; over it, it draws behind
                    # the building icons. Checked against the row's own rects from the dialog
                    # dump the plugin logs at attach -- never a constant, because which buttons
                    # are up depends on how many buildings are selected.
                    $rowBottom = 0
                    foreach ($d in @(Get-Content -LiteralPath $LogPath |
                                     Select-String -Pattern 'QINDDLG \[.*\] id=(3[3-9]|4[0-4]) ')) {
                        $r = [regex]::Match($d.Line, 'rect=\((-?\d+),(-?\d+),(-?\d+),(-?\d+)\)')
                        if ($r.Success -and [int]$r.Groups[4].Value -gt $rowBottom) {
                            $rowBottom = [int]$r.Groups[4].Value
                        }
                    }
                    Assert-That "the row's twelve buttons were found in the dialog dump (lowest edge y=$rowBottom)" `
                        ($rowBottom -gt 0)
                    Assert-That "and the line starts BELOW all of them (top=$boxT vs $rowBottom)" `
                        ($boxT -ge $rowBottom)
                    # The engine's string draw refuses outright when the box is shorter than
                    # the font, and an invisible line passes every other check here.
                    Assert-That "the band is at least as tall as the font ($boxH >= $fontH)" `
                        ($boxH -ge $fontH -and $fontH -gt 0)
                    # Do not assert on ink: the pane's own art fills this surface, so every rect
                    # reads saturated (measured 1330 of 1330 bytes over a queue icon) and
                    # `ink > 0` holds before anything of ours exists. boxDiff compares the box
                    # against a copy the game thread took while the indicator was HIDDEN, so it
                    # counts the bytes this line is responsible for and zero is a real failure.
                    # surfInk (the probe can read this surface) and refInk (it can read a control
                    # the ENGINE fills -- the wireframe row, up because this is a group
                    # selection) keep that zero honest: without them it reads as "probe blind".
                    Assert-That "the probe can read the dialog surface at all (surfInk=$surfInk)" `
                        ($surfInk -gt 0)
                    Assert-That "and a control the ENGINE fills (refInk=$refInk over control $($m.Groups['refId'].Value))" `
                        ($refInk -gt 0)
                    Assert-That "and the engine DREW the line: boxDiff=$boxDiff bytes differ from the same band without it (ink=$ink, saturated)" `
                        ($boxDiff -gt 0)
                } else {
                    # With the fan-out off one click reaches one building, so the indicator must
                    # say nothing -- which is what makes the reading above a measurement.
                    Assert-That "with the fan-out off the indicator says nothing (mode=$mode)" `
                        ($mode -eq 0)
                }
            }
        }
        else {
            Assert-That 'the indicator oracle produced a line at all' $false
        }
        Shot 'group-read'
    }

    # THE POSITIVE CONTROL, same run, same two oracles. Without it the baseline's headline is
    # unfalsifiable: "0 commands on the wire" and "the funnel watch never worked" produce
    # identical logs, as do "0 buildings gained an item" and "the queue read is broken". Same
    # key, funnel and per-building read where the engine certainly DOES act: one building
    # selected, vanilla's own path.
    Step 'POSITIVE CONTROL: click ONE building and press Train once' {
        $w = Get-World 'aim-single'
        $cc = @($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $CC_TYPE })[0]
        Assert-That 'the scan reports the viewport origin' ($null -ne $w.Screen)
        Assert-That 'and a Command Center with a sprite position' `
            ($null -ne $cc -and $cc.X -gt 0 -and $cc.Y -gt 0)
        $cx = $cc.X - $w.Screen.Left
        $cy = $cc.Y - $w.Screen.Top
        Write-Host "       CC at map ($($cc.X),$($cc.Y)), viewport ($($w.Screen.Left),$($w.Screen.Top)) -> client ($cx,$cy)"
        Assert-That "the building is on screen, inside the play area ($cx,$cy)" `
            ($cx -ge 0 -and $cx -lt 640 -and $cy -ge 0 -and $cy -lt 340)
        Send-ScClick -Hwnd $hwnd -X $cx -Y $cy
        Start-Sleep -Seconds 2

        $before = Get-ProdFan 'single-before'
        Assert-That "exactly ONE building is selected now ($($before.Buildings))" `
            ($before.Buildings -eq 1)
        $singleUnit = ($before.Rows.Count -gt 0) ? $before.Rows[0].Unit : $null
        $wasQueued = ($before.Rows.Count -gt 0) ? $before.Rows[0].EngineLen : -1
        Write-Host "       the clicked building is 0x$singleUnit, holding $wasQueued item(s)"
        if ($before.Card) {
            Write-Host "       Train button with ONE selected: slot=$($before.Card.Slot) state=$($before.Card.State)"
            $script:cardSingle = $before.Card.State
        } else {
            Write-Host "       Train button with ONE selected: NOT PRESENT on the card"
            $script:cardSingle = 'absent'
        }
        $mineralsBeforeSingle = $before.Minerals

        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScKey -Hwnd $hwnd -VirtualKey $TRAIN_KEY
        Start-Sleep -Seconds 3
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $cmds = @($lines | Select-String -Pattern "CMD id=$TRAIN_CMD ")
        Write-Host "       $($cmds.Count) Train command(s) reached the funnel:"
        $cmds | ForEach-Object { Write-Host "         $($_.Line)" }

        # Must pass in BOTH arms: the feature does not touch the single-building path, and if
        # it ever did, this is where it shows.
        Assert-That "exactly ONE Train command reached the funnel ($($cmds.Count))" `
            ($cmds.Count -eq 1)
        $after = Get-ProdFan 'single-after'
        Assert-That "the same one building is still selected ($($after.Buildings))" `
            ($after.Buildings -eq 1)
        if ($after.Rows.Count -gt 0) {
            Assert-That 'and it is the same building that was clicked' `
                ($after.Rows[0].Unit -eq $singleUnit) "(0x$($after.Rows[0].Unit) vs 0x$singleUnit)"
            Assert-Queue 'the clicked building' $after.Rows[0] ($wasQueued + 1) $SCV_TYPE
        }
        Assert-That "one SCV was paid for, exactly $SCV_COST minerals ($($mineralsBeforeSingle) -> $($after.Minerals))" `
            (($mineralsBeforeSingle - $after.Minerals) -eq $SCV_COST)
        $script:controlOk = ($cmds.Count -eq 1)
        Shot 'single-trained'
    }

    }   # end: everything above is skipped for the `cap` arm

    # A BUILDING ALREADY AT ITS QUEUE CAP must be skipped without eating a click or a payment.
    # Nothing in the plugin implements that skip: it falls out of addToBuildQueue's own
    # `CMP EAX,0x5`, which returns 0 WITHOUT touching the array or the player's resources
    # (research/production-queue.md 4.1). This step turns that reading of the disassembly
    # into a measurement. The building is filled by ordinary play -- selected alone, Train
    # pressed until the client stops sending -- so it is full for the engine's own reasons.
    if ($Arm -eq 'cap') {
        Step 'CRITERION 5: fill ONE building to the engine cap, then Train the group again' {
            # Nothing has been queued yet in this game, so no SCV exists and none can for
            # about ten seconds after the first press -- the entire window this step needs.
            $w = Get-World 'aim-cap-single'
            $cc = @($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $CC_TYPE })[0]
            Assert-That 'the scan reports the viewport origin and a building' `
                ($null -ne $w.Screen -and $null -ne $cc)
            $cx = $cc.X - $w.Screen.Left
            $cy = $cc.Y - $w.Screen.Top
            Assert-That "the building to fill is on screen ($cx,$cy)" `
                ($cx -ge 0 -and $cx -lt 640 -and $cy -ge 0 -and $cy -lt 340)
            Send-ScClick -Hwnd $hwnd -X $cx -Y $cy
            Start-Sleep -Seconds 2

            $pre = Get-ProdFan 'fill-before'
            Assert-That 'exactly one building is selected to fill' ($pre.Buildings -eq 1)
            $fillUnit = ($pre.Rows.Count -gt 0) ? $pre.Rows[0].Unit : $null
            $have = ($pre.Rows.Count -gt 0) ? $pre.Rows[0].EngineLen : 0
            Write-Host "       0x$fillUnit holds $have; topping it up to $ENGINE_SLOTS"
            # A loop, not (5 - have) presses: the first press starts production, so an SCV can
            # pop out while the queue is being filled, leaving it at four and the step
            # measuring nothing. Re-read until it is genuinely at the cap.
            $filled = $null
            for ($attempt = 1; $attempt -le 12; $attempt++) {
                $filled = Get-ProdFan "fill-$attempt"
                if ($filled.Rows.Count -lt 1) { break }
                if ($filled.Rows[0].EngineLen -ge $ENGINE_SLOTS) { break }
                Send-ScKey -Hwnd $hwnd -VirtualKey $TRAIN_KEY
                Start-Sleep -Milliseconds 300
            }
            Assert-That "the building reached the engine cap of $ENGINE_SLOTS ($(($filled.Rows.Count -gt 0) ? $filled.Rows[0].EngineLen : -1))" `
                ($filled.Rows.Count -gt 0 -and $filled.Rows[0].EngineLen -ge $ENGINE_SLOTS)
            $script:mineralsFilled = $filled.Minerals

            # Do not -Reuse here, even inside a ten-second window: the reuse path skips the
            # world scan and with it the check for anything else in the box -- exactly the
            # check that names a completed SCV silently boxed instead of the buildings.
            $aimed = Select-ScUnitsByMap -Units $script:ccs -TileX $script:ccTile.X -TileY $script:ccTile.Y -Tag 'aim-cap'
            Assert-That 'the block is on screen and was boxed again' $aimed
            $before = Get-ProdFan 'cap-before'
            Assert-That "the group is all $Buildings again ($($before.Buildings))" `
                ($before.Buildings -eq $Buildings)
            $wasFull = @($before.Rows | Where-Object { $_.EngineLen -ge $ENGINE_SLOTS })
            # At least one at cap and at least one with room, or the step cannot tell skipped
            # from not-skipped. Counted rather than assumed: production runs during setup.
            Assert-That "at least one of them is at the engine cap ($($wasFull.Count))" `
                ($wasFull.Count -ge 1)
            Assert-That "and at least one still has room ($($Buildings - $wasFull.Count))" `
                ($wasFull.Count -lt $Buildings)
            $roomy = @($before.Rows | Where-Object { $_.EngineLen -lt $ENGINE_SLOTS })
            $mineralsBeforeCap = $before.Minerals
            # Compared PER BUILDING, not as a total: a total can balance while the wrong one moved.
            $wasLen = @{}
            foreach ($r in $before.Rows) { $wasLen[$r.Unit] = $r.EngineLen }

            $mark = Get-ScLogLineCount -LogPath $LogPath
            Send-ScKey -Hwnd $hwnd -VirtualKey $TRAIN_KEY
            Start-Sleep -Seconds 3
            $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
            $cmds = @($lines | Select-String -Pattern "CMD id=$TRAIN_CMD ")
            Write-Host "       $($cmds.Count) Train command(s) reached the funnel"
            # The fan-out still emits one pair per building; it does not pre-judge which can
            # accept. The ENGINE refuses the full one, which is why the payment below is the test.
            Assert-That "the press was fanned out again, one pair per building ($($cmds.Count) command at the funnel)" `
                ($cmds.Count -eq 1 -and
                 @($lines | Select-String -Pattern "FANOUT start: cmd=0x1F.*-> $Buildings Select\+order pairs").Count -eq 1)

            $after = Get-ProdFan 'cap-after'
            $after.Rows | ForEach-Object {
                Write-Host ("         unit=0x{0} {1} -> {2}" -f $_.Unit, $wasLen[$_.Unit], $_.EngineLen)
            }

            # Payment FIRST, because timing cannot spoil it: a unit finishing inside the window
            # shortens a queue but never un-spends a mineral. This is the drain-proof form of
            # "a building at its cap must not silently eat a payment".
            $paid = $mineralsBeforeCap - $after.Minerals
            Assert-That "exactly $($roomy.Count) x $SCV_COST minerals left, NOT $Buildings x $SCV_COST ($paid)" `
                ($paid -eq $roomy.Count * $SCV_COST) `
                "(a payment for the full building would read $($Buildings * $SCV_COST))"
            Assert-That 'so the building at its cap cost the player nothing' `
                ($paid -lt $Buildings * $SCV_COST)

            # An SCV completing (about ten seconds) CAN land between the two reads and pop an
            # item off a queue. Detected, not tolerated: if the totals move by exactly the
            # number of buildings with room, nothing completed and every building is asserted
            # individually; otherwise the step says so and the payment assertion carries it.
            $sumBefore = ($before.Rows | Measure-Object EngineLen -Sum).Sum
            $sumAfter = ($after.Rows | Measure-Object EngineLen -Sum).Sum
            $quiet = (($sumAfter - $sumBefore) -eq $roomy.Count)
            if ($quiet) {
                foreach ($r in $after.Rows) {
                    $was = $wasLen[$r.Unit]
                    if ($was -ge $ENGINE_SLOTS) {
                        Assert-That "the FULL building 0x$($r.Unit) stayed at $ENGINE_SLOTS and was not overfilled ($($r.EngineLen))" `
                            ($r.EngineLen -eq $ENGINE_SLOTS)
                    } else {
                        Assert-That "building 0x$($r.Unit) gained exactly one ($was -> $($r.EngineLen))" `
                            ($r.EngineLen -eq $was + 1)
                    }
                }
            } else {
                Write-Host "       (a unit completed inside the window: queue total moved $sumBefore -> $sumAfter, not +$($roomy.Count); the per-building growth check is skipped and the payment assertion above carries this step)"
            }
            # True whatever the timing: the engine's ring cannot exceed five.
            $over = @($after.Rows | Where-Object { $_.EngineLen -gt $ENGINE_SLOTS })
            Assert-That "no building holds more than the engine's $ENGINE_SLOTS slots" ($over.Count -eq 0)
            $script:capPaid = $paid
            $script:capSkipped = $Buildings - $roomy.Count
            Shot 'cap-case'
        }
    }

    Step 'the measurement, stated as numbers' {
        Write-Host ''
        Write-Host "       ARM                                    : $Arm"
        if ($Arm -eq 'cap') {
            Write-Host "       buildings at the engine cap            : $($script:capSkipped) of $Buildings"
            Write-Host "       minerals the group click moved         : $($script:capPaid)"
            Write-Host "       what a payment for the full one would be: $($Buildings * $SCV_COST)"
        } else {
            Write-Host "       Train button, $Buildings buildings selected  : $($script:cardGroup)"
            Write-Host "       Train button, 1 building selected      : $($script:cardSingle)"
            Write-Host "       0x1F at the funnel, group              : $($script:groupCmds)"
            Write-Host "       0x1F at the funnel, single             : 1 (the positive control)"
            Write-Host "       buildings that gained an item, group   : $($script:groupQueued) of $Buildings"
            Write-Host "       minerals moved by the group click      : $($script:mineralsBefore - $script:mineralsAfterGroup)"
            Write-Host "       buildings PRODUCING after the click    : $($script:producing) of $Buildings (CUnit+0xEC non-null)"
            Write-Host "       queue the STATUS AREA draws            : the primary selection's only"
            # The control is what licenses every zero above to be read as a zero.
            Assert-That 'the positive control fired, so a zero in the group case is a real zero' `
                ($script:controlOk -eq $true)
        }
        Write-Host ''
    }
}
finally {
    if ($gamePid -gt 0 -and -not $KeepOpen) {
        try {
            & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | ForEach-Object { Write-Host "       $_" }
        }
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
    Remove-ScOwnFixtureDir -Dir $mapDir
    if ($launchLock) { Exit-ScLaunchLock -Lock $launchLock; $launchLock = $null }
}

Write-Host ''
Write-Host '[final] the run must balance'
$left = if ($gamePid -gt 0) { Get-Process -Id $gamePid -ErrorAction SilentlyContinue } else { $null }
Assert-That 'the game process this test started is gone' ($KeepOpen -or $null -eq $left)
Assert-That 'the generated map was cleaned up' ($KeepOpen -or -not (Test-Path -LiteralPath $mapPath))

# The plugin spends nothing of its own: every queued item is paid for by the engine's
# addToBuildQueue. The stats line turns that from a claim about the source into a reading.
$statLine = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
              Select-String -Pattern 'PRODFAN STATS: ')
if ($statLine.Count -gt 0) {
    Write-Host "  $($statLine[-1].Line)"
    $m = [regex]::Match($statLine[-1].Line, 'fanned=(\d+) refused=(\d+) buildingsReached=(\d+)')
    if ($m.Success) {
        $wantFanned = switch ($Arm) { 'feature' { 1 } 'cap' { 1 } default { 0 } }
        Assert-That "the run fanned out $wantFanned Train command(s) ($($m.Groups[1].Value))" `
            ([int]$m.Groups[1].Value -eq $wantFanned)
    }
} else { Assert-That 'the plugin wrote its group-production stats line' $false }

$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-group-production ($Arm): $failures failure(s)"
Write-Host "frames (diagnostic): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
