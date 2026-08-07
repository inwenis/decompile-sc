#Requires -Version 7
<#
.SYNOPSIS
    Creates a patchable working copy of a StarCraft 1.16.1 install, verifying
    integrity against known-good fingerprints before and after the copy.

.DESCRIPTION
    Copies -Source (a pristine, read-only StarCraft install) to -Destination
    (a scratch area OUTSIDE any git repo) via robocopy /MIR, then verifies:
      - sha256 of StarCraft.exe and storm.dll in the SOURCE match the known
        fingerprint (catches a corrupted/tampered source before we trust it)
      - sha256 of StarCraft.exe and storm.dll in the DESTINATION match the
        same fingerprint (catches a corrupted copy)
      - battle.snp size matches in both source and destination
      - recursive file count and total size match between source and
        destination exactly, and are close to the documented whole-install
        baseline (242 files, ~1068 MB)

    Refuses to run if -Destination already exists, unless -Force is passed
    (in which case robocopy /MIR re-syncs it — safe to re-run any time).
    Never writes to -Source.

.EXAMPLE
    ./tools/make-working-copy.ps1
    ./tools/make-working-copy.ps1 -Force
    ./tools/make-working-copy.ps1 -Source D:\sc-install\Starcraft -Destination D:\sc-work\1161-base
#>

