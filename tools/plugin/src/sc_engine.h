// sc_engine.h -- the plugin's ONE relocation layer, and the probe every read of
// game memory goes through first.
//
// StarCraft.exe is linked at SC_PREFERRED_IMAGE_BASE (0x00400000) and loaded
// somewhere else, so every static VA in sc_addresses.h has to be shifted by the
// same delta before it is touched:
//
//     runtime = actualModuleBase + (staticVA - SC_PREFERRED_IMAGE_BASE)
//
// The image is loaded once per process and never moves, so that delta is ONE
// process-wide value. It used to be twelve: a `static BYTE* g_base` and a
// three-line `Rt()` copied into every module .cpp, because each of those modules
// was written by a worker on its own branch and a shared header would have made
// a sibling task rebase (the reason is still quoted in sc_prodfan.cpp's history).
// This header is what those twelve copies collapse into.

#ifndef SC_ENGINE_H
#define SC_ENGINE_H

#include <windows.h>

#include "sc_addresses.h"

// Where StarCraft.exe actually is. Written ONLY through ScEngineSetModuleBase;
// read on the hot paths through the inline accessors below, which is why it is
// an extern global rather than a getter call.
extern BYTE* g_scModuleBase;

// Set from whoever learns the load address first:
//   * the plugin  -- scplugin.cpp's DllMain, off GetModuleHandleA(NULL);
//   * hooktest.exe -- the fake module image it builds, through a module's
//     Sc*TestBegin.
//
// A NULL is IGNORED, and that is the one rule worth knowing about this header. A
// module's Init/TestBegin still takes a `moduleBase` because passing NULL is how
// hooktest says "leave THIS module inert" -- it is a statement about one module,
// never a claim that the image moved or went away. Honouring it here would blind
// every module that is still live off the same image.
void ScEngineSetModuleBase(BYTE* moduleBase);

// "Is there a game image to read at all?" -- what the modules used to ask by
// testing their own g_base for NULL.
static inline BYTE* ScEngineModuleBase(void) { return g_scModuleBase; }

// An SC_VA_* out of sc_addresses.h -> where it actually is in this process.
static inline void* ScRuntimeAddr(DWORD staticVa) {
    return (void*)(g_scModuleBase + (staticVa - SC_PREFERRED_IMAGE_BASE));
}

// The same answer as a DWORD, for the many reads that index off it.
static inline DWORD ScRuntimeVa(DWORD staticVa) {
    return (DWORD)(DWORD_PTR)ScRuntimeAddr(staticVa);
}

// Is [addr, addr+len) committed and readable RIGHT NOW?
//
// Every dereference of an address the GAME handed us -- a dialog pointer, a
// sprite, a font handle -- is guarded by this. The plugin runs inside the game's
// own threads, so a stale pointer has to fail closed here rather than fault
// there. Addresses the plugin computed itself from a validated base do not need
// it; the bounds check that validated the base is the guard.
//
// Two spellings of one question, because half the callers hold a VA and half hold
// a pointer. There is no overload: `ScReadable(NULL, 4)` would be ambiguous, and
// this probe is exactly where an ambiguity must not be resolved by luck.
bool ScReadable(DWORD addr, DWORD len);

// Initialise `cs` the first time this is reached and never again. Two modules hold a
// critical section they cannot initialise at load time (DllMain runs under the loader
// lock) and both had their own copy of this.
static inline void ScEnsureLock(CRITICAL_SECTION* cs, bool* ready) {
    if (!*ready) { InitializeCriticalSection(cs); *ready = true; }
}
bool ScReadableAt(const void* addr, size_t len);

// The probe plus the copy: reads `len` bytes out only if the whole range passes.
// A wrong static address produces a log line saying "unreadable" instead of a
// crashed game, which is the entire reason the observer can walk engine lists at
// all.
bool ScSafeRead(const void* addr, void* out, size_t len);

#endif // SC_ENGINE_H
