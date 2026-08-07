#Requires -Version 7
<#
.SYNOPSIS
Build research/data/command-ids.tsv -- every wire command StarCraft.exe 1.16.1 emits,
with its byte length and the functions that emit it.

.DESCRIPTION
Two steps, both reproducible from a prepared Ghidra project (tools/ghidra/sweep.ps1
-Mode Prepare):

 1. HookProbe.java over queueCommand (0x00485BD0) writes a .callers file listing every
    instruction that calls it. Every outgoing command in the binary goes through that
    one function, so its caller list is the complete inventory of command builders.
 2. HookProbe.java over each of those callers dumps their disassembly. This script then
    reads each dump and, for every `CALL 0x00485bd0`, walks backwards to find:
      - `MOV EDX,<imm>`                      -> the command's byte length
      - `LEA/MOV ECX,[EBP + -0xNN]`          -> where the command buffer lives
      - `MOV byte ptr [EBP + -0xNN],<imm>`   -> the id byte written into buffer[0]
    The backward walk stops at any intervening CALL and after 14 instructions, so a
    length can only be attributed to the call it actually precedes. Widening that
    window to 40 instructions produces an identical table, which is the check that
    the association is not an artefact of the window size.

Sites whose buffer is not an [EBP + disp] local (a handful build theirs elsewhere)
are counted and reported, not silently dropped.

.EXAMPLE
./tools/ghidra/sweep.ps1 -Mode Prepare -InputPE C:\sc-work\1161-base\StarCraft.exe `
    -ProjectDir work/scratch/ghidra-sweep -LogFile work/scratch/ghidra-sweep/import.log
./tools/ghidra/sweep.ps1 -Mode Run -ProjectDir work/scratch/ghidra-sweep `
    -ProgramName StarCraft.exe -Script HookProbe.java `
    -ScriptArgs work/scratch/hookprobe/hook-targets.tsv, tools/ghidra/specs/hook-targets.spec
./tools/ghidra/build-command-table.ps1
#>
[CmdletBinding()]
param(
    [string]$ProjectDir = 'work/scratch/ghidra-sweep',
    [string]$WorkDir    = 'work/scratch/allcmd',
    [string]$OutTsv     = 'research/data/command-ids.tsv',
    [string]$CallersFile = 'work/scratch/hookprobe/queueCommand.FUN_00485bd0.callers',
    [switch]$SkipSweep
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
Set-Location $repoRoot

if (-not (Test-Path -LiteralPath $CallersFile)) {
    throw "build-command-table: $CallersFile not found. Run HookProbe.java over tools/ghidra/specs/hook-targets.spec first (see .EXAMPLE)."
}

$addrs = Get-Content $CallersFile | Select-Object -Skip 1 |
         ForEach-Object { ($_ -split "`t")[3] } | Sort-Object -Unique | Where-Object { $_ }
Write-Host "build-command-table: $($addrs.Count) distinct callers of queueCommand"

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

if (-not $SkipSweep) {
    $spec = Join-Path $WorkDir 'allcmd.spec'
    ($addrs | ForEach-Object { "c$($_.Substring(2)),$_" }) -join "`n" |
        Set-Content -NoNewline -LiteralPath $spec
    & (Join-Path $PSScriptRoot 'sweep.ps1') -Mode Run -ProjectDir $ProjectDir `
        -ProgramName 'StarCraft.exe' -Script 'HookProbe.java' `
        -ScriptArgs "$WorkDir/allcmd.tsv", $spec | Write-Host
}

$sites = @()
$unresolved = 0
foreach ($f in Get-ChildItem (Join-Path $WorkDir 'c*.asm') | Sort-Object Name) {
    $lines = Get-Content $f.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch 'CALL 0x00485bd0') { continue }
        $len = ''; $id = ''; $ecx = ''
        for ($j = $i - 1; $j -ge 0 -and $j -gt $i - 14; $j--) {
            if ($lines[$j] -match 'CALL ') { break }
            if (-not $len -and $lines[$j] -match 'MOV EDX,(0x[0-9a-f]+)') { $len = $Matches[1] }
            if (-not $ecx -and $lines[$j] -match '(LEA|MOV) ECX,\[EBP \+ (-0x[0-9a-f]+)\]') { $ecx = $Matches[2] }
        }
        if ($ecx) {
            for ($j = $i - 1; $j -ge 0 -and $j -gt $i - 60; $j--) {
                if ($lines[$j] -match ('MOV byte ptr \[EBP \+ ' + [regex]::Escape($ecx) + '\],(0x[0-9a-f]+|\d+)')) {
                    $id = $Matches[1]; break
                }
            }
        }
        if ($id) {
            $sites += [pscustomobject]@{
                id  = [Convert]::ToInt32($id.Replace('0x', ''), 16)
                len = $len
                fn  = '0x' + $f.Name.Split('.')[0].Substring(1)
            }
        }
        else { $unresolved++ }
    }
}

$groups = $sites | Group-Object id | Sort-Object { [int]$_.Name }
New-Item -ItemType Directory -Path (Split-Path $OutTsv -Parent) -Force | Out-Null

$out = [System.Collections.Generic.List[string]]::new()
$out.Add(("cmdId`tbyteLen`temitterCount`temitters"))
foreach ($g in $groups) {
    $lens = @($g.Group.len | Where-Object { $_ } | Sort-Object -Unique)
    $lenCell = if ($lens.Count -eq 0) { 'computed' } else { ($lens | ForEach-Object { [Convert]::ToInt32($_.Replace('0x',''),16) }) -join '/' }
    $em = @($g.Group.fn | Sort-Object -Unique)
    $out.Add(("0x{0:X2}`t{1}`t{2}`t{3}" -f [int]$g.Name, $lenCell, $em.Count, ($em -join ';')))
}
Set-Content -LiteralPath $OutTsv -Value $out -Encoding utf8

Write-Host "build-command-table: $($groups.Count) command ids across $($sites.Count) emit sites -> $OutTsv"
Write-Host "build-command-table: $unresolved emit site(s) had no [EBP + disp] command buffer and are NOT in the table"
