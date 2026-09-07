#Requires -Version 7
<#
.SYNOPSIS
Build the StarCraft observer plugin (32-bit DLL) and its injector (32-bit EXE),
then verify both are really x86 PE32.

.DESCRIPTION
Toolchain resolution, first hit wins: -ToolchainBin, $env:SC_MINGW32_BIN, the
default below; it lives outside every worktree so pruning one cannot delete it
(tools/plugin/README.md). -OutDir is gitignored: the repo never tracks binaries.
The build FAILS unless both artifacts are Machine=0x014C / PE32 -- -m32 silently
producing an x64 binary surfaces only as "the DLL will not load", much later.

.EXAMPLE
./tools/plugin/build.ps1
#>
[CmdletBinding()]
param(
    [string]$ToolchainBin,
    [string]$OutDir,
    [switch]$DebugBuild,
    # Build AND RUN hooktest.exe, the offline unit test for the inline-detour
    # engine (src/hooktest.cpp); no StarCraft file is involved. A non-zero exit
    # fails this build: the detour engine is the one piece that writes executable
    # memory inside the game, so it is proved here before it is used there.
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

# --- build identity ----------------------------------------------------------
# Stamped INTO the binary, not written beside it: a sidecar file describes
# whatever it was last written for, and the DLL it claims to describe can be
# replaced under it without a word. tools/plugin/sc-build-id.ps1 says what each
# of the two values answers and why +dirty is not cosmetic. The stamp is a gate,
# not a label: run-with-plugin.ps1 refuses to launch a DLL whose SRC digest does
# not match the source sitting beside it.
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
    # -Werror: the toolchain is pinned and this warning set is clean, so a new
    # warning is a change in OUR code.
    '-Wall', '-Wextra', '-Werror'
    '-static', '-static-libgcc', '-static-libstdc++'
    '-fno-exceptions', '-fno-rtti'
    # The two values sc_buildid.cpp turns into the embedded stamp. Quoted -D args
    # reach a native command intact under PowerShell 7.3+ (measured on this
    # machine, pwsh 7.6.4); if a shell ever stops doing so, Assert-BuildStamp
    # below FAILS THE BUILD rather than shipping a DLL that says UNSTAMPED.
    "-DSC_BUILD_ID=`"$($identity.BuildId)`""
    "-DSC_BUILD_SRC=`"$srcDigest`""
    # Unpinned, two builds of one tree differ in 6705 bytes: the PE TimeDateStamp,
    # which the linker fills with the wall clock, and the IMAGE BASE, which
    # binutils picks per link for a DLL -- 0x6A980000 and 0x711C0000 on two
    # consecutive builds here -- moving every relocated address and accounting for
    # nearly all 6705 bytes. Pinning both makes the build byte-reproducible
    # (measured: two builds of one tree, identical SHA256), which is what lets a
    # DLL hash mean anything. It does NOT replace the stamp: a hash still needs a
    # table to map it back to a tree, the stamp needs nothing.
    '-Wl,--no-insert-timestamp'
)
if ($DebugBuild) { $common += @('-O0', '-g') } else { $common += @('-O2', '-s') }

# DLL only; scinject.exe keeps the standard EXE base.
#
# 0x71000000, NOT the conventional 0x10000000: WMode.dll is early-injected into
# this game before the plugin on every windowed launch and it sits AT 0x10000000
# (scinject prints that HMODULE as it early-injects it), so a plugin based there
# is relocated by the loader every run and the file's fixed base is a fiction the
# moment it loads -- two builds would then hash identically while claiming a
# determinism the running image does not have.
# 0x71xxxxxx is free by demonstration, not assumption: every plugin base binutils
# has picked on this machine landed in 0x71000000-0x73FFFFFF and the loader
# honoured all of them (0x71E50000, 0x724A0000, 0x73360000, each stable across
# every run of its own build). The ATTACH banner prints where the DLL actually
# landed against the base in its own PE header, so "the pinned base took" is a
# read-back rather than a hope.
$dllLink = @('-Wl,--image-base=0x71000000')

$dllOut  = Join-Path $OutDir 'scplugin.dll'
$exeOut  = Join-Path $OutDir 'scinject.exe'
$testOut = Join-Path $OutDir 'hooktest.exe'

$pluginSrc = @('scplugin.cpp', 'sc_log.cpp', 'sc_engine.cpp', 'sc_hook.cpp', 'sc_fanout.cpp', 'sc_circles.cpp', 'sc_hudrow.cpp', 'sc_prodqueue.cpp', 'sc_card.cpp', 'sc_upgrades.cpp', 'sc_prodfan.cpp', 'sc_queueind.cpp', 'sc_screen.cpp', 'sc_buildid.cpp', 'sc_session.cpp', 'sc_console.cpp', 'sc_stormpresent.cpp') |
             ForEach-Object { Join-Path $srcDir $_ }
$testSrc   = @('hooktest.cpp', 'sc_log.cpp', 'sc_engine.cpp', 'sc_hook.cpp', 'sc_fanout.cpp', 'sc_circles.cpp', 'sc_hudrow.cpp', 'sc_prodqueue.cpp', 'sc_card.cpp', 'sc_upgrades.cpp', 'sc_prodfan.cpp', 'sc_queueind.cpp', 'sc_screen.cpp', 'sc_session.cpp') |
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
    # The mechanism rests on a define surviving a shell, a compiler and a linker
    # into a string in .rdata, and each of those can drop or mangle it: a -D
    # argument that reaches g++ with a stray backslash produces no stamp at all.
    # Printing $identity here instead of the file's own bytes would report such a
    # build as stamped. See AGENTS.md § "Oracles: absence and defect-era checks".
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
