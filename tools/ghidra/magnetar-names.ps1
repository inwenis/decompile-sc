#Requires -Version 7
<#
.SYNOPSIS
Magnetar 1.16.1 name table: fetch the pinned offsets.cpp and parse it into address -> name rows.

.DESCRIPTION
Dot-source this file. Magnetar (MIT, Joan Karadimov) names ~5k StarCraft.exe 1.16.1 functions
and ~4k globals in one C++ source; three line shapes carry an address:
  DECL_FUNC(<ret> (<conv>*name)(<args>), name, 0xaddr);   function with a compiler convention
  <ret> name(<args>) {  /  int address = 0xaddr;           function called through inline asm
  <type>& name = * ((decltype(&name)) 0xaddr);              global
Every name is a hypothesis for READING; AGENTS.md § "Claims about the binary" applies before one
enters research/. IDA auto-names (sub_, dword_, aString...) are dropped: they say nothing.
#>

# Pinned commit of https://github.com/joankaradimov/Magnetar (MIT). Bump deliberately, then re-run
# tools/ghidra/decomp-all.ps1 so the decompiled C and the table agree.
$script:MagnetarSha = 'd7c019a82937e5b27937d3f501f11d101ce07a1c'

function Get-MagnetarOffsets {
    param([Parameter(Mandatory)][string]$CacheDir)
    $path = Join-Path $CacheDir "offsets-$script:MagnetarSha.cpp"
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/joankaradimov/Magnetar/$script:MagnetarSha/MagnetarCraft/src/starcraft_exe/offsets.cpp" -OutFile $path
    }
    $path
}

function ConvertFrom-MagnetarOffsets {
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines)
    $auto = '^(sub|loc|dword|word|byte|stru|unk|off|flt|dbl|qword|asc|nullsub|j)_|^a[A-Z0-9]'
    $seen = @{}
    $rows = [System.Collections.Generic.List[object]]::new()
    $add = {
        param($kind, $addr, $name, $conv)
        # An auto-name says nothing, but the convention beside it still shapes the decompile.
        if ($name -match $auto) { $name = ''; if (-not $conv) { return } }
        $key = '0x{0:X8}' -f [Convert]::ToInt64($addr.Substring(2), 16)
        if ($seen.ContainsKey($key)) { return }
        $seen[$key] = $true
        $rows.Add([pscustomobject]@{ kind = $kind; addr = $key; name = $name; conv = $conv })
    }
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $l = $Lines[$i]
        if ($l -match '^DECL_FUNC\((?<decl>.*),\s*(?<name>\w+),\s*(?<addr>0x[0-9a-fA-F]+)\);') {
            $name = $Matches.name; $addr = $Matches.addr
            # No convention in the pointer type = the C++ default, cdecl.
            $conv = if ($Matches.decl -match '\((__cdecl|__stdcall|__fastcall|__thiscall)\s*\*') { $Matches[1] } else { '__cdecl' }
            & $add 'func' $addr $name $conv
        }
        elseif ($l -match '^\S[^(]*?\b(?<name>\w+)\s*\(.*\)\s*\{\s*$' -and ($i + 1) -lt $Lines.Count -and
                $Lines[$i + 1] -match 'int address = (?<addr>0x[0-9a-fA-F]+);') {
            # ponytail: the __asm block documents a register convention; name only, no storage.
            & $add 'func' $Matches.addr ([regex]::Match($l, '^\S[^(]*?\b(\w+)\s*\(').Groups[1].Value) ''
        }
        elseif ($l -match 'decltype\(&(?<name>\w+)\)\)\s*(?<addr>0x[0-9a-fA-F]+)\);') {
            & $add 'data' $Matches.addr $Matches.name ''
        }
    }
    $rows
}

function Export-MagnetarTsv {
    param([Parameter(Mandatory)][object[]]$Rows, [Parameter(Mandatory)][string]$Path)
    $lines = @("kind`taddr`tname`tconv") + @($Rows | ForEach-Object { "$($_.kind)`t$($_.addr)`t$($_.name)`t$($_.conv)" })
    Set-Content -LiteralPath $Path -Value $lines -Encoding utf8
}
