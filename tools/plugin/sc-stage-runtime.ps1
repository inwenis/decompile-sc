#Requires -Version 7
<#
.SYNOPSIS
Assemble the tree a player double-clicks: plugin\ (our binaries, the launch scripts, the
pinned presenter), the launcher, its .cmd shim and the player card.

.DESCRIPTION
Dot-sourced by tools/deploy.ps1 (the desktop install, next to a mirrored game tree) and
tools/package-release.ps1 (the release zip, next to an empty game\ the player fills). One
staging function, so the two installs cannot drift: whatever the deployed launcher needs,
the zip gets, and the other way round.

The tree runs with no repo and no toolchain beside it: run-with-plugin.ps1 dot-sources
every helper listed below, and reads the build identity out of the DLL when there is no
src\ to compare against.
#>

# Pinned sha256 of cnc-ddraw v7.1.0.0's ddraw.dll -- provenance in
# tools/plugin/fetch-cnc-ddraw.ps1 (zip pin) and research/renderer-viewport.md 14.1
# (dll pin). A mismatch is a hard stop, never a re-pin.
$CNC_DDRAW_DLL_SHA256 = '85e0f7d530dfda134793a57cb3e76b0287dcc96892ee57162dd68f47283b03a9'

# run-with-plugin.ps1 and every file it dot-sources. tests/deploy-runtime.Tests.ps1 holds
# this list against the dot-source lines in run-with-plugin.ps1; a helper missing here
# fails only on the player's machine, in a hidden pwsh with no console to fail in.
$SC_RUNTIME_SCRIPTS = @(
    'run-with-plugin.ps1'
    'check-game-windows.ps1'
    'sc-canonical-path.ps1'
    'sc-audio-mute.ps1'
    'sc-launch-lock.ps1'
    'sc-foreground.ps1'
    'sc-desktop.ps1'      # "am I on the desktop the monitor shows?" is asked before every launch
    'sc-build-id.ps1'     # the DLL's build identity is read on every launch, the user's included
)

function Get-ScWidescreenGeometry {
    <#
    .SYNOPSIS
    The screen size the plugin was built for, read from the generated patch table.
    #>
    param([string]$PatchHeader = (Join-Path $PSScriptRoot 'src\sc_screen_patches.h'))
    $w = [int]((Select-String -LiteralPath $PatchHeader -Pattern '^#define\s+SC_WS_SCREEN_W\s+(\d+)' | Select-Object -First 1).Matches[0].Groups[1].Value)
    $h = [int]((Select-String -LiteralPath $PatchHeader -Pattern '^#define\s+SC_WS_SCREEN_H\s+(\d+)' | Select-Object -First 1).Matches[0].Groups[1].Value)
    if ($w -lt 640 -or $h -lt 480) { throw "stage-runtime: could not read SC_WS_SCREEN_W/H from $PatchHeader (got ${w}x${h})" }
    [pscustomobject]@{ Width = $w; Height = $h }
}

