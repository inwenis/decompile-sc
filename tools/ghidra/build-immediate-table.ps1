#Requires -Version 7
<#
.SYNOPSIS
Turns the raw ImmediateSweep output into the committed constant inventory, assigning each
occurrence a ROLE.

.DESCRIPTION
The point of the inventory is the role, not the count. `research/selection-cap.md` §7 candidate
5 proposes byte-patching "the immediates 12, 0xC, 0x30" and expects that to fail; whether it
fails depends entirely on what each occurrence DOES. A `MOV ECX,0xc` feeding a REP STOSD is a
buffer length and moving it corrupts memory; a `CMP DL,0xc` on an incoming packet field is a
policy check with no array write behind it. Same number, opposite consequences.

Roles are assigned mechanically from the mnemonic and the OPERAND KIND that ImmediateSweep
recorded at the point of match, so the classification is reproducible rather than an opinion.

The operand kind is not a detail. An x86 instruction can carry a memory displacement and an
immediate at the same time, and round 1 of this task classified on instruction text alone:

    CMP byte ptr [ESI + 0x1],0xc        0x004C275A, in CMDRECV_Select

matched the "has a [reg + 0x..] displacement" rule and was filed as struct-or-stack-offset,
capRelevant=False -- when the watched value here is the 0xc, the cap the received packet count
is checked against, and the 0x1 is just where the count byte sits in the packet. The most
load-bearing site in the inventory was therefore missing from exactly the filter
(capRelevant=True) that a reader would use to find it. The rule now keys off `opKind`: a value
is a displacement only when the sweep says the scalar it matched WAS the displacement.

  loop-bound     value loaded into a register that then drives a counted loop (MOV/LEA form)
  comparison     value is the right-hand side of a CMP/TEST -- a check, not a length
  index-scale    value multiplies or steps an index (IMUL / SUB-stride / SHL on an address)
  array-size     a real buffer extent: a REP STOS element count, or a byte length pushed as a
                 call argument (0x180 = 384 = sizeof(playersSelections))
  and the non-cap roles below, which exist because the same byte values appear constantly in
  code that has nothing to do with selection and must not be mistaken for cap sites:
  struct-or-stack-offset, abi-stack-cleanup (RET 0xc / ADD ESP,0xc / SUB ESP,0xc -- calling
  convention and frame arithmetic), unit-tag-shift, command-id, unrelated-constant

`note` carries what was confirmed by reading the surrounding code; rows without one were
classified by form alone. `capRelevant` is the column to filter on: it marks the occurrences
that actually encode the 12-unit selection limit or an array's extent.

.PARAMETER InFile
ImmediateSweep TSV (work/scratch/ghidra-sweep/immediates.tsv).

.PARAMETER OutFile
Destination TSV (research/data/selection-immediates.tsv).

.PARAMETER Watch
The values ImmediateSweep was told to watch, so this script can report the ones that produced
ZERO rows. An absent constant is a finding -- "0x2C never appears as an immediate" is why the
last element of a 12-pointer array is known to be reached by pointer walking rather than by a
+44 displacement -- and an absence is invisible in the output file by construction. Must match
the sweep's watch list.
#>
param(
    [Parameter(Mandatory)][string]$InFile,
    [Parameter(Mandatory)][string]$OutFile,
    [int[]]$Watch = @(0xc, 0xb, 0x30, 0x2c, 0x12, 0x180, 0x1b00, 0x6c0, 0x360, 0x60)
)

$ErrorActionPreference = 'Stop'

# Per-instruction notes recorded while reading the surrounding disassembly. Anything not listed
# here is classified by form only; that difference is visible in the output.
$notes = @{
    '0x0046F206' = 'SortAllUnits list-full check; JL (SIGNED) at 0x0046F209 -> overflow handler 0x0046F040. GPTP annotates this site as 0x0046F208, which is the address of the 0x0C IMMEDIATE BYTE inside this 3-byte instruction, not of the instruction.'
    '0x0049A857' = 'getActivePlayerNextSelection iterator bound; JC (UNSIGNED) -> returns NULL once selection_iterator reaches 12. selection-cap.md §4.4 calls this loop bound-agnostic; it is not.'
    '0x0049AF89' = 'addUnitToSelectionSlot slot bound; matches GPTP selection_slot < SELECTION_ARRAY_LENGTH.'
    '0x004C256D' = 'CMDRECV_ShiftSelect packet count check; JA (UNSIGNED) -> counts 13..255 all rejected. GPTP types this parameter s8.'
    '0x004C25E0' = 'CMDRECV_ShiftSelect index+count check; JG (SIGNED), matches GPTP index + bCount <= SELECTION_ARRAY_LENGTH.'
    '0x004C275A' = 'CMDRECV_Select packet count check, read straight from the packet byte at +1; JA (UNSIGNED) -> the wire count is unsigned, so the protocol ceiling is 255, not 127.'
    '0x004C2873' = 'CMDRECV_Hotkey group-slot check; JA (UNSIGNED) so slots 0..18 pass, but the per-player stride is 864 = 18 groups (0..17). Slot 18 passes this guard and is outside the array.'
    '0x004C38B3' = 'updateSelectedUnitData: element count of the 12-dword copy activePlayerSelection -> clientSelectionGroup. This is selection-cap.md §8 q4 fixed-size copy #1.'
    '0x004C3909' = 'updateSelectedUnitData single-unit special case: after putting the one unit in slot 0, clear the remaining 11. SELECTION_ARRAY_LENGTH-1.'
    '0x00496D41' = 'selectSingleUnitFromID: per-player stride of selection_hotkeys. 864 = 18 groups x 12 slots x 4 bytes -- binary confirmation of the [8][18][12] shape.'
    '0x00496D61' = 'selectSingleUnitFromID: per-group stride, 48 = 12 slots x 4 bytes.'
    '0x004965A3' = 'REP STOSD element count clearing selection_hotkeys: 1728 dwords = 6912 bytes = 8x18x12x4. Second independent binary confirmation of the array size.'
    '0x004EEC73' = 'REP STOSD element count clearing selection_hotkeys: 1728 dwords = 6912 bytes.'
    '0x0049A32F' = 'REP STOSD element count clearing playersSelections: 96 dwords = 384 bytes = 8x12x4.'
    '0x004EED1F' = 'REP STOSD element count clearing playersSelections: 96 dwords = 384 bytes.'
    '0x004EEDE5' = 'REP STOSD element count clearing playersSelections: 96 dwords = 384 bytes.'
    '0x004C0A9B' = 'Not a selection bound: this is the wire command id 0x0B (SelectRemove/ShiftDeselect) being written into the outgoing command buffer. selection-cap.md §4.3 notes 0x0B rested on screp alone; the binary confirms it.'
    '0x0047B7E7' = 'Not a selection constant: a unit-id comparison inside unit_IsStandardAndMovable.'
    '0x0046F596' = 'Not a selection constant: a struct field read at +0x12.'
}

