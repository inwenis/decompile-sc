#Requires -Version 7
<#
.SYNOPSIS
Run the modded game from this checkout: build the plugin if needed, then launch
StarCraft 1.16.1 from the working copy with it injected.

Thin wrapper over tools/plugin/run-with-plugin.ps1 -- every argument passes through.
#>
& (Join-Path $PSScriptRoot 'tools/plugin/run-with-plugin.ps1') @args
exit $LASTEXITCODE
