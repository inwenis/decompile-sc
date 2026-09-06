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
#include "sc_engine.h"
#include "sc_env.h"
#include "sc_hook.h"
#include "sc_ledger.h"
#include "sc_log.h"
#include "sc_prodqueue.h"
#include "sc_queueind.h"   // ScQueueIndRingGen -- the phantom window's seqlock (task 066)
#include "sc_session.h"
#include "sc_unit.h"

// One line per SITE, first call and any CHANGE. The phantom bracket's whole safety
// argument is "every engine reader of the ring runs on the game thread" (sc_queueind.h);
// these lines are how a run MEASURES that instead of trusting it. The observer's own
// site is expected to print a DIFFERENT id -- that is the thread the seqlock exists for.
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

// Which GAME the records in g_rec[] belong to (sc_session.h). 0 = nothing has been
// synced yet, which is distinguishable from every real epoch because those start at 1.
static unsigned g_session = 0;

// Is this pointer still the building we wrote down? The four terms and the cost of
// `deep` are documented once, on ScUnitRecordLive in sc_unit.h.
static bool RecordStillLive(const ProdRecord* r, bool deep) {
    return ScUnitRecordLive(r->unit, r->uniqueness, r->player, deep);
}

// ---------------------------------------------------------------------------
// The engine's queue, read and written exactly the way the engine does
// ---------------------------------------------------------------------------

// A faithful re-implementation of findFreeBuildQueueSlot (0x004669B0), whose thirteen
// instructions are quoted in research/production-queue.md 3.1: start at the head, wrap
// past slot 4, five tries, and 5 means "there is no free slot". Re-implemented rather
// than called because the engine's version takes its CUnit* in EDX and this one is also
// wanted offline, in hooktest, where there is no engine to call.
static int FindFreeSlot(DWORD unit) {
    unsigned slot = *(BYTE*)(unit + SC_CUNIT_OFF_BUILD_QUEUE_SLOT);
    for (int tries = SC_BUILD_QUEUE_SLOTS; tries > 0; --tries) {
        if (slot >= SC_BUILD_QUEUE_SLOTS) slot = 0;
        if (ScUnitQueueSlot(unit, (int)slot) == SC_BUILD_QUEUE_EMPTY) return (int)slot;
        ++slot;
    }
    return SC_BUILD_QUEUE_SLOTS;
}

// ---------------------------------------------------------------------------
// Money -- ONE DIRECTION ONLY
//
// The plugin never pays for anything. Every item in a record was accepted by the engine's
// own addToBuildQueue (0x00467250), which checked the player could afford it and deducted
// the cost there; the plugin only ever moved it out of the ring afterwards. So the only
// resource write here is the REFUND, for an item that is destroyed while the plugin is
// holding it, and it reads the same two per-type tables the engine's own refund
// (refundByType 0x0042CEC0) reads and honours the same units.dat "this type moves no
// resources" bit. Spend and refund therefore cancel exactly, with the engine on one side
// of the identity and the plugin on the other.
// ---------------------------------------------------------------------------

static bool TypeMovesResources(unsigned type) {
    BYTE f = *(BYTE*)(ScRuntimeVa(SC_VA_UNIT_COST_FLAGS) + (DWORD)type * 4);
    return (f & SC_UNIT_COST_FLAG_NO_SPEND) == 0;
}
static DWORD MineralCost(unsigned type) {
    return *(WORD*)(ScRuntimeVa(SC_VA_UNIT_MINERAL_COST) + (DWORD)type * 2);
}
static DWORD GasCost(unsigned type) {
    return *(WORD*)(ScRuntimeVa(SC_VA_UNIT_GAS_COST) + (DWORD)type * 2);
}

// A no-op for a type whose cost flag says the engine would not have moved anything on the
// way in either.
static void Refund(BYTE player, unsigned type) {
    if (player >= SC_MAX_PLAYERS || !TypeMovesResources(type)) return;
    *ScPlayerMinerals(player) += MineralCost(type);
    *ScPlayerGas(player)      += GasCost(type);
    g_stat[SC_PRODQ_STAT_MINERALS_REFUNDED] += (int)MineralCost(type);
    g_stat[SC_PRODQ_STAT_GAS_REFUNDED]      += (int)GasCost(type);
}

// ---------------------------------------------------------------------------
// Records
// ---------------------------------------------------------------------------

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

