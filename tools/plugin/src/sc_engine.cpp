// sc_engine.cpp -- see sc_engine.h.

#include "sc_engine.h"

BYTE* g_scModuleBase = NULL;

void ScEngineSetModuleBase(BYTE* moduleBase) {
    // NULL means "this module is inert", not "the image moved" -- see sc_engine.h.
    if (moduleBase) g_scModuleBase = moduleBase;
}

bool ScReadable(DWORD addr, DWORD len) {
    if (!addr || len == 0) return false;
    MEMORY_BASIC_INFORMATION mbi;
    if (VirtualQuery((LPCVOID)(DWORD_PTR)addr, &mbi, sizeof(mbi)) != sizeof(mbi)) return false;
    if (mbi.State != MEM_COMMIT) return false;
    if (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD)) return false;
    const DWORD ok = PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY |
                     PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY;
    if ((mbi.Protect & ok) == 0) return false;
    DWORD regionEnd = (DWORD)(DWORD_PTR)mbi.BaseAddress + (DWORD)mbi.RegionSize;
    return addr + len <= regionEnd;
}
