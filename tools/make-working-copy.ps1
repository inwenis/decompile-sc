#Requires -Version 7
<#
.SYNOPSIS
    Creates a patchable working copy of a StarCraft 1.16.1 install, verifying
    integrity against known-good fingerprints before and after the copy.
.DESCRIPTION
    -Source is a pristine install; -Destination is scratch space OUTSIDE any
    git repo. Both trees are checked against the known-good fingerprint, so a
    tampered source or a corrupted copy is caught before anything is patched.
    Never writes to -Source; an existing -Destination needs -Force.
.EXAMPLE
    ./tools/make-working-copy.ps1
    ./tools/make-working-copy.ps1 -Force
    ./tools/make-working-copy.ps1 -Force -PurgeExtras
    ./tools/make-working-copy.ps1 -Source D:\sc-install\Starcraft -Destination D:\sc-work\1161-base
#>

[CmdletBinding()]
param(
    [string]$Source = 'C:\sc-install\Starcraft',
    [string]$Destination = 'C:\sc-work\1161-base',
    [switch]$Force,
    # Re-sync as a true mirror: also delete the destination-only files a
    # re-sync keeps by default (see $PreservedExtraPrefixes).
    [switch]$PurgeExtras
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

# Guards a mistyped -Destination: a reset deletes whatever lives there, so
# only an empty, StarCraft-looking, or known-scratch path may be reset.
$KnownScratchRoots = @('C:\sc-work')

# Destination-only paths under these prefixes survive a reset by default: they
# are not part of the pristine install (player profiles in characters\; replays
# and generated test maps from tools/README-test-map.md under Maps\), so keeping
# them cannot affect whether the copy faithfully reproduces the binary.
$PreservedExtraPrefixes = @('characters', 'Maps')

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

# Keys are lowercased: NTFS is case-insensitive, so a source and destination
# path that differ only in case are the same file and must compare equal.
function Get-RelativeInventory {
    param([string]$Root)
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $files = @{}
    $dirs = @{}
    Get-ChildItem -Path $Root -Recurse -Force | ForEach-Object {
        $rel = $_.FullName.Substring($rootFull.Length)
        $key = $rel.ToLowerInvariant()
        if ($_.PSIsContainer) {
            $dirs[$key] = $rel
        } else {
            $files[$key] = [PSCustomObject]@{ Relative = $rel; Bytes = $_.Length }
        }
    }
    [PSCustomObject]@{ Files = $files; Dirs = $dirs }
}

function Test-PreservedExtra {
    param([string]$Relative)
    foreach ($prefix in $PreservedExtraPrefixes) {
        if ($Relative -ieq $prefix -or $Relative -ilike "$prefix\*") { return $true }
    }
    return $false
}

if (-not (Test-Path $Source)) {
    throw "Source does not exist: $Source"
}

Write-Host "== Verifying SOURCE integrity: $Source =="
$sourceOk = Test-KeyBinaries -Root $Source -Label 'source'
if (-not $sourceOk) {
    throw "Source failed integrity check against known-good fingerprint. Refusing to copy from a source that does not match research/pe-anatomy.md. Do not modify $Source."
}
$sourceInventory = Get-RelativeInventory -Root $Source

# Stay empty for a fresh destination: no prior content, nothing to purge.
$purgeFiles = @()
$purgeDirs = @()

if (Test-Path $Destination) {
    if (-not $Force) {
        throw "Destination already exists: $Destination`nPass -Force to re-sync it, or choose a different -Destination."
    }
    if (-not (Test-SafeMirrorDestination -Path $Destination)) {
        throw "Refusing to mirror-reset $Destination -- it is not empty, does not look like a StarCraft install (no StarCraft.exe found), and is not under a known scratch root ($($KnownScratchRoots -join ', ')). A reset deletes anything in the destination not present in the source (or not preserved -- see -PurgeExtras); this guards against wiping a mistyped -Destination. Pass a different -Destination, or empty this one first if you're sure."
    }
    Write-Host "Destination exists, -Force passed: re-syncing."

    $preCopyInventory = Get-RelativeInventory -Root $Destination
    $preserveFiles = @()
    foreach ($key in $preCopyInventory.Files.Keys) {
        if ($sourceInventory.Files.ContainsKey($key)) { continue }
        $entry = $preCopyInventory.Files[$key]
        if (-not $PurgeExtras -and (Test-PreservedExtra -Relative $entry.Relative)) {
            $preserveFiles += $entry
        } else {
            $purgeFiles += $entry
        }
    }
    $preserveDirs = @()
    foreach ($key in $preCopyInventory.Dirs.Keys) {
        if ($sourceInventory.Dirs.ContainsKey($key)) { continue }
        $relative = $preCopyInventory.Dirs[$key]
        if (-not $PurgeExtras -and (Test-PreservedExtra -Relative $relative)) {
            $preserveDirs += $relative
        } else {
            $purgeDirs += $relative
        }
    }

    Write-Host "== Extras in destination not present in source =="
    if ($preserveFiles.Count -gt 0 -or $preserveDirs.Count -gt 0) {
        Write-Host "Preserving $($preserveFiles.Count) file(s), $($preserveDirs.Count) dir(s) -- profile/replay/test-map data, not part of the pristine install:"
        $preserveFiles | ForEach-Object { Write-Host "  keep    $($_.Relative)  ($($_.Bytes) bytes)" }
        $preserveDirs | ForEach-Object { Write-Host "  keep    $_\" }
    }
    if ($purgeFiles.Count -gt 0 -or $purgeDirs.Count -gt 0) {
        $why = if ($PurgeExtras) { '-PurgeExtras: true mirror' } else { 'not under characters\ or Maps\' }
        Write-Host "Removing $($purgeFiles.Count) file(s), $($purgeDirs.Count) dir(s) ($why):"
        $purgeFiles | ForEach-Object { Write-Host "  DELETE  $($_.Relative)  ($($_.Bytes) bytes)" }
        $purgeDirs | ForEach-Object { Write-Host "  DELETE  $_\ (and contents)" }
    } else {
        Write-Host "Nothing to remove."
    }
} else {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

Write-Host "== Copying $Source -> $Destination =="
$robocopyArgs = @(
    $Source, $Destination,
    '/E',        # not /MIR: extras are purged below instead, so what gets
                 # deleted is exactly what the report above listed
    '/COPY:DAT', # no ACLs/owner: copying those would require elevation
    '/R:2', '/W:2',
    '/NFL', '/NDL', '/NP'
)
& robocopy @robocopyArgs | Out-Host
# robocopy exit codes 0-7 are success; >=8 is a real failure.
if ($LASTEXITCODE -ge 8) {
    throw "robocopy failed with exit code $LASTEXITCODE"
}
Write-Host "robocopy exit code $LASTEXITCODE (success)"

if ($purgeFiles.Count -gt 0 -or $purgeDirs.Count -gt 0) {
    Write-Host "== Removing extras reported above =="
    foreach ($f in $purgeFiles) {
        Remove-Item -LiteralPath (Join-Path $Destination $f.Relative) -Force
    }
    foreach ($d in ($purgeDirs | Sort-Object { $_.Length } -Descending)) {
        $p = Join-Path $Destination $d
        if (Test-Path $p) { Remove-Item -LiteralPath $p -Recurse -Force }
    }
    Write-Host "Removed $($purgeFiles.Count) file(s), $($purgeDirs.Count) dir(s)."
}

Write-Host "== Verifying DESTINATION integrity: $Destination =="
$destOk = Test-KeyBinaries -Root $Destination -Label 'dest'

Write-Host "== Comparing file count / total size =="
$srcCount = $sourceInventory.Files.Count
$srcBytes = ($sourceInventory.Files.Values | Measure-Object -Property Bytes -Sum).Sum
$dstInventory = Get-RelativeInventory -Root $Destination
$coreBytesSum = 0
$coreCount = 0
$extraCount = 0
$extraBytesSum = 0
foreach ($key in $dstInventory.Files.Keys) {
    $entry = $dstInventory.Files[$key]
    if ($sourceInventory.Files.ContainsKey($key)) {
        $coreCount++
        $coreBytesSum += $entry.Bytes
    } else {
        $extraCount++
        $extraBytesSum += $entry.Bytes
    }
}
Write-Host ("source:                        {0} files, {1:N1} MB" -f $srcCount, ($srcBytes / 1MB))
Write-Host ("destination (core):            {0} files, {1:N1} MB  <- compared to source below" -f $coreCount, ($coreBytesSum / 1MB))
if ($extraCount -gt 0) {
    Write-Host ("destination (preserved extra): {0} files, {1:N1} MB  <- NOT part of the pristine install; excluded from the comparison below" -f $extraCount, ($extraBytesSum / 1MB))
}

$statsOk = $true
if ($coreCount -ne $srcCount -or $coreBytesSum -ne $srcBytes) {
    Write-Warning "Core file count/size MISMATCH between source and destination (preserved extras excluded from this comparison)."
    $statsOk = $false
}
if ([Math]::Abs($srcCount - $ExpectedFileCountApprox) -gt 5) {
    Write-Warning "Source file count ($srcCount) drifted from documented baseline (~$ExpectedFileCountApprox). Update research/pe-anatomy.md context if this is expected."
}
if ([Math]::Abs($srcBytes - $ExpectedTotalBytesApprox) -gt 50MB) {
    Write-Warning "Source total size ($([Math]::Round($srcBytes/1MB,1)) MB) drifted from documented baseline (~$([Math]::Round($ExpectedTotalBytesApprox/1MB,0)) MB)."
}

if (-not ($sourceOk -and $destOk -and $statsOk)) {
    throw "Integrity verification FAILED. See errors above. Working copy at $Destination should not be trusted."
}

Write-Host ""
Write-Host "OK: working copy verified at $Destination"
exit 0
