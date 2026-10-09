#Requires -Version 7
<#
.SYNOPSIS
Every check that gates a merge, in order: .ps1 parse, Pester, the game-content guard,
tools/*.py byte-compile, the reuse gate, the comment-narration gate. CI runs it through
test.sh, so a green run here is a green CI. Needs Pester 5 (setup-onetime.ps1), python and
Node's npx on PATH.
#>
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$files = git ls-files '*.ps1'
$failed = $false
foreach ($f in $files) {
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $PSScriptRoot $f), [ref]$null, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -gt 0) {
        $failed = $true
        Write-Host "::error file=$f::Parse errors in $f"
        foreach ($e in $parseErrors) {
            Write-Host "  line $($e.Extent.StartLineNumber): $($e.Message)"
        }
    }
}
if ($failed) { throw 'One or more PowerShell files failed to parse' }
Write-Host "Parsed $($files.Count) .ps1 files OK"

Import-Module Pester -MinimumVersion 5.0.0
Invoke-Pester -Path tests -CI

# Project hard rule 1: never commit game binaries, archives or maps (a generated fixture
# is an edited copy of a Blizzard map); a size cap catches large binary blobs of other
# extensions too.
$bannedExt = @('.exe', '.dll', '.mpq', '.snp', '.grp', '.chk', '.rep', '.idb', '.i64', '.gpr', '.scm', '.scx')
$maxBytes = 5MB
$tracked = git ls-files
$badExt = $tracked | Where-Object {
    $bannedExt -contains ([System.IO.Path]::GetExtension($_).ToLowerInvariant())
}
$badSize = @()
foreach ($f in $tracked) {
    if ((Test-Path -LiteralPath $f -PathType Leaf) -and ((Get-Item -LiteralPath $f).Length -gt $maxBytes)) {
        $badSize += $f
    }
}
$bad = @($badExt) + @($badSize) | Select-Object -Unique
if ($bad.Count -gt 0) {
    foreach ($f in $bad) { Write-Host "::error file=$f::tracked game-content or oversized binary file" }
    throw "Tracked game-content/binary files found: $($bad -join ', ')"
}
Write-Host 'No tracked game-content files found'

# Only from here: the Pester suites run failing interpreters on purpose and read
# $LASTEXITCODE themselves.
$PSNativeCommandUseErrorActionPreference = $true
python -m compileall -q tools
# Fails only on duplication NOT already in a tools/check-reuse.*.baseline: "no new copies".
# The block scan is jscpd through npx; tests/check-reuse.Tests.ps1 covers the checker.
python tools/check-reuse.py
# Comments state a why, not history (AGENTS.md § "Comments"). --selftest runs the
# checker's own negative control first, so a checker that stopped matching anything
# cannot pass by finding nothing.
python tools/check-comment-narration.py --selftest
python tools/check-comment-narration.py
