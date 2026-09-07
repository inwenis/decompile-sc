#Requires -Version 7
<#
.SYNOPSIS
Does the Create Game screen's Game Type combo answer posted keyboard messages at all?

.DESCRIPTION
Send-ScDropdownPick needs the foreground because the combo is press-and-hold and the
game calls SetCapture on button-DOWN -- a requirement of the MOUSE walk. Posted keys
take a different path (WM_KEYDOWN/WM_KEYUP, no capture), so that tax may not apply to
them, and every other posted input measures fine off-screen. Nothing here asserts the
combo changed (a measured negative is as reportable as a positive) and it never presses
Start, so it plays no game. See AGENTS.md § "Game Type / `Custom Type`".

.EXAMPLE
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-gametype-keyboard.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogPath = 'C:\sc-work\logs\050-probe-gametype-keyboard.log'
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'drive-game.ps1')

$VK_TAB = 0x09; $VK_UP = 0x26; $VK_DOWN = 0x28; $VK_RETURN = 0x0D

# A stock map keeps the probe generating nothing, so there is nothing to clean up.
$stock = @(Get-ChildItem -LiteralPath (Join-Path $GameDir 'Maps\BroodWar') -File `
    -Include '*.scm', '*.scx' -ErrorAction SilentlyContinue | Sort-Object Name)
if ($stock.Count -eq 0) { throw "probe-gametype-keyboard: no stock map found under $GameDir\Maps\BroodWar." }
$mapPath = $stock[0].FullName

if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }

$gamePid = 0
& (Join-Path $scriptDir 'run-with-plugin.ps1') `
    -InjectWindowedHelper WMode -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
        Write-Host $_
        if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
    }
if (-not $gamePid) { throw 'probe-gametype-keyboard: could not parse the game pid from scinject output.' }
$hwnd = Get-ScGameWindow -ProcessId $gamePid

try {
    Start-Sleep -Seconds 2
    Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
    Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # StarCraft: Brood War (Expansion)
    Start-Sleep -Seconds 1
    Send-ScClick -Hwnd $hwnd -X 75  -Y 111        # first entry in the Registry list
    Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
    Start-Sleep -Seconds 2
    Send-ScClick -Hwnd $hwnd -X 327 -Y 415        # Play Custom -- opens in Maps\BroodWar
    Start-Sleep -Seconds 2
    Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir -MapPath $mapPath | Out-Null

    # Every arm reads the engine's own dialog list back: "no exception" is not a read-back
    # (AGENTS.md § "Oracles: what counts as a read-back").
    $before = Get-ScGameTypeControl -LogPath $LogPath
    if (-not $before) { throw 'probe-gametype-keyboard: no Create dialog found at baseline -- the lobby never came up.' }
    Write-Host "probe: [A] baseline -- Custom Type reads '$($before.Value)'"

    # Nothing establishes focus first: does the combo already carry this dialog system's
    # notion of "current" for keyboard input?
    Send-ScKey -Hwnd $hwnd -VirtualKey $VK_DOWN -SettleMs 300
    Send-ScKey -Hwnd $hwnd -VirtualKey $VK_RETURN -SettleMs 300
    $blind = Get-ScGameTypeControl -LogPath $LogPath
    if (-not $blind) {
        Write-Host 'probe: [B] blind Down+Enter -- the Create dialog is GONE (Enter left this screen). Treat as CHANGED-AWAY, not a combo readback.'
    }
    else {
        Write-Host ("probe: [B] blind Down+Enter, no click/Tab first -- reads '{0}' ({1})" -f `
            $blind.Value, $(if ($blind.Value -eq $before.Value) { 'UNCHANGED' } else { 'CHANGED' }))
    }

    # The added leading Tab is what this arm tests: does this custom dialog system have a
    # Win32-like tab order that can land focus on the combo? It runs on whatever state the
    # blind arm left, so it reads back against that arm's value, not the baseline.
    Send-ScKey -Hwnd $hwnd -VirtualKey $VK_TAB -SettleMs 300
    Send-ScKey -Hwnd $hwnd -VirtualKey $VK_DOWN -SettleMs 300
    Send-ScKey -Hwnd $hwnd -VirtualKey $VK_RETURN -SettleMs 300
    $tabbed = Get-ScGameTypeControl -LogPath $LogPath
    if (-not $tabbed) {
        Write-Host 'probe: [C] Tab then Down+Enter -- the Create dialog is GONE (Tab moved focus onto a control whose Enter left this screen -- most likely OK/Cancel, not the combo).'
    }
    else {
        Write-Host ("probe: [C] Tab then Down+Enter -- reads '{0}' ({1})" -f `
            $tabbed.Value, $(if ($blind -and $tabbed.Value -eq $blind.Value) { 'UNCHANGED' } else { 'CHANGED' }))
    }

    $anyChange = ($blind -and $blind.Value -ne $before.Value) -or ($tabbed -and $blind -and $tabbed.Value -ne $blind.Value)
    if ($anyChange) {
        Write-Host 'probe: RESULT -- keyboard input DOES move this combo. Foreground requirement narrows: see AGENTS.md.'
    }
    else {
        Write-Host 'probe: RESULT -- keyboard input has NO EFFECT on this combo across both arms. Measured negative: the foreground requirement for a Game Type pick stands as-is.'
    }
}
finally {
    if ($gamePid) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch { Write-Warning "probe-gametype-keyboard: close-game.ps1 failed: $_" }
    }
}
