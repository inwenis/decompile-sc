#Requires -Version 7
<#
.SYNOPSIS
Build decompile-sc. There is nothing to build yet — this repo currently holds
documentation, task orchestration data, and (eventually) Python/Ghidra
tooling that runs from source. This script exists to honor the standing rule
that every repo carries setup.ps1 / build.ps1 / run.ps1; it will grow real
steps when the repo grows build artifacts.
#>
$ErrorActionPreference = 'Stop'

Write-Host 'build: nothing to build yet — this repo has no build artifacts.'
Write-Host 'build: research docs and Python tooling run from source; see setup.ps1.'
exit 0
