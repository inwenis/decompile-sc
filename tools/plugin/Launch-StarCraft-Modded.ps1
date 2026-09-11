#Requires -Version 7
<#
StarCraft Modded launcher -- no arguments. Runs from the install root, next to plugin\
and game\; sc-stage-runtime.ps1 copies it there for tools/deploy.ps1 and
tools/package-release.ps1. Edit this file in the repo, never the installed copy.

Baked feature set: fan-out select-past-12, selection circles, HUD row paging, over-cap
production queue with its badge, group production, upgrade queue, and WIDESCREEN:
-Widescreen 1 -WidescreenStage 3 patch the engine in-process at launch to the width in
tools/plugin/src/sc_screen_patches.h (the exe on disk stays byte-identical), and
-StormPresent widen is the buffer->glass copy of the new columns. It must be passed as
an argument: run-with-plugin.ps1's exported default reaches the DLL as 0, and the wide
game then shows a black right band. Known imperfections: widescreen-card.md.

Presenter: cnc-ddraw (WMode.dll has no export table and no config, so it cannot scale a
window or clip the cursor; cnc-ddraw can). plugin\cnc-ddraw-2x.ini sets the window size
and locks the cursor to the window on the first click inside it; hold Ctrl or Right Alt
to free it.

-Sound: run-with-plugin.ps1 mutes by default for unattended suites; this is the user
asking for the game. -NoForegroundRestore: a worker launch hands the foreground back to
whatever window had it, because an unattended suite must not own the user's screen; this
launch is the user's, so the game keeps the foreground it takes. -NoLaunchLock: the
worker launch lock must be structurally unreachable from here, on top of
run-with-plugin.ps1's own $env:AGENT_TASK check, because this runs
`pwsh -WindowStyle Hidden` with no console: a held or wedged lock would mean a
double-click that silently shows nothing for the whole wait budget.

The try/catch exists for the same reason, generalised: ANY failure in a hidden process is
otherwise invisible. On failure it writes logs\launch-error.log and shows a message box.
#>
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
try {
    $gameDir = Join-Path $here 'game'
    $exe = Join-Path $gameDir 'StarCraft.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        throw ("No StarCraft.exe in $gameDir.`r`n`r`nCopy the contents of your StarCraft: Brood War 1.16.1 folder " +
               'into that game folder (a copy, not your only install), then launch again.')
    }
    # The plugin patches addresses of exactly this binary (research/pe-anatomy.md); any
    # other build would be patched in the wrong places. Refuse with the reason rather than
    # crash without one.
    $STARCRAFT_1161_SHA256 = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
    $exeHash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
    if ($exeHash -ne $STARCRAFT_1161_SHA256) {
        throw ("$exe is not StarCraft: Brood War 1.16.1.`r`n  expected sha256 $STARCRAFT_1161_SHA256`r`n" +
               "  found          $exeHash`r`nThis mod patches that one build and no other.")
    }

    & (Join-Path $here 'plugin\run-with-plugin.ps1') `
        -GameDir  $gameDir `
        -BuildDir (Join-Path $here 'plugin') `
        -LogPath  (Join-Path $here 'logs\sc-plugin.log') `
        -Mode fanout `
        -Windowed `
        -WindowedHelperDll (Join-Path $here 'plugin\cnc-ddraw\ddraw.dll') `
        -WindowedHelperIni (Join-Path $here 'plugin\cnc-ddraw-2x.ini') `
        -Widescreen 1 `
        -WidescreenStage 3 `
        -StormPresent widen `
        -Sound `
        -NoLaunchLock `
        -NoForegroundRestore `
        -Circles 1 `
        -HudRow 1 `
        -ProdQueue 1 `
        -ProdFan 1 `
        -UpgradeQueue 1 `
        -QueueIndicator 1
}
catch {
    $errLog = Join-Path $here 'logs\launch-error.log'
    New-Item -ItemType Directory -Path (Split-Path $errLog -Parent) -Force | Out-Null
    "$([DateTime]::Now.ToString('o'))`r`n$($_ | Out-String)" | Out-File -LiteralPath $errLog -Append -Encoding utf8
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "StarCraft Modded failed to launch:`r`n`r`n$($_.Exception.Message)`r`n`r`nDetails logged to:`r`n$errLog",
        'StarCraft Modded', 'OK', 'Error') | Out-Null
    exit 1
}
