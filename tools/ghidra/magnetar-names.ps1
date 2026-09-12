#Requires -Version 7
<#
.SYNOPSIS
Magnetar 1.16.1 tables: fetch the pinned sources, parse names, prototypes, register storage, global
declarations and the struct/enum header into inputs for ApplyTypes.java and ApplyNames.java.

.DESCRIPTION
Dot-source this file. Magnetar (MIT, Joan Karadimov) describes StarCraft.exe 1.16.1 in offsets.cpp:
  DECL_FUNC(<ret> (<conv>*name)(<args>), name, 0xaddr);   standard calling convention
  <ret> name(<args>) {  int address = 0xaddr; __asm {...}  register convention, spelled out in asm
  <type>& name = * ((decltype(&name)) 0xaddr);              global
and in types.h, an IDA local-types export: structs, sized enums, one static_assert per struct size.
Every name and type is a hypothesis for READING; AGENTS.md § "Claims about the binary" applies before
one enters research/. IDA auto-names (sub_, dword_, aString...) are dropped: they say nothing.
#>

# Pinned commit of https://github.com/joankaradimov/Magnetar (MIT). Bump deliberately, then re-run
# tools/ghidra/decomp-all.ps1 so the decompiled C and the tables agree.
$script:MagnetarSha = 'd7c019a82937e5b27937d3f501f11d101ce07a1c'

function Get-MagnetarFile {
    param([Parameter(Mandatory)][string]$CacheDir, [Parameter(Mandatory)][ValidateSet('offsets.cpp', 'types.h')][string]$Name)
    $rel = @{ 'offsets.cpp' = 'src/starcraft_exe/offsets.cpp'; 'types.h' = 'include/starcraft_exe/types.h' }[$Name]
    $path = Join-Path $CacheDir "$script:MagnetarSha-$Name"
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/joankaradimov/Magnetar/$script:MagnetarSha/MagnetarCraft/$rel" -OutFile "$path.part"
        Move-Item -LiteralPath "$path.part" -Destination $path
    }
    $path
}

# Top-level commas only: a function-pointer parameter carries its own argument list.
function Split-CArgs([string]$Text) {
    $parts = [System.Collections.Generic.List[string]]::new(); $depth = 0; $start = 0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        switch ($Text[$i]) {
            '(' { $depth++ } ')' { $depth-- }
            ',' { if ($depth -eq 0) { $parts.Add($Text.Substring($start, $i - $start).Trim()); $start = $i + 1 } }
        }
    }
    $last = $Text.Substring($start).Trim()
    if ($last -and $last -ne 'void') { $parts.Add($last) }
    $parts.ToArray()
}

function Get-CArgName([string]$Arg) {
    if ($Arg -match '\(\s*(?:__\w+\s*)?\*\s*(\w+)\s*\)\s*\(') { return $Matches[1] }
    if (($Arg -replace '\[[^\]]*\]', '') -match '(\w+)\s*$') { return $Matches[1] }
    $Arg
}

# ret=<reg>;<arg>=<reg>|S<stack offset>;... from the wrapper's asm, or '?' when an argument never
# reaches the call (unmappable: the prototype would then claim storage the asm does not show).
function Get-AsmStorage([string[]]$Asm, [string[]]$ArgNames, [bool]$ReturnsValue) {
    $reg = @{}; $pushes = [System.Collections.Generic.List[string]]::new(); $ret = 'EAX'
    foreach ($t in $Asm) {
        if ($t -match '^mov\s+(\w+),\s*(?:(?:byte|word|dword)\s+ptr\s+)?(\w+)$' -and $ArgNames -contains $Matches[2]) { $reg[$Matches[2]] = $Matches[1].ToUpper() }
        elseif ($t -match '^push\s+(?:dword\s+ptr\s+)?(\w+)$' -and $ArgNames -contains $Matches[1]) { $pushes.Add($Matches[1]) }
        elseif ($t -match '^mov\s+result_,\s*(\w+)$') { $ret = $Matches[1].ToUpper() }
    }
    $parts = @(if ($ReturnsValue) { "ret=$ret" })
    foreach ($a in $ArgNames) {
        $j = $pushes.LastIndexOf($a)
        # Pushed last = nearest the return address: the first stack argument, at +4.
        if ($j -ge 0) { $parts += "$a=S$(4 + 4 * ($pushes.Count - 1 - $j))" }
        elseif ($reg.ContainsKey($a)) { $parts += "$a=$($reg[$a])" }
        else { return '?' }
    }
    $parts -join ';'
}

