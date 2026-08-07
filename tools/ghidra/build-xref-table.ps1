#Requires -Version 7
<#
.SYNOPSIS
Merges the two XrefSweep passes into the committed per-instruction cross-reference table.

.DESCRIPTION
XrefSweep writes two files and NEITHER is the answer on its own:

  <out>.tsv            pass 1 -- Ghidra's Reference database. One row per (reference, target
                       byte). Rich: knows the containing function and the reference type. But
                       it misses instruction forms Ghidra declines to reference -- on this
                       binary, `MOV dword ptr [EDX*0x4 + 0x6284e8],ESI` at 0x004C26B6 writes
                       into playersSelections and produced no reference at all.

  <out>.rawhits.tsv    pass 2 -- every little-endian dword in initialized memory whose VALUE
                       lands in a swept range, classified COVERED/UNCOVERED against pass 1.
                       Finds the encoded address regardless of disassembly, but knows nothing
                       about it.

This script folds pass 1 down to one row per (global, instruction) -- collapsing the per-byte
rows into the set of array element indices that instruction touches -- and then appends the
UNCOVERED pass-2 hits that live in executable memory, so the committed table is the union
rather than either half. Rows carry `discovery` so a reader can tell which pass found them.

Pass-2 hits in .rsrc (icon/dialog bitmaps) and in .rdata/.data string tables are byte
coincidences, not references, and are dropped -- with a count reported so the drop is visible
rather than silent.

.PARAMETER SweepDir
Directory holding the XrefSweep output (xrefs2.tsv and xrefs2.tsv.rawhits.tsv by default).

.PARAMETER Pass1
Pass-1 TSV path. Default: <SweepDir>/xrefs2.tsv

.PARAMETER OutFile
Destination TSV. Default: research/data/selection-xrefs.tsv relative to the repo root.

.EXAMPLE
./tools/ghidra/build-xref-table.ps1 -SweepDir work/scratch/ghidra-sweep `
    -OutFile research/data/selection-xrefs.tsv
#>
param(
    [Parameter(Mandatory)][string]$SweepDir,
    [string]$Pass1,
    [Parameter(Mandatory)][string]$OutFile
)

$ErrorActionPreference = 'Stop'

if (-not $Pass1) { $Pass1 = Join-Path $SweepDir 'xrefs2.tsv' }
$rawPath = $Pass1 + '.rawhits.tsv'
foreach ($p in @($Pass1, $rawPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "missing sweep output: $p" }
}

# NOT $pass1: PowerShell variable names are case-insensitive, so `$pass1` IS the `[string]$Pass1`
# parameter. Assigning the imported rows to it silently COERCES them to a single string, and the
# script then "succeeds" with one meaningless row instead of failing.
$refRows = Import-Csv -LiteralPath $Pass1 -Delimiter "`t"
$raw = Import-Csv -LiteralPath $rawPath -Delimiter "`t"
if ($refRows.Count -lt 1) { throw "pass-1 file parsed to $($refRows.Count) rows: $Pass1" }

$rows = [System.Collections.Generic.List[object]]::new()

# Pass 1: collapse the per-target-byte rows into one row per (global, instruction).
$pass1Groups = @($refRows | Group-Object -Property label, fromAddr)
foreach ($g in $pass1Groups) {
    $first = $g.Group[0]
    $elems = @($g.Group | ForEach-Object { [int]$_.elemIndex } | Sort-Object -Unique)
    $types = @($g.Group | ForEach-Object { $_.refType } | Sort-Object -Unique)
    # Not every Ghidra reference comes from an instruction. A DEFINED POINTER DATUM whose value
    # happens to land in a swept range produces one too, and Ghidra renders it "addr XXXXXXXX".
    # Both such rows here sit in .rdata inside a virtual-key table and are byte coincidences
    # against the 6912-byte selection_hotkeys span. Kept in the table but marked, so the
    # instruction count stays a count of instructions.
    $isDataPointer = $first.instruction -match '^addr\s'
    $rows.Add([pscustomobject]@{
            global      = $first.label
            insAddr     = $first.fromAddr
            funcEntry   = $first.funcEntry
            refType     = ($types -join '|')
            elemIndices = ($elems -join ',')
            elemCount   = $elems.Count
            firstTarget = ($g.Group | Sort-Object { [int]$_.byteOffset } | Select-Object -First 1).targetAddr
            instruction = $first.instruction
            discovery   = if ($isDataPointer) { 'data-pointer-not-instruction' } else { 'ghidra-ref' }
        })
}

# Pass 2: the blind spots. Only executable memory -- a dword in .rsrc or a string table that
# happens to equal a global's address is a coincidence, not a reference.
$uncovered = @($raw | Where-Object { $_.coverage -eq 'UNCOVERED' })
$droppedNonText = @($uncovered | Where-Object { $_.block -ne '.text' })
foreach ($h in $uncovered | Where-Object { $_.block -eq '.text' }) {
    $rows.Add([pscustomobject]@{
            global      = $h.label
            insAddr     = if ($h.codeUnitAddr) { $h.codeUnitAddr } else { $h.atAddr }
            funcEntry   = $h.funcEntry
            refType     = 'UNCLASSIFIED'
            elemIndices = [string]([int]([int]$h.byteOffsetInRange / 4))
            elemCount   = 1
            firstTarget = $h.encodedValue
            instruction = $h.codeUnit
            discovery   = 'raw-dword-only'
        })
}

$sorted = $rows | Sort-Object global, {
    $h = ([string]$_.insAddr) -replace '^0x', ''
    if ([string]::IsNullOrWhiteSpace($h)) { [long]0 } else { [Convert]::ToInt64($h, 16) }
}

$outDir = Split-Path $OutFile -Parent
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$sorted | Export-Csv -LiteralPath $OutFile -Delimiter "`t" -NoTypeInformation -UseQuotes Never

Write-Host "build-xref-table.ps1: $($sorted.Count) rows -> $OutFile"
Write-Host "  pass-1 (ghidra-ref)     : $(($sorted | Where-Object discovery -eq 'ghidra-ref').Count)"
Write-Host "  pass-2 (raw-dword-only) : $(($sorted | Where-Object discovery -eq 'raw-dword-only').Count)"
Write-Host "  dropped as data coincidences (non-.text UNCOVERED hits): $($droppedNonText.Count)"
$sorted | Group-Object global | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,-24} instructions={1}" -f $_.Name, $_.Count)
}
