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

Build identity (issue #73, task 056). Every scplugin.dll this script produces
carries the commit and the source digest it was built from, as a plain string in
the image:

    SCPLUGIN_BUILD_ID=<short sha>[+dirty] SRC=<12 hex>

The plugin logs it in its ATTACH banner, run-with-plugin.ps1 refuses to launch a
DLL whose SRC does not match the source next to it, and deploy.ps1 reads it back
out of the deployed file -- so "which build is this" is answerable from a log,
from a running game, or from a DLL sitting on disk, without hashing anything or
comparing mtimes against commit timestamps. The stamp is READ BACK OUT of the
built file before this script exits (Assert-BuildStamp): what it prints is the
file's own bytes, never the value it passed to the compiler.

The output is also byte-reproducible as of task 056 -- see the linker flags
below for the two things that were not, and what that measurement was.

.EXAMPLE
./tools/plugin/build.ps1
#>
[CmdletBinding()]
param(
    [string]$ToolchainBin,
    [string]$OutDir,
    [switch]$DebugBuild,
    # Build AND RUN hooktest.exe, the offline unit test for the inline-detour
    # engine (src/hooktest.cpp). No StarCraft file is involved. A non-zero exit
    # from it fails this build -- the detour engine is the one piece that writes
    # executable memory inside the game, so it is proved here before it is used
    # there.
    [switch]$Test
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot  = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
$srcDir    = Join-Path $scriptDir 'src'

. (Join-Path $scriptDir 'sc-build-id.ps1')

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

# --- build identity (issue #73, task 056) ------------------------------------
# Stamped INTO the binary, not written beside it: a sidecar file describes
# whatever it was last written for, and the DLL it claims to describe can be
# replaced under it without a word. See tools/plugin/sc-build-id.ps1 for what
# each of the two values answers and why +dirty is not cosmetic.
$identity  = Get-ScBuildIdentity -RepoRoot $repoRoot
$srcDigest = Get-ScSourceDigest -SrcDir $srcDir -BuildScript $PSCommandPath
Write-Host "build: build id  $($identity.BuildId)  src=$srcDigest"
if ($identity.Dirty) {
    Write-Host "build: the tree has uncommitted changes -- this DLL is NOT $($identity.Sha), it is $($identity.Sha) plus whatever is on disk. That is what +dirty says, and it is why the src digest exists."
}

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
    # Task 056. The two values sc_buildid.cpp turns into the embedded stamp.
    # Passed as quoted -D args: PowerShell 7.3+ passes an embedded quote through
    # to a native command correctly (measured on this machine, pwsh 7.6.4), and
    # if a shell ever stops doing so the Assert-BuildStamp check below FAILS THE
    # BUILD rather than shipping a DLL that says UNSTAMPED.
    "-DSC_BUILD_ID=`"$($identity.BuildId)`""
    "-DSC_BUILD_SRC=`"$srcDigest`""
    # --- reproducible output (task 056; task 048 measured the old build was not) --
    # Two builds of one tree used to differ in 6705 bytes, from two causes:
    #   * the PE TimeDateStamp, which the linker fills with the wall clock;
    #   * the IMAGE BASE, which binutils picks per link for a DLL -- 0x6A980000
    #     and 0x711C0000 on two consecutive builds here -- moving every relocated
    #     address in the file and accounting for nearly all 6705 bytes.
    # Pinning both makes the build byte-reproducible (measured: two builds of the
    # same tree, identical SHA256), which is what lets a DLL hash mean anything at
    # all. It does NOT replace the stamp -- a hash still needs a table to map it
    # back to a tree, and the stamp needs nothing.
    '-Wl,--no-insert-timestamp'
)
if ($DebugBuild) { $common += @('-O0', '-g') } else { $common += @('-O2', '-s') }

# DLL only; scinject.exe keeps the standard EXE base.
#
# 0x71000000, NOT the conventional 0x10000000: WMode.dll is early-injected into
# this game before the plugin on every windowed launch and it IS at 0x10000000 --
#     scinject: early-injected C:\sc-work\1161-base\WMode.dll -> HMODULE 0x10000000
# -- so a plugin based there would be relocated by the loader every run, and the
# file's fixed base would be a fiction the moment it was loaded. Worse than the
# old state, not better: two builds would hash identically while claiming a
# determinism the running image does not have, which is the exact class of lie
# this task exists to remove.
#
# 0x71xxxxxx is free by demonstration, not by assumption: every plugin base
# binutils has picked on this machine landed in 0x71000000-0x73FFFFFF and the
# loader honoured all of them (0x71E50000, 0x724A0000, 0x73360000 in tonight's
# scinject lines, each stable across every run of its own build). The ATTACH
# banner now prints where the DLL actually landed against the base in its own PE
# header, so "the pinned base took" is a read-back rather than a hope.
$dllLink = @('-Wl,--image-base=0x71000000')

$dllOut  = Join-Path $OutDir 'scplugin.dll'
$exeOut  = Join-Path $OutDir 'scinject.exe'
$testOut = Join-Path $OutDir 'hooktest.exe'

# The plugin is several translation units since task 011: the observer, the log,
# the detour engine, the fan-out hooks, (task 014) the selection circles,
# (task 017) the HUD selection-row paging, (task 025) the production queue,
# (task 026) the command-card read-back, (task 029) the upgrade queue,
# (task 030) the group production fan-out, (task 033) the queue-overflow indicator,
# (task 034) the widescreen patch set, (task 056) the build identity and
# (task 054) the game-session epoch.
$pluginSrc = @('scplugin.cpp', 'sc_log.cpp', 'sc_hook.cpp', 'sc_fanout.cpp', 'sc_circles.cpp', 'sc_hudrow.cpp', 'sc_prodqueue.cpp', 'sc_card.cpp', 'sc_upgrades.cpp', 'sc_prodfan.cpp', 'sc_queueind.cpp', 'sc_screen.cpp', 'sc_buildid.cpp', 'sc_session.cpp') |
             ForEach-Object { Join-Path $srcDir $_ }
$testSrc   = @('hooktest.cpp', 'sc_log.cpp', 'sc_hook.cpp', 'sc_fanout.cpp', 'sc_circles.cpp', 'sc_hudrow.cpp', 'sc_prodqueue.cpp', 'sc_card.cpp', 'sc_upgrades.cpp', 'sc_prodfan.cpp', 'sc_queueind.cpp', 'sc_screen.cpp', 'sc_session.cpp') |
             ForEach-Object { Join-Path $srcDir $_ }

Write-Host 'build: compiling scplugin.dll ...'
& $gpp @common @dllLink -shared @pluginSrc -o $dllOut -I $srcDir
if ($LASTEXITCODE -ne 0) { throw "build: g++ failed for scplugin.dll (exit $LASTEXITCODE)" }

Write-Host 'build: compiling scinject.exe ...'
& $gpp @common (Join-Path $srcDir 'scinject.cpp') -o $exeOut
if ($LASTEXITCODE -ne 0) { throw "build: g++ failed for scinject.exe (exit $LASTEXITCODE)" }

if ($Test) {
    Write-Host 'build: compiling hooktest.exe ...'
    & $gpp @common @testSrc -o $testOut -I $srcDir
    if ($LASTEXITCODE -ne 0) { throw "build: g++ failed for hooktest.exe (exit $LASTEXITCODE)" }
}

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

function Assert-BuildStamp {
    # READ THE STAMP BACK OUT OF THE FILE, do not report what we passed in.
    # The whole mechanism rests on a define surviving a shell, a compiler and a
    # linker into a string in .rdata, and every one of those is a place it can
    # be dropped or mangled -- an earlier spelling of the -D argument reached g++
    # as a stray backslash and produced no stamp at all. Printing $identity here
    # instead of the file's own bytes would have reported that build as stamped.
    # See AGENTS.md: an absence check is worth nothing until the pattern has been
    # shown to match where it should.
    param([string]$Path, [string]$ExpectId, [string]$ExpectSrc)
    $stamp = Get-ScDllBuildStamp -Path $Path
    if (-not $stamp) {
        throw ("verify: $(Split-Path $Path -Leaf) carries NO build stamp. The -D defines did not reach " +
               'sc_buildid.cpp (shell quoting, or the file was dropped from the source list). ' +
               'A DLL that cannot say what it is must not leave this script.')
    }
    if ($stamp.BuildId -ne $ExpectId -or $stamp.SrcDigest -ne $ExpectSrc) {
        throw ("verify: $(Split-Path $Path -Leaf) is stamped '$($stamp.Stamp)' but this build asked for " +
               "'SCPLUGIN_BUILD_ID=$ExpectId SRC=$ExpectSrc'.")
    }
    Write-Host ("verify: {0,-14} stamp {1}" -f (Split-Path $Path -Leaf), $stamp.Stamp)
}

Assert-Pe32 $dllOut
Assert-Pe32 $exeOut
if ($Test) { Assert-Pe32 $testOut }

Assert-BuildStamp -Path $dllOut -ExpectId $identity.BuildId -ExpectSrc $srcDigest

if (Test-Path -LiteralPath $objdump) {
    Write-Host 'verify: objdump cross-check'
    & $objdump -f $dllOut | Select-String 'file format|architecture' | ForEach-Object { "  $_" }
    Write-Host 'verify: scplugin.dll imports'
    & $objdump -p $dllOut | Select-String 'DLL Name:' | ForEach-Object { "  $_" }
}

if ($Test) {
    Write-Host ''
    Write-Host 'build: running hooktest.exe (detour engine, no game involved) ...'
    & $testOut
    if ($LASTEXITCODE -ne 0) { throw "build: hooktest.exe FAILED (exit $LASTEXITCODE)" }
    Write-Host 'build: hooktest OK'
}

Write-Host ''
Write-Host "build: OK  build id $($identity.BuildId)  src=$srcDigest"
Write-Host "  $dllOut  sha256=$((Get-FileHash -LiteralPath $dllOut -Algorithm SHA256).Hash)"
Write-Host "  $exeOut"
if ($Test) { Write-Host "  $testOut" }
