#Requires -Version 7
<#
.SYNOPSIS
End-to-end, UNATTENDED test of task 014's selection circles: launches the game, walks
the menus, loads a stock map, drives a drag box and an order with posted window
messages, and asserts on the plugin's own log.

.DESCRIPTION
Everything here is task 012's D1 recipe (research/automated-testing-options.md §4.1)
via tools/plugin/drive-game.ps1: PostMessage with CLIENT coordinates in lParam, no
synthetic OS input anywhere, no screen coordinates, focus not required. The window must
not be minimised.

THE ORACLE IS THE PLUGIN LOG, not the picture (research/automated-testing-options.md
O1/O2). The log is written from inside the process, so it reports what the engine
actually did. Frames are captured at every step as a DIAGNOSTIC only -- they land
outside the repo because they reproduce game artwork (AGENTS.md hard rule 1) and must
never be committed.

WHAT IT CANNOT PROVE. That the attached image is actually DRAWN. `CIRCLES show: N/N`
means the engine accepted the attach and returned an image; only an eye on the frames
in -ShotDir can confirm pixels. That is the one question this script hands back to a
human.

ASSUMPTIONS, all of which fail loudly rather than silently:
  * the working copy is at -GameDir and has Maps\campaign\(1)Enslavers02b.scm;
  * a player profile already exists (the Registry screen's first list entry is picked);
  * the menu layout is stock 1.16.1 at 640x480.

.EXAMPLE
./tools/plugin/test-selection-circles.ps1

.EXAMPLE
./tools/plugin/test-selection-circles.ps1 -ShotDir C:\temp\sc-frames -KeepOpen
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogPath = 'C:\sc-work\logs\014-circles-test.log',
    # Frames land here. MUST be outside the repo: they reproduce game artwork.
    [string]$ShotDir = 'C:\sc-work\logs\014-frames',
    [switch]$KeepOpen,
    [switch]$NoCircles          # the off-switch run: fan-out on, circles off
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

# The windowed-mode helper leaves its caption inside the reported client rectangle, so
# a coordinate read off a captured frame is 5 px right and 32 px down from the client
# coordinate a message must carry. Every constant below is already a CLIENT coordinate;
# this note is here so the next person reading a frame does not re-derive it.
function Step {
    param([string]$Name, [scriptblock]$Body)
    $script:step++
    Write-Host ''
    Write-Host ("[{0}] {1}" -f $script:step, $Name)
    & $Body
}

# --- launch ------------------------------------------------------------------
if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null

$circles = if ($NoCircles) { '0' } else { '1' }
$launch = & (Join-Path $scriptDir 'run-with-plugin.ps1') `
    -Mode fanout -Circles $circles -InjectWindowedHelper WMode `
    -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object { Write-Host $_; "$_" }

$gamePid = 0
foreach ($l in $launch) { if ($l -match 'scinject:\s*PID=(\d+)') { $gamePid = [int]$Matches[1] } }
if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }

$hwnd = Get-ScGameWindow -ProcessId $gamePid
$shotN = 0
function Shot([string]$tag) {
    $script:shotN++
    Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $ShotDir ("{0:d2}-{1}.png" -f $script:shotN, $tag)) -FullWindow | Out-Null
}

