#Requires -Version 7
<#
.SYNOPSIS
Build research/data/command-opcodes.tsv -- every command opcode StarCraft.exe 1.16.1
ACCEPTS, with the length the engine reads for it, the handler it dispatches to, how that
handler uses the receiving player's selection, and the fan-out policy that follows.

.DESCRIPTION
research/data/command-ids.tsv (task 011) is the SEND side: which ids the binary emits and
how long each buffer is. This is the RECEIVE side, which is what a fan-out policy has to
be decided from -- "may this command be replayed against another twelve units?" is a
question about what the engine DOES with it, not about how it was built.

Four inputs, all derived here from the binary:

 1. The command-length table at 0x005005F8 -- one dword per opcode id, 0xFFFFFFFF for an
    id the engine does not accept, the MAXIMUM length for a variable-length one. Read
    straight out of the PE's .rdata by this script (VA -> file offset through the section
    headers), so it needs no Ghidra pass of its own.

 2. The dispatcher at 0x004865D0 -- the receive loop. Decompiled, then parsed: each
    `case N:` gives the length the engine consumes for that opcode and the handler it
    calls. This is the authority; the length table is only consulted by the dispatcher's
    SKIP path, so the two can legitimately disagree (they do, for 0x37) and both are
    reported rather than one being silently preferred.

 3. Each handler, decompiled and classified by how it walks the selection:
      LOOP    `selectionIterator = 0; u = getActivePlayerNextSelection();
               while (u) { ...per unit...; u = getActivePlayerNextSelection(); }`
              -- the engine applies this command to EVERY unit it holds.
      SINGLE  the second iterator call is tested against 0 and the body sits inside that
              test -- the command only does anything when EXACTLY ONE unit is selected.
      NONE    the handler never touches the selection iterator.
      LOOP*   the handler forwards to an applier that loops (0x14 and 0x15 only).

 4. Whether the handler CALLS DIRECTLY, AT ONE LEVEL, a function that moves the player's
    resources. 0x00467250 subtracts from the two per-player resource arrays 0x0057F0F0 and
    0x0057F120; 0x00468280 is the cancel/refund path. Either one makes the command
    resource-costed.

    THE SCAN IS DEPTH 1 -- a text match over the handler's own decompiled body, not a
    transitive closure over its call graph. Two indirect chains are known and are NOT found
    by it: the 0x20 handler reaches 0x00468280 through 0x00466A70, and the 0x34 handler
    reaches it through a tail jump in 0x004E66E0. Neither changes any policy in the current
    table, because both opcodes are SINGLE-gated and therefore passthrough on the shape rule
    alone -- but a FUTURE opcode that loops the selection and spends indirectly would be
    mis-cleared by this scan. Anything added to the fan-out set on the strength of an empty
    `resourceFns` column must have its call graph checked by hand until this is a real
    closure.

The policy falls out of 3 and 4 and nothing else:

    fan-out  <=>  the handler applies the command to every selected unit (LOOP/LOOP*)
                  AND it does not move the player's resources.

Everything else is passthrough. A SINGLE-gated command is the sharp case: it does nothing
at all with twelve units selected, but a fan-out chunk CAN be one unit long, so replaying
it would make a command fire that the player's own selection never would.

