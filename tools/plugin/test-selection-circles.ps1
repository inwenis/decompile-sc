#Requires -Version 7
<#
.SYNOPSIS
Unattended end-to-end test of the selection circles: launch, menus, stock map, drag box
and order -- asserted on the plugin's own log.
.DESCRIPTION
Input is PostMessage with CLIENT coordinates in lParam via drive-game.ps1
(research/automated-testing-options.md §4.1): no synthetic OS input, no screen
coordinates, focus not required, the window not minimised. THE ORACLE IS THE PLUGIN LOG,
not the picture (O1/O2 in that doc): written inside the process, it reports what the
engine actually did. `CIRCLES show: N/N`
proves only that the engine accepted the attach and returned an image; whether the pixels
are DRAWN is the one question the frames in -ShotDir hand back to a human.
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

. (Join-Path $scriptDir 'sc-suite.ps1')

$failures = 0
$step = 0

# --- on-disk binary, BEFORE anything runs ------------------------------------
# AGENTS.md § "Hard rules": patching is in-process only, so StarCraft.exe on disk must
# stay byte-identical to pristine -- hashed and shown, not attested.
$exePath = Join-Path $GameDir 'StarCraft.exe'
if (-not (Test-Path -LiteralPath $exePath)) { throw "test: $exePath not found." }
$hashBefore = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "[0] StarCraft.exe SHA-256 before: $hashBefore"

