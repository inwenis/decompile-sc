#Requires -Version 7
<#
.SYNOPSIS
Download, verify and unpack the pinned 32-bit MinGW-w64 toolchain build.ps1 expects.

.DESCRIPTION
Idempotent: a present g++.exe under -InstallRoot means nothing to do. The install lives
outside every worktree (tools/plugin/README.md "Toolchain (pinned)"): it is gitignored,
so pruning a worktree that held it would delete it with no warning. Provenance and the
sha256 (GitHub's own digest for the release asset) are in that README's table; a mismatch
deletes the download and stops, because an artifact that changed under a fixed tag needs
re-review, never a re-pin.

.EXAMPLE
./tools/plugin/install-toolchain.ps1
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\re-tools\mingw32-gcc-16.1.0-i686-msvcrt',
    [string]$Url = 'https://github.com/brechtsanders/winlibs_mingw/releases/download/16.1.0posix-14.0.0-msvcrt-r4/winlibs-i686-posix-dwarf-gcc-16.1.0-mingw-w64msvcrt-14.0.0-r4.zip',
    [string]$ExpectedSha256 = 'a5817469f554314b03cd5298c0b247057d7a7da5b85a01d89d9fc9feb7adbc19'
)
$ErrorActionPreference = 'Stop'

$gpp = Join-Path $InstallRoot 'mingw32\bin\g++.exe'
if (Test-Path -LiteralPath $gpp) {
    Write-Host "install-toolchain: already present: $gpp"
    exit 0
}

$zip = Join-Path ([IO.Path]::GetTempPath()) (Split-Path $Url -Leaf)
if (-not (Test-Path -LiteralPath $zip)) {
    Write-Host "install-toolchain: downloading $Url (~283 MB)"
    # Invoke-WebRequest's progress bar makes a large download several times slower.
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $zip
}
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -ne $ExpectedSha256) {
    Remove-Item -LiteralPath $zip -Force
    throw "install-toolchain: sha256 mismatch for $zip`n  expected $ExpectedSha256`n  got      $hash`nThe download was deleted."
}
Write-Host "install-toolchain: sha256 OK, unpacking to $InstallRoot"
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
# 7z unpacks the 20k-file zip in seconds; Expand-Archive takes minutes. Both give the same tree.
$sevenZip = Get-Command 7z -ErrorAction SilentlyContinue
if ($sevenZip) {
    & $sevenZip.Source x $zip "-o$InstallRoot" -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "install-toolchain: 7z exited $LASTEXITCODE" }
}
else {
    Expand-Archive -LiteralPath $zip -DestinationPath $InstallRoot
}
if (-not (Test-Path -LiteralPath $gpp)) { throw "install-toolchain: unpacked, but $gpp is not there" }
Remove-Item -LiteralPath $zip -Force
Write-Host "install-toolchain: OK $gpp"
& $gpp --version | Select-Object -First 1
