#Requires -Version 7
<#
.SYNOPSIS
What the widescreen probes share: the numbered assert and the finding line, the
log/frame directories and counters, the stage-3 cnc-ddraw launch, the menu walk
into a loaded game, the tagged buffer dump with its camera, and the close-down.

.DESCRIPTION
Dot-sourced, like sc-suite.ps1, so `$script:failures`, `$script:step` and
`$script:findings` are the CALLING probe's own. Every function that drives the
game takes the window, the log and the fixture as parameters rather than reading
the caller's variables by name.

.EXAMPLE
. (Join-Path $PSScriptRoot 'sc-wsprobe.ps1')
#>

# One numbered assertion line; the detail prints on both outcomes so a passing
# run still shows the numbers it was judged on.
function Assert-True {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    $script:step++
    if ($Ok) { Write-Host "  [$script:step] OK   $What $Detail" }
    else { Write-Host "  [$script:step] FAIL $What $Detail"; $script:failures++ }
}

function Report-Finding {
    param([string]$What)
    $script:findings += $What
    Write-Host "  ---- FINDING: $What"
}

# Directories, the three counters and the four handles every probe starts from.
function Initialize-ScWsProbe {
    param([Parameter(Mandatory)][string]$LogDir, [Parameter(Mandatory)][string]$FrameDir)
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    New-Item -ItemType Directory -Path $FrameDir -Force | Out-Null
    $script:failures = 0
    $script:step = 0
    $script:findings = @()
    $script:launchLock = $null
    $script:fixtures = $null
    $script:gamePid = 0
    $script:completed = $false
}

# The one-Nexus fixture: an explored start with black map beyond its sight.
function New-ScNexusFixture {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$FixtureDir,
          [Parameter(Mandatory)][string]$MapName, [string]$Noun = 'probe')
    $run = New-ScFixtureRun -Dir $FixtureDir -Names @($MapName)
    $mapPath = Join-Path $FixtureDir $MapName
    $gen = & (Join-Path $RepoRoot 'tools/make-test-map.ps1') `
        -UnitCount 1 -UnitType 'nexus' -Player 0 -ClearPlayerUnits -Race 'protoss' `
        -StartingMinerals 500 -StartingGas 0 -OutputPath $mapPath 2>&1
    @($gen | Where-Object { "$_" -notmatch 'WARNING:StormLibFinder' }) | ForEach-Object { Write-Host "       $_" }
    if (-not (Test-Path -LiteralPath $mapPath)) { throw "${Noun}: the fixture was never generated." }
    $run
}

