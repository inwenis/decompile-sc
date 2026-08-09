#Requires -Version 7
<#
.SYNOPSIS
Name the Ghost's Personnel Cloaking button: sweep the command-card hotkeys and log which
wire command each one actually emits.

.DESCRIPTION
THE QUESTION, inherited from task 022. That task could not drive Cloak. It reported that
`C` emits nothing even at full energy, and that clicking the bottom-left command-card slot
produced a frame reading "Select Target" -- i.e. that slot is a TARGETED ability
(Lockdown), so the click armed something and issued nothing. The underlying mechanism was
answered without it, but the user's original report was about a CLOAKED GHOST
specifically, so the unit itself is still unanswered.

WHAT THIS MEASURES, and why a sweep rather than a guess. Every command the client sends
goes through queueCommand, which the plugin logs as `CMD id=0x.. len=.. bytes=[..]`
(research/command-path.md 1). So a keypress with a >12 Ghost selection has exactly three
possible outcomes, and all three are visible:

  * it emits a command -- the id names the ability (Personnel Cloaking is 0x21:
    research/ability-semantics.md 3, the handler that deducts energy and sets the
    secondary order to 0x6D);
  * it emits nothing and ARMS a targeted order -- no CMD line at press time, and the
    NEXT left-click issues one. The sweep cancels with a right-click and records the
    key as "armed nothing", which is what task 022 saw for the slot it clicked;
  * it emits nothing at all.

THE CONTROL TASK 022 MAY NOT HAVE HAD. Personnel Cloaking is RESEARCHED tech: without it
the button is not on the card at all and its key emits nothing -- which is
indistinguishable, from the outside, from "the key is not C". This fixture sets the tech
in PTEx (`-TechResearched personnel-cloaking`) and asserts the generator wrote it, so a
key that emits nothing here really does mean the key is wrong.

Positive before negative (AGENTS.md, 2026-08-09): the sweep only concludes "key X is
Cloak" when 0x21 was SEEN, and it reports the whole key->command table either way so a
run that names nothing still says what every key did.

.EXAMPLE
./tools/plugin/probe-ghost-cloak.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogDir = 'C:\sc-work\logs\023',
    [string]$FixtureDir,
    [int]$UnitCount = 18,
    # A..Z. The command card's hotkeys are plain letters -- no modifier is involved, so
    # task 021's accelerator finding does not apply (drive-game.ps1 KNOWN LIMITS).
    [string[]]$Keys = @('A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
                        'Q','R','S','T','U','V','W','X','Y','Z'),
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

$failures = 0
function Assert-That {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "  ok   $What" }
    else { Write-Host "  FAIL $What $Detail"; $script:failures++ }
}

$CLOAK_CMD = '0x21'      # Personnel Cloaking (research/ability-semantics.md 3)
$CLOAK_ORDER2 = 0x6D     # what 0x00491B30 writes to CUnit+0xA6 after deducting energy
$GHOST_TYPE = 1

if (-not $FixtureDir) { $FixtureDir = Join-Path $GameDir 'Maps\BroodWar\00-t023' }
$mapName = 'ghost-cloak.scx'
$mapPath = Join-Path $FixtureDir $mapName
$fixtures = New-ScFixtureRun -Dir $FixtureDir -Names @($mapName)
$logPath = Join-Path $LogDir 'ghost-cloak.log'
$shotDir = Join-Path $LogDir 'ghost-cloak-frames'
$markerPath = Join-Path $LogDir 'marker.txt'
New-Item -ItemType Directory -Path $LogDir, $shotDir -Force | Out-Null
foreach ($p in @($logPath, $markerPath)) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }

