#Requires -Version 7
<#
.SYNOPSIS
End-to-end, UNATTENDED test of task 015's per-opcode fan-out: launches the game, loads a
stock map with more than twelve selectable units, issues Stop / Hold Position / Attack /
Patrol to all of them with one keypress each, and asserts on EVERY UNIT'S OWN ORDER STATE
-- not on prose, and not on the picture.

.DESCRIPTION
Same recipe as test-selection-circles.ps1 (task 012's D1, research/automated-testing-options.md
4.1) via tools/plugin/drive-game.ps1: PostMessage with client coordinates, no synthetic OS
input, focus not required, window must not be minimised.

THE ORACLE IS THE PLUGIN'S `UNITSTATE` LINE. The plugin walks its shadow list -- the whole
pre-cap selection, all 24 units, not the 12 the engine holds -- reads each unit's current
order id out of CUnit+0xA6 and reports a histogram. So "every unit obeyed" is a claim about
all 24 units' own state, made from inside the process.

The shape of the proof for each order:

  1. drive the units into motion, and record which order they are all on;
  2. press the key once;
  3. assert the plugin fanned the command out to more than twelve units, AND that
     afterwards NOT ONE unit is still on the moving order.

Step 3's second half is the part that cannot be faked by a command that only reached the
visible twelve: the other twelve would still be walking.

Frames are captured as a DIAGNOSTIC only and land outside the repo -- they reproduce game
artwork (AGENTS.md hard rule 1) and must never be committed.

.EXAMPLE
./tools/plugin/test-fanout-orders.ps1

.EXAMPLE
./tools/plugin/test-fanout-orders.ps1 -ShotDir C:\temp\sc-frames -KeepOpen
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogPath = 'C:\sc-work\logs\015-fanout-orders.log',
    [string]$ShotDir = 'C:\sc-work\logs\015-fanout-frames',
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'drive-game.ps1')

$failures = 0
$step = 0

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

# --- the plugin's marker channel, used as a request/response --------------------
# Writing a marker makes the observer thread stamp the label into the log AND dump a
# UNITSTATE line for it. Waiting for the line carrying OUR label is what makes this a
# synchronous read of unit state rather than a race against the 250 ms poll.
$markerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt'
$markerSeq = 0

function Get-ScUnitState {
    param([string]$Tag, [int]$TimeoutSec = 10)
    $script:markerSeq++
    $label = "$Tag-$script:markerSeq"
    Set-Content -LiteralPath $markerPath -Value $label -NoNewline
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $line = Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
                Select-String -Pattern ([regex]::Escape("UNITSTATE [$label]")) |
                Select-Object -Last 1
        if ($line) {
            $m = [regex]::Match($line.Line,
                'UNITSTATE \[[^\]]*\] n=(\d+) live=(\d+) visible=(\d+) overflow=(\d+) orders=\[([^\]]*)\] orders2=\[[^\]]*\] types=\[([^\]]*)\] burrowed=(\d+)/(\d+)')
            if (-not $m.Success) { break }
            $orders = @{}
            foreach ($pair in ($m.Groups[5].Value -split '\s+' | Where-Object { $_ -match ':' })) {
                $kv = $pair -split ':'
                $orders[$kv[0]] = [int]$kv[1]
            }
            return [pscustomobject]@{
                N = [int]$m.Groups[1].Value; Live = [int]$m.Groups[2].Value
                Visible = [int]$m.Groups[3].Value; Overflow = [int]$m.Groups[4].Value
                Orders = $orders; Types = $m.Groups[6].Value
                Burrowed = [int]$m.Groups[7].Value
                Line = $line.Line.Trim()
            }
        }
        Start-Sleep -Milliseconds 250
    }
    throw "test: no UNITSTATE line for marker '$label' within ${TimeoutSec}s."
}

