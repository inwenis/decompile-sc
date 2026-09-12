#Requires -Version 7
<#
.SYNOPSIS
Play from this checkout: the desktop shortcut's feature set in a 1x window, the plugin
rebuilt when stale. Runs in the foreground until the game exits, then takes the presenter
DLL back out of the working copy the test suites share.

Any tools/plugin/run-with-plugin.ps1 parameter overrides a default:
  ./run.ps1 -Geometry 1536x864
  ./run.ps1 -Mode observe        (the plugin's off switch)
  ./run.ps1 -Sound:$false
#>
$play = [ordered]@{
    Mode = 'fanout'; Windowed = $true; WindowedHelperDll = 'C:\sc-work\cnc-ddraw\v7.1.0.0\ddraw.dll'
    Widescreen = '1'; WidescreenStage = '3'; Geometry = '1280x880'; StormPresent = 'widen'; MenuCentre = '1'
    Circles = '1'; HudRow = '1'; ProdQueue = '1'; ProdFan = '1'; UpgradeQueue = '1'; QueueIndicator = '1'
    Sound = $true; WaitForExit = $true
}
# Into the table rather than re-splatting $args: a re-splatted `-Switch:$false` loses its
# value, which then binds to the first positional parameter.
for ($i = 0; $i -lt $args.Count; $i++) {
    if ("$($args[$i])" -notmatch '^-(\w+)(:?)$') { throw "run.ps1: expected -Name [value], got '$($args[$i])'" }
    $name = $Matches[1]
    $hasValue = $Matches[2] -or ($i + 1 -lt $args.Count -and "$($args[$i + 1])" -notmatch '^-\w')
    $play[$name] = $hasValue ? $args[++$i] : $true
}
$launcher = Join-Path $PSScriptRoot 'tools/plugin/run-with-plugin.ps1'
& $launcher @play
$code = $LASTEXITCODE
$gameDir = @{}
if ($play.Contains('GameDir')) { $gameDir.GameDir = $play.GameDir }
& $launcher -RemoveWindowed -NoLaunch -NoLaunchLock @gameDir | Out-Null
exit $code
