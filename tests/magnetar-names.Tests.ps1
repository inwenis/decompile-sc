#Requires -Version 7
<#
The Magnetar parser (tools/ghidra/magnetar-names.ps1) feeds every name the decompiled C
carries. Each of its three line shapes, the auto-name filter and the duplicate-address rule
are checked against a hand-written fixture, and the fixture also carries lines that must NOT
produce a row, so a parser that matches everything fails here.
#>

BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/ghidra/magnetar-names.ps1')
    $script:fixture = @'
#define DECL_FUNC(decl, func, offset) decl = (decltype(func)) offset;
DECL_FUNC(void (__thiscall*showImage)(CImage *this_), showImage, 0x401120);
DECL_FUNC(void (*plainDefault)(int a), plainDefault, 0x401130);
DECL_FUNC(int (__cdecl*sub_401140)(), sub_401140, 0x401140);
CUnit * IterateAllScannerSweeps(int (__fastcall *a1)(CUnit *a1, int a2), int a2) {
    int address = 0x401150;
    __asm { call address }
}
int sub_401160(int a1) {
    int address = 0x401160;
}
void notAWrapper(int a1) {
    return;
}
DECL_FUNC(void (__stdcall*dupOfWrapper)(), dupOfWrapper, 0x401150);
CUnit(&unitTable)[1700] = * ((decltype(&unitTable)) 0x59cca8);
int& dword_6D60F0 = * ((decltype(&dword_6D60F0)) 0x6d60f0);
char(&aRuntimeError)[15] = * ((decltype(&aRuntimeError)) 0x4fe624);
'@ -split "`r?`n"
}

Describe 'ConvertFrom-MagnetarOffsets' {
    It 'keeps every named shape once, drops auto-names but keeps their convention' {
        $rows = ConvertFrom-MagnetarOffsets -Lines $fixture
        ($rows | ForEach-Object { "$($_.kind) $($_.addr) $($_.name) $($_.conv)" }) | Should -Be @(
            'func 0x00401120 showImage __thiscall',
            'func 0x00401130 plainDefault __cdecl',
            'func 0x00401140  __cdecl',
            'func 0x00401150 IterateAllScannerSweeps ',
            'data 0x0059CCA8 unitTable '
        )
    }
}
