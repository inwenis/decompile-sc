// sc_hook.h -- minimal x86 inline-detour engine.
//
// This is the first code in this project that WRITES to the running game, so the
// design is deliberately narrow and paranoid:
//
//  * No length disassembler. The caller supplies `patchLen` -- the exact number of
//    whole instruction bytes to relocate -- as a constant taken from a disassembly
//    of THIS binary (tools/ghidra/scripts/HookProbe.java prints it, and also prints
//    whether any instruction in that window is PC-relative and therefore NOT
//    relocatable). Guessing an instruction length inside a foreign process is the
//    fastest way to corrupt it; a table checked against the binary is not a guess.
//
//  * Prologue signature check. The caller also supplies the bytes it expects to
//    find. Install REFUSES if memory does not match. A wrong address, a different
//    build, or an already-hooked target therefore fails loudly at install time
//    instead of executing spliced garbage.
//
//  * Allocate and re-protect BEFORE suspending threads. VirtualAlloc/VirtualProtect
//    take process-wide locks; taking one while another thread is suspended holding
//    it would deadlock the game. Only the memcpy happens under suspension.
//
//  * Every hook is removable, and RemoveAll runs on detach.

#ifndef SC_HOOK_H
#define SC_HOOK_H

#include <windows.h>

#define SC_HOOK_MAX_PATCH 16

struct ScHook {
    const char* name;
    void*  target;        // runtime address of the hooked function
    void*  detour;        // our replacement
    BYTE*  trampoline;    // relocated prologue + JMP back to target+patchLen
    int    patchLen;
    BYTE   saved[SC_HOOK_MAX_PATCH];
    bool   installed;
};

// Installs a 5-byte JMP detour at `target`.
//   patchLen  : whole-instruction byte count covering the JMP (>= 5, <= 16)
//   expect    : expected first `expectLen` bytes at target (must be <= patchLen)
// Returns false and logs the reason on any mismatch or Win32 failure.
bool ScHookInstall(ScHook* h, const char* name, void* target, void* detour,
                   int patchLen, const BYTE* expect, int expectLen);

bool ScHookRemove(ScHook* h);

// Suspends every thread in this process except the caller. Returns the number
// suspended. Pair with ScHookResumeThreads(). Exposed because installing several
// hooks under one suspension is both faster and safer than one at a time.
int  ScHookSuspendThreads(void);
void ScHookResumeThreads(void);

#endif // SC_HOOK_H
