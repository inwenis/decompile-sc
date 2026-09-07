#Requires -Version 7
<#
.SYNOPSIS
Unattended proof that the bottom-HUD row pages a >12 selection: page 1 is the engine's own
12 plus an indicator, right-clicks flip pages, a page-2 portrait click selects that shadow
unit through the engine's own click path, and any selection change snaps back to page 1.
.DESCRIPTION
Oracle: in-process UI-state read-back (`HUDROW show` = unit tags read out of the live dialog's
button records; `HUDROW rects` aims the clicks). Frame captures only corroborate that a flip
changes pixels: diagnostic, never the oracle, never committed. Fixture and driving recipe as
test-burrow-fanout.ps1; the map is generated per run and deleted (game content, hard rule 1).
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
    # Plugin build to run (default: run-with-plugin.ps1's). A parameter so a before/after
    # pair can run this suite against a defect build in its own directory: before-numbers
    # and before-frames then come from the build that actually ships, not a description.
    [string]$BuildDir,
    # Folder under Maps\ the fixture is generated into; see test-burrow-fanout.ps1.
    [string]$FixtureDir,
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

# The fixture name is this SUITE's own (AGENTS.md § Shared test-fixture folder): two suites
# generating the same name make "delete only your own file" undecidable. With
# $env:AGENT_TASK set the folder resolves per agent, so two concurrent runs of this same
# suite cannot overwrite each other's identically-named fixture.
if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-testmap' -Suite 'hud-row' }
$mapDir = $FixtureDir
$mapName = 'hud-row.scx'
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
    # `Indicator` is read through the CONTROL's own pszText, not the module's buffer; the
    # fields after it say whether the player can SEE it: linked into the dialog's child
    # chain, the engine's visible bit, the box, and the ink the engine's text routine left
    # inside that box. Groups are BY NAME, NOT BY POSITION: a positional parse survives a
    # field inserted into this line without failing, it just reads one number out of another.
    $m = [regex]::Match($hits[-1],
        'HUDROW show n=(?<n>\d+) page=(?<page>\d+)/(?<pages>\d+) slots=(?<slots>\d+) ' +
        '\[(?<tags>[0-9A-F ]*)\] indicator="(?<text>[^"]*)" ' +
        'indLinked=(?<linked>\d+) indVisible=(?<visible>\d+) ' +
        'indBounds=\((?<l>-?\d+),(?<t>-?\d+),(?<r>-?\d+),(?<b>-?\d+)\) indInk=(?<ink>-?\d+)' +
        # The tail is OPTIONAL so this one suite can also run a defect build that does not log
        # these six fields: a run that cannot parse its own log is a broken run, not a
        # measurement. A missing field reads as -1, "no answer", and each assertion that
        # depends on one fails saying so.
        '(?: indBoxDiff=(?<boxDiff>-?\d+) indRefInk=(?<refInk>-?\d+) indRefId=(?<refId>-?\d+)' +
        ' indSurfInk=(?<surfInk>-?\d+) indFontH=(?<fontH>-?\d+) indShowing=(?<showing>\d+))?')
    if (-not $m.Success) { throw "test: unparseable HUDROW show line: $($hits[-1])" }
    function Num($g) { if ($m.Groups[$g].Success) { [int]$m.Groups[$g].Value } else { -1 } }
    @{
        N         = [int]$m.Groups['n'].Value
        Page      = [int]$m.Groups['page'].Value
        Pages     = [int]$m.Groups['pages'].Value
        Slots     = [int]$m.Groups['slots'].Value
        Tags      = @($m.Groups['tags'].Value -split ' ' | Where-Object { $_ })
        Indicator = $m.Groups['text'].Value
        IndLinked = $m.Groups['linked'].Value -eq '1'
        IndVisible= $m.Groups['visible'].Value -eq '1'
        IndBox    = @([int]$m.Groups['l'].Value, [int]$m.Groups['t'].Value,
                      [int]$m.Groups['r'].Value, [int]$m.Groups['b'].Value)
        IndInk    = [int]$m.Groups['ink'].Value
        BoxDiff   = (Num 'boxDiff')
        RefInk    = (Num 'refInk')
        RefId     = (Num 'refId')
        SurfInk   = (Num 'surfInk')
        FontH     = (Num 'fontH')
        Showing   = $m.Groups['showing'].Value -eq '1'
        Line      = $hits[-1]
    }
}

