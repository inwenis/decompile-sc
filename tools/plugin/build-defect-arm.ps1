#Requires -Version 7
<#
.SYNOPSIS
Build a baseline arm and a patched arm, and report every hooktest check whose verdict moved.

.DESCRIPTION
Builds two throwaway copies of tools/plugin -- baseline and defect (one patch applied) --
runs build.ps1 -Test on each (hooktest.exe, no game) and prints every check whose verdict
CHANGED. A check that stays green while the code under it is broken was never testing that
code, so an unchanged verdict is a finding about the suite, not a pass for the patch.
Measured this way, one real defect build moved 28 balance checks to FAIL while every
"spent NOTHING" check stayed green -- that family of checks was never testing its code.
Both arms are copies: Get-ScSourceDigest over the real tools/plugin/src is taken around the
run, and the run throws if it differs.

.EXAMPLE
./tools/plugin/build-defect-arm.ps1 -Patch work/defects/prodqueue-cap-off-by-slots.patch
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Patch,
    [string]$Name = [IO.Path]::GetFileNameWithoutExtension($Patch),
    [string]$ToolchainBin
)

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$repoRoot  = (Resolve-Path (Join-Path $scriptDir '..' '..')).Path
. (Join-Path $scriptDir 'sc-build-id.ps1')   # Get-ScSourceDigest

$patchPath = (Resolve-Path -LiteralPath $Patch).Path
$realSrc   = Join-Path $repoRoot 'tools/plugin/src'
$realBuild = Join-Path $repoRoot 'tools/plugin/build.ps1'
$digestBefore = Get-ScSourceDigest -SrcDir $realSrc -BuildScript $realBuild

$armsRoot = Join-Path $repoRoot "work/scratch/defect-arm/$Name"
Remove-Item -LiteralPath $armsRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $armsRoot -Force | Out-Null

function Build-Arm {
    param([string]$ArmName, [string]$ApplyPatch)
    $copyRoot = Join-Path $armsRoot $ArmName
    Copy-Item -LiteralPath (Join-Path $repoRoot 'tools/plugin') -Destination (Join-Path $copyRoot 'tools/plugin') -Recurse
    if ($ApplyPatch) {
        & git -C $copyRoot apply --whitespace=nowarn -- $ApplyPatch
        if ($LASTEXITCODE -ne 0) { throw "defect-arm: '$ApplyPatch' did not apply cleanly against a fresh copy of tools/plugin -- regenerate it against the current tree." }
        Write-Host "defect-arm: $ArmName arm patched with $ApplyPatch"
    }
    $log = Join-Path $copyRoot 'hooktest.log'
    $buildArgs = @('-OutDir', (Join-Path $copyRoot 'out'), '-Test')
    if ($ToolchainBin) { $buildArgs += @('-ToolchainBin', $ToolchainBin) }
    & pwsh -NoProfile -File (Join-Path $copyRoot 'tools/plugin/build.ps1') @buildArgs *> $log
    $text = Get-Content -LiteralPath $log -Raw
    if ($text -notmatch 'hooktest: \d+ failure') {
        throw "defect-arm: $ArmName arm never reached hooktest's own summary line (build failure or crash) -- see $log`n$((Get-Content -LiteralPath $log -Tail 25) -join "`n")"
    }
    return $text
}

Write-Host "defect-arm: building baseline (unpatched) ..."
$baseText = Build-Arm -ArmName 'baseline'
Write-Host "defect-arm: building defect ($Name) ..."
$defText  = Build-Arm -ArmName 'defect' -ApplyPatch $patchPath

# Verdicts are compared by position: both arms run the same Check() sequence, so index i is
# the same check -- unless the patch changed control flow, which the count check below catches
# rather than silently misaligning.
function Get-HooktestChecks {
    param([string]$Text)
    $part = '(none)'
    $checks = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\[\d+\]\s+(.+)$') { $part = $Matches[1]; continue }
        if ($line -match '^\s*(ok|FAIL)\s+(.*?)\s+=\s+-?\d+') {
            $checks.Add([pscustomobject]@{ Part = $part; What = $Matches[2]; Status = $Matches[1] })
        }
    }
    return $checks
}

$baseChecks = @(Get-HooktestChecks $baseText)
$defChecks  = @(Get-HooktestChecks $defText)
$baseFail   = @($baseChecks | Where-Object Status -eq 'FAIL').Count
$defFail    = @($defChecks  | Where-Object Status -eq 'FAIL').Count
Write-Host "`ndefect-arm: baseline $($baseChecks.Count) checks, $baseFail failure(s)"
Write-Host "defect-arm: defect   $($defChecks.Count) checks, $defFail failure(s)"
if ($baseChecks.Count -ne $defChecks.Count) {
    Write-Host "defect-arm: CHECK COUNT DIFFERS ($($baseChecks.Count) vs $($defChecks.Count)) -- the patch changed control flow, not just a value. Comparing only the common prefix."
}
$n = [Math]::Min($baseChecks.Count, $defChecks.Count)

$changed = @(0..($n - 1) | Where-Object { $baseChecks[$_].Status -ne $defChecks[$_].Status } | ForEach-Object {
    [pscustomobject]@{ Part = $baseChecks[$_].Part; What = $baseChecks[$_].What; Before = $baseChecks[$_].Status; After = $defChecks[$_].Status }
})

if (-not $changed) {
    Write-Host "`ndefect-arm: NO check's verdict changed. This patch is INVISIBLE to hooktest -- that is a finding about the suite, not a clean bill of health for the patch."
} else {
    foreach ($p in @($changed.Part | Select-Object -Unique)) {
        Write-Host "`n=== $p ==="
        Write-Host "CAUGHT it (verdict changed):"
        $changed | Where-Object Part -eq $p | ForEach-Object { Write-Host ("  {0,-4} -> {1,-4} {2}" -f $_.Before, $_.After, $_.What) }
        $missed = 0..($n - 1) | Where-Object { $baseChecks[$_].Part -eq $p -and $baseChecks[$_].Status -eq $defChecks[$_].Status }
        if ($missed) {
            Write-Host "did NOT catch it (same part, unchanged):"
            $missed | ForEach-Object { Write-Host ("  {0,-4}       {1}" -f $baseChecks[$_].Status, $baseChecks[$_].What) }
        }
    }
}

$digestAfter = Get-ScSourceDigest -SrcDir $realSrc -BuildScript $realBuild
if ($digestBefore -ne $digestAfter) {
    throw "defect-arm: the REAL tree changed during this run (src digest $digestBefore -> $digestAfter). This must never happen."
}
Write-Host "`ndefect-arm: real tools/plugin/src untouched -- digest $digestBefore before and after"
$porcelain = @(& git -C $repoRoot status --porcelain -- tools/plugin)
Write-Host "defect-arm: git status --porcelain -- tools/plugin : $(if ($porcelain) { $porcelain -join '; ' } else { '(clean)' })"