function Publish-ScPluginRuntime {
    <#
    .SYNOPSIS
    Copy the built plugin, the launch scripts, the pinned cnc-ddraw, the launcher, its shim
    and the card into -Dest. Returns where things landed.

    .PARAMETER Borderless
    Write the 2x ini as borderless full screen (fullscreen=true, aspect kept) instead of a
    2x window. deploy.ps1 decides from the primary monitor; the release zip always says
    yes, because the machine that plays is not the one that packages.
    #>
    param(
        [Parameter(Mandatory)][string]$Dest,
        [Parameter(Mandatory)][string]$BuiltDll,
        [Parameter(Mandatory)][string]$BuiltExe,
        [Parameter(Mandatory)][string]$CncDdrawDir,
        [Parameter(Mandatory)][bool]$Borderless
    )
    $pluginDir  = $PSScriptRoot
    $pluginDest = Join-Path $Dest 'plugin'
    New-Item -ItemType Directory -Path $pluginDest -Force | Out-Null
    Copy-Item -LiteralPath $BuiltDll -Destination (Join-Path $pluginDest 'scplugin.dll') -Force
    Copy-Item -LiteralPath $BuiltExe -Destination (Join-Path $pluginDest 'scinject.exe') -Force
    foreach ($s in $SC_RUNTIME_SCRIPTS) {
        Copy-Item -LiteralPath (Join-Path $pluginDir $s) -Destination (Join-Path $pluginDest $s) -Force
    }
    Write-Host "plugin runtime copied: scplugin.dll, scinject.exe, $($SC_RUNTIME_SCRIPTS -join ', ')"

    # The launcher presents through cnc-ddraw, not WMode: WMode.dll has no export table and
    # no config (tools/plugin/README.md "Windowed mode: injected, not proxied"), so it cannot
    # scale a window or clip the cursor and it crops to 640 columns whatever it is asked,
    # while cnc-ddraw FOLLOWs the full widened width (research/renderer-viewport.md 12.6, 14).
    # The DLL is a third-party game-adjacent binary: staged from the pinned fetch, never
    # committed (AGENTS.md § "Hard rules"), sha256-verified HERE so a stage cannot ship a DLL
    # the pin does not vouch for. run-with-plugin.ps1 -WindowedHelperDll copies it into the
    # game dir per launch and -WindowedHelperIni picks which ini travels with it: unscaled
    # cnc-ddraw.ini (width=0/height=0) or cnc-ddraw-2x.ini (2x scale, cursor locked). Both
    # are staged unconditionally so either can be run standalone.
    $cncSrcDll = Join-Path $CncDdrawDir 'ddraw.dll'
    if (-not (Test-Path -LiteralPath $cncSrcDll)) {
        throw ("stage-runtime: cnc-ddraw not found at $cncSrcDll. Run tools/plugin/fetch-cnc-ddraw.ps1 " +
               'first (downloads + pin-verifies v7.1.0.0), then re-run.')
    }
    $cncHash = (Get-FileHash -LiteralPath $cncSrcDll -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($cncHash -ne $CNC_DDRAW_DLL_SHA256) {
        throw "stage-runtime: cnc-ddraw ddraw.dll SHA256 MISMATCH at $cncSrcDll`n  expected $CNC_DDRAW_DLL_SHA256`n  got      $cncHash`nDo not ship an unvouched helper; re-run fetch-cnc-ddraw.ps1 and re-review."
    }
    $cncDest = Join-Path $pluginDest 'cnc-ddraw'
    New-Item -ItemType Directory -Path $cncDest -Force | Out-Null
    Copy-Item -LiteralPath $cncSrcDll -Destination (Join-Path $cncDest 'ddraw.dll') -Force
    Copy-Item -LiteralPath (Join-Path $pluginDir 'cnc-ddraw.ini') -Destination (Join-Path $pluginDest 'cnc-ddraw.ini') -Force

    # The 2x ini is GENERATED from tools/plugin/cnc-ddraw-2x.ini with width/height set to
    # twice the geometry the plugin was actually built for (SC_WS_SCREEN_W/H in the
    # generated sc_screen_patches.h), so the window always matches the binary it presents.
    # The committed file keeps the stock 1280x960 (2x of 640x480) as its documented example.
    # Borderless: cnc-ddraw's fullscreen=true + windowed=true stretches the game to the
    # desktop with the aspect ratio kept (maintas), letterboxed as needed; its cursor lock
    # engages on activation there. The width/height lines stay at 2x for the verify
    # (cnc-ddraw ignores them under fullscreen=true).
    $geom  = Get-ScWidescreenGeometry
    $cnc2x = Get-Content -Raw -LiteralPath (Join-Path $pluginDir 'cnc-ddraw-2x.ini')
    $cnc2x = $cnc2x -replace '(?m)^width=\d+', "width=$($geom.Width * 2)" -replace '(?m)^height=\d+', "height=$($geom.Height * 2)"
    if ($Borderless) {
        $cnc2x = $cnc2x -replace '(?m)^fullscreen=false', 'fullscreen=true'
        $cnc2x = $cnc2x -replace '(?m)^(renderer=gdi\r?\n)', "`$1maintas=true`n"
    }
    $cnc2xPath = Join-Path $pluginDest 'cnc-ddraw-2x.ini'
    Set-Content -LiteralPath $cnc2xPath -Value $cnc2x -Encoding ascii -NoNewline
    $present = $Borderless ? "borderless full screen, aspect kept" : "window $($geom.Width * 2)x$($geom.Height * 2) = 2x the $($geom.Width)x$($geom.Height) the plugin renders"
    Write-Host "cnc-ddraw staged: $cncDest\ddraw.dll (sha256 verified) + plugin\cnc-ddraw.ini + plugin\cnc-ddraw-2x.ini ($present)"

    foreach ($f in 'Launch-StarCraft-Modded.ps1', 'Launch-StarCraft-Modded.cmd') {
        Copy-Item -LiteralPath (Join-Path $pluginDir $f) -Destination (Join-Path $Dest $f) -Force
    }
    # The one-page card travels with the install, next to the launcher it describes.
    Copy-Item -LiteralPath (Join-Path $pluginDir '..\widescreen-card.md') -Destination (Join-Path $Dest 'widescreen-card.md') -Force
    Write-Host "launcher, shim and card copied -> $Dest"

    [pscustomobject]@{
        PluginDir    = $pluginDest
        LauncherPath = Join-Path $Dest 'Launch-StarCraft-Modded.ps1'
        Cnc2xIniPath = $cnc2xPath
        Width        = $geom.Width
        Height       = $geom.Height
        Borderless   = $Borderless
    }
}

function Test-ScPluginRuntime {
    <#
    .SYNOPSIS
    Re-check a staged tree from what actually shipped: every file the launcher needs, the
    cnc-ddraw pin, and the 2x ini's geometry. Throws on the first defect.
    #>
    param(
        [Parameter(Mandatory)][string]$Dest,
        [Parameter(Mandatory)][bool]$Borderless
    )
    $pluginDest = Join-Path $Dest 'plugin'
    $geom = Get-ScWidescreenGeometry
    foreach ($f in @('scplugin.dll', 'scinject.exe', 'cnc-ddraw.ini', 'cnc-ddraw-2x.ini', 'cnc-ddraw\ddraw.dll') + $SC_RUNTIME_SCRIPTS) {
        if (-not (Test-Path -LiteralPath (Join-Path $pluginDest $f))) { throw "stage-runtime: plugin\$f missing under $Dest" }
    }
    foreach ($f in 'Launch-StarCraft-Modded.ps1', 'Launch-StarCraft-Modded.cmd', 'widescreen-card.md') {
        if (-not (Test-Path -LiteralPath (Join-Path $Dest $f))) { throw "stage-runtime: $f missing under $Dest" }
    }
    # The staged DLL must still match the pin: a copy that half-took otherwise surfaces as a
    # user-facing DirectDraw error rather than a staging error.
    $stagedCnc  = Join-Path $pluginDest 'cnc-ddraw\ddraw.dll'
    $stagedHash = (Get-FileHash -LiteralPath $stagedCnc -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($stagedHash -ne $CNC_DDRAW_DLL_SHA256) { throw "stage-runtime: staged cnc-ddraw hash mismatch after copy: $stagedCnc" }
    $iniText = Get-Content -Raw -LiteralPath (Join-Path $pluginDest 'cnc-ddraw-2x.ini')
    # \r?$ : the ini inherits CRLF from the committed file, and under (?m) .NET's $ matches
    # before \n only -- without the \r? this check rejects its own correct output.
    if ($iniText -notmatch "(?m)^width=$($geom.Width * 2)\r?$" -or $iniText -notmatch "(?m)^height=$($geom.Height * 2)\r?$") {
        throw "stage-runtime: plugin\cnc-ddraw-2x.ini does not carry width=$($geom.Width * 2)/height=$($geom.Height * 2) (2x the plugin's $($geom.Width)x$($geom.Height))."
    }
    if ($Borderless -and ($iniText -notmatch "(?m)^fullscreen=true\r?$" -or $iniText -notmatch "(?m)^maintas=true\r?$")) {
        throw 'stage-runtime: plugin\cnc-ddraw-2x.ini must be borderless (fullscreen=true + maintas=true) when staged as such.'
    }
    Write-Host "verify: launcher, shim, pinned cnc-ddraw, both inis (2x ini at $($geom.Width * 2)x$($geom.Height * 2)$($Borderless ? ', borderless' : '')) + card all present"
}
