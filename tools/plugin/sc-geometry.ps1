#Requires -Version 7
<#
.SYNOPSIS
The widescreen geometry of a preset, read from its generated patch table.

.NOTES
Dot-source it:  . (Join-Path $PSScriptRoot 'sc-geometry.ps1')
#>

# No Set-StrictMode here: this file is DOT-SOURCED, so a mode set here applies to
# the whole calling script (deploy.ps1 does not run under it).

function Get-ScWidePresetNames {
    # The presets the DLL carries, default first: SC_WS_PRESETS in sc_screen_presets.h.
    $listed = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'src/sc_screen_presets.h')
    @([regex]::Matches($listed, '&SC_WS_GEOM_(\d+x\d+)') | ForEach-Object { $_.Groups[1].Value })
}

function Get-ScWideGeometry {
    <#
    .SYNOPSIS
    The widescreen geometry of a preset, read from the generated table header.
    .DESCRIPTION
    tools/plugin/src/sc_screen_patches_<WxH>.h is GENERATED (tools/renderer_patch_sites.py),
    one per geometry preset, and is the one place a preset's width/height live. Every probe
    that asserts a client size, a dump size or a band extent reads them here: a literal
    width copied into a probe goes stale, silently, the moment the target size moves.
    The preset is the one the DLL will read from %SCPLUGIN_WS_GEOMETRY% (unset = default),
    so a suite and its game agree by construction.
    #>
    [CmdletBinding()]
    param(
        [string]$Geometry = $(if ($env:SCPLUGIN_WS_GEOMETRY) { $env:SCPLUGIN_WS_GEOMETRY } else { '1280x880' })
    )
    $src = Join-Path $PSScriptRoot 'src'
    $header = Join-Path $src "sc_screen_patches_$Geometry.h"
    if (-not (Test-Path -LiteralPath $header)) {
        $known = @(Get-ChildItem -LiteralPath $src -Filter 'sc_screen_patches_*.h' |
                   ForEach-Object { $_.BaseName -replace '^sc_screen_patches_', '' })
        throw "sc-geometry: no geometry preset '$Geometry'; presets: $($known -join ', ')"
    }
    $read = {
        param([string]$Name, [string]$File = $header)
        $m = Select-String -LiteralPath $File -Pattern "^#define\s+$Name\s+(\d+)" | Select-Object -First 1
        if (-not $m) { throw "sc-geometry: $Name not found in $File" }
        [int]$m.Matches[0].Groups[1].Value
    }
    # The stock screen is one for every preset, so it lives in the hand-written record header.
    $common = Join-Path $src 'sc_screen_patch.h'
    [pscustomobject]@{
        Name   = $Geometry
        W      = & $read 'SC_WS_SCREEN_W'
        H      = & $read 'SC_WS_SCREEN_H'
        PfW    = & $read 'SC_WS_PLAYFIELD_W'
        PfH    = & $read 'SC_WS_PLAYFIELD_H'
        StockW = & $read 'SC_WS_STOCK_W' $common
        StockH = & $read 'SC_WS_STOCK_H' $common
        # How far the bottom console sits below its stock place (PF_H - 400; 0 at
        # the stock playfield height). A WIDE arm passes this to Get-ScMinimapPoint.
        ConsoleShiftY = & $read 'SC_WS_CONSOLE_SHIFT_Y'
    }
}