// THE EPOCH TEST, and it runs at the top of every entry point this file has --
// including the read-backs, so that no caller can observe a record from a game it does
// not belong to (sc_session.h, "how a module adopts it").
//
// It is FIRST in every one of them, before CollectGarbage and before anything reads
// r->unit. That ordering is the whole difference between this and the checks it sits
// in front of: RecordStillLive asks the UNIT whether it is still the same unit, and a
// save restores the uniqueness byte, the player and the hitpoints verbatim into the
// same seat of the same static array -- so it answers "yes" for a record belonging to
// a game that ended (issue #63, measured).
//
// NO REFUND on this path, and it is not an oversight. RefundRecord exists for a
// building that died in THIS game, where the engine has taken the minerals and the
// player must get them back. Here the minerals were taken in a different game whose
// player state is gone; paying them into the loaded game would hand out three free
// Probes' worth of minerals on every cross-load, which is a bigger bug than the one
// being fixed.
static void ProdQSessionSync(void) {
    const unsigned now = ScSessionEpoch();
    if (g_session == now) return;
    const int items = ScLedgerItemCount(g_rec, g_recCount);
    if (g_recCount > 0) {
        ScLog("PRODQEV session %u -> %u: dropping %d building record(s) holding %d "
              "item(s) queued in a game that has ended -- NOT refunded (those minerals "
              "were spent in that game, not this one)",
              g_session, now, g_recCount, items);
        g_stat[SC_PRODQ_STAT_STALE_SESSION] += items;
    }
    g_recCount = 0;
    g_session  = now;
}

static void CollectGarbage(bool deep) {
    for (int i = g_recCount - 1; i >= 0; --i) {
        if (RecordStillLive(&g_rec[i], deep) && g_rec[i].count > 0) continue;
        if (g_rec[i].count > 0) RefundRecord(&g_rec[i], deep ? "building-gone" : "building-gone-fast");
        ScLedgerDropAt(g_rec, &g_recCount, i);
    }
}

// ---------------------------------------------------------------------------
// Rebalancing: keep the engine's ring at SC_PRODQ_ENGINE_HOLD, hold the rest
//
// Both directions are a bare store into the engine's own ring and move NO resources --
// the engine paid for every one of these items when it accepted it. Nothing else in
// addToBuildQueue applies here: the cost tables it fills are consumed by its own
// deduction two instructions later, the secondary order is already set (the ring cannot
// be non-empty otherwise), and it never touches the building-AI mirror arrays either.
// ---------------------------------------------------------------------------

// The slot holding the item accepted MOST RECENTLY. Occupied slots run contiguously from
// the head -- findFreeBuildQueueSlot (0x004669B0) scans from the head for the first
// 0xE4 and stops there, so a gap behind the head is unreachable and never occurs -- which
// makes the newest of `len` items the one at (head + len - 1) % 5.
static int TailSlot(DWORD unit, int len) {
    if (len <= 0) return -1;
    unsigned head = *(BYTE*)(unit + SC_CUNIT_OFF_BUILD_QUEUE_SLOT);
    if (head >= SC_BUILD_QUEUE_SLOTS) head = 0;
    return (int)((head + (unsigned)(len - 1)) % SC_BUILD_QUEUE_SLOTS);
}

// How many more items this record may take. The bound is against the engine's FIVE, not
// against the hold: once the plugin stops taking items back, the ring fills to five and
// stays there, so the largest logical queue reachable is five plus whatever is held --
// which is exactly `g_maxTotal` when the room is measured this way. Measuring it against
// the hold instead would let one more item in than the maximum says.
//
// Leaving the ring full IS the cap. The client greys its own Train button out at five
// (research/production-queue.md 4.1), so the press after the maximum is refused by
// vanilla's own UI, in vanilla's own way -- nothing is silently swallowed and nothing has
// to be un-spent.
static int HoldRoom(const ProdRecord* r) {
    int held = r ? r->count : 0;
    int room = g_maxTotal - SC_BUILD_QUEUE_SLOTS - held;
    int cap  = SC_PRODQ_HARD_MAX - held;
    if (room > cap) room = cap;
    return room > 0 ? room : 0;
}

static int PromoteInto(ProdRecord* r) {
    int promoted = 0;
    while (r->count > 0 && ScUnitQueueLength(r->unit) < SC_PRODQ_ENGINE_HOLD) {
        int slot = FindFreeSlot(r->unit);
        if (slot >= SC_BUILD_QUEUE_SLOTS) break;
        WORD type = r->types[0];
        ScUnitSetQueueSlot(r->unit, slot, type);
        for (int i = 1; i < r->count; ++i) r->types[i - 1] = r->types[i];
        --r->count;
        ++promoted;
        ++g_stat[SC_PRODQ_STAT_PROMOTED];
        ScLog("PRODQEV promote unit=0x%08X type=0x%03X -> slot=%d overflowLeft=%d",
              (unsigned)r->unit, (unsigned)type, slot, r->count);
    }
    if (promoted && !g_testing) {
        // Tell the status area to redraw, the way the Train handler's own tail does
        // (0x004C1C7C writes this flag). Without it an icon can lag a frame.
        *(BYTE*)ScRuntimeAddr(SC_VA_STAT_DIRTY) = 1;
    }
    return promoted;
}

