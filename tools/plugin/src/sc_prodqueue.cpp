// sc_prodqueue.cpp -- more than five items in a building's production queue.
//
// Read sc_prodqueue.h first: it states the mechanism and the resource rule. The
// evidence for every address and every constant is research/production-queue.md.
//
// Everything in this file runs on the GAME THREAD, from one of three detours. The only
// exception is ScProdQueueLogState, which the observer thread calls from the marker
// channel and which never writes.

#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "sc_addresses.h"
#include "sc_hook.h"
#include "sc_log.h"
#include "sc_prodqueue.h"

#define SC_GAME_ENTRY __attribute__((force_align_arg_pointer))

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

struct ProdRecord {
    DWORD unit;          // CUnit*, bounds/stride-validated when the record was made
    BYTE  uniqueness;    // CUnit+0xA5 at that moment -- the slot-reuse test
    BYTE  player;        // CUnit+0x4C at that moment
    int   count;
    WORD  types[SC_PRODQ_HARD_MAX];   // FIFO: [0] is promoted next
};

static BYTE* g_base    = NULL;
static bool  g_enabled = false;
static bool  g_testing = false;      // driven by hooktest with no hooks anywhere
static int   g_maxTotal = SC_PRODQ_DEFAULT_MAX;

static CRITICAL_SECTION g_lock;
static bool g_lockReady = false;

static ProdRecord g_rec[SC_PRODQ_MAX_BUILDINGS];
static int        g_recCount = 0;

static int g_stat[SC_PRODQ_STAT__COUNT] = { 0 };

// The deep garbage collection (the player-unit-list walk) is O(units) per record, and
// the tick detour runs for every producing building on every frame. So the tick does
// the cheap terms only and the walk runs on the two RARE detours -- a Train or a Cancel
// Train command, i.e. a player action. A building that dies while the player is idle is
// therefore refunded on their next click rather than on the next frame; that latency is
// deliberate and is the one thing this split costs.
static bool g_deepGc = false;

static void* Rt(DWORD staticVa) { return (void*)(g_base + (staticVa - SC_PREFERRED_IMAGE_BASE)); }
static DWORD RtA(DWORD staticVa) { return (DWORD)(DWORD_PTR)Rt(staticVa); }

// ---------------------------------------------------------------------------
// Unit validation -- the same shape as sc_fanout's UnitPtrValid/PassesGate, because the
// question is the same one: is this pointer still the building we wrote down?
// ---------------------------------------------------------------------------

static bool UnitPtrValid(DWORD ptr) {
    if (!ptr) return false;
    DWORD arrayBase = RtA(SC_VA_UNIT_ARRAY_BASE);
    if (ptr < arrayBase) return false;
    DWORD off = ptr - arrayBase;
    if (off % SC_CUNIT_SIZE != 0) return false;
    return (off / SC_CUNIT_SIZE + 1) <= SC_MAX_UNIT_INDEX;
}

// Reachable from playerUnitList[player] via CUnit+0x6C. A unit removed from play is
// unlinked there (sc_addresses.h, SC_VA_PLAYER_UNIT_LIST), and a removed building is
// exactly what has to give its queued resources back.
static bool InPlayerUnitList(DWORD ptr, BYTE player) {
    if (player >= SC_MAX_PLAYERS) return false;
    DWORD head = *(DWORD*)(RtA(SC_VA_PLAYER_UNIT_LIST) + (DWORD)player * 4);
    int n = 0;
    for (DWORD u = head; u && n < SC_MAX_UNITS_WALK; ++n) {
        if (!UnitPtrValid(u)) return false;
        if (u == ptr) return true;
        u = *(DWORD*)(u + SC_CUNIT_OFF_LIST_NEXT);
    }
    return false;
}

// `deep` adds the list walk. Without it this is four loads.
static bool RecordStillLive(const ProdRecord* r, bool deep) {
    if (!UnitPtrValid(r->unit)) return false;
    if (*(BYTE*)(r->unit + SC_CUNIT_OFF_UNIQUENESS) != r->uniqueness) return false;
    if (*(BYTE*)(r->unit + SC_CUNIT_OFF_PLAYER) != r->player) return false;
    if (*(DWORD*)(r->unit + SC_CUNIT_OFF_HITPOINTS) == 0) return false;
    if (deep && !InPlayerUnitList(r->unit, r->player)) return false;
    return true;
}

