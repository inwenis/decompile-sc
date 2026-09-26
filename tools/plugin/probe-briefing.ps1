#Requires -Version 7
<#
.SYNOPSIS
The mission briefing (ready room) under the centred menus, off-screen through cnc-ddraw at
the deployed geometry: a briefing plays while the window is captured every -SampleMs, then
Start. -Arms fresh launches, because the screen is reported to vanish only sometimes.

.DESCRIPTION
Per sample: the engine's own dialog list (is the ready-room root still listed, and where)
beside the lit pixels of the capture inside the centred glue rect (frame-capture.py glass,
region = the rect shrunk by a margin for cnc-ddraw's stretch). A sample with the root
listed and the rect dark is the report's "it disappears"; the frame is beside it for a
human. The map is a generated fixture whose briefing shows a talking Marine over the map's
name and description, or -StockMap for a stock map with a real briefing (portraits, WAVs).
Frames go to -FrameDir (gitignored) and are corroboration, never the verdict
(AGENTS.md § "Screenshots").

.EXAMPLE
$env:AGENT_TASK = '212'; ./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-briefing.ps1 -SuiteArgs @{ Arms = 3 }
.EXAMPLE
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-briefing.ps1 -SuiteArgs @{ StockMap = 'C:\decompile-sc-data\sc-work\1161-base\Maps\campaign\(1)Enslavers01.scm'; MenuCentre = '0' }
#>
[CmdletBinding()]
param(
    [string]$Geometry = '1280x880',
    [string]$GameDir = 'C:\decompile-sc-data\sc-work\1161-base',
    [string]$LogDir = 'C:\decompile-sc-data\sc-work\logs',
    [string]$BuildDir,
    [string]$FixtureDir,
    [string]$FrameDir,
    [string]$CncDdrawDll = 'C:\decompile-sc-data\sc-work\cnc-ddraw\v7.1.0.0\ddraw.dll',
    # A stock map with a real briefing instead of the generated fixture.
    [string]$StockMap,
    # Bisect knobs, each the deployed launcher's value by default.
    [string]$Mode = 'fanout',
    [string]$MenuCentre = '1',
    [string]$Widescreen = '1',
    # 'cnc' = cnc-ddraw (the deployed presenter), 'wmode' = the WMode shim.
    [ValidateSet('cnc', 'wmode')]
    [string]$Presenter = 'cnc',
    [int]$Arms = 2,
    [int]$BriefSec = 18,
    [int]$SampleMs = 250,
    # Below this fraction of the rect lit, a sample counts as dark (a settled ready room
    # measures well above a half).
    [double]$DarkFrac = 0.10
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
foreach ($lib in 'drive-game.ps1', 'sc-launch-lock.ps1', 'sc-suite.ps1', 'sc-wsprobe.ps1') { . (Join-Path $scriptDir $lib) }
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path

$env:SCPLUGIN_WS_GEOMETRY = $Geometry
$geo = Get-ScWideGeometry
# The glue rect is centred only with both the widescreen and the centring on; otherwise
# every screen sits at (0,0) and the browser's glue coordinates need no shift.
$centred = ($Widescreen -eq '1' -and $MenuCentre -eq '1' -and $Mode -ne 'observe')
$DX = $centred ? [int](($geo.W - $geo.StockW) / 2) : 0
$DY = $centred ? [int](($geo.H - $geo.StockH) / 2) : 0
$task = if ($env:AGENT_TASK) { $env:AGENT_TASK } else { 'brief' }
if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-testmap' -Suite 'briefing' }
if (-not $FrameDir) { $FrameDir = "C:\decompile-sc-data\sc-work\logs\$task-frames\briefing" }
$mapName = 'briefing.scx'
$mapPath = if ($StockMap) { $StockMap } else { Join-Path $FixtureDir $mapName }
$markerPath = Join-Path $LogDir 'marker.txt'
$tool = Join-Path $scriptDir 'frame-capture.py'
$briefingRoot = '^(\w+RR|Ready\w*)$'
New-Item -ItemType Directory -Path $LogDir, $FrameDir -Force | Out-Null
$script:failures = $script:step = 0
$launchLock = $fixtures = $null

# Lit fraction of the capture inside the glue rect, 24 px in from every edge.
function Measure-Inside([string]$Png) {
    $out = @(& python $tool glass --png $Png --x0 ($DX + 24) --y0 ($DY + 24) --x1 ($DX + 640 - 24) --y1 ($DY + 480 - 24) 2>&1 | ForEach-Object { "$_" })
    [double](Get-ScToolValue $out 'glass_lit_frac')
}

function Invoke-Arm {
    param([Parameter(Mandatory)][int]$Index)
    $log = Join-Path $LogDir "$task-briefing-$(Split-Path $FrameDir -Leaf)-$Index.log"
    foreach ($f in @($log, $markerPath)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
    $armDir = Join-Path $FrameDir "arm$Index"
    New-Item -ItemType Directory -Path $armDir -Force | Out-Null
    $r = [ordered]@{ Index = $Index; Log = $log; Samples = @(); Root = $null; Walked = $false; WalkError = $null
                     Dark = 0; Unlisted = 0; MinLit = -1; MaxLit = -1; FirstDark = $null }
    $gamePid = 0
    Write-Host ''
    Write-Host "probe-briefing: ARM $Index ($Geometry, offset $DX,$DY, -Mode $Mode -MenuCentre $MenuCentre -Widescreen $Widescreen, $BriefSec s of briefing at $SampleMs ms)"
    try {
        $launch = @{ Mode = $Mode; Widescreen = $Widescreen; WidescreenStage = 3; Geometry = $Geometry; StormPresent = 'widen'
                     MenuCentre = $MenuCentre; NoLaunchLock = $true; GameDir = $GameDir; LogPath = $log }
        if ($Presenter -eq 'cnc') { $launch.Windowed = $true; $launch.WindowedHelperDll = $CncDdrawDll }
        else { $launch.InjectWindowedHelper = 'WMode' }
        if ($BuildDir) { $launch.BuildDir = $BuildDir }
        & (Join-Path $scriptDir 'run-with-plugin.ps1') @launch 6>&1 | ForEach-Object {
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $gamePid = [int]$Matches[1] }
        }
        if (-not $gamePid) { throw "no game pid for arm $Index" }
        $h = Get-ScGameWindow -ProcessId $gamePid
        if (-not (Wait-ScDialog -LogPath $log -Name '^MainMenu$' -TimeoutSec 60)) { throw 'the main menu never came up' }
        Start-Sleep -Seconds 2
        $env:SCDRIVE_POST_ACTIVATE = '1'
        Invoke-ScDialogStep $h $log 'inglePlayer' 'xpansion'
        Invoke-ScDialogStep $h $log 'xpansion' 'Ok$'
        Invoke-ScDialogStep $h $log 'Ok$' 'Custom'
        Invoke-ScDialogStep $h $log 'Custom' 'ListMap'
        if ($script:fixtures) { Assert-ScFixtureStillMine -Run $script:fixtures -MapPath $mapPath }
        Set-ScGlueOrigin -X $DX -Y $DY
        try { Select-ScBrowserMap -Hwnd $h -GameDir $GameDir -MapPath $mapPath | Out-Null }
        finally { Set-ScGlueOrigin }
        Assert-ScGameType -LogPath $log
        Invoke-ScDialogControl -Hwnd $h -LogPath $log -Pattern 'Ok$' | Out-Null
        if (-not (Wait-ScDialog -LogPath $log -Name $briefingRoot -TimeoutSec 40)) { throw 'the mission briefing never appeared' }
        $rr = @(Get-ScDialogs -LogPath $log | Where-Object { $_.Name -match $briefingRoot })[0]
        $r.Root = $rr.Name
        Write-Host "       briefing root '$($rr.Name)' listed at ($($rr.Left),$($rr.Top),$($rr.Right),$($rr.Bottom))"

        # THE MEASUREMENT: the window every -SampleMs while the briefing plays, each beside
        # the dialog list of the same moment.
        $t0 = Get-Date
        $n = 0
        while (((Get-Date) - $t0).TotalSeconds -lt $BriefSec) {
            $n++
            $png = Join-Path $armDir ('{0:d3}.png' -f $n)
            Save-ScWindowImage -Hwnd $h -Path $png | Out-Null
            $dl = @(Get-ScDialogs -LogPath $log)
            $root = @($dl | Where-Object { $_.Name -match $briefingRoot })
            $lit = Measure-Inside $png
            $s = [pscustomobject]@{ N = $n; T = [Math]::Round(((Get-Date) - $t0).TotalSeconds, 2); Lit = $lit
                                    Listed = ($root.Count -gt 0)
                                    Rect = $(if ($root.Count) { "$($root[0].Left),$($root[0].Top),$($root[0].Right),$($root[0].Bottom)" } else { '-' })
                                    Others = (@($dl | Where-Object { $_.Name -notmatch $briefingRoot } | ForEach-Object Name) -join '+')
                                    Png = $png }
            $r.Samples += $s
            if ($s.Lit -lt $DarkFrac) { $r.Dark++; if (-not $r.FirstDark) { $r.FirstDark = $s } }
            if (-not $s.Listed) { $r.Unlisted++ }
            if ($r.MinLit -lt 0 -or $s.Lit -lt $r.MinLit) { $r.MinLit = $s.Lit }
            if ($s.Lit -gt $r.MaxLit) { $r.MaxLit = $s.Lit }
            Start-Sleep -Milliseconds $SampleMs
        }
        $summary = @($r.Samples | ForEach-Object { '{0}s:{1:N2}{2}' -f $_.T, $_.Lit, ($(if ($_.Listed) { '' } else { '!' })) }) -join ' '
        Write-Host "       $n samples (t:lit, '!' = root not listed): $summary"

        Invoke-ScDialogControl -Hwnd $h -LogPath $log -Pattern 'Start$' -TimeoutSec 20 | Out-Null
        $env:SCDRIVE_POST_ACTIVATE = '0'
        if (-not (Wait-ScDialog -LogPath $log -Name '^StatBtn$' -TimeoutSec 60)) { throw 'the game never started after Start (no StatBtn)' }
        $r.Walked = $true
        Start-Sleep -Seconds 2
        $gamePng = Join-Path $armDir 'ingame.png'
        Save-ScWindowImage -Hwnd $h -Path $gamePng | Out-Null
    }
    catch {
        $r.WalkError = $_.Exception.Message
        Write-Host "       arm FAILED: $($r.WalkError)"
    }
    finally {
        $env:SCDRIVE_POST_ACTIVATE = '0'
        Set-ScGlueOrigin
        if ($gamePid) {
            try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Out-Null } catch { }
            Start-Sleep -Seconds 2
        }
    }
    [pscustomobject]$r
}

try {
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId "$task-briefing"
    if ($StockMap) {
        if (-not (Test-Path -LiteralPath $StockMap)) { throw "probe-briefing: -StockMap '$StockMap' does not exist" }
        Write-Host "       stock map: $StockMap"
    } else {
        $fixtures = New-ScFixtureRun -Dir $FixtureDir -Names @($mapName)
        $script:fixtures = $fixtures
        $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') -UnitCount 1 -UnitType 'marine' -Player 0 -ClearPlayerUnits `
            -Briefing -StartingMinerals 500 -OutputPath $mapPath 2>&1
        @($gen | Where-Object { "$_" -match '^\s*(OK|wrote|  TRIG)' }) | ForEach-Object { Write-Host "       $_" }
    }

    $results = @()
    foreach ($k in 1..$Arms) { $results += Invoke-Arm -Index $k }

    Write-Host ''
    Write-Host "probe-briefing: assertions ($Geometry, $Arms arm(s), dark = lit fraction under $DarkFrac)"
    foreach ($a in $results) {
        $tag = "arm $($a.Index)"
        Assert-True "$tag reached the briefing and then the game" $a.Walked "$($a.WalkError)"
        Assert-True "${tag}: the briefing root was listed at every sample ($($a.Unlisted) unlisted of $($a.Samples.Count))" ($a.Samples.Count -gt 0 -and $a.Unlisted -eq 0)
        Assert-True "${tag}: the ready room stayed lit inside the centred rect (min $($a.MinLit), max $($a.MaxLit), $($a.Dark) dark sample(s))" ($a.Samples.Count -gt 0 -and $a.Dark -eq 0)
        if ($a.FirstDark) { Write-Host "       first dark sample: t=$($a.FirstDark.T)s lit=$($a.FirstDark.Lit) listed=$($a.FirstDark.Listed) rect=$($a.FirstDark.Rect) others='$($a.FirstDark.Others)' frame=$($a.FirstDark.Png)" }
        $cLog = @(Get-Content -LiteralPath $a.Log -ErrorAction SilentlyContinue)
        $pal = @($cLog | Where-Object { $_ -match 'MENU palette' })
        if ($pal.Count) { Write-Host "       palette lines: $($pal.Count); last: $($pal[-1] -replace '^.*\] ', '')" }
        $stats = @($cLog | Where-Object { $_ -match 'MENUSTATS ' })
        if ($stats.Count) { Write-Host "       $($stats[-1] -replace '^.*\] ', '')" }
    }
}
catch { Write-ScStepFailure $_ 'the probe' }
finally {
    if ($fixtures) { Remove-ScOwnFixture -Run $fixtures; Remove-ScOwnFixtureDir -Dir $FixtureDir }
    if ($launchLock) { Exit-ScLaunchLock -Lock $launchLock }
}

Write-Host "`nprobe-briefing: $script:failures failure(s); frames under $FrameDir"
exit ($script:failures -gt 0 ? 1 : 0)