// Takes the newest items back out of the ring until it is down to the hold, appending
// each to the record in the order the engine accepted them -- which keeps the logical
// queue in the player's order, because the only item that can be above the hold is the
// one that has just arrived.
//
// `rp` may point at a NULL record: one is created on the first item actually held, so a
// building the plugin has nothing to say about never occupies a slot in the table.
static int HoldBack(DWORD unit, BYTE player, ProdRecord** rp) {
    int held = 0;
    for (;;) {
        int len = ScUnitQueueLength(unit);
        if (len <= SC_PRODQ_ENGINE_HOLD) break;
        if (HoldRoom(*rp) <= 0) break;
        if (!*rp && g_recCount >= SC_PRODQ_MAX_BUILDINGS) {
            ScLog("PRODQEV refuse-table unit=0x%08X buildings=%d", (unsigned)unit, g_recCount);
            break;
        }
        int slot = TailSlot(unit, len);
        WORD type = ScUnitQueueSlot(unit, slot);
        if (type == SC_BUILD_QUEUE_EMPTY) break;   // cannot happen; never loop on it

        if (!*rp) {
            ProdRecord* n = &g_rec[g_recCount++];
            n->unit       = unit;
            n->uniqueness = ScUnitUniqueness(unit);
            n->player     = player;
            n->count      = 0;
            *rp = n;
        }
        ScUnitSetQueueSlot(unit, slot, SC_BUILD_QUEUE_EMPTY);
        (*rp)->types[(*rp)->count++] = type;
        ++held;
        ++g_stat[SC_PRODQ_STAT_CAPTURED];
        ScLog("PRODQEV hold unit=0x%08X type=0x%03X <- slot=%d engineLen=%d overflow=%d "
              "logical=%d",
              (unsigned)unit, (unsigned)type, slot, len - 1, (*rp)->count,
              (len - 1) + (*rp)->count);
    }
    if (held && !g_testing) *(BYTE*)ScRuntimeAddr(SC_VA_STAT_DIRTY) = 1;
    return held;
}

// THE INVARIANT, in one place: the ring holds SC_PRODQ_ENGINE_HOLD items whenever the
// plugin has anything to give it, and never more than that while the plugin can take the
// excess. Hold first, then promote -- the other order would put an item back only to take
// it straight out again.
static void Rebalance(DWORD unit, BYTE player, ProdRecord** rp) {
    HoldBack(unit, player, rp);
    if (*rp && (*rp)->count > 0) PromoteInto(*rp);
    if (*rp && (*rp)->count == 0) {
        ScLedgerDropAt(g_rec, &g_recCount, (int)(*rp - g_rec));
        *rp = NULL;
    }
}

// ---------------------------------------------------------------------------
// Core entry points
// ---------------------------------------------------------------------------

void ScProdQueueOnTrain(DWORD unit, unsigned type, bool wasFull) {
    if (!g_enabled || !unit) return;
    { static DWORD tid = 0; ScThreadCheck("prodq-train", &tid); }
    EnterCriticalSection(&g_lock);
    ProdQSessionSync();
    CollectGarbage(true);

    do {
        if (!ScUnitPtrValid(unit)) break;
        BYTE player = ScUnitPlayer(unit);
        if (player >= SC_MAX_PLAYERS) break;
        ProdRecord* r = ScLedgerFind(g_rec, g_recCount, unit);

        if (wasFull) {
            // The ring was already full when the command arrived, so the engine dropped
            // it at its own `CMP EAX,0x5` without touching the array or the player's
            // resources. Under this design that only happens once the logical queue has
            // reached its maximum and the plugin has stopped making room -- so it is the
            // cap doing its job, and the item is refused, not lost.
            ++g_stat[SC_PRODQ_STAT_REFUSED_FULL];
            ScLog("PRODQEV refuse-full unit=0x%08X type=0x%03X logical=%d max=%d",
                  (unsigned)unit, type,
                  ScUnitQueueLength(unit) + (r ? r->count : 0), g_maxTotal);
            break;
        }

        // The engine has just accepted and paid for an item. Take the excess back so the
        // ring stays below the five at which the client stops sending, and give a freed
        // slot to the oldest held item.
        Rebalance(unit, player, &r);
    } while (0);

    LeaveCriticalSection(&g_lock);
}