# `HUDROW band after stock` answers "did leaving paged mode strand any of our pixels". The
# plugin writes it once per hand-back, on a stock frame AFTER the one that hid the line (the
# repaint it asked for has not run on that one). Returns $null when the running build never
# wrote one; the caller reports that as a failed assertion, not an exception: "this build
# cannot answer the question" is the measurement.
function Get-HudBand {
    param([int]$FromLine, [int]$TimeoutSec = 15)
    $hits = @()
    try {
        $hits = @(Wait-ScLogMatch -LogPath $LogPath -FromLine $FromLine -TimeoutSec $TimeoutSec `
            -Pattern 'HUDROW band after stock: ')
    } catch { return $null }
    if ($hits.Count -eq 0) { return $null }
    $m = [regex]::Match($hits[-1],
        'HUDROW band after stock: rect=\((?<l>-?\d+),(?<t>-?\d+),(?<r>-?\d+),(?<b>-?\d+)\) ' +
        'glyphBytes=(?<glyph>-?\d+) stranded=(?<stranded>-?\d+) surfInk=(?<surfInk>-?\d+) ' +
        'episodes=(?<episodes>\d+)')
    if (-not $m.Success) { throw "test: unparseable HUDROW band line: $($hits[-1])" }
    @{
        Rect     = @([int]$m.Groups['l'].Value, [int]$m.Groups['t'].Value,
                     [int]$m.Groups['r'].Value, [int]$m.Groups['b'].Value)
        Glyph    = [int]$m.Groups['glyph'].Value
        Stranded = [int]$m.Groups['stranded'].Value
        SurfInk  = [int]$m.Groups['surfInk'].Value
        Line     = $hits[-1]
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
    # AND THE SAME RECTS UNCOMPOSED. The indicator's own bounds are logged RAW -- dialog-local,
    # like every control's -- so "the line is below the row" has to be compared in that space
    # or it compares a client-pixel number against a dialog-local one and passes for free.
    $local = @()
    foreach ($m in [regex]::Matches($line, 'b(\d+)=\[(-?\d+),(-?\d+),(-?\d+),(-?\d+)\]')) {
        $local += , @([int]$m.Groups[2].Value, [int]$m.Groups[3].Value,
                      [int]$m.Groups[4].Value, [int]$m.Groups[5].Value)
    }
    @{
        Rects = $rects
        Local = $local
        Root  = @($rootL, $rootT)
        # The row's own extent in dialog-local coordinates: the lowest edge of ALL TWELVE
        # buttons (they are two rows of six) and their leftmost edge.
        RowBottom = (($local | ForEach-Object { $_[3] } | Measure-Object -Maximum).Maximum)
        RowLeft   = (($local | ForEach-Object { $_[0] } | Measure-Object -Minimum).Minimum)
        RowTop    = (($local | ForEach-Object { $_[1] } | Measure-Object -Minimum).Minimum)
        Line  = $line
    }
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
        # AGENTS.md § Shared test-fixture folder: the folder may be shared between workers
        # and the map browser opens a ROW, so a foreign .scx moves which map loads. Wait for
        # theirs to go; clear only ours; never the folder.
        Wait-ScFixtureFolderFree -Run $fixtures
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
            -UnitCount $UnitCount -UnitType lurker -Player 0 -OutputPath $mapPath 2>&1
        $gen | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote the map' (Test-Path -LiteralPath $mapPath)
        Assert-That 'its structural validation passed' `
            (@($gen | Select-String -Pattern '^OK: ').Count -gt 0)
    }

    $runArgs = @{ Mode = 'fanout'; InjectWindowedHelper = 'WMode'; GameDir = $GameDir; LogPath = $LogPath }
    if ($BuildDir) { $runArgs.BuildDir = $BuildDir }
    # Hash the plugin this run is about to load, before it loads it: when the suite runs
    # against two builds, "which tree did that DLL come from" must not need answering by hand.
    $dllDir  = if ($BuildDir) { $BuildDir } else { Join-Path $repoRoot 'work/scratch/plugin-build' }
    $dllPath = Join-Path $dllDir 'scplugin.dll'
    if (Test-Path -LiteralPath $dllPath) {
        Write-Host ("[0] scplugin.dll SHA-256: {0}  ({1})" -f `
            (Get-FileHash -LiteralPath $dllPath -Algorithm SHA256).Hash, $dllPath)
    } else {
        Write-Host "[0] scplugin.dll not found at $dllPath -- run-with-plugin will say so"
    }
    & (Join-Path $scriptDir 'run-with-plugin.ps1') @runArgs 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'test: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step 'the hudrow hook is actually installed, by NAME (task 047 / task 050)' {
        # Compare hook NAMES, never a hardcoded total: a count mismatch names no hook
        # (AGENTS.md § Your DIAGNOSTICS are under the same rule as your assertions), and a
        # total stays silent if statDataUpdate (the ONE hook this suite exists to test) is
        # replaced by some other hook while the count happens to hold. The expected sets
        # live in drive-game.ps1 (Get-ScFanoutExpectedHooks / Compare-ScHookNames).
        $cfg = @(Wait-ScLogMatch -LogPath $LogPath -Pattern 'FANOUT config: .*hudrow=1' -TimeoutSec 20)
        Assert-That 'the config line says hudrow=1' ($cfg.Count -gt 0)
        $cm = [regex]::Match($cfg[-1], 'circles=(\d) hudrow=(\d) queueind=(\d)')
        Assert-That "the config line carries circles/hudrow/queueind flags ($($cfg[-1]))" $cm.Success
        # TWO SETS, different on purpose. `HOOK <name>: installed at` lines carry EVERY
        # module's hooks, so the by-name comparison is against the whole plugin's set. The
        # `HOOK: n/n installed` summary is sc_fanout's own count of what sc_fanout installed,
        # so the count corroboration is against the fan-out set alone. Cross-comparing them
        # compares two things never meant to be equal.
        $expectedFanout = Get-ScFanoutExpectedHooks -Circles ($cm.Groups[1].Value -eq '1') `
            -HudRow ($cm.Groups[2].Value -eq '1') -QueueInd ($cm.Groups[3].Value -eq '1')
        $expectedAll = Get-ScPluginExpectedHooks -Circles ($cm.Groups[1].Value -eq '1') `
            -HudRow ($cm.Groups[2].Value -eq '1') -QueueInd ($cm.Groups[3].Value -eq '1')

        $hookLines = @(Wait-ScLogMatch -LogPath $LogPath -Pattern 'HOOK (\S+): installed at ' -TimeoutSec 20)
        $actualNames = @($hookLines | ForEach-Object {
            [regex]::Match($_, 'HOOK (\S+): installed at ').Groups[1].Value
        })
        $cmp = Compare-ScHookNames -Expected $expectedAll -Actual $actualNames
        Assert-That "the installed hooks are exactly this arm's set ([$($cmp.Actual -join ', ')])" $cmp.Ok `
            ($cmp.Ok ? '' : "(missing: [$($cmp.Missing -join ', ')] extra: [$($cmp.Extra -join ', ')])")

        # Corroborate against the plugin's own summary line -- same install, independent
        # read -- with the total DERIVED from the named set rather than a second literal.
        $hooks = @(Wait-ScLogMatch -LogPath $LogPath -Pattern 'HOOK: (\d+)/(\d+) installed' -TimeoutSec 20)
        $m = [regex]::Match($hooks[-1], 'HOOK: (\d+)/(\d+) installed')
        Assert-That "sc_fanout's own count agrees ($($m.Groups[1].Value)/$($m.Groups[2].Value) vs $($expectedFanout.Count) fan-out hooks expected by name)" `
            ($m.Groups[1].Value -eq $m.Groups[2].Value -and [int]$m.Groups[2].Value -eq $expectedFanout.Count)
        # And the epoch's two, by name, in the same run. They are counted nowhere else,
        # so without this the union above could be satisfied by the fan-out set alone if
        # Get-ScSessionExpectedHooks were ever emptied.
        $sessionHooks = @(Get-ScSessionExpectedHooks)
        $sessionSeen = @($sessionHooks | Where-Object { $actualNames -contains $_ })
        Assert-That "the game-session epoch's hooks are spliced ($($sessionSeen -join ', '))" `
            ($sessionSeen.Count -eq $sessionHooks.Count) `
            "(expected $($sessionHooks -join ', '); saw $($sessionSeen.Count) of $($sessionHooks.Count))"
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
        Set-ScGameType -Hwnd $hwnd -LogPath $LogPath -Index 2      # Use Map Settings, verified
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok -> mission briefing
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 10
        # The tips dialog is found in the engine's own dialog list and dismissed by ITS OWN
        # OK button, then asserted gone -- never a fixed point, never the registry (AGENTS.md).
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
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
        # Everything above reads a STRING; none of it says the player can see it. Do not
        # assert the string out of the module's own buffer: a nine-pixel indicator box, shorter
        # than the font, makes the engine's text routine return without drawing anything, and
        # a buffer read-back passes over that. The string comes through the CONTROL's pszText,
        # and the two assertions below are what catch an invisible control.
        Assert-That 'the indicator control is linked into the status dialog' ($p2.IndLinked)
        Assert-That "and the ENGINE's own visible bit is set on it" ($p2.IndVisible)

        # Do not assert `IndInk > 0`: ink counts non-background bytes, so over a region the
        # engine also paints it SATURATES and cannot fail. Measured: box (32,9,180,25) =
        # 148 x 16 = 2368 bytes read indInk=2368 for "1-12 (1/3)", "13-24 (2/3)" and the wrap
        # back -- three strings, one number, the full area (research/status-pane-text.md
        # § 5.2). Ink stays logged as corroboration. The oracle is boxDiff, the band compared
        # against a copy of the SAME RECT with none of our line on it; its two blindness
        # checks come first so boxDiff=0 and "the probe cannot read anything" are not the
        # same reading.
        Assert-That "the probe can read the dialog surface at all (surfInk=$($p2.SurfInk))" `
            ($p2.SurfInk -gt 0)
        Assert-That "and a control the ENGINE fills (refInk=$($p2.RefInk) over control $($p2.RefId))" `
            ($p2.RefInk -gt 0)
        Assert-That ("the engine DREW the line: boxDiff=$($p2.BoxDiff) bytes of the band " +
                     "differ from the same band without it (ink=$($p2.IndInk), saturated)") `
            ($p2.BoxDiff -gt 0)

        # AND IT IS NOT ON TOP OF THE ICON ROW. Both numbers are dialog-local: the button
        # rects come from the plugin's own `HUDROW rects` line, read off the LIVE controls,
        # never a constant -- so "outside the row" is a number rather than an opinion.
        $rowBottom = $rects.RowBottom
        Assert-That "the row's twelve buttons were measured (lowest edge y=$rowBottom, left x=$($rects.RowLeft))" `
            ($rowBottom -gt 0)
        Assert-That "and the line starts BELOW all of them (top=$($p2.IndBox[1]) vs $rowBottom)" `
            ($p2.IndBox[1] -ge $rowBottom)
        Assert-That "it is flush with the row's left edge (left=$($p2.IndBox[0]) vs $($rects.RowLeft))" `
            ($p2.IndBox[0] -eq $rects.RowLeft)
        # The engine's string draw refuses OUTRIGHT when the box is shorter than the font
        # (research/status-pane-text.md § 5), so the band's height is checked against the
        # font's own, read live.
        $boxH = $p2.IndBox[3] - $p2.IndBox[1]
        $boxW = $p2.IndBox[2] - $p2.IndBox[0]
        Assert-That "the band is at least as tall as the font ($boxH >= $($p2.FontH))" `
            ($boxH -ge $p2.FontH -and $p2.FontH -gt 0)
        # A box too NARROW does not fail loudly, it draws a TRUNCATION -- which reads as a
        # working feature and is worse than nothing. 5 px/char is a conservative floor.
        $need = $p2.Indicator.Length * 5
        Assert-That "and wide enough to draw the whole line ($boxW px for $need)" ($boxW -ge $need)
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

        # The indicator box sits in the band BELOW the row, where no control repaints it (a
        # box over the first buttons would be repainted whenever they redraw), so the module
        # asks for its own rect to be repainted on hand-back (updateControl on the hidden
        # control). This measures that ask instead of arguing it: `stranded` counts the bytes
        # our line owns that STILL hold its value once the row is back to stock, 0 is the
        # pass; `glyphBytes` travels with it because stranded=0 over an EMPTY mask is a probe
        # that never saw the line, not a clean band.
        $band = Get-HudBand -FromLine $mark
        if ($null -eq $band) {
            Assert-That ('the plugin reported the band after the hand-back ' +
                         '(a build without this reading cannot answer criterion 4)') $false
        } else {
            Write-Host "       $($band.Line)"
            Assert-That "the probe could still read the surface (surfInk=$($band.SurfInk))" `
                ($band.SurfInk -gt 0)
            Assert-That ("the line had actually been on the band, so there is something to " +
                         "check ($($band.Glyph) bytes)") ($band.Glyph -gt 0)
            Assert-That ("and leaving paged mode stranded NONE of them " +
                         "(stranded=$($band.Stranded) of $($band.Glyph))") ($band.Stranded -eq 0)
        }
    }

    # Unit death and removal (transport load, mind control, archon merge) are not exercised
    # here: the fixture has no combat and no transports (one unit-less computer slot, no
    # enemy, no triggers -- what keeps the map from ending itself; see test-burrow-fanout.ps1),
    # and producing them unattended would need an attacker/transport and a reliable wait.
    # They are covered OFFLINE in hooktest part [10]: damage death (HP->0, uniqueness
    # UNCHANGED), slot reuse, persistent engine-side divergence (hand back to stock, no
    # churn, heal on the next commit), and the CLICK GATE swallowing a click on a
    # removed-not-killed overflow unit before it reaches the engine's Select.
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
        Remove-ScOwnFixture -Run $fixtures
        # And take the FOLDER away too when it is empty. An abandoned empty folder still
        # pushes every entry below it down a row, and only six rows are visible.
        # Remove-ScOwnFixtureDir refuses if anything at all is still in it.
        Remove-ScOwnFixtureDir -Dir $mapDir
    }
}

Write-Host ''
Write-Host '[final] the run must balance'
$left = if ($gamePid -gt 0) { Get-Process -Id $gamePid -ErrorAction SilentlyContinue } else { $null }
Assert-That 'the game process this test started is gone' ($KeepOpen -or $null -eq $left)
# This test's own fixture, not the folder: the folder is shared with other workers
# (AGENTS.md § Shared test-fixture folder).
Assert-That 'the generated map was cleaned up' ($KeepOpen -or -not (Test-Path -LiteralPath $mapPath))

$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "  StarCraft.exe SHA-256 after:  $hashAfter"
Assert-That 'StarCraft.exe on disk is byte-identical to before the run' ($hashAfter -eq $hashBefore)
Assert-That 'and still byte-identical to pristine 1.16.1' ($hashAfter -eq $PRISTINE_SHA256)

# COVERAGE, printed beside the verdict on every run (AGENTS.md § A random suite must report
# the coverage of its SEAM). The ONE state this suite exists to reach is the row PAGING a
# >12 selection: nothing above says anything about the indicator unless the run got there,
# and a run that never did looks exactly like a clean pass. Counted and printed, not inferred.
Write-Host ''
Write-Host '[coverage] the seam this suite exists to reach'
$logLines = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue)
$showLines = @($logLines | Select-String -Pattern 'HUDROW show n=\d+ page=').Count
$statsLine = @($logLines | Select-String -Pattern 'HUDROW stats: ') | Select-Object -Last 1
$episodes = -1
if ($statsLine) {
    Write-Host "  $($statsLine.Line)"
    $sm = [regex]::Match($statsLine.Line, 'pagedEpisodes=(\d+)')
    if ($sm.Success) { $episodes = [int]$sm.Groups[1].Value }
}
Write-Host "  paged layouts logged: $showLines"
if ($episodes -ge 0) { Write-Host "  paged episodes (entries into the >12 state): $episodes" }
else { Write-Host '  paged episodes (entries into the >12 state): NOT REPORTED by this build (pre-task-048 plugin)' }
if ($showLines -eq 0 -and $episodes -le 0) {
    Write-Host 'COVERAGE  NO frame reached the >12 PAGED state. A run that never pages CANNOT'
    Write-Host '          detect anything about the page indicator, whatever its verdict says.'
    $failures++
} else {
    Write-Host "COVERAGE  the row paged a >12 selection ($showLines layouts logged), so the"
    Write-Host '          indicator assertions above were actually exercised.'
}

Write-Host ''
Write-Host "test-hud-row: $failures failure(s)"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
