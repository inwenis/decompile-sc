// sc_session.cpp -- see sc_session.h for the mechanism, the call-graph proof that the
// clock covers a LOAD, and the disassembly the patch window comes from.

#include <windows.h>

#include "sc_addresses.h"
#include "sc_hook.h"
#include "sc_log.h"
#include "sc_session.h"

static BYTE* g_base = NULL;

// Written by the game thread from inside a detour, read by the observer thread and by
// every module's SessionSync. A LONG through the Interlocked* API rather than a plain
// unsigned: the bump is a read-modify-write and the reader must never see a torn or
// stale value on a machine that reorders.
static volatile LONG g_epoch = 1;

static volatile LONG g_stat[SC_SESSION_STAT__COUNT] = { 0, 0 };
static volatile LONG g_epochAtLastLoad = 0;

static void* Rt(DWORD staticVa) { return (void*)(g_base + (staticVa - SC_PREFERRED_IMAGE_BASE)); }

// A PLAIN ALIGNED LOAD, deliberately, and this is the one function in the plugin where
// that choice is worth measuring rather than assuming: it is on the fast path of every
// adopting module's SessionSync, and those sit inside the status dispatcher, which runs
// hundreds of thousands of times a second.
//
// The first version used `InterlockedCompareExchange(&g_epoch, 0, 0)` as a "safe read".
// It is not safer here and it is not free: measured over 200,000,000 calls against an
// empty control loop (work/scratch/054/bench-session.cpp), the interlocked form costs
// 7.67 ns/call, because a LOCK CMPXCHG is a locked read-modify-write of a line the game
// thread is also writing.
//
// The plain load is correct on this target for two reasons that are properties of the
// platform, not of this code. This is a 32-bit x86 process, so an aligned 4-byte load
// cannot tear -- there is no interleaving in which a reader sees half of an epoch. And
// the only writer is InterlockedIncrement, which is a full barrier, so a reader either
// sees the old value or the new one and never anything else. `volatile` stops the
// compiler from hoisting the load out of a caller's loop, which is the only reordering
// that would matter.
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

// ---------------------------------------------------------------------------
// The two events
// ---------------------------------------------------------------------------

// Is the engine about to deserialise a save? `pendingSaveName` (0x006D1218) is the
// heap buffer the Load Game path allocates and `startGame`'s caller frees on the way
// out (0x004E07D5: `MOV EAX,[0x006D1218]; TEST EAX,EAX; JE ...; CALL free; MOV
// dword ptr [0x006D1218],0`). Read here PURELY so the log line can say which kind of
// game start this was -- nothing branches on it, because the epoch must move for both.
static bool LoadPending(void) {
    if (!g_base) return false;
    return *(DWORD*)Rt(SC_VA_PENDING_SAVE_NAME) != 0;
}

static void OnGameStart(void) {
    const LONG now = InterlockedIncrement(&g_epoch);
    InterlockedIncrement(&g_stat[SC_SESSION_STAT_STARTS]);
    // ENTRY as well as outcome (AGENTS.md, task 030): this line is the only evidence
    // that the clock ticked at all, so it names the kind of start rather than merely
    // recording that one happened. A run whose load produces no `load=1` line here is
    // a run whose epoch did not cover the load, and that is the failure mode the whole
    // mechanism has to be checked against.
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

// ---------------------------------------------------------------------------
// The detours
//
// Both are spliced into the middle of the engine's own straight-line code with live
// registers, so neither may disturb anything: an explicit thunk saves everything,
// calls a C function that takes no arguments at all, restores, and jumps to the
// trampoline. Same shape (and same reasons) as sc_circles.cpp's.
// ---------------------------------------------------------------------------

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

// force_align_arg_pointer for the same reason every other entry point the game calls
// carries it: GCC at -O2 assumes a 16-byte-aligned incoming stack, StarCraft is a
// VC6-class build that guarantees 4.
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
// PC-relative operand. See sc_session.h for why the function's own entry cannot be
// used and for the four instructions either side of this one.
static const BYTE kSiteGameStart[] = { 0xB8, 0xFF, 0xFF, 0x00, 0x00 };

// loadSavedGame (0x004CFEF0), the function that reads the save file:
//     0x004CFEF0  55        PUSH EBP
//     0x004CFEF1  8BEC      MOV EBP,ESP
//     0x004CFEF3  83EC0C    SUB ESP,0xC
// six bytes, three whole instructions, none PC-relative.
static const BYTE kSiteLoad[] = { 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x0C };

int ScSessionInstall(BYTE* moduleBase, bool enabled) {
    g_base = moduleBase;
    if (!enabled) {
        ScLog("SESSION: not installed (observe mode writes nothing to game memory). "
              "The epoch stays 1 for the life of the process, which is correct -- no "
              "module holds cross-frame state in this mode.");
        return 0;
    }

    int n = 0;
    if (ScHookInstall(&g_hkStart, "gameStartClear+7", Rt(SC_VA_GAME_START_EPOCH_SITE),
                      (void*)&ScSessionOnGameStartThunk, 5,
                      kSiteGameStart, (int)sizeof(kSiteGameStart))) {
        g_sessionStartTramp = g_hkStart.trampoline;
        ++n;
    }
    // The witness. Its absence does NOT disable the epoch: it costs nothing at runtime
    // and buys nothing but evidence, so a failure here is logged and the feature carries
    // on with one hook.
    if (ScHookInstall(&g_hkLoad, "loadSavedGame", Rt(SC_VA_LOAD_SAVED_GAME),
                      (void*)&ScSessionOnLoadThunk, 6,
                      kSiteLoad, (int)sizeof(kSiteLoad))) {
        g_sessionLoadTramp = g_hkLoad.trampoline;
        ++n;
    }

    if (!g_hkStart.installed) {
        // Say it in the terms the consequence has, not as "a hook failed": with no bump
        // every module's SessionSync becomes a no-op and issue #67's whole class is back.
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
          // The one comparison a reader should not have to make by hand. A load seen in
          // an epoch older than the current one would mean a save was deserialised
          // before the bump that is supposed to precede it.
          (ScSessionStat(SC_SESSION_STAT_LOADS) > 0 &&
           ScSessionEpochAtLastLoad() != ScSessionEpoch())
              ? "  WARNING: the last load was seen in an epoch that is no longer current"
              : "");
}

// ---------------------------------------------------------------------------
// Test seam
// ---------------------------------------------------------------------------

void ScSessionTestBegin(void) {
    InterlockedExchange(&g_epoch, 1);
    InterlockedExchange(&g_stat[SC_SESSION_STAT_STARTS], 0);
    InterlockedExchange(&g_stat[SC_SESSION_STAT_LOADS], 0);
    InterlockedExchange(&g_epochAtLastLoad, 0);
    g_base = NULL;
}

void ScSessionTestNewGame(void) {
    InterlockedIncrement(&g_epoch);
    InterlockedIncrement(&g_stat[SC_SESSION_STAT_STARTS]);
}

void ScSessionTestLoad(void) {
    InterlockedIncrement(&g_stat[SC_SESSION_STAT_LOADS]);
    InterlockedExchange(&g_epochAtLastLoad, (LONG)ScSessionEpoch());
}