// ---------------------------------------------------------------------------
// The engine's queue, read and written exactly the way the engine does
// ---------------------------------------------------------------------------

static WORD QueueSlot(DWORD unit, int slot) {
    return *(WORD*)(unit + SC_CUNIT_OFF_BUILD_QUEUE + (DWORD)slot * 2);
}
static void SetQueueSlot(DWORD unit, int slot, WORD type) {
    *(WORD*)(unit + SC_CUNIT_OFF_BUILD_QUEUE + (DWORD)slot * 2) = type;
}

// A faithful re-implementation of findFreeBuildQueueSlot (0x004669B0), whose thirteen
// instructions are quoted in research/production-queue.md 3.1: start at the head, wrap
// past slot 4, five tries, and 5 means "there is no free slot". Re-implemented rather
// than called because the engine's version takes its CUnit* in EDX and this one is also
// wanted offline, in hooktest, where there is no engine to call.
static int FindFreeSlot(DWORD unit) {
    unsigned slot = *(BYTE*)(unit + SC_CUNIT_OFF_BUILD_QUEUE_SLOT);
    for (int tries = SC_BUILD_QUEUE_SLOTS; tries > 0; --tries) {
        if (slot >= SC_BUILD_QUEUE_SLOTS) slot = 0;
        if (QueueSlot(unit, (int)slot) == SC_BUILD_QUEUE_EMPTY) return (int)slot;
        ++slot;
    }
    return SC_BUILD_QUEUE_SLOTS;
}

static int EngineQueueLength(DWORD unit) {
    int n = 0;
    for (int i = 0; i < SC_BUILD_QUEUE_SLOTS; ++i) {
        if (QueueSlot(unit, i) != SC_BUILD_QUEUE_EMPTY) ++n;
    }
    return n;
}

// ---------------------------------------------------------------------------
// Money
//
// Both directions read the SAME two per-type tables the engine's own spend
// (addToBuildQueue 0x00467250, through setPendingCost 0x0042D140) and its own refund
// (refundByType 0x0042CEC0) read, and both honour the same units.dat "this type moves
// no resources" bit. That is what makes "paid exactly once" an arithmetic identity
// rather than a hope.
// ---------------------------------------------------------------------------

static bool TypeMovesResources(unsigned type) {
    BYTE f = *(BYTE*)(RtA(SC_VA_UNIT_COST_FLAGS) + (DWORD)type * 4);
    return (f & SC_UNIT_COST_FLAG_NO_SPEND) == 0;
}
static DWORD MineralCost(unsigned type) {
    return *(WORD*)(RtA(SC_VA_UNIT_MINERAL_COST) + (DWORD)type * 2);
}
static DWORD GasCost(unsigned type) {
    return *(WORD*)(RtA(SC_VA_UNIT_GAS_COST) + (DWORD)type * 2);
}
static DWORD* MineralsOf(BYTE player) {
    return (DWORD*)(RtA(SC_VA_PLAYER_MINERALS) + (DWORD)player * 4);
}
static DWORD* GasOf(BYTE player) {
    return (DWORD*)(RtA(SC_VA_PLAYER_GAS) + (DWORD)player * 4);
}

static bool CanAfford(BYTE player, unsigned type) {
    if (player >= SC_MAX_PLAYERS) return false;
    if (!TypeMovesResources(type)) return true;
    return *MineralsOf(player) >= MineralCost(type) && *GasOf(player) >= GasCost(type);
}

// Both of these are no-ops for a type whose cost flag says the engine would not have
// moved anything either.
static void Spend(BYTE player, unsigned type) {
    if (player >= SC_MAX_PLAYERS || !TypeMovesResources(type)) return;
    *MineralsOf(player) -= MineralCost(type);
    *GasOf(player)      -= GasCost(type);
    g_stat[SC_PRODQ_STAT_MINERALS_SPENT] += (int)MineralCost(type);
    g_stat[SC_PRODQ_STAT_GAS_SPENT]      += (int)GasCost(type);
}
static void Refund(BYTE player, unsigned type) {
    if (player >= SC_MAX_PLAYERS || !TypeMovesResources(type)) return;
    *MineralsOf(player) += MineralCost(type);
    *GasOf(player)      += GasCost(type);
    g_stat[SC_PRODQ_STAT_MINERALS_REFUNDED] += (int)MineralCost(type);
    g_stat[SC_PRODQ_STAT_GAS_REFUNDED]      += (int)GasCost(type);
}

