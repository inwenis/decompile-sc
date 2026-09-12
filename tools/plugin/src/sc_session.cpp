// sc_session.cpp -- see sc_session.h for the mechanism, the call-graph proof that the
// clock covers a LOAD, and the disassembly the patch window comes from.

#include <windows.h>

#include "sc_addresses.h"
#include "sc_engine.h"
#include "sc_hook.h"
#include "sc_log.h"
#include "sc_session.h"

// Written by the game thread from inside a detour, read by the observer thread and by
// every module's SessionSync. A LONG through the Interlocked* API rather than a plain
// unsigned: the bump is a read-modify-write, and no reader may see a torn or stale value.
static volatile LONG g_epoch = 1;

static volatile LONG g_stat[SC_SESSION_STAT__COUNT] = { 0, 0 };
static volatile LONG g_epochAtLastLoad = 0;

// A PLAIN ALIGNED LOAD, deliberately: this is on the fast path of every adopting
// module's SessionSync, and those sit inside the status dispatcher, which runs hundreds
// of thousands of times a second. Do NOT "make it safe" with
// `InterlockedCompareExchange(&g_epoch, 0, 0)`: it is not safer here and it is not free
// -- measured at 7.67 ns/call over 200,000,000 calls against an empty control loop,
// because a LOCK CMPXCHG is a locked read-modify-write of a line the game thread writes.
// The plain load is correct as a property of the platform: in a 32-bit x86 process an
// aligned 4-byte load cannot tear, and the only writer is InterlockedIncrement, a full
// barrier, so a reader sees the old value or the new one and nothing else. `volatile`
// stops the compiler hoisting the load out of a caller's loop.
unsigned ScSessionEpoch(void) {
    const LONG e = g_epoch;
    return (unsigned)(e > 0 ? e : 1);
}

unsigned ScSessionStat(int which) {
    if (which < 0 || which >= SC_SESSION_STAT__COUNT) return 0;
    return (unsigned)InterlockedCompareExchange(&g_stat[which], 0, 0);
}

unsigned ScSessionEpochAtLastLoad(void) {
    return (unsigned)InterlockedCompareExchange(&g_epochAtLastLoad, 0, 0);
}

// --- the two events --------------------------------------------------------

// Is the engine about to deserialise a save? The load-game FILE* (sc_addresses.h,
// SC_VA_LOAD_GAME_FILE) is non-null only while one is pending. Read PURELY so the log line
// can say which kind of game start this was -- nothing branches on it, because the epoch
// must move for both.
static bool LoadPending(void) {
    if (!ScEngineModuleBase()) return false;
    return *(DWORD*)ScRuntimeAddr(SC_VA_LOAD_GAME_FILE) != 0;
}

static void OnGameStart(void) {
    const LONG now = InterlockedIncrement(&g_epoch);
    InterlockedIncrement(&g_stat[SC_SESSION_STAT_STARTS]);
    // ENTRY as well as outcome (AGENTS.md § "Diagnostics and reporting"): this line is
    // the only evidence that the clock ticked at all, so it names the kind of start
    // rather than merely recording that one happened. A run whose load produces no
    // `load=1` line here is a run whose epoch did not cover the load, and that is the
    // failure mode the whole mechanism has to be checked against.
    ScLog("SESSION start: epoch %u -> %u (load=%d) -- every record stamped with an "
          "earlier epoch now belongs to a game that no longer exists",
          (unsigned)(now - 1), (unsigned)now, LoadPending() ? 1 : 0);
}

static void OnLoadSavedGame(void) {
    const unsigned e = ScSessionEpoch();
    InterlockedIncrement(&g_stat[SC_SESSION_STAT_LOADS]);
    InterlockedExchange(&g_epochAtLastLoad, (LONG)e);
    ScLog("SESSION load: the save deserialiser (0x004CFEF0) is running in epoch %u "
          "after %u game start(s) -- the epoch is OLDER than every unit this load is "
          "about to restore", e, ScSessionStat(SC_SESSION_STAT_STARTS));
}

// --- the detours -----------------------------------------------------------
// Both are spliced into the middle of the engine's own straight-line code with live
// registers, so neither may disturb anything: an explicit thunk saves everything, calls
// a C function that takes no arguments at all, restores, and jumps to the trampoline.

extern "C" void ScSessionOnGameStartThunk(void);
extern "C" void ScSessionOnLoadThunk(void);
extern "C" void* g_sessionStartTramp;
extern "C" void* g_sessionLoadTramp;
void* g_sessionStartTramp = NULL;
void* g_sessionLoadTramp  = NULL;

extern "C" void ScSessionOnGameStartC(void);
extern "C" void ScSessionOnLoadC(void);

asm(
    ".text\n"
    ".globl _ScSessionOnGameStartThunk\n"
"_ScSessionOnGameStartThunk:\n"
    "  pushal\n"
    "  pushfl\n"
    "  call _ScSessionOnGameStartC\n"
    "  popfl\n"
    "  popal\n"
    "  jmp *_g_sessionStartTramp\n"
    ".globl _ScSessionOnLoadThunk\n"
"_ScSessionOnLoadThunk:\n"
    "  pushal\n"
    "  pushfl\n"
    "  call _ScSessionOnLoadC\n"
    "  popfl\n"
    "  popal\n"
    "  jmp *_g_sessionLoadTramp\n"
);