void ScProdQueueOnTick(DWORD unit) {
    // g_recCount == 0 short-circuits BEFORE the epoch test on purpose: with no records
    // there is nothing a stale epoch could be holding, and this detour runs for every
    // producing building on every frame. The sync then happens on the next tick that
    // has something to look at, or on the next Train/Cancel/read-back, all of which
    // take it unconditionally.
    if (!g_enabled || !unit || g_recCount == 0) return;
    { static DWORD tid = 0; ScThreadCheck("prodq-tick", &tid); }
    EnterCriticalSection(&g_lock);
    ProdQSessionSync();

    if (g_deepGc) { CollectGarbage(true); g_deepGc = false; }
    else CollectGarbage(false);

    ProdRecord* r = ScLedgerFind(g_rec, g_recCount, unit);
    if (r) Rebalance(unit, r->player, &r);

    LeaveCriticalSection(&g_lock);
}

bool ScProdQueueOnCancel(DWORD unit, unsigned payload) {
    if (!g_enabled || !unit) return false;
    { static DWORD tid = 0; ScThreadCheck("prodq-cancel", &tid); }
    bool consumed = false;
    EnterCriticalSection(&g_lock);
    ProdQSessionSync();
    CollectGarbage(true);

    // Only the "cancel the last queued item" form (payload 0xFE, the engine's own
    // cancelLastQueued at 0x00466E40) can be ours, and only when we are actually
    // holding the tail of this building's logical queue. Everything else -- a specific
    // slot 0..4, or the 0xFF no-op -- is the engine's, and it refunds it itself.
    ProdRecord* r = ScLedgerFind(g_rec, g_recCount, unit);
    if (r && r->count > 0 && payload == SC_CANCEL_TRAIN_LAST) {
        WORD type = r->types[--r->count];
        Refund(r->player, type);
        ++g_stat[SC_PRODQ_STAT_CANCELLED];
        ScLog("PRODQEV cancel-last unit=0x%08X type=0x%03X overflowLeft=%d back=%u/%u",
              (unsigned)unit, (unsigned)type, r->count,
              (unsigned)MineralCost(type), (unsigned)GasCost(type));
        if (r->count == 0) ScLedgerDropAt(g_rec, &g_recCount, (int)(r - g_rec));
        consumed = true;
    } else if (payload < SC_BUILD_QUEUE_SLOTS &&
               ScUnitQueueSlot(unit, (int)(((unsigned)*(BYTE*)(unit + SC_CUNIT_OFF_BUILD_QUEUE_SLOT)
                                      + payload) % SC_BUILD_QUEUE_SLOTS))
                   == SC_BUILD_QUEUE_EMPTY) {
        // A specific queue ICON whose RING SLOT IS EMPTY, payload = its display index.
        //
        // Clicking icon k emits {0x20, k} and the engine calls cancelBuildQueueSlot(k),
        // which refunds `buildQueue[(head + k) % 5]` and compacts
        // (research/production-queue.md 8.1). The test above is that same arithmetic, made
        // on the building's own memory: if the slot the payload names holds 0xE4 then this
        // icon is NOT drawing an engine item, and handing the click to the engine would
        // have it refund BY THE SENTINEL TYPE 228 -- reading two cost tables out of bounds
        // and crediting the player whatever is there.
        //
        // Vanilla can never produce such a click: an empty slot's icon is drawn DISABLED
        // and both of the engine's input paths refuse a disabled control
        // (research/command-card.md 5). Task 033's indicator CAN, because it draws those
        // icons from the plugin's own overflow (the user: "when i queue more then 5 units
        // the 5'th slot is emtpy") and lights them. So the plugin owns every such click:
        // it cancels its own item, or swallows the click if it no longer has one.
        const int engineLen = ScUnitQueueLength(unit);
        const int idx = (int)payload - engineLen;
        {
            if (r && idx >= 0 && idx < r->count) {
                WORD type = r->types[idx];
                Refund(r->player, type);
                for (int i = idx + 1; i < r->count; ++i) r->types[i - 1] = r->types[i];
                --r->count;
                ++g_stat[SC_PRODQ_STAT_CANCELLED];
                ScLog("PRODQEV cancel-icon unit=0x%08X display=%u -> overflow[%d] "
                      "type=0x%03X overflowLeft=%d back=%u/%u",
                      (unsigned)unit, payload, idx, (unsigned)type, r->count,
                      (unsigned)MineralCost(type), (unsigned)GasCost(type));
                if (r->count == 0) ScLedgerDropAt(g_rec, &g_recCount, (int)(r - g_rec));
            } else {
                // Nothing behind that icon any more -- it drained between the draw and the
                // click. SWALLOW rather than pass through: the engine's own handler would
                // refund an EMPTY ring slot, and the player's minerals are on the other
                // side of that call. Vanilla cannot reach this case at all.
                ScLog("PRODQEV cancel-icon unit=0x%08X display=%u names an empty ring slot "
                      "(engineLen=%d overflow=%d) -- swallowed, the engine is not asked to "
                      "refund 0xE4", (unsigned)unit, payload, engineLen, r ? r->count : 0);
            }
            consumed = true;
        }
    }

    LeaveCriticalSection(&g_lock);
    return consumed;
}

