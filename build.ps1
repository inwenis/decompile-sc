#Requires -Version 7
<#
.SYNOPSIS
Build the plugin (scplugin.dll + scinject.exe) from this checkout into work\scratch\plugin-build.
Thin wrapper over tools/plugin/build.ps1; every argument passes through (-Test runs hooktest).
#>
& (Join-Path $PSScriptRoot 'tools/plugin/build.ps1') @args
exit $LASTEXITCODE
