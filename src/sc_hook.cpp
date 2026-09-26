// sc_hook.cpp -- see sc_hook.h.

#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <string.h>

#include "sc_hook.h"
#include "sc_log.h"

// ---------------------------------------------------------------------------
// Thread suspension
// ---------------------------------------------------------------------------

#define SC_MAX_SUSPENDED 64
static HANDLE g_suspended[SC_MAX_SUSPENDED];
static int    g_suspendedCount = 0;

int ScHookSuspendThreads(void) {
    if (g_suspendedCount != 0) return 0;  // already suspended; refuse to nest

    const DWORD selfPid = GetCurrentProcessId();
    const DWORD selfTid = GetCurrentThreadId();

    HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (snap == INVALID_HANDLE_VALUE) {
        ScLog("HOOK suspend: CreateToolhelp32Snapshot failed gle=%u",
              (unsigned)GetLastError());
        return 0;
    }

    THREADENTRY32 te;
    te.dwSize = sizeof(te);
    if (Thread32First(snap, &te)) {
        do {
            if (te.th32OwnerProcessID != selfPid) continue;
            if (te.th32ThreadID == selfTid) continue;
            if (g_suspendedCount >= SC_MAX_SUSPENDED) {
                ScLog("HOOK suspend: more than %d threads -- NOT suspending the rest",
                      SC_MAX_SUSPENDED);
                break;
            }
            HANDLE th = OpenThread(THREAD_SUSPEND_RESUME, FALSE, te.th32ThreadID);
            if (!th) continue;
            if (SuspendThread(th) == (DWORD)-1) { CloseHandle(th); continue; }
            g_suspended[g_suspendedCount++] = th;
        } while (Thread32Next(snap, &te));
    }
    CloseHandle(snap);
    return g_suspendedCount;
}

void ScHookResumeThreads(void) {
    for (int i = 0; i < g_suspendedCount; ++i) {
        ResumeThread(g_suspended[i]);
        CloseHandle(g_suspended[i]);
        g_suspended[i] = NULL;
    }
    g_suspendedCount = 0;
}

// ---------------------------------------------------------------------------
// Install / remove
// ---------------------------------------------------------------------------

bool ScHookInstall(ScHook* h, const char* name, void* target, void* detour,
                   int patchLen, const BYTE* expect, int expectLen) {
    memset(h, 0, sizeof(*h));
    h->name = name;

    if (patchLen < 5 || patchLen > SC_HOOK_MAX_PATCH) {
        ScLog("HOOK %s: refusing, patchLen=%d out of range [5,%d]",
              name, patchLen, SC_HOOK_MAX_PATCH);
        return false;
    }
    if (expectLen > patchLen) {
        ScLog("HOOK %s: refusing, expectLen=%d > patchLen=%d", name, expectLen, patchLen);
        return false;
    }

    // --- signature check: is the code at `target` the code we disassembled? ----
    BYTE actual[SC_HOOK_MAX_PATCH];
    memcpy(actual, target, (size_t)patchLen);
    if (expectLen > 0 && memcmp(actual, expect, (size_t)expectLen) != 0) {
        char got[SC_HOOK_MAX_PATCH * 2 + 1], want[SC_HOOK_MAX_PATCH * 2 + 1];
        ScHexDump(actual, expectLen, got, sizeof(got));
        ScHexDump(expect, expectLen, want, sizeof(want));
        ScLog("HOOK %s: REFUSED at %p -- prologue is %s, expected %s "
              "(wrong address, wrong build, or already hooked)", name, target, got, want);
        return false;
    }

    // --- allocate the trampoline (before any suspension) ----------------------
    BYTE* tramp = (BYTE*)VirtualAlloc(NULL, 64, MEM_COMMIT | MEM_RESERVE,
                                      PAGE_EXECUTE_READWRITE);
    if (!tramp) {
        ScLog("HOOK %s: VirtualAlloc failed gle=%u", name, (unsigned)GetLastError());
        return false;
    }
    memcpy(tramp, target, (size_t)patchLen);
    tramp[patchLen] = 0xE9;  // JMP rel32 back into the original body
    *(DWORD*)(tramp + patchLen + 1) =
        (DWORD)((BYTE*)target + patchLen) - (DWORD)(tramp + patchLen + 5);

    // --- make the target writable (before any suspension) ---------------------
    DWORD oldProtect = 0;
    if (!VirtualProtect(target, (SIZE_T)patchLen, PAGE_EXECUTE_READWRITE, &oldProtect)) {
        ScLog("HOOK %s: VirtualProtect failed gle=%u", name, (unsigned)GetLastError());
        VirtualFree(tramp, 0, MEM_RELEASE);
        return false;
    }

    // --- the only thing done under suspension is the splice -------------------
    BYTE patch[SC_HOOK_MAX_PATCH];
    memset(patch, 0x90, sizeof(patch));  // NOP-fill the tail of the window
    patch[0] = 0xE9;
    *(DWORD*)(patch + 1) = (DWORD)detour - ((DWORD)target + 5);

    memcpy(h->saved, actual, (size_t)patchLen);
    memcpy(target, patch, (size_t)patchLen);

    FlushInstructionCache(GetCurrentProcess(), target, (SIZE_T)patchLen);

    DWORD ignore = 0;
    VirtualProtect(target, (SIZE_T)patchLen, oldProtect, &ignore);

    h->target = target;
    h->detour = detour;
    h->trampoline = tramp;
    h->patchLen = patchLen;
    h->installed = true;

    char sig[SC_HOOK_MAX_PATCH * 2 + 1];
    ScHexDump(h->saved, patchLen, sig, sizeof(sig));
    ScLog("HOOK %s: installed at %p (patch %dB, was %s) detour=%p tramp=%p",
          name, target, patchLen, sig, detour, tramp);
    return true;
}

bool ScHookRemove(ScHook* h) {
    if (!h->installed) return true;

    DWORD oldProtect = 0;
    if (!VirtualProtect(h->target, (SIZE_T)h->patchLen, PAGE_EXECUTE_READWRITE, &oldProtect)) {
        ScLog("HOOK %s: remove VirtualProtect failed gle=%u", h->name,
              (unsigned)GetLastError());
        return false;
    }
    memcpy(h->target, h->saved, (size_t)h->patchLen);
    FlushInstructionCache(GetCurrentProcess(), h->target, (SIZE_T)h->patchLen);
    DWORD ignore = 0;
    VirtualProtect(h->target, (SIZE_T)h->patchLen, oldProtect, &ignore);

    // The trampoline is deliberately LEAKED: another thread may be executing
    // inside it right now, and freeing it would be a use-after-free in the game.
    // 64 bytes per hook, once per process lifetime.
    h->installed = false;
    ScLog("HOOK %s: removed, original bytes restored", h->name);
    return true;
}