$sweep = Import-Csv -LiteralPath $InFile -Delimiter "`t"
if (-not ($sweep | Get-Member -Name opKind -MemberType NoteProperty)) {
    throw "$InFile has no opKind column -- it was produced by a pre-round-2 ImmediateSweep.java. Re-run the sweep; classifying without opKind reproduces the displacement/immediate bug."
}

$rows = $sweep | ForEach-Object {
    $ins = $_.instruction
    $val = [int]$_.valueDec
    $mn = $_.mnemonic
    $opKind = $_.opKind

    # Order matters: the non-cap forms are recognised FIRST, because 12 as a struct offset or a
    # stack-cleanup count vastly outnumbers 12 as the selection limit and would otherwise swamp
    # the inventory with false cap sites.
    $role =
    if ($mn -eq 'RET') { 'abi-stack-cleanup' }
    elseif ($mn -eq 'ADD' -and $ins -match '^ADD ESP,') { 'abi-stack-cleanup' }   # cdecl caller cleanup
    elseif ($mn -eq 'SUB' -and $ins -match '^SUB ESP,') { 'abi-stack-cleanup' }   # prologue frame alloc
    elseif ($opKind -eq 'mem-operand') { 'struct-or-stack-offset' }
    elseif ($opKind -ne 'immediate') { 'unclassified-review' }
    elseif ($val -eq 11 -and $mn -in @('SAR', 'SHL')) { 'unit-tag-shift' }
    elseif ($_.insAddr -eq '0x004C0A9B') { 'command-id' }
    elseif ($_.insAddr -in @('0x0047B7E7', '0x0046F596')) { 'unrelated-constant' }
    # ADD/SUB of a watched value into a register is a STRIDE STEP, not arithmetic on data:
    # `ADD EDI,0x30` / `SUB EDI,0x30` walks one 12-pointer row. ADD ESP / SUB ESP are already
    # taken above, so this cannot swallow frame arithmetic.
    elseif ($mn -in @('IMUL', 'SUB', 'ADD')) { 'index-scale' }
    elseif ($mn -in @('CMP', 'TEST')) { 'comparison' }
    elseif ($mn -in @('MOV', 'LEA', 'PUSH') -and $val -in @(96, 384, 1728, 6912)) { 'array-size' }
    elseif ($mn -in @('MOV', 'LEA')) { 'loop-bound' }
    else { 'unclassified-review' }

    $capRelevant = $role -in @('loop-bound', 'comparison', 'index-scale', 'array-size')

    [pscustomobject]@{
        function    = $_.label
        funcEntry   = $_.funcEntry
        insAddr     = $_.insAddr
        valueHex    = $_.valueHex
        valueDec    = $_.valueDec
        mnemonic    = $mn
        opKind      = $opKind
        role        = $role
        capRelevant = $capRelevant
        instruction = $ins
        note        = $notes[$_.insAddr]
    }
}

$outDir = Split-Path $OutFile -Parent
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$rows | Export-Csv -LiteralPath $OutFile -Delimiter "`t" -NoTypeInformation -UseQuotes AsNeeded

Write-Host "build-immediate-table.ps1: $($rows.Count) rows -> $OutFile"
$rows | Group-Object role | Sort-Object Name | ForEach-Object {
    Write-Host ("  {0,-24} {1}" -f $_.Name, $_.Count)
}
Write-Host "  cap-relevant occurrences: $(($rows | Where-Object capRelevant).Count)"

$present = @($rows | ForEach-Object { [int]$_.valueDec } | Sort-Object -Unique)
$absent = @($Watch | Where-Object { $_ -notin $present })
Write-Host "  watched values present: $($present.Count) of $($Watch.Count)"
if ($absent.Count) {
    Write-Host "  watched values with ZERO occurrences: $(($absent | ForEach-Object { '0x{0:X}' -f $_ }) -join ', ')"
}