// ---------------------------------------------------------------------------
// Records
// ---------------------------------------------------------------------------

static ProdRecord* FindRecord(DWORD unit) {
    for (int i = 0; i < g_recCount; ++i) if (g_rec[i].unit == unit) return &g_rec[i];
    return NULL;
}

static void DropRecordAt(int i) {
    if (i < 0 || i >= g_recCount) return;
    g_rec[i] = g_rec[g_recCount - 1];
    --g_recCount;
}

// A record whose building has gone gives its items back. Vanilla does the same for the
// engine's own five: the unit-removal path 0x0049FD00 calls cancelAllAndClearQueue
// (0x00466E80), which refunds every occupied slot before clearing the array
// (research/production-queue.md 4.4). Matching that is what keeps a destroyed building
// from being a way to burn minerals.
static void RefundRecord(ProdRecord* r, const char* why) {
    for (int i = 0; i < r->count; ++i) {
        Refund(r->player, r->types[i]);
        ++g_stat[SC_PRODQ_STAT_REFUNDED];
    }
    if (r->count > 0) {
        ScLog("PRODQEV refund unit=0x%08X player=%u items=%d reason=%s",
              (unsigned)r->unit, (unsigned)r->player, r->count, why);
    }
    r->count = 0;
}

static void CollectGarbage(bool deep) {
    for (int i = g_recCount - 1; i >= 0; --i) {
        if (RecordStillLive(&g_rec[i], deep) && g_rec[i].count > 0) continue;
        if (g_rec[i].count > 0) RefundRecord(&g_rec[i], deep ? "building-gone" : "building-gone-fast");
        DropRecordAt(i);
    }
}

// ---------------------------------------------------------------------------
// Promotion: hand as many overflow items as there are free slots to the engine
//
// This is a bare store into the engine's own ring, at the slot the engine's own
// free-slot rule picks, and it moves NO resources -- the item was paid for when it was
// accepted. Nothing else in addToBuildQueue applies here: the cost tables it fills are
// consumed by its own deduction two instructions later, the secondary order is already
// set (the queue cannot be non-empty otherwise), and the building-AI mirror arrays it
// never touches either.
// ---------------------------------------------------------------------------

static int PromoteInto(ProdRecord* r) {
    int promoted = 0;
    while (r->count > 0) {
        int slot = FindFreeSlot(r->unit);
        if (slot >= SC_BUILD_QUEUE_SLOTS) break;
        WORD type = r->types[0];
        SetQueueSlot(r->unit, slot, type);
        for (int i = 1; i < r->count; ++i) r->types[i - 1] = r->types[i];
        --r->count;
        ++promoted;
        ++g_stat[SC_PRODQ_STAT_PROMOTED];
        ScLog("PRODQEV promote unit=0x%08X type=0x%03X -> slot=%d overflowLeft=%d",
              (unsigned)r->unit, (unsigned)type, slot, r->count);
    }
    if (promoted && !g_testing) {
        // Tell the status area to redraw, the way the Train handler's own tail does
        // (0x004C1C7C writes this flag). Without it the fifth icon can lag a frame.
        *(BYTE*)Rt(SC_VA_STAT_DIRTY) = 1;
    }
    return promoted;
}

// ---------------------------------------------------------------------------
// Core entry points
// ---------------------------------------------------------------------------