// ---------------------------------------------------------------------------
// Oracles
// ---------------------------------------------------------------------------

// The same read made COHERENT for the observer thread (task 066): the phantom bracket
// makes owned ring slots non-empty for the length of each queueLayout call on the game
// thread, and a log line must never carry that state -- a phantom item in a PRODQSEL
// line is precisely the harm task 061 named. The guarded section is the SIX RAW READS
// and nothing else; the first version formatted five strings inside it, and at the
// layout's real call rate (~40k brackets/s measured) that section straddled a window on
// every one of its retries in run 2. Formatting happens on the local copy, outside.
// Returns 0 when 32 straddles in a row left the value suspect, which the caller PRINTS
// (ringStable=0) rather than swallows.
static int CoherentEngineQueue(DWORD unit, char* out, int outLen, BYTE* head, int* len) {
    WORD ring[SC_BUILD_QUEUE_SLOTS];
    int stable = 0;
    for (int attempt = 0; attempt < 32 && !stable; ++attempt) {
        unsigned g1 = ScQueueIndRingGen();
        if (g1 & 1) continue;
        *head = *(BYTE*)(unit + SC_CUNIT_OFF_BUILD_QUEUE_SLOT);
        for (int i = 0; i < SC_BUILD_QUEUE_SLOTS; ++i) ring[i] = ScUnitQueueSlot(unit, i);
        if (ScQueueIndRingGen() == g1) stable = 1;
    }
    if (!stable) {
        *head = *(BYTE*)(unit + SC_CUNIT_OFF_BUILD_QUEUE_SLOT);
        for (int i = 0; i < SC_BUILD_QUEUE_SLOTS; ++i) ring[i] = ScUnitQueueSlot(unit, i);
    }
    int used = 0;
    int n = 0;
    out[0] = '\0';
    for (int s = 0; s < SC_BUILD_QUEUE_SLOTS && used + 8 < outLen; ++s) {
        used += _snprintf(out + used, outLen - used, "%s0x%03X", s ? "," : "",
                          (unsigned)ring[s]);
        if (ring[s] != SC_BUILD_QUEUE_EMPTY) ++n;
    }
    *len = n;
    return stable;
}