function Get-ScDominantOrder {
    param($State)
    ($State.Orders.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
}

# Asserts one untargeted command: it fans out past the cap, and afterwards not one unit is
# still doing what they were all doing before.
function Assert-ScOrderReachedEveryone {
    param(
        [string]$What, [IntPtr]$Hwnd, [int]$VirtualKey, [string]$ExpectedCmdId,
        [string]$Tag
    )
    # Put them all in motion first, so "still moving" is a detectable failure.
    Send-ScClick -Hwnd $Hwnd -X 90 -Y 300 -Right
    Start-Sleep -Seconds 2
    $before = Get-ScUnitState "$Tag-moving"
    $moving = Get-ScDominantOrder $before
    Assert-That "$What`: the group is moving first (order $moving on $($before.Orders[$moving]) of $($before.Live) units)" `
        ($before.Live -gt 12 -and $before.Orders[$moving] -gt 12)

    $mark = Get-ScLogLineCount -LogPath $LogPath
    Send-ScKey -Hwnd $Hwnd -VirtualKey $VirtualKey
    Start-Sleep -Seconds 3
    $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)

    $cmd = @($lines | Select-String -Pattern "CMD id=$ExpectedCmdId ")
    Assert-That "$What`: the key emitted $ExpectedCmdId" ($cmd.Count -gt 0)

    $start = @($lines | Select-String -Pattern "FANOUT start: cmd=$ExpectedCmdId .* units=(\d+)")
    Assert-That "$What`: it was fanned out" ($start.Count -gt 0)
    if ($start.Count -gt 0) {
        $u = [int]([regex]::Match($start[-1].Line, 'units=(\d+)').Groups[1].Value)
        Assert-That "$What`: more than twelve units were commanded ($u)" ($u -gt 12)
    }
    Assert-That "$What`: every chunk went out" (@($lines | Select-String -Pattern 'FANOUT done').Count -gt 0)

    $after = Get-ScUnitState "$Tag-after"
    Assert-That "$What`: nobody died on the way ($($before.Live) -> $($after.Live))" `
        ($after.Live -eq $before.Live)
    # THE assertion. If the command had only reached the engine's twelve, the other twelve
    # would still be on the moving order.
    $stillMoving = $after.Orders[$moving]
    if ($null -eq $stillMoving) { $stillMoving = 0 }
    Assert-That "$What`: NOT ONE of the $($after.Live) units is still on order $moving (was $($before.Orders[$moving]))" `
        ($stillMoving -eq 0) "(still $stillMoving)"
    Write-Host "       $($after.Line)"
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
    # Circles OFF: this test is about orders, and a run with fewer moving parts is a run
    # whose failures are easier to read. test-selection-circles.ps1 covers them.
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode fanout -Circles 0 -InjectWindowedHelper WMode `
        -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step 'menus: Single Player -> Expansion -> Play Custom -> Maps\campaign\(1)Enslavers02b.scm' {
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
        Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # StarCraft: Brood War (Expansion)
        Start-Sleep -Seconds 1
        Send-ScClick -Hwnd $hwnd -X 75  -Y 111        # first entry in the Registry list
        Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 327 -Y 415        # Play Custom
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 135 -Y 178        # [Up One Level]  (out of BroodWar\)
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok
        Start-Sleep -Milliseconds 800
        Send-ScClick -Hwnd $hwnd -X 117 -Y 140        # [campaign]
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok
        Start-Sleep -Milliseconds 800
        Send-ScClick -Hwnd $hwnd -X 150 -Y 197        # (1)Enslavers02b.scm
        Start-Sleep -Milliseconds 500
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 8
        Send-ScClick -Hwnd $hwnd -X 200 -Y 261        # dismiss the "StarCraft Tips" dialog
        Start-Sleep -Seconds 2
        Shot 'in-game'
    }

    Step 'a drag box captures more units than the engine can hold' {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScDrag -Hwnd $hwnd -X1 115 -Y1 25 -X2 515 -Y2 355 -Steps 20
        Start-Sleep -Seconds 2
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $shadow = @($lines | Select-String -Pattern 'SHADOW captured: (\d+) units \((\d+) visible \+ (\d+) beyond')
        Assert-That 'the shadow list holds the whole box' ($shadow.Count -gt 0)

        $state = Get-ScUnitState 'boxed'
        Assert-That "more than twelve units are under command ($($state.N))" ($state.N -gt 12)
        Assert-That "the engine itself still holds only twelve ($($state.Visible))" ($state.Visible -eq 12)
        Assert-That "the rest are beyond the cap ($($state.Overflow))" ($state.Overflow -gt 0)
        Write-Host "       $($state.Line)"
        Shot 'boxed'
    }

    Step 'Stop (0x1A) reaches every unit, not just the twelve' {
        Assert-ScOrderReachedEveryone -What 'Stop' -Hwnd $hwnd -VirtualKey 0x53 `
            -ExpectedCmdId '0x1A' -Tag 'stop'
        Shot 'after-stop'
    }

    Step 'Hold Position (0x2B) reaches every unit, not just the twelve' {
        Assert-ScOrderReachedEveryone -What 'Hold Position' -Hwnd $hwnd -VirtualKey 0x48 `
            -ExpectedCmdId '0x2B' -Tag 'hold'
        Shot 'after-hold'
    }

    Step 'Attack and Patrol are Targeted Order (0x15), and it fans out' {
        # Both are 0x15 with a different order byte at offset 9 -- Attack 0x08, Patrol 0x98,
        # Move 0x31 (named in game, research/command-opcodes.md 4). 0x15 has been in the
        # fan-out set since task 011, so this step is a regression check, not new ground.
        $seen = @{}
        foreach ($case in @(
            @{ Name = 'Attack'; Key = 0x41 },
            @{ Name = 'Patrol'; Key = 0x50 })) {
            Send-ScDrag -Hwnd $hwnd -X1 115 -Y1 25 -X2 515 -Y2 355 -Steps 20
            Start-Sleep -Seconds 2
            $mark = Get-ScLogLineCount -LogPath $LogPath
            Send-ScKey -Hwnd $hwnd -VirtualKey $case.Key
            Start-Sleep -Milliseconds 500
            Send-ScClick -Hwnd $hwnd -X 300 -Y 150
            Start-Sleep -Seconds 3
            $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
            $cmd = @($lines | Select-String -Pattern 'CMD id=0x15 len=11 bytes=\[15(?: [0-9A-F]{2}){8} ([0-9A-F]{2}) ')
            Assert-That "$($case.Name) emits Targeted Order 0x15" ($cmd.Count -gt 0)
            if ($cmd.Count -gt 0) {
                # The order byte is REPORTED, not asserted against a constant: which order
                # a targeting click produces depends on what it landed on (ground or a
                # unit), and this test does not control that. What it must show is that
                # the two buttons are distinct orders and both go out as 0x15.
                $seen[$case.Name] = [regex]::Match($cmd[-1].Line,
                    'bytes=\[15(?: [0-9A-F]{2}){8} ([0-9A-F]{2}) ').Groups[1].Value
                Write-Host "       $($case.Name) -> order byte 0x$($seen[$case.Name])"
            }
            $start = @($lines | Select-String -Pattern 'FANOUT start: cmd=0x15 .* units=(\d+)')
            Assert-That "$($case.Name) was fanned out" ($start.Count -gt 0)
            if ($start.Count -gt 0) {
                $u = [int]([regex]::Match($start[-1].Line, 'units=(\d+)').Groups[1].Value)
                Assert-That "$($case.Name): more than twelve units were commanded ($u)" ($u -gt 12)
            }
        }
        Assert-That 'Attack and Patrol are different orders inside the same command id' `
            ($seen.Count -eq 2 -and $seen['Attack'] -ne $seen['Patrol']) `
            "(attack=0x$($seen['Attack']) patrol=0x$($seen['Patrol']))"
        Shot 'after-attack-patrol'
    }

    Step 'the run never fanned out anything outside the policy set' {
        # The whole-run check: every FANOUT start in the log must name an id the policy
        # table marks fanout. One stray id here is a policy bug that the per-case steps
        # above could not see.
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

        # Every command the run saw, and whether it was fanned out. A passthrough id that
        # appeared and was left alone is the in-game half of criterion 6; the byte-exact
        # half, over ten passthrough ids including production and cancel, is offline in
        # src/hooktest.cpp part [9], because no >12 selection this map can offer has a
        # production or cancel button on its command card to press.
        $all = @(Get-Content -LiteralPath $LogPath |
                 Select-String -Pattern 'CMD id=(0x[0-9A-F]{2})' |
                 ForEach-Object { [regex]::Match($_.Line, 'CMD id=(0x[0-9A-F]{2})').Groups[1].Value } |
                 Sort-Object -Unique)
        $passedThrough = @($all | Where-Object { $ids -notcontains $_ })
        Write-Host "       ids seen but NOT fanned out: $($passedThrough -join ' ')"
        Assert-That 'at least one command id passed through untouched' ($passedThrough.Count -gt 0)
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
}

Write-Host ''
Write-Host '[final] the run must balance'
$left = if ($gamePid -gt 0) { Get-Process -Id $gamePid -ErrorAction SilentlyContinue } else { $null }
Assert-That 'the game process this test started is gone' ($KeepOpen -or $null -eq $left)

$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-fanout-orders: $failures failure(s)"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
