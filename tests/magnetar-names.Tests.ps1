#Requires -Version 7
<#
The Magnetar parser (tools/ghidra/magnetar-names.ps1) feeds every name, prototype, register
assignment and struct layout the decompiled C carries. Each line shape is checked against a
hand-written fixture that also carries lines which must NOT produce a row, so a parser that
matches everything, or maps an argument to the wrong register, fails here.
#>

BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/ghidra/magnetar-names.ps1')
    $script:offsets = @'
#define DECL_FUNC(decl, func, offset) decl = (decltype(func)) offset;
DECL_FUNC(void (__thiscall*showImage)(CImage *this_), showImage, 0x401120);
DECL_FUNC(void (*plainDefault)(int a), plainDefault, 0x401130);
DECL_FUNC(int (__cdecl*sub_401140)(), sub_401140, 0x401140);
DECL_FUNC(void (__cdecl*AI_Stop)(), AI_Stop, 0x403380);
CUnit * IterateAllScannerSweeps(int (__fastcall *fn)(CUnit *a1, int a2), int a2) {
    int address = 0x401150;
    CUnit * result_;
    __asm {
        push dword ptr a2
        mov eax, fn
        call address
        mov result_, eax
    }
    return result_;
}
void BWFXN_RefreshTarget(int left, int bottom, int top, int right) {
    int address = 0x41e0d0;
    __asm {
        push dword ptr right
        mov ecx, top
        mov edx, bottom
        mov eax, left
        call address
    }
}
u8 twoPushes(char a1, int a2, int a3) {
    int address = 0x401170;
    u8 result_;
    __asm {
        xor eax, eax
        push dword ptr a3
        push dword ptr a2
        mov al, a1
        call address
        mov result_, al
    }
    return result_;
}
void lostArg(int a1, int a2) {
    int address = 0x401180;
    __asm {
        mov esi, a1
        call address
    }
}
void notAWrapper(int a1) {
    return;
}
DECL_FUNC(void (__stdcall*dupOfWrapper)(), dupOfWrapper, 0x401150);
CUnit(&UnitNodeTable)[1700] = * ((decltype(&UnitNodeTable)) 0x59cca8);
CHAR(&ProcName)[] = * ((decltype(&ProcName)) 0x4fe5fc);
CUnit *& firstUnit = * ((decltype(&firstUnit)) 0x628430);
char(&active_players)[8] = * ((decltype(&active_players)) 0x6509a4);
int& dword_6D60F0 = * ((decltype(&dword_6D60F0)) 0x6d60f0);
char(&aRuntimeError)[15] = * ((decltype(&aRuntimeError)) 0x4fe624);
'@ -split "`r?`n"

    $script:types = @'
#pragma once
#include <Windows.h>
#define __hidden
namespace game::starcraft
{
typedef unsigned __int8 u8;
enum Order : unsigned __int8;
enum Flags;
struct CUnitFighter
{
  CUnit *parent;
  bool inHanger;
};
static_assert(sizeof(CUnitFighter) == 8, "Incorrect size for type `CUnitFighter`. Expected: 8");

enum Order : unsigned __int8
{
  Order_Die = 0x0,
  Order_Stop = 0x1,
};

enum Flags
{
};

}
'@ -split "`r?`n"
}