.EXAMPLE
./tools/ghidra/sweep.ps1 -Mode Prepare -InputPE C:\sc-work\1161-base\StarCraft.exe `
    -ProjectDir work/scratch/ghidra-sweep -LogFile work/scratch/ghidra-sweep/import.log
./tools/ghidra/build-opcode-policy.ps1
#>
[CmdletBinding()]
param(
    [string]$ProjectDir = 'work/scratch/ghidra-sweep',
    [string]$WorkDir    = 'work/scratch/opcode-policy',
    [string]$OutTsv     = 'research/data/command-opcodes.tsv',
    [string]$InputPE    = 'C:\sc-work\1161-base\StarCraft.exe',
    [string]$SendTsv    = 'research/data/command-ids.tsv',
    [switch]$SkipSweep
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
Set-Location $repoRoot

$DISPATCHER   = '0x004865D0'
$LEN_TABLE_VA = 0x005005F8
$LEN_TABLE_N  = 0x76      # entries before the table gives way to unrelated .rdata data
$ITER         = 'FUN_0049a850'    # getActivePlayerNextSelection

# Functions that move the player's minerals/gas. Both were read in this binary:
#   0x00467250  `(&DAT_0057f0f0)[player] -= ...; (&DAT_0057f120)[player] -= ...`
#   0x00468280  the cancel path, which refunds through 0x0042CEC0 / 0x0042CE70
# Matched at ONE LEVEL only -- see the .DESCRIPTION note on the two known indirect chains.
$RESOURCE_FNS = @('FUN_00467250', 'FUN_00468280')

# 0x14 and 0x15 do not touch the selection iterator themselves -- they forward to an
# applier that does. Recorded explicitly rather than left to look like NONE.
$APPLIERS = @{ 0x14 = '0x004560D0'; 0x15 = '0x0049AB00' }

New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# --- 1. the length table, straight out of the PE ------------------------------
if (-not (Test-Path -LiteralPath $InputPE)) { throw "build-opcode-policy: $InputPE not found." }
$pe = [IO.File]::ReadAllBytes($InputPE)
$peOff     = [BitConverter]::ToInt32($pe, 0x3C)
$nSections = [BitConverter]::ToUInt16($pe, $peOff + 6)
$optSize   = [BitConverter]::ToUInt16($pe, $peOff + 20)
$imageBase = [BitConverter]::ToUInt32($pe, $peOff + 24 + 28)
$secOff    = $peOff + 24 + $optSize
function ConvertTo-RawOffset([uint32]$va) {
    for ($i = 0; $i -lt $nSections; $i++) {
        $o = $secOff + $i * 40
        $vaddr   = [BitConverter]::ToUInt32($pe, $o + 12)
        $rawSize = [BitConverter]::ToUInt32($pe, $o + 16)
        $rawPtr  = [BitConverter]::ToUInt32($pe, $o + 20)
        $start = $imageBase + $vaddr
        if ($va -ge $start -and $va -lt $start + $rawSize) { return $rawPtr + ($va - $start) }
    }
    throw ("build-opcode-policy: VA 0x{0:X8} is in no raw section" -f $va)
}
$lenTable = @{}
for ($i = 0; $i -lt $LEN_TABLE_N; $i++) {
    $lenTable[$i] = [BitConverter]::ToUInt32($pe, (ConvertTo-RawOffset ([uint32]($LEN_TABLE_VA + $i * 4))))
}
Write-Host ("build-opcode-policy: length table 0x{0:X8}, {1} entries read from {2}" -f $LEN_TABLE_VA, $LEN_TABLE_N, $InputPE)

# --- 2. the dispatcher ---------------------------------------------------------
$dispSpec = Join-Path $WorkDir 'dispatcher.spec'
"dispatcher,$($DISPATCHER.Substring(2))" | Set-Content -LiteralPath $dispSpec
if (-not $SkipSweep) {
    & (Join-Path $PSScriptRoot 'sweep.ps1') -Mode Run -ProjectDir $ProjectDir `
        -ProgramName 'StarCraft.exe' -Script 'DecompileMany.java' `
        -ScriptArgs (Join-Path $repoRoot "$WorkDir/dispatcher.tsv"), (Join-Path $repoRoot $dispSpec) | Write-Host
}
$dispC = Get-ChildItem (Join-Path $WorkDir 'dispatcher.*.c') | Select-Object -First 1
if (-not $dispC) { throw "build-opcode-policy: the dispatcher decompile is missing from $WorkDir." }
$lines = Get-Content $dispC.FullName

# Parse the switch. A case runs until the next `case`/`default`, and inside it:
#   `local_8 = N;`                    the length the engine consumes (an immediate), or
#   `local_8 = (uint)in_EAX[1] * 2 + 2;` / `local_8 = local_8 + 5;`  a computed length;
#   the first FUN_ call that is not the string-length helper is the handler.
$cases = @{}
$cur = $null
foreach ($ln in $lines) {
    if ($ln -match '^\s*case (0x[0-9a-f]+|\d+):') {
        $cur = [Convert]::ToInt32($Matches[1].Replace('0x', ''), ($Matches[1].StartsWith('0x') ? 16 : 10))
        if (-not $cases.ContainsKey($cur)) { $cases[$cur] = [pscustomobject]@{ len = ''; handler = '' } }
        continue
    }
    if ($ln -match '^\s*default:') { $cur = $null; continue }
    if ($null -eq $cur) { continue }
    if (-not $cases[$cur].len) {
        if ($ln -match 'local_8 = (0x[0-9a-f]+|\d+);') {
            $m = $Matches[1]
            $cases[$cur].len = [Convert]::ToInt32($m.Replace('0x', ''), ($m.StartsWith('0x') ? 16 : 10))
        }
        elseif ($ln -match 'local_8 = .*in_EAX\[1\]') { $cases[$cur].len = 'computed' }
        elseif ($ln -match 'local_8 = local_8 \+ (\d+)') { $cases[$cur].len = 'computed' }
    }
    if (-not $cases[$cur].handler -and $ln -match '(FUN_00[0-9a-f]{6})\(') {
        $fn = $Matches[1]
        if ($fn -ne 'FUN_00485980') { $cases[$cur].handler = $fn }   # the string-length helper
    }
}
# A case that falls through to the next one shares its body; propagate forward.
foreach ($id in ($cases.Keys | Sort-Object)) {
    if (-not $cases[$id].len -and $cases.ContainsKey($id + 1)) {
        $cases[$id].len = $cases[$id + 1].len
        $cases[$id].handler = $cases[$id + 1].handler
    }
}
Write-Host "build-opcode-policy: dispatcher $DISPATCHER accepts $($cases.Count) opcodes"

# --- 3. every handler, classified ---------------------------------------------
$handlers = @($cases.Values.handler | Where-Object { $_ } | Sort-Object -Unique)
$handlers += @($APPLIERS.Values | ForEach-Object { 'FUN_00' + $_.Substring(4).ToLower() })
$handlers = @($handlers | Sort-Object -Unique)

$hSpec = Join-Path $WorkDir 'handlers.spec'
($handlers | ForEach-Object { "h$($_.Substring(4)),$($_.Substring(4))" }) -join "`n" |
    Set-Content -NoNewline -LiteralPath $hSpec