void ScProdQueueOnTrain(DWORD unit, unsigned type, bool wasFull) {
    if (!g_enabled || !unit) return;
    EnterCriticalSection(&g_lock);
    CollectGarbage(true);

    do {
        if (!UnitPtrValid(unit)) break;
        BYTE player = *(BYTE*)(unit + SC_CUNIT_OFF_PLAYER);
        ProdRecord* r = FindRecord(unit);

        if (wasFull) {
            // The engine ran and could not have taken it: findFreeBuildQueueSlot
            // returned 5, so addToBuildQueue returned 0 without touching the array or
            // the player's resources. The item is ours to hold or to refuse.
            if (type >= SC_MAX_TRAINABLE_UNIT_ID) break;   // the handler's own bound
            if (player >= SC_MAX_PLAYERS) break;

            int held = r ? r->count : 0;
            if (SC_BUILD_QUEUE_SLOTS + held >= g_maxTotal || (!r && g_recCount >= SC_PRODQ_MAX_BUILDINGS)) {
                ++g_stat[SC_PRODQ_STAT_REFUSED_FULL];
                ScLog("PRODQEV refuse-full unit=0x%08X type=0x%03X logical=%d max=%d",
                      (unsigned)unit, type, SC_BUILD_QUEUE_SLOTS + held, g_maxTotal);
                break;
            }
            if (!CanAfford(player, type)) {
                ++g_stat[SC_PRODQ_STAT_REFUSED_COST];
                ScLog("PRODQEV refuse-cost unit=0x%08X type=0x%03X need=%u/%u have=%u/%u",
                      (unsigned)unit, type, (unsigned)MineralCost(type), (unsigned)GasCost(type),
                      (unsigned)*MineralsOf(player), (unsigned)*GasOf(player));
                break;
            }
            if (!r) {
                r = &g_rec[g_recCount++];
                r->unit       = unit;
                r->uniqueness = *(BYTE*)(unit + SC_CUNIT_OFF_UNIQUENESS);
                r->player     = player;
                r->count      = 0;
            }
            Spend(player, type);
            r->types[r->count++] = (WORD)type;
            ++g_stat[SC_PRODQ_STAT_CAPTURED];
            ScLog("PRODQEV capture unit=0x%08X type=0x%03X overflow=%d logical=%d "
                  "paid=%u/%u left=%u/%u",
                  (unsigned)unit, type, r->count, SC_BUILD_QUEUE_SLOTS + r->count,
                  (unsigned)MineralCost(type), (unsigned)GasCost(type),
                  (unsigned)*MineralsOf(player), (unsigned)*GasOf(player));
        }

        // Whether or not this command was ours, never leave a free slot behind: a slot
        // that frees between two frames would otherwise let the NEXT command jump the
        // overflow queue.
        if (r && r->count > 0) PromoteInto(r);
        if (r && r->count == 0) DropRecordAt((int)(r - g_rec));
    } while (0);

    LeaveCriticalSection(&g_lock);
}

void ScProdQueueOnTick(DWORD unit) {
    if (!g_enabled || !unit || g_recCount == 0) return;
    EnterCriticalSection(&g_lock);

    if (g_deepGc) { CollectGarbage(true); g_deepGc = false; }
    else CollectGarbage(false);

    ProdRecord* r = FindRecord(unit);
    if (r) {
        PromoteInto(r);
        if (r->count == 0) DropRecordAt((int)(r - g_rec));
    }

    LeaveCriticalSection(&g_lock);
}

bool ScProdQueueOnCancel(DWORD unit, unsigned payload) {
    if (!g_enabled || !unit) return false;
    bool consumed = false;
    EnterCriticalSection(&g_lock);
    CollectGarbage(true);

    // Only the "cancel the last queued item" form (payload 0xFE, the engine's own
    // cancelLastQueued at 0x00466E40) can be ours, and only when we are actually
    // holding the tail of this building's logical queue. Everything else -- a specific
    // slot 0..4, or the 0xFF no-op -- is the engine's, and it refunds it itself.
    ProdRecord* r = FindRecord(unit);
    if (r && r->count > 0 && payload == SC_CANCEL_TRAIN_LAST) {
        WORD type = r->types[--r->count];
        Refund(r->player, type);
        ++g_stat[SC_PRODQ_STAT_CANCELLED];
        ScLog("PRODQEV cancel-last unit=0x%08X type=0x%03X overflowLeft=%d back=%u/%u",
              (unsigned)unit, (unsigned)type, r->count,
              (unsigned)MineralCost(type), (unsigned)GasCost(type));
        if (r->count == 0) DropRecordAt((int)(r - g_rec));
        consumed = true;
    }

    LeaveCriticalSection(&g_lock);
    return consumed;
}