void ScProdQueueLogState(const char* tag) {
    if (!g_enabled || !g_lockReady) return;
    // The observer's own site: this one is EXPECTED to print a different id from the
    // prodq-train/tick/cancel sites -- it is the thread the seqlock above exists for.
    { static DWORD tid = 0; ScThreadCheck("prodq-observer", &tid); }
    EnterCriticalSection(&g_lock);
    // The oracle syncs too, and that is the half of issue #63 a test can actually see:
    // arm 6 asserts on THIS line's `buildings=` in a game the plugin never queued in,
    // so a mechanism that only dropped stale records on the next Train would read as
    // "still holding three" here and be indistinguishable from no fix at all.
    ProdQSessionSync();

    // The SOLE SELECTED building, tracked or not. Without this the oracle is silent
    // exactly when the plugin is holding nothing -- and "the plugin is holding nothing"
    // and "the oracle did not run" would be the same observation, which is the failure
    // mode AGENTS.md's absence-assertion rule exists to stop. It also gives a test the
    // engine's own five slots to watch drain, read from the building's memory.
    {
        DWORD* sel = (DWORD*)ScRuntimeAddr(SC_VA_ACTIVE_PLAYER_SELECTION);
        DWORD u = sel[0];
        if (u && !sel[1] && ScUnitPtrValid(u)) {
            char eng[96];
            BYTE head = 0;
            int engineLen = 0;
            int stable = CoherentEngineQueue(u, eng, (int)sizeof(eng), &head, &engineLen);
            ProdRecord* r = ScLedgerFind(g_rec, g_recCount, u);
            BYTE player = ScUnitPlayer(u);
            ScLog("PRODQSEL [%s] unit=0x%08X type=0x%03X player=%u head=%u engineLen=%d "
                  "engine=[%s] overflow=%d logical=%d minerals=%u gas=%u ringStable=%d",
                  tag ? tag : "-", (unsigned)u,
                  (unsigned)*(WORD*)(u + SC_CUNIT_OFF_UNIT_ID), (unsigned)player,
                  (unsigned)head, engineLen, eng,
                  r ? r->count : 0, engineLen + (r ? r->count : 0),
                  player < SC_MAX_PLAYERS ? (unsigned)*ScPlayerMinerals(player) : 0u,
                  player < SC_MAX_PLAYERS ? (unsigned)*ScPlayerGas(player) : 0u, stable);
        } else {
            ScLog("PRODQSEL [%s] (no single building selected)", tag ? tag : "-");
        }
    }

    for (int i = 0; i < g_recCount; ++i) {
        ProdRecord* r = &g_rec[i];
        char eng[96];
        BYTE head = 0xFFu;
        int engineLen = 0;
        int stable = 1;
        if (ScUnitPtrValid(r->unit)) {
            stable = CoherentEngineQueue(r->unit, eng, (int)sizeof(eng), &head, &engineLen);
        } else lstrcpynA(eng, "(gone)", (int)sizeof(eng));
        char ovf[128];
        int used = 0;
        ovf[0] = '\0';
        for (int k = 0; k < r->count && used + 8 < (int)sizeof(ovf); ++k) {
            used += _snprintf(ovf + used, sizeof(ovf) - used, "%s0x%03X",
                              k ? "," : "", (unsigned)r->types[k]);
        }
        if (r->count == 0) lstrcpynA(ovf, "(none)", (int)sizeof(ovf));

        ScLog("PRODQ [%s] unit=0x%08X player=%u head=%u engineLen=%d engine=[%s] "
              "overflow=%d overflowTypes=[%s] logical=%d minerals=%u gas=%u ringStable=%d",
              tag ? tag : "-", (unsigned)r->unit, (unsigned)r->player,
              (unsigned)head, engineLen, eng, r->count, ovf, engineLen + r->count,
              r->player < SC_MAX_PLAYERS ? (unsigned)*ScPlayerMinerals(r->player) : 0u,
              r->player < SC_MAX_PLAYERS ? (unsigned)*ScPlayerGas(r->player) : 0u, stable);
    }
    // ALWAYS a summary line, even with zero records -- an absence has to be
    // positively reported or "the oracle did not run" and "there is nothing queued"
    // read identically (AGENTS.md, absence assertions).
    // The detour exits go on the END of this line, so every existing parser of it keeps
    // working. They are here because "the plugin is holding nothing" and "the plugin was
    // never asked" print the same zeros otherwise -- which is how task 038's bug survived
    // a passing suite: trainSeen counts the calls, trainNoUnit counts the ones that found
    // no building to act on, and the difference is the feature actually running.
    // refusedCost= was dropped from this line by task 055 (issue #66): it was a printed
    // constant zero, which AGENTS.md's task-030 rule forbids -- a count you print must be
    // a count something incremented. staleSession= is added here under that same rule and
    // meets it: ProdQSessionSync is the one path that moves it, and hooktest asserts it
    // non-zero.
    ScLog("PRODQ [%s] session=%u buildings=%d max=%d captured=%d promoted=%d cancelled=%d "
          "refunded=%d staleSession=%d refusedFull=%d trainSeen=%d trainNoUnit=%d "
          "cancelSeen=%d cancelNoUnit=%d",
          tag ? tag : "-", g_session, g_recCount, g_maxTotal,
          g_stat[SC_PRODQ_STAT_CAPTURED], g_stat[SC_PRODQ_STAT_PROMOTED],
          g_stat[SC_PRODQ_STAT_CANCELLED], g_stat[SC_PRODQ_STAT_REFUNDED],
          g_stat[SC_PRODQ_STAT_STALE_SESSION],
          g_stat[SC_PRODQ_STAT_REFUSED_FULL],
          g_stat[SC_PRODQ_STAT_TRAIN_SEEN], g_stat[SC_PRODQ_STAT_TRAIN_NO_UNIT],
          g_stat[SC_PRODQ_STAT_CANCEL_SEEN], g_stat[SC_PRODQ_STAT_CANCEL_NO_UNIT]);
    LeaveCriticalSection(&g_lock);
}