function ConvertFrom-MagnetarOffsets {
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines)
    $auto = '^(sub|loc|dword|word|byte|stru|unk|off|flt|dbl|qword|asc|nullsub|j)_|^a[A-Z0-9]'
    $seen = @{}
    $rows = [System.Collections.Generic.List[object]]::new()
    $add = {
        param($kind, $addr, $name, $conv, $proto, $storage)
        # An auto-name says nothing, but a function prototype beside it still shapes the decompile.
        # An auto-named global's type is IDA's guess, weaker than Ghidra's own string/data typing.
        # Case-sensitive: IDA's prefixes are lower case, and -match would drop AI_Stop, Accelerate.
        if ($name -cmatch $auto) { if ($kind -eq 'data' -or -not $proto) { return }; $name = '' }
        $key = '0x{0:X8}' -f [Convert]::ToInt64($addr.Substring(2), 16)
        if ($seen.ContainsKey($key)) { return }
        $seen[$key] = $true
        $rows.Add([pscustomobject]@{ kind = $kind; addr = $key; name = $name; conv = $conv; proto = $proto; storage = $storage })
    }
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $l = $Lines[$i]
        if ($l -match '^DECL_FUNC\((?<decl>.*),\s*(?<name>\w+),\s*(?<addr>0x[0-9a-fA-F]+)\);') {
            $name = $Matches.name; $addr = $Matches.addr; $proto = ''
            # No convention in the pointer type = the C++ default, cdecl.
            $conv = '__cdecl'
            if ($Matches.decl -match '^(?<ret>.+?)\s*\(\s*(?<conv>__\w+)?\s*\*\s*\w+\s*\)\s*\((?<args>.*)\)$') {
                if ($Matches.conv) { $conv = $Matches.conv }
                $proto = "$($Matches.ret) $conv __fn($($Matches.args))"
            }
            & $add 'func' $addr $name $conv $proto ''
            continue
        }
        $head = [regex]::Match($l, '^(?<ret>\S[^(]*?)\s*\b(?<name>\w+)\s*\((?<args>.*)\)\s*\{\s*$')
        $body = if ($head.Success -and ($i + 1) -lt $Lines.Count) { [regex]::Match($Lines[$i + 1], 'int address = (0x[0-9a-fA-F]+);') }
        if ($body -and $body.Success) {
            $asm = [System.Collections.Generic.List[string]]::new()
            for ($j = $i + 2; $j -lt $Lines.Count -and $Lines[$j] -notmatch '^\}'; $j++) { $asm.Add($Lines[$j].Trim()) }
            $ret = $head.Groups['ret'].Value.Trim()
            $names = @(Split-CArgs $head.Groups['args'].Value | ForEach-Object { Get-CArgName $_ })
            $storage = Get-AsmStorage $asm $names ($ret -ne 'void')
            & $add 'func' $body.Groups[1].Value $head.Groups['name'].Value '' "$ret __fn($($head.Groups['args'].Value))" $storage
            continue
        }
        if ($l -match '^(?<t>.+?)\s*\(&(?<n>\w+)\)(?<dims>(?:\[\d*\])+)\s*=.*decltype\(&\k<n>\)\)\s*(?<addr>0x[0-9a-fA-F]+)\);') {
            $m = $Matches.Clone()
            # An unsized array has no layout to apply; the label alone still names it.
            $decl = if ($m.dims.Contains('[]')) { '' } else { "$($m.t) __v$($m.dims)" }
            & $add 'data' $m.addr $m.n '' $decl ''
        }
        elseif ($l -match '^(?<t>[^(]+?)\s*&\s*(?<n>\w+)\s*=.*decltype\(&\k<n>\)\)\s*(?<addr>0x[0-9a-fA-F]+)\);') {
            & $add 'data' $Matches.addr $Matches.n '' "$($Matches.t) __v" ''
        }
        elseif ($l -match 'decltype\(&(?<name>\w+)\)\)\s*(?<addr>0x[0-9a-fA-F]+)\);') {
            & $add 'data' $Matches.addr $Matches.name '' '' ''
        }
    }
    $rows
}

