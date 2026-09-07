#Requires -Version 7
<#
.SYNOPSIS
One launch: can the engine's Save and Load dialogs be DRIVEN at all, and does a plain
(plugin-free) save/load round trip survive? Dumps the full control inventory at every step.

.DESCRIPTION
Runs in `-Mode observe`: no hooks, nothing written to game memory, so the round trip is
also the plugin-free POSITIVE CONTROL -- if a vanilla save does not come back, no
statement about the plugin means anything (AGENTS.md § "Oracles: absence and defect-era
checks"). Play Custom with NO `Set-ScGameType` call: the game-type combo is machine-wide
registry state a dropdown cannot set on the invisible desktop (AGENTS.md § "Game Type /
`Custom Type`"), and no particular game type is needed here.

.EXAMPLE
./tools/plugin/run-offscreen.ps1 -Suite ./tools/plugin/probe-save-load-dialogs.ps1
#>
[CmdletBinding()]
param(
    [string]$GameDir = 'C:\sc-work\1161-base',
    [string]$LogPath = 'C:\sc-work\logs\051\save-dialog-probe.log',
    [string]$ShotDir = 'C:\sc-work\logs\051-frames',
    [string]$StashDir = 'C:\sc-work\logs\051\stash',
    [string]$SaveName = 'slprobe',
    [switch]$KeepOpen
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'drive-game.ps1')
. (Join-Path $scriptDir 'sc-launch-lock.ps1')

$failures = 0
$step = 0
$markerPath = Join-Path (Split-Path $LogPath -Parent) 'marker.txt'
$saveRoot = Join-Path $GameDir 'save'

function Assert-That {
    param([string]$What, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { Write-Host "  ok   $What" } else { Write-Host "  FAIL $What $Detail"; $script:failures++ }
}
function Step {
    param([string]$Name, [scriptblock]$Body)
    $script:step++; Write-Host ''; Write-Host ("[{0}] {1}" -f $script:step, $Name); & $Body
}
function Get-SaveFiles {
    if (-not (Test-Path -LiteralPath $saveRoot)) { return @() }
    @(Get-ChildItem -LiteralPath $saveRoot -Recurse -File -Filter '*.snx' -ErrorAction SilentlyContinue)
}
function Get-World { param([string]$Tag) Get-ScWorldState -LogPath $LogPath -Tag $Tag -MarkerPath $markerPath }

New-Item -ItemType Directory -Path (Split-Path $LogPath -Parent) -Force | Out-Null
New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null
if (Test-Path -LiteralPath $LogPath) { Remove-Item -LiteralPath $LogPath -Force }
if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }

$gamePid = 0
$hwnd = [IntPtr]::Zero
$shotN = 0
$launchLock = $null
$roundTripRan = $false
function Shot([string]$tag) {
    if ($script:hwnd -eq [IntPtr]::Zero) { return }
    $script:shotN++
    Save-ScWindowImage -Hwnd $script:hwnd -Path (Join-Path $ShotDir ("probe-{0:d2}-{1}.png" -f $script:shotN, $tag)) -FullWindow | Out-Null
}

# This probe may destroy only its own save; every other file in the save folder belongs
# to someone else and has to come back byte-for-byte.
$stashed = @()
$mySave = $null

try {
    # A run that dies between the stash and the restore leaves other people's saves in
    # the stash directory; recover them before this run can overwrite them.
    if (Test-Path -LiteralPath $StashDir) {
        $left = @(Get-ChildItem -LiteralPath $StashDir -File -Filter '*.snx' -ErrorAction SilentlyContinue)
        foreach ($f in $left) {
            $dest = Join-Path (Join-Path $saveRoot 'asdf') $f.Name
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $f.FullName -Force }
            else { Move-Item -LiteralPath $f.FullName -Destination $dest -Force }
        }
        if ($left.Count) { Write-Host "       recovered $($left.Count) save(s) left in the stash by an earlier run" }
    }

    Wait-ScNoGameRunning
    $launchLock = Enter-ScLaunchLock -TaskId '051-save-dialog-probe'

    Step 'launch: observe -- no hooks, nothing written to game memory' {
        & (Join-Path $scriptDir 'run-with-plugin.ps1') `
            -Mode observe -LogCommands 1 -WorldScan 1 -CardScan 1 `
            -InjectWindowedHelper WMode -NoLaunchLock `
            -GameDir $GameDir -LogPath $LogPath 6>&1 | ForEach-Object {
                Write-Host $_
                if ("$_" -match 'scinject:\s*PID=(\d+)') { $script:gamePid = [int]$Matches[1] }
            }
        if (-not $gamePid) { throw 'probe: could not parse the game pid from scinject output.' }
        $script:hwnd = Get-ScGameWindow -ProcessId $gamePid
        # `\S+`, not `[A-Za-z]+`: a hook name may hold a `+` and a digit
        # (`gameStartClear+7`), and a letters-only class reports an installed hook it
        # cannot spell as an absence.
        $hooks = @(Get-Content -LiteralPath $LogPath | Select-String -Pattern 'HOOK \S+: installed at')
        Assert-That 'observe installed NOT ONE hook' ($hooks.Count -eq 0) "(got $($hooks.Count))"
    }

    Step 'menus: Single Player -> Expansion -> Play Custom -> Maps\campaign\(1)Enslavers02b.scm' {
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 215 -Y 119        # Single Player
        Send-ScClick -Hwnd $hwnd -X 373 -Y 300        # Brood War
        Start-Sleep -Seconds 1
        Send-ScClick -Hwnd $hwnd -X 75  -Y 111        # first entry in the Registry list
        Send-ScClick -Hwnd $hwnd -X 516 -Y 392        # Ok
        Start-Sleep -Seconds 2
        Send-ScClick -Hwnd $hwnd -X 327 -Y 415        # Play Custom
        Start-Sleep -Seconds 2
        Select-ScBrowserMap -Hwnd $hwnd -GameDir $GameDir `
            -MapPath (Join-Path $GameDir 'Maps\campaign\(1)Enslavers02b.scm') | Out-Null
        Send-ScClick -Hwnd $hwnd -X 516 -Y 393        # Ok
        Start-Sleep -Seconds 6
        Send-ScClick -Hwnd $hwnd -X 544 -Y 387        # Start
        Start-Sleep -Seconds 10
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
        Shot 'in-game'
        Show-ScDialogInventory -LogPath $LogPath -What 'in game, no menu'
    }

    Step 'F10: what does the in-game menu actually hold' {
        Open-ScGameMenu -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Show-ScDialogInventory -LogPath $LogPath -What 'the in-game menu'
        Shot 'menu'
        Assert-That 'the menu offers a Save control' `
            (@(Find-ScDialogControl -LogPath $LogPath -Pattern 'Save').Count -gt 0)
        Assert-That 'the menu offers a Load control' `
            (@(Find-ScDialogControl -LogPath $LogPath -Pattern 'Load').Count -gt 0)
    }

    Step 'the save dialog, and whether its name box takes posted text' {
        $before = @(Get-SaveFiles | ForEach-Object { $_.FullName })
        Write-Host "       saves already present: $($before.Count)"
        Invoke-ScDialogControl -Hwnd $hwnd -LogPath $LogPath -Pattern 'Save' -What 'Save Game' | Out-Null
        Start-Sleep -Seconds 1
        Show-ScDialogInventory -LogPath $LogPath -What 'the save dialog, as opened'
        Shot 'save-dialog'

        Send-ScText -Hwnd $hwnd -Text $SaveName -ClearCount 24
        Start-Sleep -Milliseconds 600
        Show-ScDialogInventory -LogPath $LogPath -What "the save dialog after typing '$SaveName'"
        Shot 'save-dialog-typed'
        # Read back the engine's own control text, never the variable this script typed
        # from (AGENTS.md § "Oracles: what counts as a read-back"). Send-ScText posts
        # WM_CHAR alone because the box takes BOTH the key-down and the char that
        # Send-ScKey -Char sends, landing 'slprobe' in the box as 'ssllpprroobbee'.
        $echo = @(Find-ScDialogControl -LogPath $LogPath -Pattern ('^' + $SaveName + '$'))
        $box = @(Find-ScDialogControl -LogPath $LogPath -Pattern '.') |
               Where-Object { $_.Control.Type -eq 8 } | Select-Object -First 1
        Write-Host ("       the name box now reads '{0}'" -f $(if ($box) { $box.Control.Text } else { '(no type-8 control found)' }))
        Assert-That "the name box holds EXACTLY what was typed ('$SaveName')" ($echo.Count -gt 0) `
            "(box reads '$(if ($box) { $box.Control.Text } else { '?' })')"

        # 'Save$', not '^Save$': the engine stores the hotkey in the string itself, so the
        # button's text is 's.S.ave' and its LETTERS are 'sSave'. The end anchor is what
        # tells the BUTTON from the dialog's TITLE ('Save Game' -> 'SaveGame'), which an
        # unanchored 'Save' would also match.
        Invoke-ScDialogControl -Hwnd $hwnd -LogPath $LogPath -Pattern '(^OK$|Save$)' `
            -What 'the save dialog Save button' | Out-Null
        Start-Sleep -Seconds 4
        Show-ScDialogInventory -LogPath $LogPath -What 'after clicking OK'
        Shot 'after-save'

        $after = @(Get-SaveFiles)
        $new = @($after | Where-Object { $before -notcontains $_.FullName })
        Assert-That 'the ENGINE wrote a new .snx' ($new.Count -eq 1) `
            "(new: $($new.Count); all: $(($after | ForEach-Object { $_.Name }) -join ', '))"
        if ($new.Count -eq 1) {
            $script:mySave = $new[0]
            Write-Host ("       -> {0} ({1} bytes)" -f $new[0].FullName, $new[0].Length)
            Assert-That "and it carries the typed name ('$($new[0].BaseName)')" `
                ($new[0].BaseName -ieq $SaveName) '(the box did not take the posted text)'
        }
    }

    Step 'the load dialog, and the plugin-free round trip itself' {
        if (-not $mySave) { throw 'probe: nothing was saved, so there is nothing to load.' }
        $w1 = Get-World 'before-load'
        $n1 = @($w1.Units).Count
        Write-Host "       world before the load: $n1 unit(s)"

        # A row can only be identified if the list holds nothing else, so every save that
        # is not ours moves out for the length of the load.
        New-Item -ItemType Directory -Path $StashDir -Force | Out-Null
        foreach ($f in (Get-SaveFiles)) {
            if ($f.FullName -ne $mySave.FullName) {
                $dest = Join-Path $StashDir $f.Name
                Move-Item -LiteralPath $f.FullName -Destination $dest -Force
                $script:stashed += [pscustomobject]@{ From = $f.FullName; To = $dest }
            }
        }
        Write-Host "       $($stashed.Count) other save(s) stashed for the load"

        Open-ScGameMenu -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Invoke-ScDialogControl -Hwnd $hwnd -LogPath $LogPath -Pattern 'Load' -What 'Load Game' | Out-Null
        Start-Sleep -Seconds 1
        Show-ScDialogInventory -LogPath $LogPath -What 'the load dialog'
        Shot 'load-dialog'
        $row = @(Find-ScDialogControl -LogPath $LogPath -Pattern ('^' + $SaveName + '$'))
        Write-Host ("       the list names our save in a control: {0}" -f ($row.Count -gt 0))
        if ($row.Count -gt 0) {
            Send-ScClick -Hwnd $hwnd -X $row[0].X -Y $row[0].Y
            Start-Sleep -Milliseconds 600
        }
        Invoke-ScDialogControl -Hwnd $hwnd -LogPath $LogPath -Pattern '(^OK$|Load$)' `
            -What 'the load dialog Load button' | Out-Null
        Start-Sleep -Seconds 15
        Dismiss-ScTipsDialog -Hwnd $hwnd -LogPath $LogPath | Out-Null
        Start-Sleep -Seconds 2
        Shot 'after-load'
        Show-ScDialogInventory -LogPath $LogPath -What 'after the load'

        $w2 = Get-World 'after-load'
        $n2 = @($w2.Units).Count
        $script:roundTripRan = $true
        Write-Host "       world after the load:  $n2 unit(s)"
        Assert-That "the world is still there after the load ($n1 -> $n2 units)" ($n2 -gt 0)
        Assert-That 'and it holds the same number of units as it did at the save' ($n1 -eq $n2) `
            "(before=$n1 after=$n2)"
        $t1 = (@($w1.Units | ForEach-Object { $_.Type }) | Sort-Object) -join ','
        $t2 = (@($w2.Units | ForEach-Object { $_.Type }) | Sort-Object) -join ','
        Assert-That 'and the same multiset of unit types' ($t1 -eq $t2)
    }
}
catch {
    Write-Host "  FAIL a probe step threw: $($_.Exception.Message)"
    Write-Host "       $($_.ScriptStackTrace)"
    $failures++
}
finally {
    foreach ($m in $stashed) {
        if (Test-Path -LiteralPath $m.To) { Move-Item -LiteralPath $m.To -Destination $m.From -Force }
    }
    if ($stashed.Count) { Write-Host "       $($stashed.Count) stashed save(s) put back" }
    if ($mySave -and (Test-Path -LiteralPath $mySave.FullName)) {
        Remove-Item -LiteralPath $mySave.FullName -Force
        Write-Host "       removed this probe's own save: $($mySave.Name)"
    }
    if (-not $KeepOpen -and $gamePid -gt 0) {
        try { & (Join-Path $scriptDir 'close-game.ps1') -ProcessId $gamePid | Write-Host }
        catch { Write-Host "  FAIL close-game could not shut the game down: $($_.Exception.Message)"; $failures++ }
    }
    if ($launchLock) { Exit-ScLaunchLock -Lock $launchLock }
}

Write-Host ''
if (-not $roundTripRan) {
    Write-Host "probe-save-load-dialogs: INCOMPLETE -- the round trip never ran, $failures failure(s)."
    Write-Host "frames (diagnostic, NOT committable): $ShotDir"
    exit 1
}
Write-Host "probe-save-load-dialogs: $failures failure(s)"
Write-Host "frames (diagnostic, NOT committable): $ShotDir"
exit ($failures -eq 0 ? 0 : 1)
