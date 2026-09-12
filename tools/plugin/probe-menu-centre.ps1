#Requires -Version 7
<#
.SYNOPSIS
The centred menus and their night sky (sc_menu.h), off-screen, through the deployed
presenter (cnc-ddraw), against a control arm.

.DESCRIPTION
Two arms at one preset, each walking from the main menu into a one-marine game:
  centred  -MenuCentre 1. The engine's own MainMenu and popup records must read centred;
           the walk clicks every control by NAME at the centre the engine reports, so it
           reaching a game proves input follows the move; the sky must reach the glass
           outside the menu; the console must still move in game.
  control  -MenuCentre 0. Stock placement, measured the same way: its black surround and
           its cursor that vanishes outside the menu are what the centred arm beats.
Frames go to -FrameDir (gitignored) and are corroboration, never the verdict
(AGENTS.md § "Screenshots").

.EXAMPLE
$env:AGENT_TASK = '901'; ./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-menu-centre.ps1 -SuiteArgs @{ Geometry = '1536x864' }
#>
[CmdletBinding()]
param(
    [string]$Geometry = '1280x880',
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogDir = 'C:\sc-work\logs',
    [string]$FixtureDir,
    [string]$FrameDir,
    [string]$CncDdrawDll = 'C:\sc-work\cnc-ddraw\v7.1.0.0\ddraw.dll',
    [switch]$CentredOnly
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
foreach ($lib in 'drive-game.ps1', 'sc-launch-lock.ps1', 'sc-wsprobe.ps1') { . (Join-Path $scriptDir $lib) }
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path

$env:SCPLUGIN_WS_GEOMETRY = $Geometry
$geo = Get-ScWideGeometry
$DX = [int](($geo.W - $geo.StockW) / 2)
$DY = [int](($geo.H - $geo.StockH) / 2)
$task = if ($env:AGENT_TASK) { $env:AGENT_TASK } else { 'menu' }
if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-testmap' -Suite 'menu-centre' }
if (-not $FrameDir) { $FrameDir = "C:\sc-work\logs\$task-frames" }
$mapName = 'menu-centre.scx'
$mapPath = Join-Path $FixtureDir $mapName
$markerPath = Join-Path $LogDir 'marker.txt'
$tool = Join-Path $scriptDir 'frame-capture.py'
New-Item -ItemType Directory -Path $LogDir, $FrameDir -Force | Out-Null
$script:failures = $script:step = 0
$launchLock = $fixtures = $null
$arms = [ordered]@{}

function Get-Kv([string[]]$Lines, [string]$Key) {
    $m = @($Lines | Where-Object { $_ -match "^$Key=(.*)$" })
    if ($m.Count) { ($m[0] -replace "^$Key=", '') } else { $null }
}

# Captures come back through cnc-ddraw, which on the invisible desktop draws the frame a
# few percent larger than the client (art 640 px wide spans ~648 captured), so the glue
# rect is left out with a margin rather than to the pixel.
function Measure-Glass([string]$Png, [int]$HX0, [int]$HY0) {
    $hole = "$([Math]::Max(0, $HX0 - 24)),$([Math]::Max(0, $HY0 - 24)),$($HX0 + 640 + 40),$($HY0 + 480 + 40)"
    $out = @(& python $tool glass --png $Png --hole $hole 2>&1 | ForEach-Object { "$_" })
    [int](Get-Kv $out 'glass_lit')
}

function Measure-Box([string]$A, [string]$B, [int]$X, [int]$Y) {
    $out = @(& python $tool glassdiff --a $A --b $B --x0 ($X - 30) --y0 ($Y - 30) --x1 ($X + 60) --y1 ($Y + 70) 2>&1 | ForEach-Object { "$_" })
    [int](Get-Kv $out 'glassdiff_changed')
}

# The newest DIALOGS line naming a root, parsed by the shared reader.
function Get-RootRect([string]$LogPath, [string]$Name) {
    $d = @(Get-ScDialogs -LogPath $LogPath | Where-Object Name -eq $Name)
    if ($d.Count) { "$($d[0].Left),$($d[0].Top),$($d[0].Right),$($d[0].Bottom)" } else { $null }
}

# Click a control by name at the centre the engine reports, then require the next screen's
# control to appear. Re-clicks: off-screen, the first input after a screen change can be
# lost to the activation gate (AGENTS.md § "Glue-screen (menu) input under cnc-ddraw").
function Invoke-Step([IntPtr]$Hwnd, [string]$LogPath, [string]$Pattern, [string]$Expect) {
    foreach ($try in 1..3) {
        Invoke-ScDialogControl -Hwnd $Hwnd -LogPath $LogPath -Pattern $Pattern -TimeoutSec 15 | Out-Null
        if (Wait-ScDialogControl -LogPath $LogPath -Pattern $Expect -TimeoutSec 6) { return }
    }
    Show-ScDialogInventory -LogPath $LogPath -What "after '$Pattern'"
    throw "the screen with '$Expect' never followed a click on '$Pattern'"
}

function Invoke-Arm {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][bool]$Centre)
    $log = Join-Path $LogDir "$task-menu-$Name.log"
    foreach ($f in @($log, $markerPath)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
    $ox = $Centre ? $DX : 0
    $oy = $Centre ? $DY : 0
    $r = [ordered]@{ Name = $Name; Log = $log; Ox = $ox; Oy = $oy; MainMenu = $null; Popup = $null
                     Walked = $false; WalkError = $null; StarsLit = -1; CursorShown = -1; Frames = @() }
    $gamePid = 0
    Write-Host ''
    Write-Host "probe-menu-centre: ARM '$Name' (-MenuCentre $([int]$Centre), $Geometry, offset $ox,$oy)"
    try {
        & (Join-Path $scriptDir 'run-with-plugin.ps1') `
            -Mode fanout -Widescreen 1 -WidescreenStage 3 -Geometry $Geometry -StormPresent widen `
            -MenuCentre ($Centre ? '1' : '0') -Windowed -WindowedHelperDll $CncDdrawDll `
            -NoLaunchLock -GameDir $GameDir -LogPath $log 6>&1 | ForEach-Object {
                if ("$_" -match 'scinject:\s*PID=(\d+)') { $gamePid = [int]$Matches[1] }
            }
        if (-not $gamePid) { throw "no game pid for arm '$Name'" }
        $h = Get-ScGameWindow -ProcessId $gamePid
        if (-not (Wait-ScDialog -LogPath $log -Name '^MainMenu$' -TimeoutSec 60)) { throw 'the main menu never came up' }
        Start-Sleep -Seconds 2
        $r.MainMenu = Get-RootRect $log 'MainMenu'
        Write-Host "       MainMenu root reads ($($r.MainMenu))"

        # Glass at the menu: the cursor parked inside the menu, then at a point outside BOTH
        # layouts' menus. Stock draws the cursor only where a dialog is, so there it vanishes.
        $env:SCDRIVE_POST_ACTIVATE = '1'
        $outX = $geo.W - 180; $outY = $geo.H - 120
        Send-ScMouseMove -Hwnd $h -X ($ox + 320) -Y ($oy + 240)
        Start-Sleep -Milliseconds 800
        $inPng = Join-Path $FrameDir "menu-$Geometry-$Name-cursor-in.png"
        Save-ScWindowImage -Hwnd $h -Path $inPng | Out-Null
        Send-ScMouseMove -Hwnd $h -X $outX -Y $outY
        Start-Sleep -Milliseconds 800
        $outPng = Join-Path $FrameDir "menu-$Geometry-$Name-cursor-out.png"
        Save-ScWindowImage -Hwnd $h -Path $outPng | Out-Null
        $r.Frames += $inPng, $outPng
        $r.StarsLit = Measure-Glass $inPng $ox $oy
        $r.CursorShown = Measure-Box $inPng $outPng $outX $outY
        Write-Host "       glass: $($r.StarsLit) lit px outside the menu; $($r.CursorShown) px changed where the cursor was parked outside it"

        # The walk, by control NAME: every click lands where the engine says the control
        # is, so the same walk drives both layouts.
        Invoke-Step $h $log 'inglePlayer' 'xpansion'
        $r.Popup = Get-RootRect $log 'Delete'
        Start-Sleep -Milliseconds 800
        $popPng = Join-Path $FrameDir "menu-$Geometry-$Name-popup.png"
        Save-ScWindowImage -Hwnd $h -Path $popPng | Out-Null
        $r.Frames += $popPng
        Invoke-Step $h $log 'xpansion' 'Ok$'
        Invoke-Step $h $log 'Ok$' 'Custom'
        Invoke-Step $h $log 'Custom' 'ListMap'
        Assert-ScFixtureStillMine -Run $script:fixtures -MapPath $mapPath
        # The browser's own geometry is glue coordinates: shift it by this arm's origin.
        Set-ScGlueOrigin -X $ox -Y $oy
        try { Select-ScBrowserMap -Hwnd $h -GameDir $GameDir -MapPath $mapPath | Out-Null }
        finally { Set-ScGlueOrigin }
        Assert-ScGameType -LogPath $log
        Invoke-ScDialogControl -Hwnd $h -LogPath $log -Pattern 'Ok$' | Out-Null
        Start-Sleep -Seconds 4
        Show-ScDialogInventory -LogPath $log -What 'the lobby'
        Invoke-ScDialogControl -Hwnd $h -LogPath $log -Pattern 'Start$' -TimeoutSec 20 | Out-Null
        $env:SCDRIVE_POST_ACTIVATE = '0'
        if (-not (Wait-ScDialog -LogPath $log -Name '^StatBtn$' -TimeoutSec 40)) { throw 'the game never started (no StatBtn)' }
        Dismiss-ScTipsDialog -Hwnd $h -LogPath $log | Out-Null
        Start-Sleep -Seconds 3
        $r.Walked = $true
        $gamePng = Join-Path $FrameDir "menu-$Geometry-$Name-ingame.png"
        Save-ScWindowImage -Hwnd $h -Path $gamePng | Out-Null
        $r.Frames += $gamePng
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
    $launchLock = Enter-ScLaunchLock -TaskId "$task-menu-centre"
    $fixtures = New-ScFixtureRun -Dir $FixtureDir -Names @($mapName)
    $script:fixtures = $fixtures
    $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') -UnitCount 1 -UnitType 'marine' -Player 0 -Race 'terran' -OutputPath $mapPath 2>&1
    @($gen | Where-Object { "$_" -match '^\s*(OK|wrote)' }) | ForEach-Object { Write-Host "       $_" }

    $arms['centred'] = Invoke-Arm -Name 'centred' -Centre $true
    if (-not $CentredOnly) { $arms['control'] = Invoke-Arm -Name 'control' -Centre $false }

    Write-Host ''
    Write-Host "probe-menu-centre: assertions ($Geometry, centred offset $DX,$DY)"
    $c = $arms['centred']
    $cLog = @(Get-Content -LiteralPath $c.Log)
    Assert-True 'the plugin armed the centring' (@($cLog | Where-Object { $_ -match 'MENU: ON' }).Count -eq 1)
    Assert-True 'the engine''s MainMenu record reads centred' ($c.MainMenu -eq "$DX,$DY,$($DX + 639),$($DY + 479)") "(got $($c.MainMenu))"
    Assert-True 'the Single Player popup reads centred too' ($c.Popup -eq "$($DX + 140),$($DY + 140),$($DX + 499),$($DY + 339)") "(got $($c.Popup))"
    $moves = @($cLog | Where-Object { $_ -match '\] MENU moved ' }).Count
    Assert-True 'glue roots were moved on the way through the menus' ($moves -ge 6) "(moved $moves)"
    Assert-True 'the walk through centred menus reached a game (clicks follow the move)' $c.Walked "$($c.WalkError)"
    $consoleMoves = @($cLog | Where-Object { $_ -match '\] CONSOLE moved ' }).Count
    Assert-True 'the console still moves in game after centred menus' ($consoleMoves -ge 10) "(moved $consoleMoves)"
    $stats = @($cLog | Where-Object { $_ -match 'MENUSTATS ' })
    $ok = $stats.Count -eq 1 -and $stats[0] -match 'fills=(\d+) copies=(\d+) remaps=(\d+) lockFails=(\d+)' -and
          [int]$Matches[1] -ge 1 -and [int]$Matches[2] -ge 1 -and [int]$Matches[4] -eq 0
    Assert-True 'MENUSTATS: the buffer was filled and presented, no lock failed' $ok "($($stats | Select-Object -First 1))"
    # ~1100 of the 1280x880 field's 1531 lit cells lie outside the menu; the margin costs some.
    # Stars alone light ~1,000 px at 1280x880; the nebula lights hundreds of thousands.
    Assert-True 'the sky (nebula and stars) reached the glass outside the menu' ($c.StarsLit -gt 50000) "(lit $($c.StarsLit))"
    if ($arms['control']) {
        $k = $arms['control']
        Assert-True 'control: the MainMenu record reads stock (0,0)' ($k.MainMenu -eq '0,0,639,479') "(got $($k.MainMenu))"
        Assert-True 'control: the walk reached a game' $k.Walked "$($k.WalkError)"
        # The cursor number is reported, not asserted: off-screen, the activation nudge the menu
        # walk needs re-syncs the cursor (AGENTS.md § Foreground), so a posted park is unreliable.
        Write-Host ("  ---- glass outside the menu: centred {0} lit px vs control {1}; cursor parked outside: centred {2} px changed vs control {3}" -f
            $c.StarsLit, $k.StarsLit, $c.CursorShown, $k.CursorShown)
        Assert-True 'control: the surround is black' ($k.StarsLit -lt 50) "(lit $($k.StarsLit))"
    }
    Write-Host ''
    Write-Host 'probe-menu-centre: frames for a human (gitignored, never committed):'
    foreach ($a in $arms.Values) { $a.Frames | ForEach-Object { Write-Host "       $_" } }
}
catch {
    Write-Host "  FAIL probe: $($_.Exception.Message)"
    $script:failures++
}
finally {
    if ($fixtures) {
        try { Remove-ScOwnFixture -Run $fixtures | Out-Null } catch { Write-Host "  warn: $($_.Exception.Message)" }
        try { Remove-ScOwnFixtureDir -Dir $fixtures.Dir | Out-Null } catch { Write-Host "  warn: $($_.Exception.Message)" }
    }
    try { & (Join-Path $scriptDir 'run-with-plugin.ps1') -RemoveWindowed -NoLaunch -GameDir $GameDir -NoLaunchLock | Out-Null } catch { }
    if ($launchLock) { try { Exit-ScLaunchLock -Lock $launchLock } catch { } }
}
Write-Host ''
if ($script:failures -eq 0) { Write-Host 'probe-menu-centre: PASS' } else { Write-Host "probe-menu-centre: FAIL ($script:failures)" }
exit ($script:failures -gt 0 ? 1 : 0)