// ---------------------------------------------------------------------------
// Oracles
// ---------------------------------------------------------------------------

// Formats a building's five engine slots, read straight out of CUnit+0x98.
static int FormatEngineQueue(DWORD unit, char* out, int outLen) {
    int used = 0;
    out[0] = '\0';
    for (int s = 0; s < SC_BUILD_QUEUE_SLOTS && used + 8 < outLen; ++s) {
        used += _snprintf(out + used, outLen - used, "%s0x%03X",
                          s ? "," : "", (unsigned)QueueSlot(unit, s));
    }
    return EngineQueueLength(unit);
}

void ScProdQueueLogState(const char* tag) {
    if (!g_enabled || !g_lockReady) return;
    EnterCriticalSection(&g_lock);

    // The SOLE SELECTED building, tracked or not. Without this the oracle is silent
    // exactly when the plugin is holding nothing -- and "the plugin is holding nothing"
    // and "the oracle did not run" would be the same observation, which is the failure
    // mode AGENTS.md's absence-assertion rule exists to stop. It also gives a test the
    // engine's own five slots to watch drain, read from the building's memory.
    {
        DWORD* sel = (DWORD*)Rt(SC_VA_ACTIVE_PLAYER_SELECTION);
        DWORD u = sel[0];
        if (u && !sel[1] && UnitPtrValid(u)) {
            char eng[96];
            int engineLen = FormatEngineQueue(u, eng, (int)sizeof(eng));
            ProdRecord* r = FindRecord(u);
            BYTE player = *(BYTE*)(u + SC_CUNIT_OFF_PLAYER);
            ScLog("PRODQSEL [%s] unit=0x%08X type=0x%03X player=%u head=%u engineLen=%d "
                  "engine=[%s] overflow=%d logical=%d minerals=%u gas=%u",
                  tag ? tag : "-", (unsigned)u,
                  (unsigned)*(WORD*)(u + SC_CUNIT_OFF_UNIT_ID), (unsigned)player,
                  (unsigned)*(BYTE*)(u + SC_CUNIT_OFF_BUILD_QUEUE_SLOT), engineLen, eng,
                  r ? r->count : 0, engineLen + (r ? r->count : 0),
                  player < SC_MAX_PLAYERS ? (unsigned)*MineralsOf(player) : 0u,
                  player < SC_MAX_PLAYERS ? (unsigned)*GasOf(player) : 0u);
        } else {
            ScLog("PRODQSEL [%s] (no single building selected)", tag ? tag : "-");
        }
    }

    for (int i = 0; i < g_recCount; ++i) {
        ProdRecord* r = &g_rec[i];
        char eng[96];
        int engineLen = 0;
        if (UnitPtrValid(r->unit)) engineLen = FormatEngineQueue(r->unit, eng, (int)sizeof(eng));
        else lstrcpynA(eng, "(gone)", (int)sizeof(eng));
        char ovf[128];
        int used = 0;
        ovf[0] = '\0';
        for (int k = 0; k < r->count && used + 8 < (int)sizeof(ovf); ++k) {
            used += _snprintf(ovf + used, sizeof(ovf) - used, "%s0x%03X",
                              k ? "," : "", (unsigned)r->types[k]);
        }
        if (r->count == 0) lstrcpynA(ovf, "(none)", (int)sizeof(ovf));

        ScLog("PRODQ [%s] unit=0x%08X player=%u head=%u engineLen=%d engine=[%s] "
              "overflow=%d overflowTypes=[%s] logical=%d minerals=%u gas=%u",
              tag ? tag : "-", (unsigned)r->unit, (unsigned)r->player,
              UnitPtrValid(r->unit) ? *(BYTE*)(r->unit + SC_CUNIT_OFF_BUILD_QUEUE_SLOT) : 0xFFu,
              engineLen, eng, r->count, ovf, engineLen + r->count,
              r->player < SC_MAX_PLAYERS ? (unsigned)*MineralsOf(r->player) : 0u,
              r->player < SC_MAX_PLAYERS ? (unsigned)*GasOf(r->player) : 0u);
    }
    // ALWAYS a summary line, even with zero records -- an absence has to be
    // positively reported or "the oracle did not run" and "there is nothing queued"
    // read identically (AGENTS.md, absence assertions).
    ScLog("PRODQ [%s] buildings=%d max=%d captured=%d promoted=%d cancelled=%d "
          "refunded=%d refusedFull=%d refusedCost=%d",
          tag ? tag : "-", g_recCount, g_maxTotal,
          g_stat[SC_PRODQ_STAT_CAPTURED], g_stat[SC_PRODQ_STAT_PROMOTED],
          g_stat[SC_PRODQ_STAT_CANCELLED], g_stat[SC_PRODQ_STAT_REFUNDED],
          g_stat[SC_PRODQ_STAT_REFUSED_FULL], g_stat[SC_PRODQ_STAT_REFUSED_COST]);
    LeaveCriticalSection(&g_lock);
}

