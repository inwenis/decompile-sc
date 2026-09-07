#Requires -Version 7
<#
.SYNOPSIS
Decide, from a RUNNING GAME, which unit-settings section a Brood War map's engine reads --
and whether an overridden BUILD TIME actually reaches it.
.DESCRIPTION
UNIx as the carrier of per-map unit stats is inference: the Brood War template has no UNIS
section, and the CHK section-application table at .rdata 0x5004A8 lists UNIx UPGx TECx PUNI
PUPx PTEx with no UNIS entry (the same table gives the PTEx applier 0x004CB7D0, confirmed
independently against a running game, so the table means what it appears to). One map
therefore disagrees with itself -- units.dat gives a
Marine 40 hit points, UNIx 25, a UNIS decoy 12 appended LAST so UNIS keeps the file-order
advantage -- and hp at CUnit+0x08 names the winner. The map also cuts the SCV build time to
1 game second against vanilla's 20, timed by the SCV appearing in the engine's unit list.
.EXAMPLE
./tools/plugin/probe-unit-settings.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = $(if ($env:SC_TASK_GAMEDIR) { $env:SC_TASK_GAMEDIR } else { 'C:\sc-work\1161-base' }),
    [string]$LogPath = 'C:\sc-work\logs\031\unit-settings-probe.log',
    [string]$ShotDir = 'C:\sc-work\logs\031\probe-frames',
    [string]$FixtureDir,
    # FOUR, not twelve: a lone Command Center supplies 10 and every placed Marine eats 1,
    # so a dozen Marines put the player over the cap before the probe presses anything.
    # Four leave six supply for the SCV this probe trains and still show agreement on hp.
    [int]$UnitCount = 4,
    [int]$UnixMarineHp = 25,
    [int]$UnisMarineHp = 12,
    [int]$VanillaMarineHp = 40,
    [int]$ScvBuildSeconds = 1,
    # Vanilla SCV build time, from the template's own UNIx entry: 300 = 20 game seconds.
    [int]$VanillaScvBuildSeconds = 20,
    [int]$BuildTimeoutSec = 60,
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

. (Join-Path $scriptDir 'sc-suite.ps1')

$failures = 0
$step = 0

$MARINE_TYPE = 0
$CC_TYPE     = 106
$SCV_TYPE    = 7
$TRAIN_KEY   = 0x53      # 'S' -- the Command Center card's Train SCV hotkey

if (-not $FixtureDir) { $FixtureDir = Resolve-ScFixtureDir -GameDir $GameDir -Fallback '00-t031' -Suite 'unit-settings' }
$mapName = 'unit-settings-probe.scx'
$mapPath = Join-Path $FixtureDir $mapName
$fixtures = New-ScFixtureRun -Dir $FixtureDir -Names @($mapName)

$markerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt'
function Get-World { param([string]$Tag, [int]$TimeoutSec = 20)
    Get-ScWorldState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath -TimeoutSec $TimeoutSec }

$exePath = Join-Path $GameDir 'StarCraft.exe'
$hashBefore = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host "[0] StarCraft.exe SHA-256 before: $hashBefore"

if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }
New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null

$gamePid = 0
$hwnd = [IntPtr]::Zero
$launchLock = $null