$gamePid = 0
$launchLock = $null
$table = @()
try {
    Write-Host ''
    Write-Host "[1] fixture: $UnitCount Ghosts, Personnel Cloaking researched, full energy"
    Wait-ScFixtureFolderFree -Run $fixtures
    $gen = & (Join-Path $repoRoot 'tools/make-test-map.ps1') `
        -UnitCount $UnitCount -UnitType ghost -Player 0 -Race terran `
        -TechResearched personnel-cloaking -OutputPath $mapPath 2>&1
    $gen = @($gen | Where-Object { "$_" -notmatch 'WARNING:StormLibFinder' })
    $gen | ForEach-Object { Write-Host "       $_" }
    Assert-That 'the generator succeeded' ($LASTEXITCODE -eq 0) "(exit $LASTEXITCODE)"
    # THE CONTROL. Without this the button is not on the card and every key emits
    # nothing, which would make "the key is not C" unfalsifiable.
    Assert-That 'Personnel Cloaking is marked researched for the human slot' `
        (@($gen | Select-String -Pattern 'PTEx: player 0 has researched 10\(personnel-cloaking\)').Count -gt 0)

    Write-Host ''
    Write-Host '[2] launch and box the Ghosts'
    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '023-ghost-cloak'
    & (Join-Path $scriptDir 'run-with-plugin.ps1') `
        -Mode fanout -WorldScan 1 -InjectWindowedHelper WMode -NoLaunchLock `
        -GameDir $GameDir -LogPath $logPath 6>&1 | ForEach-Object {
            Write-Host "       $_"
            if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
        }
    if (-not $gamePid) { throw 'probe: could not parse the game pid from scinject output.' }
    $hwnd = Get-ScGameWindow -ProcessId $gamePid

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
    Set-ScGameType -Hwnd $hwnd -Index 2
    Send-ScClick -Hwnd $hwnd -X 516 -Y 393
    Start-Sleep -Seconds 6
    Send-ScClick -Hwnd $hwnd -X 544 -Y 387
    Start-Sleep -Seconds 10
    Send-ScClick -Hwnd $hwnd -X 200 -Y 261
    Start-Sleep -Seconds 3

    function Select-Block { Send-ScDrag -Hwnd $hwnd -X1 115 -Y1 25 -X2 515 -Y2 330 -Steps 16 }
    Select-Block
    $state = Get-ScUnitState -LogPath $logPath -Tag 'boxed' -MarkerPath $markerPath
    Assert-That "the box holds the $UnitCount Ghosts ($($state.N))" ($state.N -eq $UnitCount)
    Assert-That 'and they really are Ghosts' ($state.Types.ContainsKey('0x01'))
    Assert-That 'none is cloaked before the sweep' `
        (-not $state.Orders2.ContainsKey('0x6D')) "($($state.Line))"
    Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $shotDir '01-boxed.png') -FullWindow | Out-Null

    Write-Host ''
    Write-Host '[3] the sweep: one key at a time, and what each one put on the wire'
    foreach ($k in $Keys) {
        $vk = [int][char]$k.ToUpperInvariant()
        $mark = Get-ScLogLineCount -LogPath $logPath
        Send-ScKey -Hwnd $hwnd -VirtualKey $vk -SettleMs 700
        $lines = @(Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue | Select-Object -Skip $mark)
        $ids = @($lines | Select-String -Pattern 'CMD id=(0x[0-9A-F]{2})' |
                 ForEach-Object { $_.Matches[0].Groups[1].Value } |
                 Where-Object { $_ -ne '0x37' } |     # the per-frame sync command, always there
                 Select-Object -Unique)
        $fanned = @($lines | Select-String -Pattern 'FANOUT select:|fan-out').Count -gt 0
        $table += [pscustomobject]@{ Key = $k; Commands = ($ids -join ' '); Fanned = $fanned }
        Write-Host ("       {0} -> {1}" -f $k, $(if ($ids.Count) { $ids -join ' ' } else { '(nothing)' }))
        # Cancel anything the key ARMED rather than issued: a right-click is the game's
        # own cancel for a targeted-order cursor, and with nothing armed it is a move
        # order to where the block already is. Then re-box, because a key that did fire
        # may have changed the selection.
        Send-ScClick -Hwnd $hwnd -X 315 -Y 180 -Right
        Start-Sleep -Milliseconds 400
        Select-Block
    }

    Write-Host ''
    Write-Host '[4] the answer'
    $hit = @($table | Where-Object { $_.Commands -match [regex]::Escape($CLOAK_CMD) })
    $table | ForEach-Object { Write-Host ("       {0,-3} {1}" -f $_.Key, $_.Commands) }
    Assert-That "exactly one key emitted Personnel Cloaking ($CLOAK_CMD)" ($hit.Count -eq 1) `
        "(keys that did: $(($hit.Key -join ', ')))"
    if ($hit.Count -eq 1) {
        Write-Host "       THE GHOST'S CLOAK KEY IS '$($hit[0].Key)'"
        # Positive proof it really cloaked, not merely that a command id went out.
        Select-Block
        Send-ScKey -Hwnd $hwnd -VirtualKey ([int][char]$hit[0].Key) -SettleMs 900
        $after = Get-ScUnitState -LogPath $logPath -Tag 'cloaked' -MarkerPath $markerPath
        Assert-That 'and pressing it puts the units into the cloak secondary order (0x6D)' `
            ($after.Orders2.ContainsKey('0x6D')) "($($after.Line))"
        Assert-That 'more than the engine''s twelve are cloaked -- it fanned out' `
            ($after.Orders2['0x6D'] -gt 12) "(0x6D on $($after.Orders2['0x6D']) unit(s))"
        Save-ScWindowImage -Hwnd $hwnd -Path (Join-Path $shotDir '02-cloaked.png') -FullWindow | Out-Null
    }
}
catch {
    Write-Host "  FAIL the probe threw: $($_.Exception.Message)"
    Write-Host "       $($_.InvocationInfo.PositionMessage)"
    $failures++
}
finally {
    if (-not $KeepOpen -and $gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch { Write-Host "  FAIL close-game: $($_.Exception.Message)"; $failures++ }
        Start-Sleep -Seconds 2
    }
    if ($launchLock) { Exit-ScLaunchLock -Lock $launchLock }
    if (-not $KeepOpen) {
        Remove-ScOwnFixture -Run $fixtures
        Remove-ScOwnFixtureDir -Dir $FixtureDir
    }
}

Write-Host ''
Write-Host "probe-ghost-cloak: $failures failure(s)"
exit ($failures -gt 0 ? 1 : 0)