void ScProdQueueLogStats(void) {
    if (!g_enabled) return;
    ScLog("PRODQSTATS captured=%d promoted=%d cancelled=%d refunded=%d refusedFull=%d "
          "refusedCost=%d mineralsSpent=%d mineralsRefunded=%d gasSpent=%d gasRefunded=%d "
          "tracked=%d",
          g_stat[SC_PRODQ_STAT_CAPTURED], g_stat[SC_PRODQ_STAT_PROMOTED],
          g_stat[SC_PRODQ_STAT_CANCELLED], g_stat[SC_PRODQ_STAT_REFUNDED],
          g_stat[SC_PRODQ_STAT_REFUSED_FULL], g_stat[SC_PRODQ_STAT_REFUSED_COST],
          g_stat[SC_PRODQ_STAT_MINERALS_SPENT], g_stat[SC_PRODQ_STAT_MINERALS_REFUNDED],
          g_stat[SC_PRODQ_STAT_GAS_SPENT], g_stat[SC_PRODQ_STAT_GAS_REFUNDED], g_recCount);
}

int ScProdQueueOverflowCount(DWORD unit) {
    ProdRecord* r = FindRecord(unit);
    return r ? r->count : -1;
}
int ScProdQueueOverflowAt(DWORD unit, int i) {
    ProdRecord* r = FindRecord(unit);
    if (!r || i < 0 || i >= r->count) return -1;
    return (int)r->types[i];
}
int ScProdQueueTrackedBuildings(void) { return g_recCount; }
int ScProdQueueStat(int which) {
    if (which < 0 || which >= SC_PRODQ_STAT__COUNT) return 0;
    return g_stat[which];
}

// ---------------------------------------------------------------------------
// Detours
//
// The building a production command acts on is the ONE unit selected: both receive
// handlers reset selectionIterator (0x006284B6) and then require
// getActivePlayerNextSelection to yield exactly one unit
// (research/production-queue.md 2.2 quotes both prologues). Reading
// activePlayerSelection[0] and requiring [1] to be null is the same test without
// calling into the engine.
// ---------------------------------------------------------------------------

static ScHook g_hkTrain;
static ScHook g_hkCancel;
static ScHook g_hkTick;

typedef void (__attribute__((stdcall)) *CancelTrainFn)(DWORD);

static DWORD SoleSelectedUnit(void) {
    DWORD* sel = (DWORD*)Rt(SC_VA_ACTIVE_PLAYER_SELECTION);
    DWORD u = sel[0];
    if (!u || sel[1]) return 0;
    return UnitPtrValid(u) ? u : 0;
}

// Calls a trampoline whose target takes its only argument in EAX and returns void.
static void CallEax(void* fn, DWORD eax) {
    DWORD scratch;
    __asm__ __volatile__("calll *%[fn]"
                         : "=a"(scratch)
                         : "0"(eax), [fn] "r"(fn)
                         : "ecx", "edx", "cc", "memory");
    (void)scratch;
}

// cmdrecvTrain (0x004C1C20): EAX = the command bytes, void, bare RET.
extern "C" void SC_GAME_ENTRY ScProdTrainDetour(DWORD cmd) {
    DWORD unit = SoleSelectedUnit();
    unsigned type = 0xFFFFu;
    bool wasFull = false;
    if (unit) {
        // Sampled BEFORE the engine runs: afterwards, a queue that was full and a queue
        // the engine has just filled its last slot of look exactly the same.
        wasFull = FindFreeSlot(unit) >= SC_BUILD_QUEUE_SLOTS;
        if (cmd) type = *(WORD*)(cmd + 1);
    }
    CallEax(g_hkTrain.trampoline, cmd);
    g_deepGc = true;
    if (unit) ScProdQueueOnTrain(unit, type, wasFull);
}