try {
    # --- menus ---------------------------------------------------------------
    # Client coordinates, read off captured frames once and stable for stock 1.16.1.
    Step 'menu: Single Player -> Expansion' {
        Start-Sleep -Seconds 2
        Shot 'main-menu'
        Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
        Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # StarCraft: Brood War (Expansion)
        Start-Sleep -Seconds 1
        Shot 'registry'
    }

    Step 'menu: pick the first profile' {
        Send-ScClick -Hwnd $hwnd -X 75  -Y 111        # first entry in the Registry list
        Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
        Start-Sleep -Seconds 2
        Shot 'campaign-select'
    }

    Step 'menu: Play Custom -> Maps\campaign\(1)Enslavers02b.scm' {
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
        Shot 'map-selected'
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok
        Start-Sleep -Seconds 6
        Shot 'briefing'
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 8
        Send-ScClick -Hwnd $hwnd -X 200 -Y 261        # dismiss the "StarCraft Tips" dialog
        Start-Sleep -Seconds 2
        Shot 'in-game'
    }

    # --- the deterministic shift-click test, before anything has moved --------
    #
    # Ordered FIRST on purpose: the map starts with its units in fixed positions, so
    # these coordinates are reproducible. After an order they are not.
    Step 'shift-click removes exactly the clicked unit (small selection)' {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScDrag -Hwnd $hwnd -X1 195 -Y1 23 -X2 435 -Y2 73   # the three air units, top row
        Start-Sleep -Seconds 1
        $sel = @(Wait-ScLogMatch -LogPath $LogPath -Pattern 'SEL count=\d+' -FromLine $mark)
        $n0 = [int]([regex]::Match($sel[-1], 'SEL count=(\d+)').Groups[1].Value)
        Assert-That "a small box selects more than one unit (got $n0)" ($n0 -gt 1)
        Shot 'small-selection'

        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScClick -Hwnd $hwnd -X 315 -Y 48 -Shift              # the middle one
        Start-Sleep -Seconds 2
        $sel = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark |
                 Select-String -Pattern 'SEL count=(\d+)')
        if ($sel.Count -eq 0) { Assert-That 'the shift-click changed the selection' $false '(no SEL line)' }
        else {
            $n1 = [int]([regex]::Match($sel[-1].Line, 'SEL count=(\d+)').Groups[1].Value)
            # THE selectionIndex HAZARD, tested rather than assumed
            # (research/selection-circles.md §4): the engine computes a memmove offset
            # from CSprite::selectionIndex here. Exactly one unit must leave.
            Assert-That "shift-click removed exactly one unit ($n0 -> $n1)" ($n1 -eq $n0 - 1)
        }
        Shot 'after-shift-click'
    }

    # --- the feature ---------------------------------------------------------
    Step 'a 24-unit drag box circles the 12 the engine threw away' {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScDrag -Hwnd $hwnd -X1 115 -Y1 25 -X2 515 -Y2 355 -Steps 20
        Start-Sleep -Seconds 2
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)

        $sort = @($lines | Select-String -Pattern 'SORT candidates=(\d+) -> selected=(\d+)')
        Assert-That 'the box contained more than 12 units' ($sort.Count -gt 0 -and
            [int]([regex]::Match($sort[-1].Line, 'candidates=(\d+)').Groups[1].Value) -gt 12)

        $shadow = @($lines | Select-String -Pattern 'SHADOW captured: (\d+) units \((\d+) visible \+ (\d+) beyond')
        Assert-That 'the shadow list holds the whole box' ($shadow.Count -gt 0)

        $show = @($lines | Select-String -Pattern 'CIRCLES show: (\d+)/(\d+) units circled')
        if ($NoCircles) {
            Assert-That 'circles are OFF: nothing was attached' ($show.Count -eq 0)
        }
        else {
            Assert-That 'circles were attached' ($show.Count -gt 0)
            if ($show.Count -gt 0) {
                $m = [regex]::Match($show[-1].Line, 'CIRCLES show: (\d+)/(\d+)')
                $got = [int]$m.Groups[1].Value; $want = [int]$m.Groups[2].Value
                Assert-That "every over-cap unit got a circle ($got/$want)" ($got -eq $want -and $got -gt 0)
                $over = [int]([regex]::Match($shadow[-1].Line, 'beyond the cap: ?|\+ (\d+) beyond').Groups[1].Value)
                if ($over -gt 0) {
                    Assert-That "circle count matches the over-cap count ($got vs $over)" ($got -eq $over)
                }
            }
        }
        Shot 'shadow-selection'   # <-- LOOK AT THIS ONE: circles on >12 units
    }

    Step 'a shift-click inside a >12 selection cannot corrupt it' {
        # THIS is the configuration research/selection-circles.md §4 says a naive
        # implementation smashes a 48-byte stack array in: 12 engine-selected units,
        # 12 more carrying our circles, and a shift-click landing on one of them.
        #
        # Whichever set the clicked unit is in, exactly one outcome is legal:
        #   - engine-selected  -> the engine removes it, SEL count 12 -> 11;
        #   - shadow-circled   -> flag 0x08 is clear, so the branch that reads
        #                         selectionIndex is unreachable and nothing changes.
        # The click cannot be aimed at one set or the other from outside the process,
        # so both are accepted -- and anything else is a failure.
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScClick -Hwnd $hwnd -X 235 -Y 48 -Shift
        Start-Sleep -Seconds 2
        $sel = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark |
                 Select-String -Pattern 'SEL count=(\d+)')
        $alive = $null -ne (Get-Process -Id $gamePid -ErrorAction SilentlyContinue)
        Assert-That 'the game survived the shift-click' $alive
        $n = 12
        if ($sel.Count -gt 0) {
            $n = [int]([regex]::Match($sel[-1].Line, 'SEL count=(\d+)').Groups[1].Value)
        }
        Write-Host "       (the clicked unit was $(if ($n -eq 11) { 'engine-selected -> removed' } else { 'shadow-circled -> ignored' }))"
        Assert-That "the selection is 11 or 12, never anything else (SEL count=$n)" ($n -eq 11 -or $n -eq 12)
        Shot 'after-shadow-shift-click'
    }

    Step 'one order still reaches every unit (fan-out is not broken)' {
        # Re-select first. The step above may have removed a unit, and a fan-out test
        # run against an 11-unit selection would "fail" for a reason that has nothing
        # to do with the fan-out.
        Send-ScDrag -Hwnd $hwnd -X1 115 -Y1 25 -X2 515 -Y2 355 -Steps 20
        Start-Sleep -Seconds 2
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScClick -Hwnd $hwnd -X 85 -Y 250 -Right
        Start-Sleep -Seconds 3
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $start = @($lines | Select-String -Pattern 'FANOUT start: .* units=(\d+) .* -> (\d+) Select\+order pairs')
        Assert-That 'the order was fanned out' ($start.Count -gt 0)
        if ($start.Count -gt 0) {
            $u = [int]([regex]::Match($start[-1].Line, 'units=(\d+)').Groups[1].Value)
            Assert-That "more than 12 units were ordered ($u)" ($u -gt 12)
        }
        Assert-That 'every chunk went out' (@($lines | Select-String -Pattern 'FANOUT done').Count -gt 0)
        Start-Sleep -Seconds 4
        Shot 'after-order'
    }
}
finally {
    if (-not $KeepOpen) {
        & (Join-Path $scriptDir 'close-game.ps1') | Write-Host
        Start-Sleep -Seconds 2
    }
}