[CmdletBinding()]
param(
    [string]$Source = 'C:\sc-install\Starcraft',
    [string]$Destination = 'C:\sc-work\1161-base',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Known-good fingerprint for the 1.16.1 install (see research/pe-anatomy.md).
$ExpectedHashes = @{
    'StarCraft.exe' = 'AD6B58B27B8948845CCFA69BCFCC1B10D6AA7A27A371EE3E61453925288C6A46'
    'storm.dll'     = '706FF2164CA472F27C44235ED55586644E5C86E68CD69B62D76F5A78778BFF25'
}
$ExpectedSnpSize = 557310
$ExpectedFileCountApprox = 242
$ExpectedTotalBytesApprox = 1068MB

# robocopy /MIR deletes anything in -Destination not present in -Source. A
# mistyped -Destination combined with -Force would silently wipe whatever
# lives there. Only allow /MIR against a destination that is empty, already
# looks like a StarCraft install, or sits under a known scratch root.
$KnownScratchRoots = @('C:\sc-work')

function Test-SafeMirrorDestination {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
    foreach ($root in $KnownScratchRoots) {
        $rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
        if ($full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    if (Test-Path (Join-Path $Path 'StarCraft.exe')) {
        return $true
    }
    $existingItems = Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue
    return (-not $existingItems)
}

function Get-Sha256 {
    param([string]$Path)
    (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Test-KeyBinaries {
    param([string]$Root, [string]$Label)
    $ok = $true
    foreach ($name in $ExpectedHashes.Keys) {
        $path = Join-Path $Root $name
        if (-not (Test-Path $path)) {
            Write-Warning "[$Label] missing: $path"
            $ok = $false
            continue
        }
        $actual = Get-Sha256 -Path $path
        $expected = $ExpectedHashes[$name]
        if ($actual -ne $expected) {
            Write-Warning "[$Label] $name sha256 MISMATCH`n  expected: $expected`n  actual:   $actual"
            $ok = $false
        } else {
            Write-Host "[$Label] $name sha256 OK ($actual)"
        }
    }
    $snpPath = Join-Path $Root 'battle.snp'
    if (-not (Test-Path $snpPath)) {
        Write-Warning "[$Label] missing: $snpPath"
        $ok = $false
    } else {
        $snpSize = (Get-Item $snpPath).Length
        if ($snpSize -ne $ExpectedSnpSize) {
            Write-Warning "[$Label] battle.snp size MISMATCH expected=$ExpectedSnpSize actual=$snpSize"
            $ok = $false
        } else {
            Write-Host "[$Label] battle.snp size OK ($snpSize bytes)"
        }
    }
    return $ok
}

function Get-DirStats {
    param([string]$Root)
    $files = Get-ChildItem -Path $Root -Recurse -File -Force
    [PSCustomObject]@{
        Count = $files.Count
        Bytes = ($files | Measure-Object -Property Length -Sum).Sum
    }
}

if (-not (Test-Path $Source)) {
    throw "Source does not exist: $Source"
}

Write-Host "== Verifying SOURCE integrity: $Source =="
$sourceOk = Test-KeyBinaries -Root $Source -Label 'source'
if (-not $sourceOk) {
    throw "Source failed integrity check against known-good fingerprint. Refusing to copy from a source that does not match research/pe-anatomy.md. Do not modify $Source."
}

if (Test-Path $Destination) {
    if (-not $Force) {
        throw "Destination already exists: $Destination`nPass -Force to re-sync it (robocopy /MIR), or choose a different -Destination."
    }
    if (-not (Test-SafeMirrorDestination -Path $Destination)) {
        throw "Refusing to robocopy /MIR into $Destination -- it is not empty, does not look like a StarCraft install (no StarCraft.exe found), and is not under a known scratch root ($($KnownScratchRoots -join ', ')). /MIR deletes anything in the destination not present in the source; this guards against wiping a mistyped -Destination. Pass a different -Destination, or empty this one first if you're sure."
    }
    Write-Host "Destination exists, -Force passed: re-syncing via robocopy /MIR."
} else {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

Write-Host "== Copying $Source -> $Destination (robocopy /MIR) =="
$robocopyArgs = @(
    $Source, $Destination,
    '/MIR',      # mirror: idempotent re-run, removes stray files no longer in source
    '/COPY:DAT', # data, attributes, timestamps (no ACLs/owner - avoids needing elevated perms)
    '/R:2', '/W:2',
    '/NFL', '/NDL', '/NP'
)
& robocopy @robocopyArgs | Out-Host
# robocopy exit codes 0-7 are success (see docs); >=8 is a real failure.
if ($LASTEXITCODE -ge 8) {
    throw "robocopy failed with exit code $LASTEXITCODE"
}
Write-Host "robocopy exit code $LASTEXITCODE (success)"

Write-Host "== Verifying DESTINATION integrity: $Destination =="
$destOk = Test-KeyBinaries -Root $Destination -Label 'dest'

Write-Host "== Comparing file count / total size =="
$srcStats = Get-DirStats -Root $Source
$dstStats = Get-DirStats -Root $Destination
Write-Host ("source:      {0} files, {1:N1} MB" -f $srcStats.Count, ($srcStats.Bytes / 1MB))
Write-Host ("destination: {0} files, {1:N1} MB" -f $dstStats.Count, ($dstStats.Bytes / 1MB))

$statsOk = $true
if ($srcStats.Count -ne $dstStats.Count -or $srcStats.Bytes -ne $dstStats.Bytes) {
    Write-Warning "File count/size MISMATCH between source and destination."
    $statsOk = $false
}
if ([Math]::Abs($srcStats.Count - $ExpectedFileCountApprox) -gt 5) {
    Write-Warning "Source file count ($($srcStats.Count)) drifted from documented baseline (~$ExpectedFileCountApprox). Update research/pe-anatomy.md context if this is expected."
}
if ([Math]::Abs($srcStats.Bytes - $ExpectedTotalBytesApprox) -gt 50MB) {
    Write-Warning "Source total size ($([Math]::Round($srcStats.Bytes/1MB,1)) MB) drifted from documented baseline (~$([Math]::Round($ExpectedTotalBytesApprox/1MB,0)) MB)."
}

if (-not ($sourceOk -and $destOk -and $statsOk)) {
    throw "Integrity verification FAILED. See errors above. Working copy at $Destination should not be trusted."
}

Write-Host ""
Write-Host "OK: working copy verified at $Destination"
exit 0