// productionTick (0x00468420): EAX = CUnit*, void, bare RET. Post-hook -- the frame a
// slot frees is the frame the next overflow item takes it.
extern "C" void SC_GAME_ENTRY ScProdTickDetour(DWORD unit) {
    CallEax(g_hkTick.trampoline, unit);
    if (UnitPtrValid(unit)) ScProdQueueOnTick(unit);
}

// Both targets take their argument in EAX and no C calling convention says so, so each
// gets a two-instruction thunk that turns EAX into a cdecl argument. EBX/ESI/EDI/EBP are
// preserved by the C callee, which is what the engine's own callers assume.
extern "C" void ScProdTrainThunk(void);
asm(".text\n"
    ".globl _ScProdTrainThunk\n"
    "_ScProdTrainThunk:\n"
    "  pushl %eax\n"
    "  call  _ScProdTrainDetour\n"
    "  addl  $4, %esp\n"
    "  ret\n");

extern "C" void ScProdTickThunk(void);
asm(".text\n"
    ".globl _ScProdTickThunk\n"
    "_ScProdTickThunk:\n"
    "  pushl %eax\n"
    "  call  _ScProdTickDetour\n"
    "  addl  $4, %esp\n"
    "  ret\n");

// cmdrecvCancelTrain (0x004C0100): __stdcall(const u8* cmd), RET 4 -- expressible, so no
// thunk. PRE-hook: when the plugin owns the tail of the logical queue, a "cancel the
// last item" is ours and the engine's handler must not also run.
static void __attribute__((stdcall)) SC_GAME_ENTRY HkCmdrecvCancelTrain(DWORD cmd) {
    DWORD unit = SoleSelectedUnit();
    unsigned payload = cmd ? *(WORD*)(cmd + 1) : SC_CANCEL_TRAIN_NONE;
    g_deepGc = true;
    if (unit && ScProdQueueOnCancel(unit, payload)) return;
    ((CancelTrainFn)g_hkCancel.trampoline)(cmd);
}

// Verified prologues, dumped out of the working-copy binary
// (work/scratch/025/peek.py, quoted in research/production-queue.md 6.1).
// ScHookInstall refuses to patch if memory disagrees.
//   004C1C20  56          PUSH ESI
//   004C1C21  57          PUSH EDI
//   004C1C22  8B F8       MOV EDI,EAX
//   004C1C24  C6 05 ..    MOV byte ptr [0x006284B6],0x0     -> 11 bytes, 4 instructions
static const BYTE kPrologueTrain[]  = { 0x56, 0x57, 0x8B, 0xF8, 0xC6, 0x05,
                                        0xB6, 0x84, 0x62, 0x00, 0x00 };
//   004C0100  55          PUSH EBP
//   004C0101  8B EC       MOV EBP,ESP
//   004C0103  57          PUSH EDI
//   004C0104  C6 05 ..    MOV byte ptr [0x006284B6],0x0     -> 11 bytes, 4 instructions
static const BYTE kPrologueCancel[] = { 0x55, 0x8B, 0xEC, 0x57, 0xC6, 0x05,
                                        0xB6, 0x84, 0x62, 0x00, 0x00 };
//   00468420  56          PUSH ESI
//   00468421  8B F0       MOV ESI,EAX
//   00468423  8B 86 DC..  MOV EAX,dword ptr [ESI + 0xDC]    -> 9 bytes, 3 instructions
static const BYTE kPrologueTick[]   = { 0x56, 0x8B, 0xF0, 0x8B, 0x86,
                                        0xDC, 0x00, 0x00, 0x00 };
// None of the three windows contains a PC-relative instruction, so all three relocate
// into a trampoline unchanged (the absolute `MOV [0x006284B6],0` is not PC-relative).

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