try {
    Step "generate the probe map: $UnitCount Marines (UNIx $UnixMarineHp hp) + a Command Center (SCV build ${ScvBuildSeconds}s)" {
        Wait-ScFixtureFolderFree -Run $fixtures
        if ($UnixMarineHp -eq $UnisMarineHp -or $UnixMarineHp -eq $VanillaMarineHp -or
            $UnisMarineHp -eq $VanillaMarineHp) {
            throw "probe: the three candidate hit-point values must all differ, or the read cannot discriminate."
        }
        $py = Join-Path $repoRoot '.venv/Scripts/python.exe'
        if (-not (Test-Path -LiteralPath $py)) { $py = 'python' }
        # --enemy-owner player is the generator's way to put a SECOND block of a DIFFERENT
        # type on the human's own slot: one map carries both the units to read and the
        # building to train from.
        $gen = & $py (Join-Path $repoRoot 'tools/make_test_map.py') `
            --unit-count $UnitCount --unit-type marine --player 0 --clear-player-units `
            --grid-spacing 48 --enemy-count 1 --enemy-type command-center --enemy-owner player `
            --starting-minerals 3000 `
            --unit-max-hp "marine=$UnixMarineHp" --unit-build-time "scv=$ScvBuildSeconds" `
            --output $mapPath 2>&1
        $gen | Where-Object { $_ -notmatch 'StormLibFinder' } | ForEach-Object { Write-Host "       $_" }
        # These read the generator's own report, so they prove intent only -- a tool that
        # verifies its own write with its own indexing verifies nothing -- which is why the
        # verdict is taken from the engine's memory (AGENTS.md § "Test fixtures").
        Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'it wrote UNIx and nothing it was not asked to' `
            (@($gen | Select-String -Pattern 'differs from the template ONLY in: OWNR SIDE UNIT TRIG FORC UNIx').Count -gt 0)

        $decoy = & $py (Join-Path $repoRoot 'tools/add_unis_decoy.py') `
            --map $mapPath --unit marine --max-hp $UnisMarineHp 2>&1
        $decoy | Where-Object { $_ -notmatch 'StormLibFinder' } | ForEach-Object { Write-Host "       $_" }
        Assert-That 'the UNIS decoy was appended' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
        Assert-That 'and it is the LAST chunk, so UNIS has the file-order advantage' `
            (@($decoy | Select-String -Pattern 'as the LAST chunk').Count -gt 0)
    }

    Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '031-unit-settings-probe'
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode hooktest -LogCommands 1 -Circles 0 -HudRow 0 -WorldScan 1 `
        -InjectWindowedHelper WMode -NoLaunchLock `
        -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
            Write-Host $_
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'probe: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

    Step "menus: Single Player -> Expansion -> Play Custom -> $mapName" {
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 215 -Y 119
        Send-ScClick -Hwnd $hwnd -X 373 -Y 300
        Start-Sleep -Seconds 1
        Send-ScClick -Hwnd $hwnd -X 75  -Y 111
        Send-ScClick -Hwnd $hwnd -X 516 -Y 392
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 327 -Y 415
        Start-Sleep -Seconds 2
        Assert-ScFixtureStillMine -Run $fixtures -MapPath $mapPath
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null
        Set-ScGameType -Hwnd $hwnd -LogPath $logPath -Index 2      # Use Map Settings, verified
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387
        Start-Sleep -Seconds 10
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
    }

    Step 'THE DISCRIMINATOR: read a Marine hit points out of the running game' {
        $w = Get-World 'settings'
        $marines = @($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $MARINE_TYPE })
        Assert-That "the map spawned $UnitCount Marines ($($marines.Count))" ($marines.Count -eq $UnitCount)
        Assert-That 'the world scan was not taken mid-edit' `
            ($w.Counts[0].Units -eq $w.Counts[0].Recount -and $w.Counts[0].Complete -eq 1)

        # hp is CURRENT hit points; these Marines are placed at 100%, so the read is the
        # maximum, and it is taken before any order is given.
        $hpValues = @($marines | ForEach-Object { $_.Hp } | Sort-Object -Unique)
        Write-Host "       hp values seen: $($hpValues -join ', ') (CUnit+0x08 is hp x 256)"
        Assert-That 'every Marine agrees on its hit points' ($hpValues.Count -eq 1) `
            "(got $($hpValues -join ','))"

        $got = if ($hpValues.Count -ge 1) { [int]$hpValues[0] } else { -1 }
        $verdict =
            if     ($got -eq $UnixMarineHp * 256)    { 'UNIx' }
            elseif ($got -eq $UnisMarineHp * 256)    { 'UNIS' }
            elseif ($got -eq $VanillaMarineHp * 256) { 'NEITHER (units.dat)' }
            else                                     { "UNRECOGNISED ($got)" }
        Write-Host ''
        Write-Host "       VERDICT: the engine applied $verdict"
        Write-Host ("       UNIx said {0} (hp {1}) | UNIS said {2} (hp {3}) | units.dat says {4} (hp {5})" -f `
            $UnixMarineHp, ($UnixMarineHp * 256), $UnisMarineHp, ($UnisMarineHp * 256),
            $VanillaMarineHp, ($VanillaMarineHp * 256))
        Write-Host ''
        # The UNIx claim is asserted rather than reported, so the probe FAILS when the
        # engine stops agreeing -- a probe that only prints cannot regress.
        Assert-That "the engine read UNIx: a Marine has $UnixMarineHp hit points, not $VanillaMarineHp and not $UnisMarineHp" `
            ($got -eq $UnixMarineHp * 256) "(hp=$got)"
        # THE NEGATIVE HALF, stated separately so a pass cannot be read as vacuous: the
        # decoy is in the file, it is the last chunk, and the engine still ignored it.
        Assert-That 'and it ignored the UNIS decoy despite the decoy being the LAST chunk in the file' `
            ($got -ne $UnisMarineHp * 256)
    }

    Step "BUILD TIME: one Train press, and the SCV appears in ${ScvBuildSeconds}s rather than $VanillaScvBuildSeconds" {
        $w = Get-World 'aim'
        $cc = @($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $CC_TYPE })[0]
        Assert-That 'the Command Center is in the game' ($null -ne $cc)
        $scvsBefore = @($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $SCV_TYPE }).Count
        # The NEGATIVE half of the pair: no SCV exists before the press, so the one below
        # is attributable to it.
        Assert-That "no SCV exists yet ($scvsBefore)" ($scvsBefore -eq 0)
        # SUPPLY HEADROOM, asserted rather than assumed. A Command Center supplies 10 and
        # each placed Marine eats 1; over the cap, the Train command still reaches the wire
        # and the unit simply never appears, which is indistinguishable from a build-time
        # override that did not take.
        $mine = @($w.Units | Where-Object { $_.Player -eq 0 })
        Assert-That "the placed units leave supply headroom for an SCV ($($mine.Count - 1) of 10 used)" `
            (($mine.Count - 1) -lt 10) '(a lone Command Center supplies 10)'

        # Click point derived from memory, never off a frame
        # (AGENTS.md § "Oracles: what counts as a read-back").
        $cx = $cc.X - $w.Screen.Left
        $cy = $cc.Y - $w.Screen.Top
        Write-Host "       CC at map ($($cc.X),$($cc.Y)), viewport ($($w.Screen.Left),$($w.Screen.Top)) -> client ($cx,$cy)"
        if ($cx -lt 0 -or $cx -ge 640 -or $cy -lt 0 -or $cy -ge 340) {
            # The Command Center sits +448px east of the start location, which is off the
            # opening viewport. Scroll to it with the minimap rather than guessing.
            Write-Host '       CC is off the opening viewport; centring the view on it via the minimap'
            # The fixture keeps the template's terrain: 128x96 tiles. Map pixels -> tiles is /32.
            $mm = Get-ScMinimapPoint -MapTilesW 128 -MapTilesH 96 `
                -TileX ([int]($cc.X / 32)) -TileY ([int]($cc.Y / 32))
            Send-ScClick -Hwnd $hwnd -X $mm.X -Y $mm.Y
            Start-Sleep -Seconds 2
            $w = Get-World 'aim2'
            $cc = @($w.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $CC_TYPE })[0]
            $cx = $cc.X - $w.Screen.Left
            $cy = $cc.Y - $w.Screen.Top
            Write-Host "       after scrolling -> client ($cx,$cy)"
        }
        Assert-That "the Command Center is on screen, inside the play area ($cx,$cy)" `
            ($cx -ge 0 -and $cx -lt 640 -and $cy -ge 0 -and $cy -lt 340)
        Send-ScClick -Hwnd $hwnd -X $cx -Y $cy
        Start-Sleep -Seconds 2

        $t0 = Get-Date
        Send-ScKey -Hwnd $hwnd -VirtualKey $TRAIN_KEY
        $elapsed = -1.0
        $deadline = $t0.AddSeconds($BuildTimeoutSec)
        while ((Get-Date) -lt $deadline) {
            $s = Get-World 'built'
            $scvs = @($s.Units | Where-Object { $_.Player -eq 0 -and $_.Type -eq $SCV_TYPE })
            if ($scvs.Count -gt 0) { $elapsed = ((Get-Date) - $t0).TotalSeconds; break }
        }
        Write-Host ("       first SCV existed {0:n1}s after the keypress" -f $elapsed)
        Assert-That 'an SCV was produced at all' ($elapsed -ge 0)
        # The bound is deliberately loose: what is proved is that the override REACHED THE
        # ENGINE. Vanilla's 20 game seconds measure 14.4 real seconds in this repo's
        # production suite, so under 8 seconds cannot be the vanilla build time however the
        # marker round trip and the poll interval fall.
        if ($elapsed -ge 0) {
            Assert-That "and in under 8s, which vanilla's $VanillaScvBuildSeconds game seconds (~14.4s real) cannot do" `
                ($elapsed -lt 8.0) ("(took {0:n1}s)" -f $elapsed)
        }
    }
}
catch { Write-ScStepFailure $_ 'a probe step' }
finally {
    if (-not $KeepOpen -and $gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch { Write-Host "  FAIL close-game: $($_.Exception.Message)"; $failures++ }
        Start-Sleep -Seconds 2
    }
    if (-not $KeepOpen) { Remove-ScOwnFixture -Run $fixtures }
    Remove-ScOwnFixtureDir -Dir $FixtureDir
    if ($launchLock) { Exit-ScLaunchLock -Lock $launchLock; $launchLock = $null }
}

$hashAfter = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Assert-That 'StarCraft.exe on disk is byte-identical to before the probe' ($hashAfter -eq $hashBefore)

Write-Host ''
Write-Host "probe-unit-settings: $failures failure(s)"
exit ($failures -eq 0 ? 0 : 1)
