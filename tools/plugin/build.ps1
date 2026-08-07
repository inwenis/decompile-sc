#Requires -Version 7
<#
.SYNOPSIS
Build the task-008 StarCraft observer plugin (32-bit DLL) and its injector
(32-bit EXE), then verify both are really x86 PE32.

.DESCRIPTION
Uses the pinned MinGW-w64 toolchain documented in tools/plugin/README.md. The
toolchain lives OUTSIDE every worktree (default C:\re-tools\...), so pruning a
worktree can never delete it -- same rule as tools/ghidra/README.md.

Resolution order for the toolchain, first hit wins:
  1. -ToolchainBin parameter
  2. $env:SC_MINGW32_BIN
  3. C:\re-tools\mingw32-gcc-16.1.0-i686-msvcrt\mingw32\bin   (documented default)

Output goes to -OutDir (default: <repo>/work/scratch/plugin-build, gitignored --
the repo must never track built binaries; .gitignore blocks *.dll and *.exe).

The build FAILS if either artifact is not Machine=0x014C / PE32. That check is
the point of the step, not a formality: -m32 silently producing an x64 binary
would only show up as a mystifying "the DLL will not load" much later.

.EXAMPLE
./tools/plugin/build.ps1
#>
[CmdletBinding()]
param(
    [string]$ToolchainBin,
    [string]$OutDir,
    [switch]$DebugBuild
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot  = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
$srcDir    = Join-Path $scriptDir 'src'

$DEFAULT_TOOLCHAIN = 'C:\re-tools\mingw32-gcc-16.1.0-i686-msvcrt\mingw32\bin'

if (-not $ToolchainBin) { $ToolchainBin = $env:SC_MINGW32_BIN }
if (-not $ToolchainBin) { $ToolchainBin = $DEFAULT_TOOLCHAIN }

$gpp     = Join-Path $ToolchainBin 'g++.exe'
$objdump = Join-Path $ToolchainBin 'objdump.exe'

if (-not (Test-Path -LiteralPath $gpp)) {
    throw @"
build: 32-bit C++ toolchain not found at '$gpp'.
Install the pinned toolchain (see tools/plugin/README.md 'Install'), or point at
an existing one with -ToolchainBin / `$env:SC_MINGW32_BIN.
"@
}

if (-not $OutDir) { $OutDir = Join-Path $repoRoot 'work/scratch/plugin-build' }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path

Write-Host "build: toolchain $ToolchainBin"
Write-Host "build: $((& $gpp --version | Select-Object -First 1))"
Write-Host "build: target triple $((& $gpp -dumpmachine))"
Write-Host "build: outdir    $OutDir"

# -m32                  : 32-bit x86, the whole point (game is a 32-bit process)
# -static*              : no libgcc/libstdc++ runtime DLL next to the plugin
# -fno-exceptions/-rtti : nothing here needs them; keeps the DLL free of the
#                         C++ unwinder inside a foreign 1998-era process
# -s                    : strip (smaller; no symbols we need at runtime)
$common = @(
    '-m32'
    '-Wall', '-Wextra'
    '-static', '-static-libgcc', '-static-libstdc++'
    '-fno-exceptions', '-fno-rtti'
)
if ($DebugBuild) { $common += @('-O0', '-g') } else { $common += @('-O2', '-s') }

$dllOut = Join-Path $OutDir 'scplugin.dll'
$exeOut = Join-Path $OutDir 'scinject.exe'

Write-Host 'build: compiling scplugin.dll ...'
& $gpp @common -shared (Join-Path $srcDir 'scplugin.cpp') -o $dllOut -I $srcDir
if ($LASTEXITCODE -ne 0) { throw "build: g++ failed for scplugin.dll (exit $LASTEXITCODE)" }

Write-Host 'build: compiling scinject.exe ...'
& $gpp @common (Join-Path $srcDir 'scinject.cpp') -o $exeOut
if ($LASTEXITCODE -ne 0) { throw "build: g++ failed for scinject.exe (exit $LASTEXITCODE)" }

function Assert-Pe32 {
    param([string]$Path)
    $b = [IO.File]::ReadAllBytes($Path)
    if ($b.Length -lt 0x40) { throw "verify: $Path is too small to be a PE" }
    if ($b[0] -ne 0x4D -or $b[1] -ne 0x5A) { throw "verify: $Path has no MZ header" }
    $peOff = [BitConverter]::ToInt32($b, 0x3C)
    $sig = [BitConverter]::ToUInt32($b, $peOff)
    if ($sig -ne 0x00004550) { throw "verify: $Path has no PE\0\0 signature at 0x$($peOff.ToString('X'))" }
    $machine = [BitConverter]::ToUInt16($b, $peOff + 4)
    $magic   = [BitConverter]::ToUInt16($b, $peOff + 24)
    $isDll   = ([BitConverter]::ToUInt16($b, $peOff + 22) -band 0x2000) -ne 0
    Write-Host ("verify: {0,-14} Machine=0x{1:X4}  OptMagic=0x{2:X4}  {3}" -f `
        (Split-Path $Path -Leaf), $machine, $magic, ($isDll ? 'DLL' : 'EXE'))
    if ($machine -ne 0x014C) {
        throw "verify: $Path Machine=0x$($machine.ToString('X4')), expected 0x014C (IMAGE_FILE_MACHINE_I386). A non-x86 binary cannot load into StarCraft.exe."
    }
    if ($magic -ne 0x010B) {
        throw "verify: $Path optional-header magic=0x$($magic.ToString('X4')), expected 0x010B (PE32)."
    }
}

Assert-Pe32 $dllOut
Assert-Pe32 $exeOut

if (Test-Path -LiteralPath $objdump) {
    Write-Host 'verify: objdump cross-check'
    & $objdump -f $dllOut | Select-String 'file format|architecture' | ForEach-Object { "  $_" }
    Write-Host 'verify: scplugin.dll imports'
    & $objdump -p $dllOut | Select-String 'DLL Name:' | ForEach-Object { "  $_" }
}

Write-Host ''
Write-Host "build: OK"
Write-Host "  $dllOut"
Write-Host "  $exeOut"