# The window of a launched game, once the table is live: asserts the table
# applied with nothing refused and that cnc-ddraw presents the full client area.
function Connect-ScWideGame {
    param([Parameter(Mandatory)][int]$GamePid, [Parameter(Mandatory)][string]$LogPath,
          [Parameter(Mandatory)][int]$ScreenW, [Parameter(Mandatory)][int]$ScreenH)
    $h = Get-ScGameWindow -ProcessId $GamePid
    Start-Sleep -Seconds 3
    Assert-True 'the widescreen table is ACTIVE with 0 refused' `
        (@(Get-Content -LiteralPath $LogPath | Where-Object { $_ -match 'WIDESCREEN ACTIVE' -and $_ -match ', 0 refused' }).Count -gt 0)
    $client = Get-ScClientSize -Hwnd $h
    Assert-True "cnc-ddraw presents a ${ScreenW}x${ScreenH} client area" ($client.Width -eq $ScreenW -and $client.Height -eq $ScreenH) "(got $($client.Width)x$($client.Height))"
    $h
}

# A tagged buffer dump: the marker fires the plugin's FRAMEDUMP and its WORLD
# scan; the WORLD line's screen=(x,y) is the camera that dump was taken under.
function Get-ScBufferDump {
    param([Parameter(Mandatory)][string]$LogPath, [Parameter(Mandatory)][string]$MarkerPath,
          [Parameter(Mandatory)][string]$Tag, [int]$TimeoutSec = 20)
    $from = Get-ScLogLineCount -LogPath $LogPath
    Set-ScMarker -MarkerPath $MarkerPath -Label $Tag
    $lines = Wait-ScLogMatch -LogPath $LogPath -Pattern "FRAMEDUMP \[$([regex]::Escape($Tag))\] " -TimeoutSec $TimeoutSec -FromLine $from
    $path = $null
    foreach ($l in $lines) {
        if ($l -match 'FRAMEDUMP \[[^\]]+\] w=\d+ h=\d+ bytes=\d+ reads=\d+ stable=\d path=(.+)$') { $path = $Matches[1].Trim() }
    }
    $cam = $null
    $w = @(Get-Content -LiteralPath $LogPath | Select-Object -Skip $from |
           Where-Object { $_ -match "WORLD \[$([regex]::Escape($Tag))\] screen=\((-?\d+),(-?\d+)\)" }) | Select-Object -First 1
    if ($w -and $w -match 'screen=\((-?\d+),(-?\d+)\)') { $cam = [pscustomobject]@{ X = [int]$Matches[1]; Y = [int]$Matches[2] } }
    [pscustomobject]@{ Tag = $Tag; Path = $path; Cam = $cam }
}

function Click-UntilDialog {
    param([Parameter(Mandatory)][IntPtr]$Hwnd, [Parameter(Mandatory)][string]$LogPath,
          [int]$X, [int]$Y, [string]$Name, [int]$Tries = 3, [int]$WaitSec = 12)
    for ($i = 1; $i -le $Tries; $i++) {
        Send-ScClick -Hwnd $Hwnd -X $X -Y $Y
        $d = Wait-ScDialog -LogPath $LogPath -Name $Name -TimeoutSec $WaitSec
        if ($d) { return $d }
        Write-Host "       walk: '$Name' not up after click $i/$Tries at ($X,$Y); retrying"
    }
    $null
}

# Main menu -> Single Player -> Expansion -> a Use Map Settings game on the
# fixture -> Start -> tips dismissed. Throws with the caller's noun in front.
function Walk-ToScGame {
    param([Parameter(Mandatory)][IntPtr]$Hwnd, [Parameter(Mandatory)][string]$LogPath,
          [Parameter(Mandatory)]$Fixtures, [Parameter(Mandatory)][string]$MapPath,
          [Parameter(Mandatory)][string]$GameDir, [string]$Noun = 'probe')
    $env:SCDRIVE_POST_ACTIVATE = '1'
    try {
        if (-not (Wait-ScDialog -LogPath $LogPath -Name 'MainMenu' -TimeoutSec 30)) { throw "${Noun}: main menu never appeared." }
        Start-Sleep -Seconds 3
        if (-not (Click-UntilDialog -Hwnd $Hwnd -LogPath $LogPath -X 215 -Y 119 -Name 'Delete')) { throw "${Noun}: Original/Expansion chooser never appeared." }
        Send-ScClick -Hwnd $Hwnd -X 373 -Y 300; Start-Sleep -Seconds 1
        Send-ScClick -Hwnd $Hwnd -X 75 -Y 111
        if (-not (Click-UntilDialog -Hwnd $Hwnd -LogPath $LogPath -X 516 -Y 392 -Name 'RaceSelection' -WaitSec 15)) { throw "${Noun}: RaceSelection never appeared." }
        if (-not (Click-UntilDialog -Hwnd $Hwnd -LogPath $LogPath -X 327 -Y 415 -Name 'Create' -WaitSec 15)) { throw "${Noun}: map browser never appeared." }
        Start-Sleep -Seconds 2
        Assert-ScFixtureStillMine -Run $Fixtures -MapPath $MapPath
        Select-ScBrowserMap -Hwnd $Hwnd -GameDir $GameDir -MapPath $MapPath | Out-Null
        Set-ScGameType -Hwnd $Hwnd -LogPath $LogPath -Index 2
        Send-ScClick -Hwnd $Hwnd -X 516 -Y 393; Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $Hwnd -X 544 -Y 387; Start-Sleep -Seconds 10
        Dismiss-ScTipsDialog -Hwnd $Hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 3
    } finally {
        $env:SCDRIVE_POST_ACTIVATE = '0'
    }
}

# The stage-3 cnc-ddraw launch with the frame dump armed. Returns the game pid.
function Start-ScWideGame {
    param([Parameter(Mandatory)][string]$ScriptDir, [Parameter(Mandatory)][string]$GameDir,
          [Parameter(Mandatory)][string]$LogPath, [Parameter(Mandatory)][string]$FrameDir,
          [Parameter(Mandatory)][string]$WindowedHelperDll, [string]$StormPresent = 'widen',
          [string]$Noun = 'probe')
    if (-not (Test-Path -LiteralPath $WindowedHelperDll)) { throw "${Noun}: $WindowedHelperDll not found; run fetch-cnc-ddraw.ps1." }
    $gamePid = 0
    & (Join-Path $ScriptDir 'run-with-plugin.ps1') `
        -Mode hooktest -LogCommands 1 -WorldScan 1 -NoLaunchLock `
        -Widescreen 1 -WidescreenStage 3 -StormPresent $StormPresent `
        -FrameDump $FrameDir `
        -Windowed -WindowedHelperDll $WindowedHelperDll `
        -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host "       $_"
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw "${Noun}: could not parse the game pid." }
    $gamePid
}

# The close-down every probe ends with: the game, the windowed helper, the
# fixture, the launch lock -- each step reported, none of them fatal.
# -NoLaunchLock on the -RemoveWindowed call is REQUIRED: the probe still holds
# the launch lock, and run-with-plugin takes the same lock to mutate the shared
# game dir -- without the flag this waits on its own lock for the lock's whole
# five-minute timeout.
function Stop-ScWideGame {
    param([Parameter(Mandatory)][string]$ScriptDir, [Parameter(Mandatory)][string]$GameDir,
          [int]$GamePid = 0, [switch]$KeepOpen, $Fixtures = $null, $LaunchLock = $null)
    Remove-Item Env:SCDRIVE_POST_ACTIVATE -ErrorAction SilentlyContinue
    if (-not $KeepOpen -and $GamePid -gt 0) {
        try { & (Join-Path $ScriptDir 'close-game.ps1') -ProcessId $GamePid | Write-Host }
        catch { Write-Host "  warn close-game: $($_.Exception.Message)" }
        Start-Sleep -Seconds 2
    }
    try { & (Join-Path $ScriptDir 'run-with-plugin.ps1') -RemoveWindowed -NoLaunch -NoLaunchLock -GameDir $GameDir | Write-Host }
    catch { Write-Host "  warn RemoveWindowed: $($_.Exception.Message)" }
    if ($Fixtures) {
        try { Remove-ScOwnFixture -Run $Fixtures | Out-Null } catch { Write-Host "  warn fixture: $($_.Exception.Message)" }
        try { Remove-ScOwnFixtureDir -Dir $Fixtures.Dir | Out-Null } catch { Write-Host "  warn fixture: $($_.Exception.Message)" }
    }
    if ($LaunchLock) { Exit-ScLaunchLock -Lock $LaunchLock }
}
