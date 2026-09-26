// sc_engine.cpp -- see sc_engine.h.

#include <string.h>

#include "sc_engine.h"

BYTE* g_scModuleBase = NULL;

void ScEngineSetModuleBase(BYTE* moduleBase) {
    // NULL means "this module is inert", not "the image moved" -- see sc_engine.h.
    if (moduleBase) g_scModuleBase = moduleBase;
}

bool ScReadableAt(const void* addr, size_t len) {
    if (!addr || len == 0) return false;
    MEMORY_BASIC_INFORMATION mbi;
    if (VirtualQuery(addr, &mbi, sizeof(mbi)) != sizeof(mbi)) return false;
    if (mbi.State != MEM_COMMIT) return false;
    if (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD)) return false;
    const DWORD ok = PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY |
                     PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY;
    if ((mbi.Protect & ok) == 0) return false;
    // BOTH ends, and the low one is not redundant: VirtualQuery answers about the
    // region CONTAINING addr, so an addr below mbi.BaseAddress cannot happen -- but
    // the four copies this replaces disagreed about checking it, and the strict
    // version is the one that is right whichever way that argument goes.
    const BYTE* start  = (const BYTE*)addr;
    const BYTE* regEnd = (const BYTE*)mbi.BaseAddress + mbi.RegionSize;
    return start >= (const BYTE*)mbi.BaseAddress && start + len <= regEnd;
}

bool ScReadable(DWORD addr, DWORD len) {
    return ScReadableAt((const void*)(DWORD_PTR)addr, (size_t)len);
}

bool ScSafeRead(const void* addr, void* out, size_t len) {
    if (!ScReadableAt(addr, len)) return false;
    memcpy(out, addr, len);
    return true;
}
