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

. (Join-Path $scriptDir 'sc-suite.ps1')

$failures = 0
$step = 0

# The windowed-mode helper leaves its caption inside the reported client rectangle, so
# a coordinate read off a captured frame is 5 px right and 32 px down from the client
# coordinate a message must carry. Every constant below is already a CLIENT coordinate;
# this note is here so the next person reading a frame does not re-derive it.

# --- on-disk binary, BEFORE anything runs ------------------------------------
# Project hard rule 3: "Patch memory in-process only -- StarCraft.exe on disk must stay
# byte-identical to pristine. Hash it and show the result." An attestation in a PR body
# is not that; this is.
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

# The launch itself is INSIDE the try. run-with-plugin.ps1 throws on an error dialog
# after the process is already alive, and Get-ScGameWindow throws on a 30 s timeout --
# either would strand a StarCraft process if they ran ahead of the finally that closes
# it, which is the one thing hard rule "never leave a game process running" forbids.
try {
    $circles = if ($NoCircles) { '0' } else { '1' }
    # The pid is parsed AS THE LINE STREAMS BY, not from a collected result. If the
    # launcher throws after the process is alive -- which is exactly what its
    # error-dialog check does -- a collected variable would never be assigned and the
    # finally below would have no pid to close.
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode fanout -Circles $circles -HudRow 0 -InjectWindowedHelper WMode `
        -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }

    if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }

    $hwnd = Get-ScGameWindow -ProcessId $gamePid

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
        # Up out of BroodWar, into campaign, onto the map -- every row computed from the
        # filesystem and every folder verified on screen before the next click.
        #
        # THE RUN THAT MADE THIS NECESSARY WAS THIS SUITE'S. The three fixed-row clicks
        # that used to be here worked until another task created its own fixture folder
        # under Maps\BroodWar: `[Up One Level]` sorts alphabetically among the folders, so
        # it moved off row 3, this walk opened a folder, the map never loaded, and the
        # suite timed out looking exactly like menu flake (task 022, 2026-08-09). This
        # suite generates nothing and shares nothing -- and was broken anyway, which is
        # why every browser click in this repo is computed now, not just the ones next to
        # a fixture.
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir `
            -MapPath (Join-Path $GameDir 'Maps\campaign\(1)Enslavers02b.scm') | Out-Null
        Shot 'map-selected'
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok
        Start-Sleep -Seconds 6
        Shot 'briefing'
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 8
        # The tips dialog is found in the engine's own dialog list and dismissed by ITS OWN
        # OK button, then asserted gone (task 027) -- never a fixed point, never the registry.
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
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

        # task 036 (#42, building groups) inserted `clicked=0x%08X -> engine=%u ` between
        # `candidates=` and `selected=` in the plugin's format string; this suite's regex
        # was never updated to match and so stopped matching ANY line, not just the wrong
        # one (task 046). test-building-parity.ps1's Get-ScSortLines already carries the
        # post-036 shape -- mirrored here rather than re-derived.
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
        # shadow unit instead of clicking hopefully. The plugin logs this because
        # nothing outside the process can work it out.
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
        # more carrying our circles, and a shift-click landing on one of ours.
        #
        # Because the plugin logs its circles' screen positions, the click can be AIMED
        # at one of them, and the assertion is the exact predicted behaviour rather than
        # "either branch is fine": our sprites never carry flag 0x08, so the engine
        # takes its add-to-selection branch, finds the selection already holds 12, and
        # returns -- no selection change, and no selection command on the wire.
        if ($NoCircles) {
            Write-Host '       (skipped: circles are off in this run)'
            return
        }
        if (-not $script:shadowXY -or $script:shadowXY.Count -eq 0) {
            Assert-That 'shadow circle positions were available to aim at' $false
            return
        }
        # Must be clear of the HUD, which starts around y=350 at 640x480. There is no
        # fallback to "aim at it anyway": a click behind the HUD hits nothing, and
        # "nothing happened" is exactly what this step asserts -- so the fallback would
        # be a guaranteed vacuous pass. No usable target is a FAILURE, not a shrug.
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

        # No Select / SelectAdd / SelectRemove was emitted: the engine did not treat our
        # unit as something it could add to or remove from the selection.
        $cmds = @($after | Select-String -Pattern 'CMD id=0x0(9|A|B) ')
        Assert-That 'no selection command was emitted' ($cmds.Count -eq 0) `
            ($cmds.Count -gt 0 ? "($($cmds[0].Line.Trim()))" : '')
        Shot 'after-shadow-shift-click'
    }

    Step 'an un-aimed shift-click inside the >12 selection is still legal' {
        # The complement of the step above: a click that may land on one of the ENGINE's
        # 12. Those sprites are ones this plugin never touches, so the expected result is
        # stock behaviour -- but the position of an engine-selected unit is not something
        # the plugin can report (it only knows its own), so this one cannot be aimed and
        # both outcomes are accepted. It is here for the crash/corruption check, not as a
        # behavioural assertion; see research/selection-circles.md §7.
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
catch {
    # A step that throws is a failed run, not an aborted one. Recording it here instead
    # of letting it propagate is what keeps the post-mortem below reachable -- the
    # after-close hash, the stranded-process check and the circle accounting are the
    # assertions for hard rule 3 and "never leave a game running", and those matter MOST
    # on the runs that went wrong.
    Write-Host "  FAIL a test step threw: $($_.Exception.Message)"
    Write-Host "       $($_.ScriptStackTrace)"
    $failures++
}
finally {
    # -ProcessId, always. close-game.ps1 resolving the game by NAME throws whenever any
    # other StarCraft is running -- including the user's own playable install -- and it
    # would close the wrong game.
    if (-not $KeepOpen -and $gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch {
            # close-game escalates to Stop-Process and throws only when the game is
            # STILL alive afterwards. That is a stranded game process -- the one thing
            # the hard rule forbids -- so it fails the run rather than warning about it.
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

# Check OUR pid, not the name: an unrelated StarCraft (the user's own install) is a
# scenario this repo's tooling explicitly expects, and failing on it would be a false
# alarm about the one rule that must never produce noise.
$left = if ($gamePid -gt 0) { Get-Process -Id $gamePid -ErrorAction SilentlyContinue } else { $null }
Assert-That 'the game process this test started is gone' ($KeepOpen -or $null -eq $left)

# --- on-disk binary, AFTER the run -------------------------------------------
# The other half of hard rule 3. If any code path had written to StarCraft.exe -- a
# stray patch, a botched working-copy refresh -- this is where it shows up, and it is
# an assertion rather than a claim in a report.
$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-selection-circles: $failures failure(s)"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
Write-Host 'The one thing this cannot assert is whether the circles are VISIBLE.'
Write-Host "Look at the 'shadow-selection' frame."
exit ($failures -eq 0 ? 0 : 1)
