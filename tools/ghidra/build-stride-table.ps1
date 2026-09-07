#Requires -Version 7
<#
.SYNOPSIS
Turns the raw StrideSweep output into the committed table of ENCODED row strides.

.DESCRIPTION
Widening playersSelections past 12 slots means editing every row step, but a row step carries
its stride only in scale factors -- invisible to the cross-reference sweep (instructions naming
an address) and to the immediate sweep (instructions carrying a watched constant):

    0049AFB5   LEA EDX,[EDI + EDI*0x2]      ; player * 3
    0049AFB8   LEA EAX,[EBX + EDX*0x4]      ; slot + player * 12
    0049AFBB   MOV dword ptr [EAX*0x4 + 0x6284e8],ESI

.PARAMETER InFile
StrideSweep TSV (work/scratch/ghidra-sweep/strides.tsv).

.PARAMETER OutFile
Destination TSV (research/data/selection-strides.tsv).
#>
param(
    [Parameter(Mandatory)][string]$InFile,
    [Parameter(Mandatory)][string]$OutFile
)

$ErrorActionPreference = 'Stop'

$all = Import-Csv -LiteralPath $InFile -Delimiter "`t"
if ($all.Count -lt 1) { throw "stride sweep file parsed to $($all.Count) rows: $InFile" }

# x3 is the compiler's idiom for every 3-, 6-, 12- and 24-byte struct in the binary, so a chain
# with no connection to a selection global is noise by construction: counted, never committed.
$relevant = @($all | Where-Object { $_.context -ne 'elsewhere' })
$dropped = $all.Count - $relevant.Count

$rows = $relevant | ForEach-Object {
    [pscustomobject]@{
        array          = if ($_.targetGlobal) { $_.targetGlobal } else { 'unresolved' }
        # 48 bytes = 12 dwords = one selection row, so this is the column to filter on. Other
        # strides stay in the table: an x12 chain that is NOT a row step is a near-miss a reader
        # must be able to check rather than take on trust.
        isRowStride    = ($_.strideBytes -eq '48')
        strideBytes    = $_.strideBytes
        strideElements = $_.strideElements
        funcEntry      = $_.funcEntry
        funcName       = $_.funcName
        seedAddr       = $_.seedAddr
        seedIns        = $_.seedIns
        chainAddrs     = $_.chainAddrs
        chainIns       = $_.chainIns
        consumerAddr   = $_.consumerAddr
        consumerIns    = $_.consumerIns
        chainEnd       = $_.terminated
        context        = $_.context
    }
}

$sorted = $rows | Sort-Object array, { [Convert]::ToInt64((([string]$_.seedAddr) -replace '^0x', ''), 16) }

$outDir = Split-Path $OutFile -Parent
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$sorted | Export-Csv -LiteralPath $OutFile -Delimiter "`t" -NoTypeInformation -UseQuotes AsNeeded

Write-Host "build-stride-table.ps1: $($sorted.Count) rows -> $OutFile"
Write-Host "  x3 chains found program-wide      : $($all.Count)"
Write-Host "  dropped (context=elsewhere)       : $dropped"
$sorted | Group-Object array | Sort-Object Name | ForEach-Object {
    $rowStrides = @($_.Group | Where-Object { $_.isRowStride }).Count
    Write-Host ("  {0,-24} chains={1,3}  row strides (48 B)={2}" -f $_.Name, $_.Count, $rowStrides)
}
$unresolved = @($sorted | Where-Object { $_.isRowStride -and $_.array -eq 'unresolved' }).Count
Write-Host "  row strides with no resolved target array: $unresolved"
