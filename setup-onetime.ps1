#Requires -Version 7
<#
.SYNOPSIS
One-time machine install for developing the mod: the pinned 32-bit toolchain, the pinned
cnc-ddraw presenter, given -StarCraftDir the hash-checked working copy of the game, and, once
Ghidra and that copy exist, the named decompiled C (tools/ghidra/decomp-all.ps1).

.DESCRIPTION
Idempotent: whatever is already present is skipped. Everything lands outside the repo
(C:\re-tools, C:\sc-work), so pruning a worktree cannot delete it. Per-worktree setup is
setup-worktree.ps1. Toolchain provenance and sha256: tools/plugin/README.md "Toolchain
(pinned)"; cnc-ddraw pin: tools/plugin/fetch-cnc-ddraw.ps1.

.EXAMPLE
./setup-onetime.ps1 -StarCraftDir 'C:\Program Files (x86)\StarCraft'
#>
[CmdletBinding()]
param(
    # Your own StarCraft: Brood War 1.16.1 install. Omit to make the working copy later
    # with ./tools/make-working-copy.ps1 -Source <that folder>.
    [string]$StarCraftDir,
    [string]$ToolchainRoot = 'C:\re-tools\mingw32-gcc-16.1.0-i686-msvcrt'
)
$ErrorActionPreference = 'Stop'

$gpp = Join-Path $ToolchainRoot 'mingw32\bin\g++.exe'
if (Test-Path -LiteralPath $gpp) {
    Write-Host "setup-onetime: toolchain present: $gpp"
}
else {
    $zip = Join-Path ([IO.Path]::GetTempPath()) 'winlibs-i686-gcc-16.1.0.zip'
    Write-Host 'setup-onetime: downloading the pinned toolchain (283 MB) ...'
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri 'https://github.com/brechtsanders/winlibs_mingw/releases/download/16.1.0posix-14.0.0-msvcrt-r4/winlibs-i686-posix-dwarf-gcc-16.1.0-mingw-w64msvcrt-14.0.0-r4.zip' -OutFile $zip
    $h = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    if ($h -ne 'A5817469F554314B03CD5298C0B247057D7A7DA5B85A01D89D9FC9FEB7ADBC19') { throw "setup-onetime: toolchain sha256 mismatch: $h" }
    # 7z unpacks the 20k-file zip in seconds; Expand-Archive takes minutes. Same tree either way.
    if (Get-Command 7z -ErrorAction SilentlyContinue) { 7z x $zip "-o$ToolchainRoot" -y | Out-Null }
    else { Expand-Archive -LiteralPath $zip -DestinationPath $ToolchainRoot }
    Remove-Item -LiteralPath $zip
    if (-not (Test-Path -LiteralPath $gpp)) { throw "setup-onetime: unpacked, but $gpp is not there" }
    Write-Host "setup-onetime: toolchain installed: $gpp"
}

& (Join-Path $PSScriptRoot 'tools/plugin/fetch-cnc-ddraw.ps1') | Out-Null
Write-Host 'setup-onetime: cnc-ddraw present (C:\sc-work\cnc-ddraw\v7.1.0.0)'

if ($StarCraftDir) {
    & (Join-Path $PSScriptRoot 'tools/make-working-copy.ps1') -Source $StarCraftDir
}
else {
    Write-Host "setup-onetime: no -StarCraftDir given. Make the working copy when ready: ./tools/make-working-copy.ps1 -Source '<your StarCraft folder>'"
}

# Decompiled C for reading (AGENTS.md § "Decompiled C"): needs Ghidra and the working copy.
if (Test-Path -LiteralPath 'C:\sc-work\decomp\StarCraft.exe\index.tsv') {
    Write-Host 'setup-onetime: decompiled C present (C:\sc-work\decomp\StarCraft.exe)'
}
elseif ($env:GHIDRA_INSTALL_DIR -and (Test-Path -LiteralPath 'C:\sc-work\1161-base\StarCraft.exe')) {
    & (Join-Path $PSScriptRoot 'tools/ghidra/decomp-all.ps1')
}
else {
    Write-Host 'setup-onetime: no decompiled C yet. Install Ghidra (tools/ghidra/README.md) and the working copy, then ./tools/ghidra/decomp-all.ps1'
}