# --- shutdown accounting -----------------------------------------------------
Write-Host ''
Write-Host '[final] the run must balance'
$stats = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
           Select-String -Pattern 'CIRCLES stats: shown=(\d+) hidden=(\d+) held=(-?\d+) skipped=(\d+) noImage=(\d+) lost=(\d+)')
if ($NoCircles) {
    Assert-That 'circles OFF: no stats line at all' ($stats.Count -eq 0)
}
elseif ($stats.Count -eq 0) {
    Assert-That 'a CIRCLES stats line was written on detach' $false
}
else {
    $m = [regex]::Match($stats[-1].Line, 'shown=(\d+) hidden=(\d+) held=(-?\d+) skipped=(\d+) noImage=(\d+) lost=(\d+)')
    $shown = [int]$m.Groups[1].Value; $hidden = [int]$m.Groups[2].Value
    $held  = [int]$m.Groups[3].Value; $noImg  = [int]$m.Groups[5].Value
    $lost  = [int]$m.Groups[6].Value
    Write-Host "  $($stats[-1].Line.Trim())"

    # The books must balance: every circle ever attached was either detached again or
    # is still held at the moment the process died. `held > 0` is NORMAL here -- the
    # test quits with a live selection on screen, and scplugin.cpp deliberately does
    # not un-splice on the process-exit path (walking the thread list from DllMain
    # under the loader lock is the unsafe thing, and the address space is going away
    # anyway). What would be a bug is a circle that is neither.
    Assert-That "the circle accounting balances ($shown = $hidden detached + $held held)" ($shown -eq $hidden + $held)
    # A `lost` circle is one whose unit or sprite changed underneath us, so it was
    # never taken off. Not a crash -- a circle left on screen under a unit nobody
    # selected, which is exactly the symptom this task exists to remove.
    Assert-That 'no circle was lost to a stale unit or sprite' ($lost -eq 0)
    Assert-That 'the image free list never ran out' ($noImg -eq 0)

    # The strong invariant, and the one that actually matters in play: every time the
    # selection changed, the detach pass took off EVERYTHING it was holding.
    $partial = @(Get-Content -LiteralPath $LogPath |
                 Select-String -Pattern 'CIRCLES hide: (\d+)/(\d+) removed' |
                 Where-Object { $m2 = [regex]::Match($_.Line, 'hide: (\d+)/(\d+)')
                                $m2.Groups[1].Value -ne $m2.Groups[2].Value })
    Assert-That 'no selection change ever left a circle behind' ($partial.Count -eq 0) `
        ($partial.Count -gt 0 ? "($($partial[0].Line.Trim()))" : '')
}

$left = Get-Process -Name StarCraft -ErrorAction SilentlyContinue
Assert-That 'no game process is left running' ($KeepOpen -or $null -eq $left)

Write-Host ''
Write-Host "test-selection-circles: $failures failure(s)"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
Write-Host 'The one thing this cannot assert is whether the circles are VISIBLE.'
Write-Host "Look at the 'shadow-selection' frame."
exit ($failures -eq 0 ? 0 : 1)