void ScProdQueueLogStats(void) {
    if (!g_enabled) return;
    // refusedCost=, mineralsSpent= and gasSpent= were dropped from this line by task 055
    // (issue #66) -- three printed zeros no code path could move. The refund fields stay:
    // Refund() increments them, and they are how a double refund or a swallowed item is
    // told apart from a balance that merely looks plausible. staleSession= joins them on
    // the same terms: one path increments it and hooktest asserts its value.
    ScLog("PRODQSTATS captured=%d promoted=%d cancelled=%d refunded=%d staleSession=%d "
          "refusedFull=%d "
          "mineralsRefunded=%d gasRefunded=%d "
          "tracked=%d trainSeen=%d trainNoUnit=%d cancelSeen=%d cancelNoUnit=%d session=%u",
          g_stat[SC_PRODQ_STAT_CAPTURED], g_stat[SC_PRODQ_STAT_PROMOTED],
          g_stat[SC_PRODQ_STAT_CANCELLED], g_stat[SC_PRODQ_STAT_REFUNDED],
          g_stat[SC_PRODQ_STAT_STALE_SESSION],
          g_stat[SC_PRODQ_STAT_REFUSED_FULL],
          g_stat[SC_PRODQ_STAT_MINERALS_REFUNDED],
          g_stat[SC_PRODQ_STAT_GAS_REFUNDED], g_recCount,
          g_stat[SC_PRODQ_STAT_TRAIN_SEEN], g_stat[SC_PRODQ_STAT_TRAIN_NO_UNIT],
          g_stat[SC_PRODQ_STAT_CANCEL_SEEN], g_stat[SC_PRODQ_STAT_CANCEL_NO_UNIT],
          g_session);
}

// The read-backs sync as well. A read-back that answered from the previous game would
// be a test oracle that cannot see the bug it exists to detect.
int ScProdQueueOverflowCount(DWORD unit) {
    ProdQSessionSync();
    ProdRecord* r = ScLedgerFind(g_rec, g_recCount, unit);
    return r ? r->count : -1;
}
int ScProdQueueOverflowAt(DWORD unit, int i) {
    ProdQSessionSync();
    ProdRecord* r = ScLedgerFind(g_rec, g_recCount, unit);
    if (!r || i < 0 || i >= r->count) return -1;
    return (int)r->types[i];
}
int ScProdQueueTrackedBuildings(void) { ProdQSessionSync(); return g_recCount; }
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
// (research/production-queue.md 2.2 quotes both prologues).
//
// WHICH SELECTION ARRAY THAT IS, and it is the whole of task 038's fix. There are two
// twelve-slot arrays and they ABUT, so reading the wrong one is a mistake that costs
// nothing until the day the two disagree. Task 025 read `activePlayerSelection`
// (0x006284B8) and called it "the same test without calling into the engine". It is not:
// `getActivePlayerNextSelection` (0x0049A850) walks `playersSelections` instead, indexed
// by the ACTIVE PLAYER, and the index arithmetic is in its own instructions
// (research/production-queue.md 2.2, dumped from this binary):
//
//   0049a851  MOV  BL,byte ptr [0x006284B6]            ; the selection iterator
//   0049a860  MOV  EAX,dword ptr [0x0051267C]          ; activePlayerId
//   0049a869  LEA  EAX,[EAX + EAX*2]                   ; player * 3
//   0049a86d  LEA  ESI,[ECX + EAX*4]                   ; iterator + player * 12
//   0049a870  MOV  EAX,dword ptr [ESI*4 + 0x006284E8]  ; playersSelections[player][iter]
//
// The two agree whenever the player has ONE building selected, which is why task 025
// worked and why every test of it passed. They disagree exactly when the fan-out replays
// a Select+Train pair for a GROUP: the simulation's selection is moved to one building at
// a time (that is what makes cmdrecvTrain's single-unit gate accept at all), while
// `activePlayerSelection` still holds the client's whole group -- so `sel[1]` was
// non-null, this function returned 0, the plugin held nothing back, every ring filled to
// five and the client stopped sending. MEASURED, 2026-08-12: nine presses with three
// Command Centers boxed put FIVE 0x1F on the wire and left all three rings at 5/5 with
// zero overflow.
//
// So this reads the array the ENGINE'S OWN GATE reads, with the engine's own index
// arithmetic -- the state the action will actually run in, not the state the player's
// screen is in (AGENTS.md, "Assert the ENGINE'S OWN RESULT", task 029's second half).
// ---------------------------------------------------------------------------

