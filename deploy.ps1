#Requires -Version 7
<#
.SYNOPSIS
Install or refresh the modded game on this machine from the current checkout: builds the
plugin, assembles C:\sc-deploy\starcraft-modded, writes the StarCraft Modded desktop shortcut.
Thin wrapper over tools/deploy.ps1; every argument passes through.
#>
& (Join-Path $PSScriptRoot 'tools/deploy.ps1') @args
exit $LASTEXITCODE
