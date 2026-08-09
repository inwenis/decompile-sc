#Requires -Version 7
<#
.SYNOPSIS
End-to-end, UNATTENDED proof that the bottom-HUD wireframe row pages through a >12
selection (task 017, design (c)): 36 Lurkers are boxed, the row shows page 1 (the
engine's own 12) with a "36 units" indicator, a right-click on the row flips to pages
2 and 3, clicking a page-2 portrait selects exactly that shadow unit through the
engine's own click path, and any selection change snaps back to page 1.

.DESCRIPTION
The oracle is IN-PROCESS UI-STATE READ-BACK: after every layout run the plugin logs
the unit tags it reads back OUT OF the live dialog's button records (`HUDROW show`),
plus where the buttons are on screen (`HUDROW rects`) so this script can aim clicks.
Frame captures corroborate that a page flip changes the pixels; they are a
diagnostic, never the oracle, and never committed.

The three conductor amendments to the stage-B spec are asserted here by name:
  1. any selection change (row click included) snaps back to page 1 / stock;
  2. no overflow -> no HUDROW activity at all (plus the stock-restored hand-back);
  3. clicking a shadow unit's portrait emits a vanilla 1-unit Select carrying that
     exact unit's tag, and the shadow list rebuilds coherently around it.

Same fixture and driving recipe as test-burrow-fanout.ps1 (task 016 map generator;
task 012's D1 posted-message driving). The map is generated for the run and deleted
afterwards -- generated maps are game content (AGENTS.md hard rule 1).

.EXAMPLE
./tools/plugin/test-hud-row.ps1

.EXAMPLE
./tools/plugin/test-hud-row.ps1 -KeepOpen
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogPath = 'C:\sc-work\logs\017-hud-row.log',
    [string]$ShotDir = 'C:\sc-work\logs\017-hud-row-frames',
    [int]$UnitCount = 36,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')

$failures = 0
$step = 0

$LURKER_TYPE = '0x67'

$mapDir = Join-Path $GameDir 'Maps\BroodWar\00-testmap'
$mapPath = Join-Path $mapDir 'lurkers.scx'

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
function Get-ScState {
    param([string]$Tag, [int]$TimeoutSec = 15)
    Get-ScUnitState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec
}

# Parse the newest `HUDROW show` line at or after $FromLine into
# @{ N; Page; Pages; Slots; Tags = string[] }.
function Get-HudShow {
    param([int]$FromLine, [int]$TimeoutSec = 15)
    $hits = @(Wait-ScLogMatch -LogPath $LogPath -FromLine $FromLine -TimeoutSec $TimeoutSec `
        -Pattern 'HUDROW show n=\d+ page=\d+/\d+ slots=\d+')
    $m = [regex]::Match($hits[-1],
        'HUDROW show n=(\d+) page=(\d+)/(\d+) slots=(\d+) \[([0-9A-F ]*)\] indicator="([^"]*)"')
    if (-not $m.Success) { throw "test: unparseable HUDROW show line: $($hits[-1])" }
    @{
        N         = [int]$m.Groups[1].Value
        Page      = [int]$m.Groups[2].Value
        Pages     = [int]$m.Groups[3].Value
        Slots     = [int]$m.Groups[4].Value
        Tags      = @($m.Groups[5].Value -split ' ' | Where-Object { $_ })
        Indicator = $m.Groups[6].Value
        Line      = $hits[-1]
    }
}

# Parse `HUDROW rects root=[l,t,r,b] b1=[l,t,r,b] ...`. The button bounds are
# LOCAL to the dialog's own origin (the plugin logs them raw), so client-pixel
# coordinates are root-origin + local -- composed here.
function Get-HudRects {
    param([int]$TimeoutSec = 15)
    $hits = @(Wait-ScLogMatch -LogPath $LogPath -Pattern 'HUDROW rects root=' -TimeoutSec $TimeoutSec)
    $line = $hits[-1]
    $rm = [regex]::Match($line, 'root=\[(-?\d+),(-?\d+),(-?\d+),(-?\d+)\]')
    if (-not $rm.Success) { throw "test: HUDROW rects line has no root: $line" }
    $rootL = [int]$rm.Groups[1].Value; $rootT = [int]$rm.Groups[2].Value
    $rects = @()
    foreach ($m in [regex]::Matches($line, 'b(\d+)=\[(-?\d+),(-?\d+),(-?\d+),(-?\d+)\]')) {
        # compose to client pixels. Parenthesize each element: PowerShell binds the
        # list ',' tighter than '+', so `$rootL + [int]X, ...` would parse as
        # int + array and throw op_Addition.
        $rects += , @(($rootL + [int]$m.Groups[2].Value), ($rootT + [int]$m.Groups[3].Value),
                      ($rootL + [int]$m.Groups[4].Value), ($rootT + [int]$m.Groups[5].Value))
    }
    if ($rects.Count -lt 12) { throw "test: HUDROW rects line carries $($rects.Count) rects: $line" }
    @{ Rects = $rects; Root = @($rootL, $rootT); Line = $line }
}

function Get-BtnCenter {
    param($Rects, [int]$Button)   # 1-based
    $r = $Rects.Rects[$Button - 1]
    @{ X = [int](($r[0] + $r[2]) / 2); Y = [int](($r[1] + $r[3]) / 2) }
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
    if ($script:hwnd -eq [IntPtr]::Zero) { return $null }
    $script:shotN++
    $p = Join-Path $ShotDir ("{0:d2}-{1}.png" -f $script:shotN, $tag)
    Save-ScWindowImage -Hwnd $script:hwnd -Path $p -FullWindow | Out-Null
    $p
}

# Crop a rectangle out of a saved frame and return its pixel bytes, for the
# "a flip changes the pixels" corroboration. Diagnostic only.
function Get-CropBytes {
    param([string]$PngPath, [int]$L, [int]$T, [int]$R, [int]$B)
    Add-Type -AssemblyName System.Drawing
    $bmp = [System.Drawing.Bitmap]::FromFile($PngPath)
    try {
        $w = [Math]::Min($R, $bmp.Width) - $L
        $h = [Math]::Min($B, $bmp.Height) - $T
        $bytes = [System.Collections.Generic.List[byte]]::new()
        for ($y = $T; $y -lt $T + $h; $y += 2) {
            for ($x = $L; $x -lt $L + $w; $x += 2) {
                $c = $bmp.GetPixel($x, $y)
                $bytes.Add($c.R); $bytes.Add($c.G); $bytes.Add($c.B)
            }
        }
        , $bytes.ToArray()
    }
    finally { $bmp.Dispose() }
}

try {
    Step "generate the fixture: $UnitCount Lurkers, Use Map Settings, no triggers" {
        # AGENTS.md rule 4 (task 022): the generated-fixture folder is SHARED between workers and
        # the map browser picks by ROW, so a foreign .scx silently changes which map loads --
        # and a recursive delete here takes another worker's fixture out from under its running
        # game. This suite is not otherwise touched by task 022; this is the compliance change,
        # nothing else.
        Wait-ScTestMapDirFree -Dir $mapDir -MyMapPath $mapPath
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount $UnitCount -UnitType lurker -Player 0 -OutputPath $mapPath 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
        Assert-That 'its structural validation passed' `
            (@($gen | Select-String -Pattern '^OK: ').Count -gt 0)
    }

    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode fanout -InjectWindowedHelper WMode `
        -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step 'the hudrow hook is actually installed (6 hooks in fanout mode)' {
        # queueCommand + 3 shadow hooks + circles + hudrow-dispatcher = 6.
        $cfg = @(Wait-ScLogMatch -LogPath $LogPath -Pattern 'FANOUT config: .*hudrow=1' -TimeoutSec 20)
        Assert-That 'the config line says hudrow=1' ($cfg.Count -gt 0)
        $hooks = @(Wait-ScLogMatch -LogPath $LogPath -Pattern 'HOOK: (\d+)/(\d+) installed' -TimeoutSec 20)
        $m = [regex]::Match($hooks[-1], 'HOOK: (\d+)/(\d+) installed')
        Assert-That "all hooks installed ($($m.Groups[1].Value)/$($m.Groups[2].Value))" `
            ($m.Groups[1].Value -eq $m.Groups[2].Value -and [int]$m.Groups[1].Value -eq 6)
    }

    Step 'menus: Single Player -> Expansion -> Play Custom -> 00-testmap\lurkers.scx' {
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
        Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # StarCraft: Brood War (Expansion)
        Start-Sleep -Seconds 1
        Send-ScClick -Hwnd $hwnd -X 75  -Y 111        # first entry in the Registry list
        Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 327 -Y 415        # Play Custom -- opens in Maps\BroodWar
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 117 -Y 140        # [00-testmap], first row
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok
        Start-Sleep -Milliseconds 800
        Send-ScClick -Hwnd $hwnd -X 117 -Y 159        # lurkers.scx -- row 2
        Start-Sleep -Milliseconds 500
        Send-ScDropdownPick -Hwnd $hwnd -X 265 -Y 268 -Index 2   # Use Map Settings
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> mission briefing
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 10
        Send-ScClick -Hwnd $hwnd -X 200 -Y 261        # dismiss the "StarCraft Tips" dialog
        Start-Sleep -Seconds 2
    }

    $script:rects = $null
    $script:page1 = $null

    Step "box all ${UnitCount}: the row shows page 1 -- the ENGINE'S OWN 12" {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScDrag -Hwnd $hwnd -X1 10 -Y1 10 -X2 630 -Y2 340 -Steps 20
        Start-Sleep -Seconds 2

        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        Assert-That "the shadow list captured all $UnitCount" `
            (@($lines | Select-String -Pattern "SHADOW captured: $UnitCount units \(12 visible \+ $($UnitCount-12) beyond").Count -gt 0)

        $boxed = Get-ScState 'boxed'
        Assert-That "the box holds all $UnitCount placed units" ($boxed.N -eq $UnitCount)
        Assert-That 'they are all Lurkers' (@($boxed.Types.Keys).Count -eq 1 -and
            @($boxed.Types.Keys)[0] -eq $LURKER_TYPE)

        $script:page1 = Get-HudShow -FromLine $mark
        Assert-That "the row reads back n=$UnitCount" ($page1.N -eq $UnitCount)
        Assert-That 'page 1 of 3' ($page1.Page -eq 1 -and $page1.Pages -eq 3)
        Assert-That '12 slots shown' ($page1.Slots -eq 12)
        Assert-That '12 distinct unit tags read back from the live dialog' `
            (@($page1.Tags | Sort-Object -Unique).Count -eq 12)
        Write-Host "       $($page1.Line)"

        $script:rects = Get-HudRects
        Write-Host "       $($rects.Line)"
        # The rects must be inside the 640x480 client and in the console area, or
        # the coordinate-space assumption (client pixels) is wrong -- fail loudly.
        $r1 = $rects.Rects[0]
        Assert-That "the button rects are client-space plausible (b1=[$($r1 -join ',')])" `
            ($r1[0] -ge 0 -and $r1[2] -le 640 -and $r1[1] -ge 300 -and $r1[3] -le 480)
        Shot 'page1' | Out-Null
    }

    Step 'a RIGHT-CLICK on the row flips to page 2: 12 different shadow units' {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        $c = Get-BtnCenter $rects 5
        $before = Shot 'before-flip'
        Send-ScClick -Hwnd $hwnd -X $c.X -Y $c.Y -Right
        Start-Sleep -Seconds 2
        $flip = @(Wait-ScLogMatch -LogPath $LogPath -FromLine $mark -Pattern 'HUDROW flip -> page 2/3')
        Assert-That 'the flip was logged' ($flip.Count -gt 0)
        $p2 = Get-HudShow -FromLine $mark
        Assert-That 'page 2 of 3' ($p2.Page -eq 2 -and $p2.Pages -eq 3)
        Assert-That '12 slots shown' ($p2.Slots -eq 12)
        $overlap = @($p2.Tags | Where-Object { $page1.Tags -contains $_ })
        Assert-That 'page 2 shares NO unit with page 1 (12 fresh shadow units)' `
            ($overlap.Count -eq 0) "(overlap: $($overlap -join ' '))"
        Assert-That 'the indicator text changed across the flip' `
            ($p2.Indicator -ne $page1.Indicator -and $p2.Indicator -match '13-24' -and $p2.Indicator -match '\(2/3\)') `
            "(page1='$($page1.Indicator)' page2='$($p2.Indicator)')"
        Write-Host "       $($p2.Line)"
        $script:page2 = $p2

        $after = Shot 'page2'
        # GATED rendering evidence: the row's pixels MUST change across the flip.
        # The indicator text alone guarantees it (a different string is drawn), so
        # diff -gt 0 is a sound gate, not a heuristic. The button rects are client
        # coords and the frame is the full window, so pad generously and clamp.
        $rowL = [Math]::Max(0, (($rects.Rects | ForEach-Object { $_[0] } | Measure-Object -Minimum).Minimum) - 8)
        $rowT = [Math]::Max(0, (($rects.Rects | ForEach-Object { $_[1] } | Measure-Object -Minimum).Minimum) - 8)
        $rowR = (($rects.Rects | ForEach-Object { $_[2] } | Measure-Object -Maximum).Maximum) + 40
        $rowB = (($rects.Rects | ForEach-Object { $_[3] } | Measure-Object -Maximum).Maximum) + 40
        $diff = -1
        try {
            $a = Get-CropBytes $before $rowL $rowT $rowR $rowB
            $b = Get-CropBytes $after  $rowL $rowT $rowR $rowB
            $diff = 0
            for ($i = 0; $i -lt [Math]::Min($a.Count, $b.Count); $i++) {
                if ($a[$i] -ne $b[$i]) { $diff++ }
            }
        } catch {
            Write-Host "       crop failed: $($_.Exception.Message)"
        }
        Assert-That "the row's rendered pixels changed across the flip ($diff sampled bytes differ)" `
            ($diff -gt 0)
    }

    Step 'two more right-clicks: page 3, then wrap back to page 1' {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        $c = Get-BtnCenter $rects 5
        Send-ScClick -Hwnd $hwnd -X $c.X -Y $c.Y -Right
        Start-Sleep -Seconds 1
        $p3 = Get-HudShow -FromLine $mark
        Assert-That 'page 3 of 3' ($p3.Page -eq 3 -and $p3.Pages -eq 3)
        $seen = @(@($page1.Tags) + @($page2.Tags) + @($p3.Tags) | Sort-Object -Unique)
        Assert-That "the three pages together cover all $UnitCount units" `
            ($seen.Count -eq $UnitCount) "(covered $($seen.Count))"

        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScClick -Hwnd $hwnd -X $c.X -Y $c.Y -Right
        Start-Sleep -Seconds 1
        $p1b = Get-HudShow -FromLine $mark
        Assert-That 'wrapped back to page 1' ($p1b.Page -eq 1)
        Assert-That 'page 1 shows the engine 12 again (same tags)' `
            (@($p1b.Tags | Where-Object { $page1.Tags -contains $_ }).Count -eq 12)
    }

    Step 'AMENDMENT 3: left-clicking a page-2 portrait selects THAT shadow unit' {
        # Flip to page 2 first, so a shadow (beyond-the-cap) unit is on screen.
        $c = Get-BtnCenter $rects 5
        Send-ScClick -Hwnd $hwnd -X $c.X -Y $c.Y -Right
        Start-Sleep -Seconds 1
        $mark0 = Get-ScLogLineCount -LogPath $LogPath
        $p2 = Get-HudShow -FromLine ([Math]::Max(0, $mark0 - 40))
        Assert-That 'on page 2' ($p2.Page -eq 2)
        $targetTag = $p2.Tags[2]                       # button 3's unit, read back live

        $mark = Get-ScLogLineCount -LogPath $LogPath
        $b3 = Get-BtnCenter $rects 3
        Send-ScClick -Hwnd $hwnd -X $b3.X -Y $b3.Y     # LEFT click
        Start-Sleep -Seconds 2
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)

        # The engine's own click path: a vanilla 1-unit Select carrying that tag.
        $tagLo = $targetTag.Substring(2, 2); $tagHi = $targetTag.Substring(0, 2)
        $sel = @($lines | Select-String -Pattern "CMD id=0x09 len=4 bytes=\[09 01 $tagLo $tagHi\]")
        Assert-That "a vanilla Select(1) carried the clicked unit's tag $targetTag" `
            ($sel.Count -gt 0)
        # The shadow list rebuilt coherently around the new 1-unit selection.
        Assert-That 'the shadow list rebuilt as a 1-unit selection' `
            (@($lines | Select-String -Pattern 'SELECT commit: 1 units').Count -gt 0)
        # And with no overflow left, the row handed itself back to the engine.
        Assert-That 'the row restored itself to stock' `
            (@($lines | Select-String -Pattern 'HUDROW stock restored').Count -gt 0)
        $one = Get-ScState 'clicked-one'
        Assert-That "the selection is now that one unit (n=$($one.N))" ($one.N -eq 1)
        Shot 'after-shadow-click' | Out-Null
    }

    Step 'AMENDMENT 1a: on page 2, a MAP selection change snaps back to page 1' {
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScDrag -Hwnd $hwnd -X1 10 -Y1 10 -X2 630 -Y2 340 -Steps 20
        Start-Sleep -Seconds 2
        $pA = Get-HudShow -FromLine $mark
        Assert-That 're-boxed: page 1 again' ($pA.Page -eq 1)

        # Flip to page 2 and ASSERT it happened -- otherwise the snap-back below can
        # pass vacuously (if the flip silently failed, the row was already on page 1).
        $mark = Get-ScLogLineCount -LogPath $LogPath
        $c = Get-BtnCenter $rects 5
        Send-ScClick -Hwnd $hwnd -X $c.X -Y $c.Y -Right
        Start-Sleep -Seconds 1
        $onP2 = Get-HudShow -FromLine $mark
        Assert-That 'PRECONDITION: the flip to page 2 happened' ($onP2.Page -eq 2)

        # Now change the selection from the MAP and require the next display = page 1.
        $mark = Get-ScLogLineCount -LogPath $LogPath
        Send-ScDrag -Hwnd $hwnd -X1 10 -Y1 10 -X2 630 -Y2 340 -Steps 20
        Start-Sleep -Seconds 2
        $pB = Get-HudShow -FromLine $mark
        Assert-That 'after the MAP selection change the row is back on page 1' ($pB.Page -eq 1)
    }

    Step 'AMENDMENT 1b: a SHIFT-CLICK on the row is a selection change through our hook' {
        # A different selection-change route. On a paged row the shift-click path
        # (StatusScreenButton, 0x00458220) collects the 12 VISIBLE portraits minus the
        # clicked one -- <=11 units -- so the selection drops below 13 and the row
        # leaves paged mode entirely. What we assert is the invariant the amendment is
        # about: the change routes through our hook and the row does NOT stay on page 2.
        $mark = Get-ScLogLineCount -LogPath $LogPath
        # re-box to get back over 12, then flip to page 2 and confirm it.
        Send-ScDrag -Hwnd $hwnd -X1 10 -Y1 10 -X2 630 -Y2 340 -Steps 20
        Start-Sleep -Seconds 2
        $c = Get-BtnCenter $rects 5
        Send-ScClick -Hwnd $hwnd -X $c.X -Y $c.Y -Right
        Start-Sleep -Seconds 1
        $onP2 = Get-HudShow -FromLine $mark
        Assert-That 'PRECONDITION: on page 2 before the shift-click' ($onP2.Page -eq 2)

        $mark = Get-ScLogLineCount -LogPath $LogPath
        $b4 = Get-BtnCenter $rects 4
        Send-ScClick -Hwnd $hwnd -X $b4.X -Y $b4.Y -Shift    # remove that portrait
        Start-Sleep -Seconds 2
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        Assert-That 'the shift-click emitted a selection command through our hook' `
            (@($lines | Select-String -Pattern 'CMD id=0x0(9|A|B) ').Count -gt 0)
        Assert-That 'the row left page 2 (stock hand-back logged)' `
            (@($lines | Select-String -Pattern 'HUDROW stock restored').Count -gt 0)
        $sc = Get-ScState 'shift-removed'
        # PIN the payload: a real shift-remove of 1-of-12 shown leaves 11; a SILENT
        # shift failure (drive-game.ps1 documents that risk) degenerates to a plain
        # click which leaves exactly 1. Require >= 2 so the degenerate case fails.
        Assert-That "the shift-remove left more than one unit (n=$($sc.N)) — not a degenerate plain click" `
            ($sc.N -ge 2 -and $sc.N -le 12)
    }

    Step 'AMENDMENT 2: a <=12 selection produces NO row activity at all' {
        # Re-box >12 to get a paged row, then a LEFT-click on a page-1 portrait is the
        # engine's own "select just this unit" -- a deterministic way down to a 1-unit
        # selection with no map-coordinate guessing.
        Send-ScDrag -Hwnd $hwnd -X1 10 -Y1 10 -X2 630 -Y2 340 -Steps 20
        Start-Sleep -Seconds 2
        $mark = Get-ScLogLineCount -LogPath $LogPath
        $b1 = Get-BtnCenter $rects 1
        Send-ScClick -Hwnd $hwnd -X $b1.X -Y $b1.Y
        Start-Sleep -Seconds 2
        $lines = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark)
        $small = Get-ScState 'small'
        Assert-That "the selection shrank to one unit (n=$($small.N))" ($small.N -eq 1)
        Assert-That 'the hand-back to stock was logged' `
            (@($lines | Select-String -Pattern 'HUDROW stock restored').Count -gt 0)
        # POSITIVE stock read-back (not just the absence of paging): all 12 buttons
        # own the engine interact again, the indicator is unlinked, the chain is intact.
        $verify = @($lines | Select-String -Pattern 'HUDROW verify stock: engineInteract=(\d+)/(\d+) indicatorLinked=(\d+) chainLen=(\d+)')
        Assert-That 'a positive stock read-back was logged' ($verify.Count -gt 0)
        if ($verify.Count -gt 0) {
            $vm = [regex]::Match($verify[-1].Line, 'engineInteract=(\d+)/(\d+) indicatorLinked=(\d+) chainLen=(\d+)')
            Assert-That "  all 12 buttons own the engine interact ($($vm.Groups[1].Value)/$($vm.Groups[2].Value))" `
                ($vm.Groups[1].Value -eq '12' -and $vm.Groups[2].Value -eq '12')
            Assert-That '  the indicator is unlinked from the child chain' ($vm.Groups[3].Value -eq '0')
            # PIN the chain length for this fixture/build (statdata.bin ships 57
            # controls in the status dialog; the indicator is unspliced at this point).
            Assert-That "  the child chain is intact and complete ($($vm.Groups[4].Value) controls, expect 57)" `
                ([int]$vm.Groups[4].Value -eq 57)
        }
        $mark2 = Get-ScLogLineCount -LogPath $LogPath
        Start-Sleep -Seconds 3
        $lines2 = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $mark2)
        Assert-That 'and after it, no HUDROW show/flip lines at all' `
            (@($lines2 | Select-String -Pattern 'HUDROW (show|flip)').Count -eq 0)
        Shot 'stock-small-selection' | Out-Null
    }

    # NOTE on the death / removal legs: in-game unit death and removal (transport
    # load, mind control, archon merge) are not exercised here because this fixture
    # has NO combat and no transports -- one unit-less computer slot, no enemy, no
    # triggers (exactly what keeps the map from ending itself; see
    # test-burrow-fanout.ps1). Producing any of them unattended would need an
    # attacker/transport and a reliable wait, which the fixture deliberately excludes.
    # These are instead modelled correctly OFFLINE in hooktest part [10]: real damage
    # death (HP->0, uniqueness UNCHANGED -- the case the 0xA5 bug hid), slot reuse,
    # PERSISTENT engine-side divergence (hand back to stock, no churn, heal on the
    # next commit), and the CLICK GATE swallowing a click on a removed-not-killed
    # overflow unit before it can reach the engine's Select.
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
    if (-not $KeepOpen -and (Test-Path -LiteralPath $mapDir)) {
        Remove-Item -LiteralPath $mapPath -Force -ErrorAction SilentlyContinue
        # And take the FOLDER away too when it is empty. Leaving an empty 00-testmap behind
        # is not harmless: every suite here reaches its map with positional row clicks, so an
        # extra directory shifts the rows for suites that navigate somewhere else entirely --
        # which is exactly how task 022's compliance change broke test-selection-circles'
        # route to Maps\campaign. Remove-ScOwnFixtureDir refuses if anything is still in it.
        Remove-ScOwnFixtureDir -Dir $mapDir
    }
}

Write-Host ''
Write-Host '[final] the run must balance'
$left = if ($gamePid -gt 0) { Get-Process -Id $gamePid -ErrorAction SilentlyContinue } else { $null }
Assert-That 'the game process this test started is gone' ($KeepOpen -or $null -eq $left)
# This test's own fixture, not the folder: the folder is shared with other workers and
# this suite no longer removes it (AGENTS.md rule 4 -- see the note at the generation step).
Assert-That 'the generated map was cleaned up' ($KeepOpen -or -not (Test-Path -LiteralPath $mapPath))

$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

Write-Host ''
Write-Host "test-hud-row: $failures failure(s)"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