static ScHook g_hkTrain;
static ScHook g_hkCancel;
static ScHook g_hkTick;

typedef void (__attribute__((stdcall)) *CancelTrainFn)(DWORD);

DWORD ScProdQueueSoleSelectedUnitForTest(void) { return ScSoleSelectedUnit(); }

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
    DWORD unit = ScSoleSelectedUnit();
    unsigned type = 0xFFFFu;
    bool wasFull = false;
    ++g_stat[SC_PRODQ_STAT_TRAIN_SEEN];
    if (!unit) ++g_stat[SC_PRODQ_STAT_TRAIN_NO_UNIT];
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
    if (ScUnitPtrValid(unit)) ScProdQueueOnTick(unit);
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
    DWORD unit = ScSoleSelectedUnit();
    unsigned payload = cmd ? *(WORD*)(cmd + 1) : SC_CANCEL_TRAIN_NONE;
    ++g_stat[SC_PRODQ_STAT_CANCEL_SEEN];
    if (!unit) ++g_stat[SC_PRODQ_STAT_CANCEL_NO_UNIT];
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
    return ScEnvInt("SCPLUGIN_PRODQ_MAX", SC_PRODQ_DEFAULT_MAX,
                    SC_BUILD_QUEUE_SLOTS, SC_PRODQ_HARD_MAX);
}

int ScProdQueueInstall(BYTE* moduleBase) {
    ScEngineSetModuleBase(moduleBase);
    g_recCount = 0;
    g_session  = ScSessionEpoch();
    memset(g_stat, 0, sizeof(g_stat));
    ScEnsureLock(&g_lock, &g_lockReady);

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
    if (ScHookInstall(&g_hkTrain, "cmdrecvTrain", ScRuntimeAddr(SC_VA_CMDRECV_TRAIN),
                      (void*)&ScProdTrainThunk, 11,
                      kPrologueTrain, (int)sizeof(kPrologueTrain))) ++installed;
    if (ScHookInstall(&g_hkCancel, "cmdrecvCancelTrain", ScRuntimeAddr(SC_VA_CMDRECV_CANCEL_TRAIN),
                      (void*)&HkCmdrecvCancelTrain, 11,
                      kPrologueCancel, (int)sizeof(kPrologueCancel))) ++installed;
    if (ScHookInstall(&g_hkTick, "productionTick", ScRuntimeAddr(SC_VA_PRODUCTION_TICK),
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
    ScLog("PRODQ config: enabled max=%d (ring kept at %d of its %d so the client keeps "
          "sending, plugin holds up to %d per building, %d buildings) -- "
          "%%SCPLUGIN_PRODQ_MAX%%",
          g_maxTotal, SC_PRODQ_ENGINE_HOLD, SC_BUILD_QUEUE_SLOTS,
          g_maxTotal - SC_BUILD_QUEUE_SLOTS, SC_PRODQ_MAX_BUILDINGS);
    return installed;
}

void ScProdQueueRemove(void) {
    // Un-splicing first would leave paid-for items with nothing to promote them, so the
    // refund happens before the hooks come out.
    if (g_lockReady) {
        EnterCriticalSection(&g_lock);
        // The epoch test goes in front of the refund here for the same reason it goes
        // in front of every other one: a record left over from a game that has ended
        // must be dropped, not paid back into the game the process is in now.
        ProdQSessionSync();
        for (int i = g_recCount - 1; i >= 0; --i) {
            if (ScUnitPtrValid(g_rec[i].unit)) RefundRecord(&g_rec[i], "plugin-unload");
            ScLedgerDropAt(g_rec, &g_recCount, i);
        }
        LeaveCriticalSection(&g_lock);
    }
    ScHookRemove(&g_hkTick);
    ScHookRemove(&g_hkCancel);
    ScHookRemove(&g_hkTrain);
    g_enabled = false;
}

void ScProdQueueTestBegin(BYTE* fakeModuleBase, int maxTotal) {
    ScEnsureLock(&g_lock, &g_lockReady);
    ScEngineSetModuleBase(fakeModuleBase);
    g_enabled  = fakeModuleBase != NULL;
    g_testing  = fakeModuleBase != NULL;
    g_recCount = 0;
    g_deepGc   = false;
    g_session  = ScSessionEpoch();
    g_maxTotal = maxTotal > 0 ? maxTotal : SC_PRODQ_DEFAULT_MAX;
    memset(g_stat, 0, sizeof(g_stat));
}