bool ScProdQueueEnabled(void) {
    char buf[16];
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_PRODQ", buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return false;
    return buf[0] == '1' || buf[0] == 'y' || buf[0] == 'Y';
}

static int ResolveMax(void) {
    char buf[16];
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_PRODQ_MAX", buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return SC_PRODQ_DEFAULT_MAX;
    int v = atoi(buf);
    if (v < SC_BUILD_QUEUE_SLOTS) v = SC_BUILD_QUEUE_SLOTS;
    if (v > SC_PRODQ_HARD_MAX) v = SC_PRODQ_HARD_MAX;
    return v;
}

static void EnsureLock(void) {
    if (!g_lockReady) { InitializeCriticalSection(&g_lock); g_lockReady = true; }
}

int ScProdQueueInstall(BYTE* moduleBase) {
    g_base = moduleBase;
    g_recCount = 0;
    memset(g_stat, 0, sizeof(g_stat));
    EnsureLock();

    if (!ScProdQueueEnabled()) {
        g_enabled = false;
        return 0;
    }
    g_maxTotal = ResolveMax();

    // One suspension for all three, same reasoning as the fan-out's splice: the game is
    // quiescent for microseconds instead of once per hook, and a partially installed set
    // is never observable from a game thread.
    int suspended = ScHookSuspendThreads();
    ScLog("PRODQ: suspended %d other thread(s) for the splice", suspended);

    int installed = 0;
    if (ScHookInstall(&g_hkTrain, "cmdrecvTrain", Rt(SC_VA_CMDRECV_TRAIN),
                      (void*)&ScProdTrainThunk, 11,
                      kPrologueTrain, (int)sizeof(kPrologueTrain))) ++installed;
    if (ScHookInstall(&g_hkCancel, "cmdrecvCancelTrain", Rt(SC_VA_CMDRECV_CANCEL_TRAIN),
                      (void*)&HkCmdrecvCancelTrain, 11,
                      kPrologueCancel, (int)sizeof(kPrologueCancel))) ++installed;
    if (ScHookInstall(&g_hkTick, "productionTick", Rt(SC_VA_PRODUCTION_TICK),
                      (void*)&ScProdTickThunk, 9,
                      kPrologueTick, (int)sizeof(kPrologueTick))) ++installed;

    ScHookResumeThreads();

    if (installed != 3) {
        // Any partial set is worse than none: capture without promotion strands paid-for
        // items, promotion without capture writes slots nobody asked for.
        ScLog("PRODQ: only %d of 3 hooks installed -- ROLLING BACK, production queue "
              "stays vanilla for this run", installed);
        ScProdQueueRemove();
        g_enabled = false;
        return 0;
    }

    g_enabled = true;
    ScLog("PRODQ config: enabled max=%d (engine keeps its %d, plugin holds up to %d per "
          "building, %d buildings) -- %%SCPLUGIN_PRODQ_MAX%%",
          g_maxTotal, SC_BUILD_QUEUE_SLOTS, g_maxTotal - SC_BUILD_QUEUE_SLOTS,
          SC_PRODQ_MAX_BUILDINGS);
    return installed;
}

void ScProdQueueRemove(void) {
    // Un-splicing first would leave paid-for items with nothing to promote them, so the
    // refund happens before the hooks come out.
    if (g_lockReady) {
        EnterCriticalSection(&g_lock);
        for (int i = g_recCount - 1; i >= 0; --i) {
            if (UnitPtrValid(g_rec[i].unit)) RefundRecord(&g_rec[i], "plugin-unload");
            DropRecordAt(i);
        }
        LeaveCriticalSection(&g_lock);
    }
    ScHookRemove(&g_hkTick);
    ScHookRemove(&g_hkCancel);
    ScHookRemove(&g_hkTrain);
    g_enabled = false;
}

void ScProdQueueTestBegin(BYTE* fakeModuleBase, int maxTotal) {
    EnsureLock();
    g_base     = fakeModuleBase;
    g_enabled  = fakeModuleBase != NULL;
    g_testing  = fakeModuleBase != NULL;
    g_recCount = 0;
    g_deepGc   = false;
    g_maxTotal = maxTotal > 0 ? maxTotal : SC_PRODQ_DEFAULT_MAX;
    memset(g_stat, 0, sizeof(g_stat));
}
