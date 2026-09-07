#Requires -Version 7
<#
.SYNOPSIS
Fetches the cnc-ddraw release DLL to an IGNORED path outside the repo.

.DESCRIPTION
cnc-ddraw (github.com/FunkyFr3sh/cnc-ddraw, MIT) presents the full ddraw surface
the game asks for -- the replacement candidate for WMode.dll's measured
640-column crop (research/renderer-viewport.md 12.6, 13.4). Never committed: a
game-adjacent third-party binary (AGENTS.md § "Hard rules"), so it lands under
C:\sc-work\. Nothing here builds third-party C sources, so the release asset is
taken as-is and the pinned SHA256 below -- not a source build -- is what verifies
it.

.EXAMPLE
./tools/plugin/fetch-cnc-ddraw.ps1
# prints the provenance block and the extracted ddraw.dll path
#>
[CmdletBinding()]
param(
    [string]$Version = 'v7.1.0.0',
    [string]$DestRoot = 'C:\sc-work\cnc-ddraw',
    # A mismatch is a HARD STOP: an artifact that changed under a fixed version tag
    # needs re-review, never a silent re-pin. Other versions have no pin to check.
    [string]$ExpectedZipSha256 = '0b13ab89a64c9918189b1dadd449ef6ed3cb3b7b19cabd96d8adbd95505bb908'
)

$ErrorActionPreference = 'Stop'

$dest = Join-Path $DestRoot $Version
$zip = Join-Path $dest 'cnc-ddraw.zip'
$dll = Join-Path $dest 'ddraw.dll'
$url = "https://github.com/FunkyFr3sh/cnc-ddraw/releases/download/$Version/cnc-ddraw.zip"

New-Item -ItemType Directory -Path $dest -Force | Out-Null

if (-not (Test-Path -LiteralPath $zip)) {
    Write-Host "fetch-cnc-ddraw: downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $zip
}
else { Write-Host "fetch-cnc-ddraw: using existing $zip" }

$zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($Version -eq 'v7.1.0.0' -and $ExpectedZipSha256 -notmatch '^<') {
    if ($zipHash -ne $ExpectedZipSha256.ToLowerInvariant()) {
        throw "fetch-cnc-ddraw: SHA256 MISMATCH for $zip`n  expected $ExpectedZipSha256`n  got      $zipHash`nThe upstream artifact changed; do not use it without re-review."
    }
    Write-Host 'fetch-cnc-ddraw: zip SHA256 matches the pinned value'
}

Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
if (-not (Test-Path -LiteralPath $dll)) { throw "fetch-cnc-ddraw: $dll not in the archive" }

# StarCraft.exe is x86; a wrong-arch proxy fails at LoadLibrary with nothing on
# screen. Check the PE machine field (0x14C = i386) rather than finding out live.
$bytes = [System.IO.File]::ReadAllBytes($dll)
$peOff = [BitConverter]::ToInt32($bytes, 0x3C)
$machine = [BitConverter]::ToUInt16($bytes, $peOff + 4)
if ($machine -ne 0x14C) { throw ("fetch-cnc-ddraw: ddraw.dll PE machine=0x{0:X} -- not x86 (0x14C)" -f $machine) }

$dllHash = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host 'fetch-cnc-ddraw: PROVENANCE'
Write-Host "  version    $Version"
Write-Host "  url        $url"
Write-Host "  zip sha256 $zipHash"
Write-Host "  dll sha256 $dllHash"
Write-Host "  dll        $dll (x86 PE confirmed)"
[pscustomobject]@{ Version = $Version; Url = $url; ZipSha256 = $zipHash; DllSha256 = $dllHash; DllPath = $dll }