# Ghidra's C parser sizes every enum as an int and rejects C++11 "enum X : T", so enums leave the
# header as rows with their true size; forward declarations, includes and the namespace go too.
function ConvertFrom-MagnetarTypes {
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines)
    $width = @{ '__int8' = 1; 'char' = 1; '__int16' = 2; 'short' = 2; '__int32' = 4; 'int' = 4; '__int64' = 8 }
    $header = [System.Collections.Generic.List[string]]::new()
    $enums = [System.Collections.Generic.List[object]]::new()
    $sizes = [System.Collections.Generic.List[object]]::new()
    $enum = $null; $dropBrace = $false
    foreach ($l in $Lines) {
        if ($enum) {
            if ($l -match '^\s*(\w+)\s*=\s*(-?(?:0x[0-9A-Fa-f]+|\d+)),?\s*$') {
                $enums.Add([pscustomobject]@{ enum = $enum.name; size = $enum.size; member = $Matches[1]; value = $Matches[2] }); $enum.n++
            }
            elseif ($l -match '^\};') {
                if (-not $enum.n) { $enums.Add([pscustomobject]@{ enum = $enum.name; size = $enum.size; member = ''; value = '' }) }
                $enum = $null
            }
            continue
        }
        if ($dropBrace -and $l -eq '{') { $dropBrace = $false; continue }
        if ($l -match '^enum\s+\w+[^;{]*;') { continue }
        if ($l -match '^enum\s+(\w+)\s*(?::\s*(?:unsigned\s+)?(\w+))?\s*$') {
            $size = if ($Matches[2]) { $width[$Matches[2]] } else { 4 }
            if (-not $size) { throw "ConvertFrom-MagnetarTypes: no width for enum base type in: $l" }
            $enum = @{ name = $Matches[1]; size = $size; n = 0 }; continue
        }
        if ($l -match '^static_assert\(sizeof\((\w+)\)\s*==\s*(\d+)') { $sizes.Add([pscustomobject]@{ type = $Matches[1]; size = [int]$Matches[2] }); continue }
        if ($l -match '^namespace\b') { $dropBrace = $true; continue }
        if ($l -match '^\s*#\s*(include|pragma once)') { continue }
        $header.Add($l)
    }
    # The namespace's closing brace is the last one at column 0.
    $close = $header.LastIndexOf('}')
    if ($close -ge 0) { $header.RemoveAt($close) }
    [pscustomobject]@{ header = $header.ToArray(); enums = $enums.ToArray(); sizes = $sizes.ToArray() }
}

function Export-MagnetarTsv {
    param([Parameter(Mandatory)][object[]]$Rows, [Parameter(Mandatory)][string]$Path)
    $cols = $Rows[0].PSObject.Properties.Name
    $lines = @($cols -join "`t") + @($Rows | ForEach-Object { $r = $_; ($cols | ForEach-Object { $r.$_ }) -join "`t" })
    Set-Content -LiteralPath $Path -Value $lines -Encoding utf8
}