Describe 'ConvertFrom-MagnetarOffsets' {
    BeforeAll { $script:rows = ConvertFrom-MagnetarOffsets -Lines $offsets }

    It 'keeps every named shape once, drops auto-names but keeps a function prototype' {
        ($rows | ForEach-Object { "$($_.kind) $($_.addr) $($_.name)" }) | Should -Be @(
            'func 0x00401120 showImage',
            'func 0x00401130 plainDefault',
            'func 0x00401140 ',
            'func 0x00403380 AI_Stop',
            'func 0x00401150 IterateAllScannerSweeps',
            'func 0x0041E0D0 BWFXN_RefreshTarget',
            'func 0x00401170 twoPushes',
            'func 0x00401180 lostArg',
            'data 0x0059CCA8 UnitNodeTable',
            'data 0x004FE5FC ProcName',
            'data 0x00628430 firstUnit',
            'data 0x006509A4 active_players'
        )
    }

    It 'turns a DECL_FUNC pointer type into a prototype with its convention' {
        ($rows | Where-Object name -eq 'showImage').proto | Should -Be 'void __thiscall __fn(CImage *this_)'
        ($rows | Where-Object name -eq 'plainDefault').proto | Should -Be 'void __cdecl __fn(int a)'
    }

    It 'reads register and stack storage out of the wrapper asm' {
        ($rows | Where-Object name -eq 'BWFXN_RefreshTarget').storage | Should -Be 'left=EAX;bottom=EDX;top=ECX;right=S4'
        # a function-pointer argument keeps its own name, not its inner argument's
        ($rows | Where-Object name -eq 'IterateAllScannerSweeps').storage | Should -Be 'ret=EAX;fn=EAX;a2=S4'
        # pushed last = first stack slot; the return register is the one result_ is read from
        ($rows | Where-Object name -eq 'twoPushes').storage | Should -Be 'ret=AL;a1=AL;a2=S4;a3=S8'
    }

    It 'refuses storage when an argument never reaches the call' {
        ($rows | Where-Object name -eq 'lostArg').storage | Should -Be '?'
    }

    It 'turns a global reference into a declaration, and skips an unsized array' {
        ($rows | Where-Object name -eq 'UnitNodeTable').proto | Should -Be 'CUnit __v[1700]'
        ($rows | Where-Object name -eq 'firstUnit').proto | Should -Be 'CUnit * __v'
        ($rows | Where-Object name -eq 'ProcName').proto | Should -Be ''
    }
}

Describe 'Merge-MagnetarOverrides' {
    It 'renames a Magnetar row, adds a row Magnetar lacks, and marks only those as repo' {
        $rows = ConvertFrom-MagnetarOffsets -Lines $offsets
        $over = @(
            [pscustomobject]@{ kind = 'func'; addr = '0x401120'; name = 'repoName'; decl = ''; evidence = 'x' },
            [pscustomobject]@{ kind = 'data'; addr = '0x006284B6'; name = 'selectionIterator'; decl = 'u8 __v'; evidence = 'y' })
        $m = Merge-MagnetarOverrides -Rows $rows -Overrides $over
        $m.Count | Should -Be ($rows.Count + 1)
        $f = $m | Where-Object addr -eq '0x00401120'
        "$($f.name) $($f.origin) $($f.proto)" | Should -Be 'repoName repo void __thiscall __fn(CImage *this_)'
        $d = $m | Where-Object addr -eq '0x006284B6'
        "$($d.kind) $($d.name) $($d.origin) $($d.proto)" | Should -Be 'data selectionIterator repo u8 __v'
        @($m | Where-Object origin -eq 'repo').Count | Should -Be 2
    }
}

Describe 'ConvertFrom-MagnetarTypes' {
    BeforeAll { $script:t = ConvertFrom-MagnetarTypes -Lines $types }

    It 'lifts sized enums out with their width, empty ones included' {
        ($t.enums | ForEach-Object { "$($_.enum) $($_.size) $($_.member) $($_.value)" }) | Should -Be @(
            'Order 1 Order_Die 0x0', 'Order 1 Order_Stop 0x1', 'Flags 4  ')
    }

    It 'collects struct sizes from static_assert' {
        ($t.sizes | ForEach-Object { "$($_.type) $($_.size)" }) | Should -Be @('CUnitFighter 8')
    }

    It 'leaves a header with no include, namespace, enum or static_assert' {
        $h = $t.header -join "`n"
        $h | Should -Not -Match '#include|namespace|enum |static_assert|pragma once'
        $h | Should -Match 'struct CUnitFighter'
        # braces still balance once the namespace pair is gone
        ([regex]::Matches($h, '\{')).Count | Should -Be ([regex]::Matches($h, '\}')).Count
    }
}