// force_align_arg_pointer: GCC at -O2 assumes a 16-byte-aligned incoming stack, and
// StarCraft is a VC6-class build that guarantees 4.
extern "C" void __attribute__((force_align_arg_pointer)) ScSessionOnGameStartC(void) {
    OnGameStart();
}
extern "C" void __attribute__((force_align_arg_pointer)) ScSessionOnLoadC(void) {
    OnLoadSavedGame();
}

static ScHook g_hkStart;
static ScHook g_hkLoad;

// Verified prologues -- ScHookInstall refuses to patch if memory disagrees.
//
// gameStartClear + 7 (0x004EEC37): ONE whole instruction, exactly five bytes, no
// PC-relative operand. See sc_session.h for why the function's own entry cannot be used.
static const BYTE kSiteGameStart[] = { 0xB8, 0xFF, 0xFF, 0x00, 0x00 };

// loadSavedGame (0x004CFEF0), the function that reads the save file:
//     0x004CFEF0  55        PUSH EBP
//     0x004CFEF1  8BEC      MOV EBP,ESP
//     0x004CFEF3  83EC0C    SUB ESP,0xC
// six bytes, three whole instructions, none PC-relative.
static const BYTE kSiteLoad[] = { 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x0C };

int ScSessionInstall(BYTE* moduleBase, bool enabled) {
    ScEngineSetModuleBase(moduleBase);
    if (!enabled) {
        ScLog("SESSION: not installed (observe mode writes nothing to game memory). "
              "The epoch stays 1 for the life of the process, which is correct -- no "
              "module holds cross-frame state in this mode.");
        return 0;
    }

    int n = 0;
    if (ScHookInstall(&g_hkStart, "gameStartClear+7", ScRuntimeAddr(SC_VA_GAME_START_EPOCH_SITE),
                      (void*)&ScSessionOnGameStartThunk, 5,
                      kSiteGameStart, (int)sizeof(kSiteGameStart))) {
        g_sessionStartTramp = g_hkStart.trampoline;
        ++n;
    }
    // The witness. It buys evidence and nothing else, so its absence does NOT disable
    // the epoch: a failure here is logged and the feature carries on with one hook.
    if (ScHookInstall(&g_hkLoad, "loadSavedGame", ScRuntimeAddr(SC_VA_LOAD_SAVED_GAME),
                      (void*)&ScSessionOnLoadThunk, 6,
                      kSiteLoad, (int)sizeof(kSiteLoad))) {
        g_sessionLoadTramp = g_hkLoad.trampoline;
        ++n;
    }

    if (!g_hkStart.installed) {
        // Say it in the terms the consequence has, not as "a hook failed": with no bump
        // every module's SessionSync is a no-op and records from dead games survive.
        ScLog("SESSION: the game-start splice did NOT go in -- the epoch will never "
              "move, so cross-game records will NOT be dropped. Every #67 survivor is "
              "live again in this process.");
    }
    ScLog("SESSION: %d/2 hook(s) installed, epoch=%u", n, ScSessionEpoch());
    return n;
}

void ScSessionRemove(void) {
    ScHookRemove(&g_hkStart);
    ScHookRemove(&g_hkLoad);
}

void ScSessionLogState(const char* tag) {
    ScLog("SESSION [%s] epoch=%u starts=%u loads=%u epochAtLastLoad=%u installed=%d%s",
          tag ? tag : "-", ScSessionEpoch(),
          ScSessionStat(SC_SESSION_STAT_STARTS), ScSessionStat(SC_SESSION_STAT_LOADS),
          ScSessionEpochAtLastLoad(),
          (g_hkStart.installed ? 1 : 0) + (g_hkLoad.installed ? 1 : 0),
          // A load seen in an epoch older than the current one would mean a save was
          // deserialised before the bump that is supposed to precede it.
          (ScSessionStat(SC_SESSION_STAT_LOADS) > 0 &&
           ScSessionEpochAtLastLoad() != ScSessionEpoch())
              ? "  WARNING: the last load was seen in an epoch that is no longer current"
              : "");
}

// --- test seam -------------------------------------------------------------

void ScSessionTestBegin(void) {
    InterlockedExchange(&g_epoch, 1);
    InterlockedExchange(&g_stat[SC_SESSION_STAT_STARTS], 0);
    InterlockedExchange(&g_stat[SC_SESSION_STAT_LOADS], 0);
    InterlockedExchange(&g_epochAtLastLoad, 0);
}

void ScSessionTestNewGame(void) {
    InterlockedIncrement(&g_epoch);
    InterlockedIncrement(&g_stat[SC_SESSION_STAT_STARTS]);
}

void ScSessionTestLoad(void) {
    InterlockedIncrement(&g_stat[SC_SESSION_STAT_LOADS]);
    InterlockedExchange(&g_epochAtLastLoad, (LONG)ScSessionEpoch());
}