if (-not $SkipSweep) {
    & (Join-Path $PSScriptRoot 'sweep.ps1') -Mode Run -ProjectDir $ProjectDir `
        -ProgramName 'StarCraft.exe' -Script 'DecompileMany.java' `
        -ScriptArgs (Join-Path $repoRoot "$WorkDir/handlers.tsv"), (Join-Path $repoRoot $hSpec) | Write-Host
}

function Get-HandlerFacts([string]$fn) {
    $f = Get-ChildItem (Join-Path $WorkDir "h$($fn.Substring(4)).*.c") -ErrorAction SilentlyContinue |
         Select-Object -First 1
    if (-not $f) { return [pscustomobject]@{ shape = '?'; resources = '?' } }
    $src = Get-Content $f.FullName -Raw
    $n = ([regex]::Matches($src, [regex]::Escape($ITER))).Count
    $shape = 'NONE'
    if ($n -ge 2) {
        # Decided by CONTROL FLOW, not by a text pattern near the second call: either a
        # variable the iterator assigns is a `while (x != 0)` condition, or the last
        # iterator call is the tail of a do/while body.
        $vars = @([regex]::Matches($src, '(\w+) = FUN_0049a850\(\);') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $isLoop = $false
        foreach ($v in $vars) { if ($src -match ('while\s*\(\s*' + [regex]::Escape($v) + '\s*!=\s*0\s*\)')) { $isLoop = $true } }
        if (-not $isLoop) {
            $tail = $src.Substring($src.LastIndexOf($ITER))
            if ($tail -match '\}\s*while') { $isLoop = $true }
        }
        $shape = $isLoop ? 'LOOP' : 'SINGLE'
    }
    elseif ($n -eq 1) { $shape = 'ONE-CALL' }
    $res = @($RESOURCE_FNS | Where-Object { $src -match [regex]::Escape($_) })
    [pscustomobject]@{ shape = $shape; resources = ($res -join ';') }
}

$facts = @{}
foreach ($h in $handlers) { $facts[$h] = Get-HandlerFacts $h }

# --- 4. the send-side table, for the length cross-check ------------------------
$send = @{}
if (Test-Path -LiteralPath $SendTsv) {
    Get-Content $SendTsv | Select-Object -Skip 1 | ForEach-Object {
        $p = $_ -split "`t"
        if ($p.Count -ge 2) { $send[[Convert]::ToInt32($p[0].Replace('0x',''),16)] = $p[1] }
    }
}

# --- 5. emit -------------------------------------------------------------------
$out = [System.Collections.Generic.List[string]]::new()
$out.Add("cmdId`tdispatcherLen`tlenTable`temitLen`thandler`tapplier`tselectionShape`tresourceFns`tpolicy")
foreach ($id in ($cases.Keys | Sort-Object)) {
    $c = $cases[$id]
    $applier = $APPLIERS.ContainsKey($id) ? $APPLIERS[$id] : ''
    $factFn = $applier ? ('FUN_00' + $applier.Substring(4).ToLower()) : $c.handler
    $f = $factFn ? $facts[$factFn] : [pscustomobject]@{ shape = 'INLINE'; resources = '' }
    $shape = $f.shape
    if ($applier -and $shape -eq 'LOOP') { $shape = 'LOOP*' }
    $policy = (($shape -eq 'LOOP' -or $shape -eq 'LOOP*') -and -not $f.resources) ? 'fanout' : 'passthrough'
    $lt = $lenTable.ContainsKey($id) ? ("0x{0:X8}" -f $lenTable[$id]) : ''
    $out.Add(("0x{0:X2}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}`t{8}" -f
        $id, $c.len, $lt, ($send.ContainsKey($id) ? $send[$id] : '-'),
        ($c.handler ? ('0x' + $c.handler.Substring(4).ToUpper()) : 'inline'),
        $applier, $shape, $f.resources, $policy))
}

# Ids the client EMITS but the dispatcher does not accept. Leaving them out would make the
# table look complete while hiding a real disagreement between the two sides.
foreach ($id in ($send.Keys | Sort-Object)) {
    if ($cases.ContainsKey($id)) { continue }
    $lt = $lenTable.ContainsKey($id) ? ("0x{0:X8}" -f $lenTable[$id]) : ''
    $out.Add(("0x{0:X2}`tnot-accepted`t{1}`t{2}`t-`t`tNONE`t`tpassthrough" -f $id, $lt, $send[$id]))
}
New-Item -ItemType Directory -Path (Split-Path $OutTsv -Parent) -Force | Out-Null
Set-Content -LiteralPath $OutTsv -Value $out -Encoding utf8

$fan = @($out | Select-Object -Skip 1 | Where-Object { $_ -match "`tfanout$" }).Count
Write-Host "build-opcode-policy: $($cases.Count) opcodes -> $OutTsv  ($fan fan-out, $($cases.Count - $fan) passthrough)"