# The pristine 1.16.1 hash, from tools/make-working-copy.ps1 -- the same constant that
# script verifies the working copy against after it mirrors the install.
$PRISTINE_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
Assert-That 'the working copy starts out byte-identical to pristine 1.16.1' `
    ($hashBefore -eq $PRISTINE_SHA256) "(got $hashBefore)"

# --- launch ------------------------------------------------------------------
if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null

$gamePid = 0
$hwnd = [IntPtr]::Zero
$shotN = 0
function Shot([string]$tag) {
    if ($script:hwnd -eq [IntPtr]::Zero) { return }
    $script:shotN++
    Save-ScWindowImage -Hwnd $script:hwnd -Path (Join-Path $ShotDir ("{0:d2}-{1}.png" -f $script:shotN, $tag)) -FullWindow | Out-Null
}

# The launch itself is INSIDE the try: run-with-plugin.ps1 throws on an error dialog
# after the process is already alive, and Get-ScGameWindow throws on a 30 s timeout --
# either would strand a StarCraft process if it ran ahead of the finally that closes it.
try {
    $circles = if ($NoCircles) { '0' } else { '1' }
    # The pid is parsed AS THE LINE STREAMS BY, not from a collected result: the
    # launcher's error-dialog check throws after the process is alive, and a collected
    # variable would never be assigned, leaving the finally below no pid to close.
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode fanout -Circles $circles -HudRow 0 -InjectWindowedHelper WMode `
        -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }

    if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }

    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step 'menus: Single Player -> Expansion -> Play Custom -> Maps\campaign\(1)Enslavers02b.scm' {
        Enter-ScCustomGame -Hwnd $hwnd -LogPath $LogPath -MapPath (Join-Path $GameDir 'Maps\campaign\(1)Enslavers02b.scm') -GameDir $GameDir -Noun 'test' `
            -BeforeStart { Shot 'map-selected' }
        Shot 'in-game'
    }

    # --- the deterministic shift-click test, before anything has moved --------
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
            # from CSprite::selectionIndex here, so exactly one unit must leave.
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

        # The plugin's SORT line carries `clicked=0x%08X -> engine=%u ` between
        # `candidates=` and `selected=`; a regex that omits it matches NO line at all
        # rather than the wrong one, so the shape is mirrored from
        # test-building-parity.ps1's Get-ScSortLines instead of re-derived here.
        $sort = @($lines | Select-String -Pattern 'SORT candidates=(\d+) clicked=0x([0-9A-Fa-f]+) -> engine=(\d+) selected=(\d+)')
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
        # Where the circled units are on screen, so the next step can aim at a KNOWN
        # shadow unit instead of clicking hopefully: nothing outside the process can
        # work this out, which is why the plugin logs it.
        $pos = @($lines | Select-String -Pattern 'CIRCLES pos: \d+ on screen of \d+: (.+)$')
        if (-not $NoCircles) {
            Assert-That 'the plugin reported where its circles are on screen' ($pos.Count -gt 0)
            if ($pos.Count -gt 0) {
                $script:shadowXY = @([regex]::Match($pos[-1].Line, 'on screen of \d+: (.+)$').Groups[1].Value.Trim() -split '\s+' |
                    ForEach-Object { $p = $_ -split ','; [pscustomobject]@{ X = [int]$p[0]; Y = [int]$p[1] } })
                Write-Host "       ($($script:shadowXY.Count) shadow circles on screen, first at $($script:shadowXY[0].X),$($script:shadowXY[0].Y))"
            }
        }
        Shot 'shadow-selection'   # <-- LOOK AT THIS ONE: circles on >12 units
    }

    Step 'a shift-click on a KNOWN shadow-circled unit changes nothing' {
        # THIS is the configuration research/selection-circles.md §4 says a naive
        # implementation smashes a 48-byte stack array in: 12 engine-selected units, 12
        # more carrying our circles, and a shift-click landing on one of ours. The plugin
        # logs its circles' screen positions, so the click can be AIMED and the assertion
        # is the exact predicted behaviour rather than "either branch is fine": our
        # sprites never carry flag 0x08, so the engine takes its add-to-selection branch,
        # finds the selection already holds 12, and returns -- no selection change, and
        # no selection command on the wire.
        if ($NoCircles) {
            Write-Host '       (skipped: circles are off in this run)'
            return
        }
        if (-not $script:shadowXY -or $script:shadowXY.Count -eq 0) {
            Assert-That 'shadow circle positions were available to aim at' $false
            return
        }
        # Must be clear of the HUD, which starts around y=350 at 640x480. A click behind
        # the HUD hits nothing, and "nothing happened" is exactly what this step asserts,
        # so aiming at it anyway would be a guaranteed vacuous pass: no usable target is
        # a FAILURE, not a shrug.
        $target = $script:shadowXY | Where-Object { $_.Y -lt 340 -and $_.Y -gt 10 } | Select-Object -First 1
        if (-not $target) {
            Assert-That 'at least one shadow circle is on the battlefield, not behind the HUD' $false `
                "(all $($script:shadowXY.Count) reported positions were outside y=10..340)"
            return
        }

        $mark = Get-ScLogLineCount -LogPath $LogPath
        $selBefore = @(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'SEL count=(\d+)')
        $n0 = if ($selBefore.Count) { [int]([regex]::Match($selBefore[-1].Line, 'SEL count=(\d+)').Groups[1].Value) } else { 12 }

        Write-Host "       (aiming at the shadow circle at $($target.X),$($target.Y))"
        Send-ScClick -Hwnd $hwnd -X $target.X -Y $target.Y -Shift
        Start-Sleep -Seconds 2
        $after = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)

        Assert-That 'the game survived the shift-click' `
            ($null -ne (Get-Process -Id $gamePid -ErrorAction SilentlyContinue))

        $sel = @($after | Select-String -Pattern 'SEL count=(\d+)')
        $n1 = if ($sel.Count) { [int]([regex]::Match($sel[-1].Line, 'SEL count=(\d+)').Groups[1].Value) } else { $n0 }
        Assert-That "the engine's selection is unchanged ($n0 -> $n1)" ($n1 -eq $n0)

        # Select / SelectAdd / SelectRemove: none of them may go out, because the engine
        # must not treat our unit as something it can add to or remove from the selection.
        $cmds = @($after | Select-String -Pattern 'CMD id=0x0(9|A|B) ')
        Assert-That 'no selection command was emitted' ($cmds.Count -eq 0) `
            ($cmds.Count -gt 0 ? "($($cmds[0].Line.Trim()))" : '')
        Shot 'after-shadow-shift-click'
    }

    Step 'an un-aimed shift-click inside the >12 selection is still legal' {
        # The complement of the step above: a click that may land on one of the ENGINE's
        # 12, sprites this plugin never touches, so stock behaviour is what is expected.
        # The plugin can only report its own circles' positions, so this one cannot be
        # aimed and both outcomes are accepted -- it is here for the crash/corruption
        # check, not as a behavioural assertion (research/selection-circles.md §7).
        $selBefore = @(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'SEL count=(\d+)')
        $n0 = if ($selBefore.Count) { [int]([regex]::Match($selBefore[-1].Line, 'SEL count=(\d+)').Groups[1].Value) } else { 12 }
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScClick -Hwnd $hwnd -X 235 -Y 48 -Shift
        Start-Sleep -Seconds 2
        $sel = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark |
                 Select-String -Pattern 'SEL count=(\d+)')
        $n1 = if ($sel.Count) { [int]([regex]::Match($sel[-1].Line, 'SEL count=(\d+)').Groups[1].Value) } else { $n0 }
        Assert-That 'the game survived it' `
            ($null -ne (Get-Process -Id $gamePid -ErrorAction SilentlyContinue))
        Write-Host "       (landed on $(if ($n1 -eq $n0 - 1) { 'an engine-selected unit -> removed' } else { 'nothing selectable, or one of ours -> ignored' }))"
        Assert-That "the selection changed by at most one unit ($n0 -> $n1)" `
            ($n1 -eq $n0 -or $n1 -eq $n0 - 1)
    }

    Step 'one order still reaches every unit (fan-out is not broken)' {
        # Re-select first: the step above may have removed a unit, and a fan-out run
        # against an 11-unit selection would "fail" for a reason unrelated to fan-out.
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
catch {
    # A step that throws is a failed run, not an aborted one: recording it here instead
    # of letting it propagate keeps the post-mortem reachable, and the after-close hash,
    # the stranded-process check and the circle accounting matter MOST on a bad run.
    Write-Host "  FAIL a test step threw: $($_.Exception.Message)"
    Write-Host "       $($_.ScriptStackTrace)"
    $failures++
}
finally {
    # -ProcessId, always: close-game.ps1 resolving the game by NAME throws whenever any
    # other StarCraft is running -- including the user's own playable install -- and
    # would close the wrong game.
    if (-not $KeepOpen -and $gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch {
            # close-game escalates to Stop-Process and throws only when the game is
            # STILL alive afterwards: a stranded game process fails the run rather than
            # warning about it (AGENTS.md § "Stopping a run / orphaned games").
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

# --- shutdown accounting -----------------------------------------------------
Write-Host ''
Write-Host '[final] the run must balance'
$stats = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue |
           Select-String -Pattern 'CIRCLES stats:.* shown=(\d+) hidden=(\d+) held=(-?\d+) skipped=(\d+) noImage=(\d+) lost=(\d+)')
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

    # The books must balance: every circle attached was either detached again or is still
    # held when the process died. `held > 0` is NORMAL -- the test quits with a live
    # selection, and scplugin.cpp deliberately does not un-splice on the process-exit path
    # (walking the thread list from DllMain under the loader lock is unsafe, and the
    # address space is going away anyway). A circle that is neither is the bug.
    Assert-That "the circle accounting balances ($shown = $hidden detached + $held held)" ($shown -eq $hidden + $held)
    # A `lost` circle is one whose unit or sprite changed underneath us, so it was never
    # taken off: not a crash, but a circle left on screen under a unit nobody selected --
    # the symptom the feature exists to remove.
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

# Check OUR pid, not the name: an unrelated StarCraft (the user's own install) is a
# scenario this repo's tooling expects, and failing on it would be a false alarm about
# the one rule that must never produce noise.
$left = if ($gamePid -gt 0) { Get-Process -Id $gamePid -ErrorAction SilentlyContinue } else { $null }
Assert-That 'the game process this test started is gone' ($KeepOpen -or $null -eq $left)

# --- on-disk binary, AFTER the run -------------------------------------------
# The other half of the on-disk invariant: a code path that wrote to StarCraft.exe -- a
# stray patch, a botched working-copy refresh -- shows up here as a failed assertion
# rather than as a claim in a report.
$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-selection-circles: $failures failure(s)"
Write-Host "frames (diagnostic): $ShotDir"
Write-Host 'The one thing this cannot assert is whether the circles are VISIBLE.'
Write-Host "Look at the 'shadow-selection' frame."
exit ($failures -eq 0 ? 0 : 1)
