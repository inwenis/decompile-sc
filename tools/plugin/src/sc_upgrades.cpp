// sc_upgrades.cpp -- queue more than one upgrade or research at a building.
//
// Read sc_upgrades.h first: it states the mechanism and the resource rule. The evidence
// for every address and every constant is research/upgrade-queue.md.
//
// Everything in this file runs on the GAME THREAD, from one of six detours. The only
// exception is ScUpgQueueLogState, which the observer thread calls from the marker channel
// and which never writes game memory.

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sc_addresses.h"
#include "sc_engine.h"
#include "sc_hook.h"
#include "sc_log.h"
#include "sc_session.h"
#include "sc_upgrades.h"

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

struct UpgItem {
    BYTE kind;   // SC_UPGQ_KIND_UPGRADE / SC_UPGQ_KIND_TECH
    BYTE id;
};

struct UpgRecord {
    DWORD unit;          // CUnit*, bounds/stride-validated when the record was made
    BYTE  uniqueness;    // CUnit+0xA5 at that moment -- the slot-reuse test
    BYTE  player;        // CUnit+0x4C at that moment
    int   count;
    UpgItem items[SC_UPGQ_HARD_MAX];   // FIFO: [0] is promoted next
};

static bool  g_enabled = false;
static bool  g_testing = false;
static int   g_maxTotal = SC_UPGQ_DEFAULT_MAX;

static CRITICAL_SECTION g_lock;
static bool g_lockReady = false;

static UpgRecord g_rec[SC_UPGQ_MAX_BUILDINGS];
static int       g_recCount = 0;

// Which GAME the records in g_rec[] belong to (sc_session.h). 0 = never synced.
static unsigned g_session = 0;

static int g_stat[SC_UPGQ_STAT__COUNT] = { 0 };

// The deep garbage collection (the player-unit-list walk) is O(units) per record and the
// tick detours run for every researching building on every frame, so the tick does the
// cheap terms only and the walk runs on the rare, player-driven detours. Same split, and
// the same stated cost, as sc_prodqueue: a building that dies while the player is idle is
// forgotten on their next click rather than on the next frame. Nothing is at stake in that
// latency here -- a forgotten queue owes nobody any money.
static bool g_deepGc = false;

// The promotion seam. Real in the game, faked by hooktest.
static int  EngineStartItem(DWORD unit, int kind, unsigned id);
static ScUpgStartFn g_start = &EngineStartItem;

// ---------------------------------------------------------------------------
// Unit validation -- the same shape as sc_prodqueue's, because the question is the same:
// is this pointer still the building we wrote down?
// ---------------------------------------------------------------------------

static bool UnitPtrValid(DWORD ptr) {
    if (!ptr) return false;
    DWORD arrayBase = ScRuntimeVa(SC_VA_UNIT_ARRAY_BASE);
    if (ptr < arrayBase) return false;
    DWORD off = ptr - arrayBase;
    if (off % SC_CUNIT_SIZE != 0) return false;
    return (off / SC_CUNIT_SIZE + 1) <= SC_MAX_UNIT_INDEX;
}

static bool InPlayerUnitList(DWORD ptr, BYTE player) {
    if (player >= SC_MAX_PLAYERS) return false;
    DWORD head = *(DWORD*)(ScRuntimeVa(SC_VA_PLAYER_UNIT_LIST) + (DWORD)player * 4);
    int n = 0;
    for (DWORD u = head; u && n < SC_MAX_UNITS_WALK; ++n) {
        if (!UnitPtrValid(u)) return false;
        if (u == ptr) return true;
        u = *(DWORD*)(u + SC_CUNIT_OFF_LIST_NEXT);
    }
    return false;
}

static bool RecordStillLive(const UpgRecord* r, bool deep) {
    if (!UnitPtrValid(r->unit)) return false;
    if (*(BYTE*)(r->unit + SC_CUNIT_OFF_UNIQUENESS) != r->uniqueness) return false;
    if (*(BYTE*)(r->unit + SC_CUNIT_OFF_PLAYER) != r->player) return false;
    if (*(DWORD*)(r->unit + SC_CUNIT_OFF_HITPOINTS) == 0) return false;
    if (deep && !InPlayerUnitList(r->unit, r->player)) return false;
    return true;
}

// ---------------------------------------------------------------------------
// The building's own research state
//
// CUnit+0xC8 / +0xC9 are a UNION ARM (research/upgrade-queue.md 2.3) -- for a unit that is
// not a building they hold an order target pointer. So EVERY read goes through this gate
// first, which is what upgradeTick (`flags & 2`) and btnLiftOffCondition do.
// ---------------------------------------------------------------------------

static bool IsResearchableBuilding(DWORD unit) {
    if (!UnitPtrValid(unit)) return false;
    DWORD flags = *(DWORD*)(unit + SC_CUNIT_OFF_FLAGS);
    if ((flags & SC_UNIT_FLAG_BUILDING) == 0) return false;
    if ((flags & SC_UNIT_FLAG_COMPLETED) == 0) return false;
    return *(BYTE*)(unit + SC_CUNIT_OFF_PLAYER) < SC_MAX_PLAYERS;
}

static BYTE UpgradeInProgress(DWORD unit) {
    return *(BYTE*)(unit + SC_CUNIT_OFF_UPGRADE_PROGRESS);
}
static BYTE TechInProgress(DWORD unit) {
    return *(BYTE*)(unit + SC_CUNIT_OFF_TECH_PROGRESS);
}

// "The engine's one slot is occupied." Both fields, because an Academy can be doing either.
static bool EngineBusy(DWORD unit) {
    return UpgradeInProgress(unit) != SC_UPGRADE_NONE || TechInProgress(unit) != SC_TECH_NONE;
}

// ---------------------------------------------------------------------------
// Costs -- READ ONLY, and only to decide whether to offer an item to the engine
//
// Nothing in this file writes 0x0057F0F0 or 0x0057F120. The engine's own start functions
// do that, once, when the item actually begins. These readers exist so a queue waiting on
// income does not make the engine play its "insufficient minerals" error once a frame; the
// engine re-checks affordability itself either way, so a stale read here can only delay an
// item by a frame, never spend anything.
// ---------------------------------------------------------------------------

static DWORD CurrentUpgradeLevel(BYTE player, unsigned id) {
    if (id < SC_UPGRADE_COUNT_VANILLA) {
        return *(BYTE*)(ScRuntimeVa(SC_VA_UPGRADE_LEVEL) + (DWORD)player * SC_UPGRADE_STRIDE_VANILLA + id);
    }
    return *(BYTE*)(ScRuntimeVa(SC_VA_UPGRADE_LEVEL_BW) + (DWORD)player * SC_UPGRADE_STRIDE_BW + id);
}

static DWORD U16At(DWORD table, unsigned index) {
    return *(WORD*)(ScRuntimeVa(table) + (DWORD)index * 2);
}

// base + factor * currentLevel, the expression 0x0042D190 and 0x00454170 both compute.
static void UpgradeCost(BYTE player, unsigned id, DWORD* minerals, DWORD* gas) {
    DWORD level = CurrentUpgradeLevel(player, id);
    *minerals = (WORD)(U16At(SC_VA_UPGRADE_MINERAL_BASE, id) +
                       U16At(SC_VA_UPGRADE_MINERAL_FACTOR, id) * level);
    *gas      = (WORD)(U16At(SC_VA_UPGRADE_GAS_BASE, id) +
                       U16At(SC_VA_UPGRADE_GAS_FACTOR, id) * level);
}

static void TechCost(unsigned id, DWORD* minerals, DWORD* gas) {
    *minerals = U16At(SC_VA_TECH_MINERAL_COST, id);
    *gas      = U16At(SC_VA_TECH_GAS_COST, id);
}

static void ItemCost(BYTE player, int kind, unsigned id, DWORD* minerals, DWORD* gas) {
    if (kind == SC_UPGQ_KIND_TECH) TechCost(id, minerals, gas);
    else                           UpgradeCost(player, id, minerals, gas);
}

static DWORD MineralsOf(BYTE player) {
    return *(DWORD*)(ScRuntimeVa(SC_VA_PLAYER_MINERALS) + (DWORD)player * 4);
}
static DWORD GasOf(BYTE player) {
    return *(DWORD*)(ScRuntimeVa(SC_VA_PLAYER_GAS) + (DWORD)player * 4);
}

static bool CanAfford(BYTE player, int kind, unsigned id) {
    if (player >= SC_MAX_PLAYERS) return false;
    DWORD m = 0, g = 0;
    ItemCost(player, kind, id, &m, &g);
    return MineralsOf(player) >= m && GasOf(player) >= g;
}

// ---------------------------------------------------------------------------
// Records
// ---------------------------------------------------------------------------

static UpgRecord* FindRecord(DWORD unit) {
    for (int i = 0; i < g_recCount; ++i) if (g_rec[i].unit == unit) return &g_rec[i];
    return NULL;
}

static void DropRecordAt(int i) {
    if (i < 0 || i >= g_recCount) return;
    g_rec[i] = g_rec[g_recCount - 1];
    --g_recCount;
}

// A record whose building has gone is simply forgotten. There is deliberately no refund
// here and no counterpart to sc_prodqueue's RefundRecord: a held item was never paid for,
// so there is nothing to give back. Vanilla still refunds the item that was actually
// RUNNING, on its own death path (0x0049FD00), which this module does not touch.
// THE EPOCH TEST (sc_session.h), at the top of every entry point in this file --
// issue #67 item 1, and the file's RecordStillLive is BYTE-IDENTICAL to the one #63
// was measured against: unit pointer, uniqueness, player, hitpoints, list walk. Every
// one of those five is restored verbatim by a load, so a record from another game
// passes all five and the stale upgrade it holds gets promoted into a game that never
// queued it. This test is the only one of the six that a save cannot satisfy.
//
// Unlike sc_prodqueue there is nothing to refund here either way -- a held upgrade was
// never paid for (see CollectGarbage) -- so the only thing the epoch changes is which
// counter says why the record went.
static void UpgSessionSync(void) {
    const unsigned now = ScSessionEpoch();
    if (g_session == now) return;
    int items = 0;
    for (int i = 0; i < g_recCount; ++i) items += g_rec[i].count;
    if (g_recCount > 0) {
        ScLog("UPGQEV session %u -> %u: dropping %d building record(s) holding %d "
              "item(s) queued in a game that has ended", g_session, now, g_recCount, items);
        g_stat[SC_UPGQ_STAT_STALE_SESSION] += items;
    }
    g_recCount = 0;
    g_session  = now;
}

static void CollectGarbage(bool deep) {
    for (int i = g_recCount - 1; i >= 0; --i) {
        if (RecordStillLive(&g_rec[i], deep) && g_rec[i].count > 0) continue;
        if (g_rec[i].count > 0) {
            g_stat[SC_UPGQ_STAT_DROPPED] += g_rec[i].count;
            ScLog("UPGQEV drop unit=0x%08X player=%u items=%d reason=%s (nothing to refund "
                  "-- held items are unpaid)",
                  (unsigned)g_rec[i].unit, (unsigned)g_rec[i].player, g_rec[i].count,
                  deep ? "building-gone" : "building-gone-fast");
        }
        DropRecordAt(i);
    }
}

// ASK FOR THE CARD TO BE REBUILT, the way the engine's own accept tail does
// (0x004C1B78..0x004C1B8F). Setting SC_VA_STAT_DIRTY alone is NOT enough and the first
// in-game run proved it: the status area redrew but the command card did not, so after the
// second and third queueing press the card still held the buttons it had been laid out with
// one press earlier -- and at the cap it went on offering an upgrade the plugin would then
// have to refuse. The card is relaid on 0x0068C1B0, not on 0x0068C1F8.
static void RequestRedraw(void) {
    if (g_testing) return;
    *(DWORD*)ScRuntimeAddr(SC_VA_REDRAW_CARD)    = 1;
    *(BYTE*) ScRuntimeAddr(SC_VA_REDRAW_CONSOLE) = 1;
    *(BYTE*) ScRuntimeAddr(SC_VA_STAT_DIRTY)     = 1;
    *(DWORD*)ScRuntimeAddr(SC_VA_REDRAW_SEL_A)   = 0;
    *(DWORD*)ScRuntimeAddr(SC_VA_REDRAW_SEL_B)   = 0;
}

// The engine's one slot plus whatever this record holds.
static int LogicalLength(DWORD unit, const UpgRecord* r) {
    int engine = EngineBusy(unit) ? SC_UPGQ_ENGINE_SLOTS : 0;
    return engine + (r ? r->count : 0);
}

static int QueueRoom(DWORD unit, const UpgRecord* r) {
    int room = g_maxTotal - LogicalLength(unit, r);
    int cap  = SC_UPGQ_HARD_MAX - (r ? r->count : 0);
    if (room > cap) room = cap;
    return room > 0 ? room : 0;
}

// ---------------------------------------------------------------------------
// Promotion -- the ENGINE's own accept path, with the unit supplied by the plugin
// ---------------------------------------------------------------------------

// Declared above the asm helpers so the file reads top-down; defined after them.
static int PromoteOldest(UpgRecord* r);

// ---------------------------------------------------------------------------
// Core entry points
// ---------------------------------------------------------------------------

bool ScUpgQueueShouldUnblock(DWORD unit) {
    if (!g_enabled || !unit) return false;
    UpgSessionSync();
    if (!IsResearchableBuilding(unit)) return false;
    // Only lie when the engine's one slot is actually taken. An idle building needs no
    // help, and lying about it would make the card offer buttons vanilla also offers --
    // pointless, and it would put a second answer in play for a state that already works.
    if (!EngineBusy(unit)) return false;
    UpgRecord* r = FindRecord(unit);
    return QueueRoom(unit, r) > 0;
}

// ---------------------------------------------------------------------------
// LEVEL STACKING -- Weapons 2 queued behind Weapons 1, and why it is safe
//
// The card refuses the running upgrade's OWN button through a second, independent test:
// the gate calls upgradeBusy (0x004281B0), which reads a PER-PLAYER, PER-UPGRADE
// in-progress bitfield at 0x0058F3E0. Suppressing that test naively would break a real
// engine rule -- it is also what stops TWO BUILDINGS researching the same upgrade at once,
// and the consequence of breaking it is not cosmetic. Both buildings would set
// `CUnit+0xCD = currentLevel + 1`, i.e. the SAME target level; when the first finished,
// upgradeTick's guard `currentLevel < unit->0xCD` would already be false at the second, so
// it would end immediately, raise nothing, and the player would have paid twice for one
// level (upgradeTick 0x004546A0, quoted in research/upgrade-queue.md 6).
//
// So the suppression is scoped by a condition a second building CANNOT satisfy:
//
//     this building's own 0xC9 already holds this very upgrade id.
//
// A second Engineering Bay's 0xC9 holds 61, or a different id, so its button stays hidden
// and the two-buildings rule is untouched. Only the building that already owns the upgrade
// is allowed to be asked about it again.
//
// The LEVEL is not a problem either, and this was verified rather than assumed:
// startUpgrade (0x00454A80) computes `0xCD = currentLevel + 1` from the level array AT THE
// MOMENT IT RUNS, and the plugin promotes through that same function. So a queued Weapons
// is not "level 2" when it is queued -- it is "the next level", resolved when it starts.
// ---------------------------------------------------------------------------

static DWORD MaxUpgradeLevel(BYTE player, unsigned id) {
    if (id < SC_UPGRADE_COUNT_VANILLA) {
        return *(BYTE*)(ScRuntimeVa(SC_VA_UPGRADE_MAX_LEVEL) +
                        (DWORD)player * SC_UPGRADE_STRIDE_VANILLA + id);
    }
    return *(BYTE*)(ScRuntimeVa(SC_VA_UPGRADE_MAX_BW) + (DWORD)player * SC_UPGRADE_STRIDE_BW + id);
}

static BYTE* UpgradeBusyByte(BYTE player, unsigned id) {
    return (BYTE*)(ScRuntimeVa(SC_VA_UPGRADE_INPROGRESS_BITS) +
                   (DWORD)player * SC_UPGRADE_BITS_STRIDE + (id >> 3));
}

static int QueuedCountOf(const UpgRecord* r, int kind, unsigned id) {
    int n = 0;
    if (!r) return 0;
    for (int i = 0; i < r->count; ++i) {
        if (r->items[i].kind == (BYTE)kind && r->items[i].id == (BYTE)id) ++n;
    }
    return n;
}

// The LEVEL this press would be asking for: the one being produced right now, plus every
// copy of the same upgrade already queued behind it, plus one.
static DWORD WantedLevel(DWORD unit, const UpgRecord* r, int kind, unsigned id) {
    DWORD running = *(BYTE*)(unit + SC_CUNIT_OFF_UPGRADE_LEVEL);
    return running + (DWORD)QueuedCountOf(r, kind, id) + 1;
}

static BYTE* UpgradeLevelByte(BYTE player, unsigned id) {
    if (id < SC_UPGRADE_COUNT_VANILLA) {
        return (BYTE*)(ScRuntimeVa(SC_VA_UPGRADE_LEVEL) +
                       (DWORD)player * SC_UPGRADE_STRIDE_VANILLA + id);
    }
    return (BYTE*)(ScRuntimeVa(SC_VA_UPGRADE_LEVEL_BW) + (DWORD)player * SC_UPGRADE_STRIDE_BW + id);
}

// True when the card may be shown THIS upgrade's own button at THIS building: the building
// is the one researching it, and there is a level left over after everything already
// running or queued. The headroom term keeps the card honest -- without it a player could
// stack five Weapons presses behind a 3-level upgrade and watch two of them be dropped at
// promotion, which is safe (no money moves) but reads as the feature losing them.
bool ScUpgQueueMaySuppressBusyBit(DWORD unit, int kind, unsigned id) {
    if (!g_enabled || !unit || !IsResearchableBuilding(unit)) return false;
    UpgSessionSync();
    if (kind != SC_UPGQ_KIND_UPGRADE) return false;   // a tech has no levels to stack
    if (id >= SC_UPGRADE_COUNT) return false;
    if (UpgradeInProgress(unit) != (BYTE)id) return false;   // <- the two-buildings guard
    BYTE player = *(BYTE*)(unit + SC_CUNIT_OFF_PLAYER);
    if (player >= SC_MAX_PLAYERS) return false;
    return WantedLevel(unit, FindRecord(unit), kind, id) <= MaxUpgradeLevel(player, id);
}

bool ScUpgQueueOnCommand(DWORD unit, int kind, unsigned id) {
    if (!g_enabled || !unit) return false;
    bool consumed = false;
    EnterCriticalSection(&g_lock);
    UpgSessionSync();
    CollectGarbage(true);

    do {
        if (!IsResearchableBuilding(unit)) break;
        // Not busy -> this is an ordinary first item. Let the engine have it: it runs its
        // own gate, starts it and pays for it, which is the whole point of the design.
        if (!EngineBusy(unit)) break;
        if (kind == SC_UPGQ_KIND_UPGRADE && id >= SC_UPGRADE_COUNT) break;
        if (kind == SC_UPGQ_KIND_TECH    && id >= SC_TECH_COUNT) break;

        BYTE player = *(BYTE*)(unit + SC_CUNIT_OFF_PLAYER);
        UpgRecord* r = FindRecord(unit);
        if (QueueRoom(unit, r) <= 0) {
            // Reachable only from a replay or a peer: at the cap the card conditions stop
            // being unblocked, so the client hides the button and never sends. Counted
            // rather than silently swallowed, and the item is refused, not lost -- nothing
            // was paid for it.
            ++g_stat[SC_UPGQ_STAT_REFUSED_FULL];
            ScLog("UPGQEV refuse-full unit=0x%08X kind=%d id=%u logical=%d max=%d",
                  (unsigned)unit, kind, id, LogicalLength(unit, r), g_maxTotal);
            consumed = true;   // still ours: the engine must not overwrite the running item
            break;
        }
        if (!r) {
            if (g_recCount >= SC_UPGQ_MAX_BUILDINGS) {
                ScLog("UPGQEV refuse-table unit=0x%08X buildings=%d", (unsigned)unit, g_recCount);
                break;   // fall through to the engine, which will refuse it as vanilla does
            }
            r = &g_rec[g_recCount++];
            r->unit       = unit;
            r->uniqueness = *(BYTE*)(unit + SC_CUNIT_OFF_UNIQUENESS);
            r->player     = player;
            r->count      = 0;
        }
        r->items[r->count].kind = (BYTE)kind;
        r->items[r->count].id   = (BYTE)id;
        ++r->count;
        ++g_stat[SC_UPGQ_STAT_QUEUED];
        consumed = true;
        ScLog("UPGQEV queue unit=0x%08X kind=%s id=%u queued=%d logical=%d max=%d "
              "(unpaid -- the engine pays when it starts)",
              (unsigned)unit, kind == SC_UPGQ_KIND_TECH ? "tech" : "upgrade", id,
              r->count, LogicalLength(unit, r), g_maxTotal);
        RequestRedraw();
    } while (0);

    LeaveCriticalSection(&g_lock);
    return consumed;
}

void ScUpgQueueOnTick(DWORD unit) {
    // Same short-circuit-before-sync note as sc_prodqueue's tick: no records means
    // nothing a stale epoch could be holding, and this runs every frame per building.
    if (!g_enabled || !unit || g_recCount == 0) return;
    EnterCriticalSection(&g_lock);
    UpgSessionSync();

    if (g_deepGc) { CollectGarbage(true); g_deepGc = false; }
    else CollectGarbage(false);

    UpgRecord* r = FindRecord(unit);
    if (r && r->count > 0 && UnitPtrValid(unit) && !EngineBusy(unit)) {
        PromoteOldest(r);
        if (r->count == 0) DropRecordAt((int)(r - g_rec));
    }

    LeaveCriticalSection(&g_lock);
}

bool ScUpgQueueOnCancel(DWORD unit) {
    if (!g_enabled || !unit) return false;
    bool consumed = false;
    EnterCriticalSection(&g_lock);
    UpgSessionSync();
    CollectGarbage(true);

    // TAIL FIRST, matching task 025's 0xFE rule: the last item of the logical queue really
    // is the plugin's, so the plugin is its correct owner. Press again to keep unwinding;
    // once the plugin holds nothing the cancel falls through to vanilla, which stops the
    // RUNNING item and refunds it exactly. Nothing is refunded here because a held item
    // was never paid for.
    UpgRecord* r = FindRecord(unit);
    if (r && r->count > 0) {
        UpgItem it = r->items[--r->count];
        ++g_stat[SC_UPGQ_STAT_CANCELLED];
        ScLog("UPGQEV cancel-last unit=0x%08X kind=%s id=%u queuedLeft=%d "
              "(no refund -- it was never paid for)",
              (unsigned)unit, it.kind == SC_UPGQ_KIND_TECH ? "tech" : "upgrade",
              (unsigned)it.id, r->count);
        if (r->count == 0) DropRecordAt((int)(r - g_rec));
        RequestRedraw();
        consumed = true;
    }

    LeaveCriticalSection(&g_lock);
    return consumed;
}

// ---------------------------------------------------------------------------
// Oracles
// ---------------------------------------------------------------------------

static void FormatQueue(const UpgRecord* r, char* out, int outLen) {
    int used = 0;
    out[0] = '\0';
    if (!r || r->count == 0) { lstrcpynA(out, "(none)", outLen); return; }
    for (int i = 0; i < r->count && used + 12 < outLen; ++i) {
        used += _snprintf(out + used, outLen - used, "%s%s:%u",
                          i ? "," : "",
                          r->items[i].kind == SC_UPGQ_KIND_TECH ? "T" : "U",
                          (unsigned)r->items[i].id);
    }
}

// One line naming the building's OWN research state, read out of its CUnit. This is what
// an unattended run asserts on: "upg=7 lvl=1 time=3117" is the engine's memory, not the
// status area's pixels.
static void LogUnitLine(const char* what, const char* tag, DWORD unit, const UpgRecord* r) {
    char q[192];
    FormatQueue(r, q, (int)sizeof(q));
    BYTE player = *(BYTE*)(unit + SC_CUNIT_OFF_PLAYER);
    ScLog("%s [%s] unit=0x%08X type=0x%03X player=%u upg=%u tech=%u lvl=%u time=%u "
          "busy=%d queued=%d queue=[%s] logical=%d minerals=%u gas=%u",
          what, tag ? tag : "-", (unsigned)unit,
          (unsigned)*(WORD*)(unit + SC_CUNIT_OFF_UNIT_ID), (unsigned)player,
          (unsigned)UpgradeInProgress(unit), (unsigned)TechInProgress(unit),
          (unsigned)*(BYTE*)(unit + SC_CUNIT_OFF_UPGRADE_LEVEL),
          (unsigned)*(WORD*)(unit + SC_CUNIT_OFF_RESEARCH_TIME),
          EngineBusy(unit) ? 1 : 0, r ? r->count : 0, q, LogicalLength(unit, r),
          player < SC_MAX_PLAYERS ? (unsigned)MineralsOf(player) : 0u,
          player < SC_MAX_PLAYERS ? (unsigned)GasOf(player) : 0u);
}

// THE "IT TOOK EFFECT" ORACLE. An item that finished is not the same claim as an item that
// left the queue, and the difference is in two arrays the engine writes on completion:
// upgradeTick raises upgradeLevel[player][id] (0x0058D2B0) and techTick sets
// techResearched[player][tech] (0x0058CF44 / 0x0058F128, the pair task 026 evidenced from
// the other direction). Only the NON-ZERO entries are listed, with an explicit count, so
// an empty answer is still an answer -- the before/after pair a test needs is
// `levels=[] techs=[]` first and `levels=[7:1] techs=[]` later, from the same line.
static void LogPlayerProgress(const char* tag, BYTE player) {
    if (player >= SC_MAX_PLAYERS) return;
    char lv[192]; int lvUsed = 0; int lvN = 0; lv[0] = '\0';
    for (unsigned id = 0; id < SC_UPGRADE_COUNT; ++id) {
        DWORD lvl = CurrentUpgradeLevel(player, id);
        if (!lvl) continue;
        ++lvN;
        if (lvUsed + 12 < (int)sizeof(lv)) {
            lvUsed += _snprintf(lv + lvUsed, sizeof(lv) - lvUsed, "%s%u:%u",
                                lvUsed ? "," : "", id, (unsigned)lvl);
        }
    }
    char tc[192]; int tcUsed = 0; int tcN = 0; tc[0] = '\0';
    for (unsigned t = 0; t < SC_TECH_COUNT; ++t) {
        BYTE done = (t < (unsigned)SC_TECH_COUNT_VANILLA)
            ? *(BYTE*)(ScRuntimeVa(SC_VA_TECH_RESEARCHED) + (DWORD)player * SC_TECH_STRIDE_VANILLA + t)
            : *(BYTE*)(ScRuntimeVa(SC_VA_TECH_RESEARCHED_BW) + (DWORD)player * SC_TECH_STRIDE_BW + t);
        if (!done) continue;
        ++tcN;
        if (tcUsed + 8 < (int)sizeof(tc)) {
            tcUsed += _snprintf(tc + tcUsed, sizeof(tc) - tcUsed, "%s%u", tcUsed ? "," : "", t);
        }
    }
    ScLog("UPGQLVL [%s] p=%u levels=[%s] levelCount=%d techs=[%s] techCount=%d "
          "minerals=%u gas=%u",
          tag ? tag : "-", (unsigned)player, lv, lvN, tc, tcN,
          (unsigned)MineralsOf(player), (unsigned)GasOf(player));
}

void ScUpgQueueLogState(const char* tag) {
    if (!g_enabled || !g_lockReady) return;
    EnterCriticalSection(&g_lock);
    // The oracle syncs too -- a read-back that answered out of the previous game would
    // be the reason a suite could not see this bug (sc_prodqueue has the same note).
    UpgSessionSync();

    // The SOLE SELECTED building, tracked or not. Without this the oracle is silent
    // exactly when the plugin is holding nothing -- and "holding nothing" and "the oracle
    // did not run" would be the same observation, which is the failure mode AGENTS.md's
    // absence-assertion rule exists to stop.
    {
        DWORD* sel = (DWORD*)ScRuntimeAddr(SC_VA_ACTIVE_PLAYER_SELECTION);
        DWORD u = sel[0];
        if (u && !sel[1] && UnitPtrValid(u)) {
            LogUnitLine("UPGQSEL", tag, u, FindRecord(u));
            LogPlayerProgress(tag, *(BYTE*)(u + SC_CUNIT_OFF_PLAYER));
        } else {
            ScLog("UPGQSEL [%s] (no single unit selected)", tag ? tag : "-");
        }
    }

    for (int i = 0; i < g_recCount; ++i) {
        if (UnitPtrValid(g_rec[i].unit)) LogUnitLine("UPGQ", tag, g_rec[i].unit, &g_rec[i]);
        else ScLog("UPGQ [%s] unit=0x%08X (gone) queued=%d",
                   tag ? tag : "-", (unsigned)g_rec[i].unit, g_rec[i].count);
    }
    // ALWAYS a summary line, even with zero records.
    ScLog("UPGQ [%s] session=%u buildings=%d max=%d queued=%d promoted=%d cancelled=%d dropped=%d "
          "staleSession=%d refusedFull=%d refusedGate=%d waitingCost=%d unblocked=%d unblockedLevel=%d",
          tag ? tag : "-", g_session, g_recCount, g_maxTotal,
          g_stat[SC_UPGQ_STAT_QUEUED], g_stat[SC_UPGQ_STAT_PROMOTED],
          g_stat[SC_UPGQ_STAT_CANCELLED], g_stat[SC_UPGQ_STAT_DROPPED],
          g_stat[SC_UPGQ_STAT_STALE_SESSION],
          g_stat[SC_UPGQ_STAT_REFUSED_FULL], g_stat[SC_UPGQ_STAT_REFUSED_GATE],
          g_stat[SC_UPGQ_STAT_WAITING_COST], g_stat[SC_UPGQ_STAT_UNBLOCKED],
          g_stat[SC_UPGQ_STAT_UNBLOCKED_LEVEL]);
    LeaveCriticalSection(&g_lock);
}

void ScUpgQueueLogStats(void) {
    if (!g_enabled) return;
    // mineralsSpent= and gasSpent= were dropped from this line by task 055 (issue #66) --
    // two printed zeros this module has no way to move. staleSession= is added on the
    // opposite footing: UpgSessionSync increments it and hooktest asserts it non-zero.
    ScLog("UPGQSTATS queued=%d promoted=%d cancelled=%d dropped=%d staleSession=%d "
          "refusedFull=%d "
          "refusedGate=%d waitingCost=%d unblocked=%d unblockedLevel=%d tracked=%d session=%u",
          g_stat[SC_UPGQ_STAT_QUEUED], g_stat[SC_UPGQ_STAT_PROMOTED],
          g_stat[SC_UPGQ_STAT_CANCELLED], g_stat[SC_UPGQ_STAT_DROPPED],
          g_stat[SC_UPGQ_STAT_STALE_SESSION],
          g_stat[SC_UPGQ_STAT_REFUSED_FULL], g_stat[SC_UPGQ_STAT_REFUSED_GATE],
          g_stat[SC_UPGQ_STAT_WAITING_COST], g_stat[SC_UPGQ_STAT_UNBLOCKED],
          g_stat[SC_UPGQ_STAT_UNBLOCKED_LEVEL], g_recCount, g_session);
}

// The read-backs sync as well, for the reason ScUpgQueueLogState does.
int ScUpgQueueCount(DWORD unit) {
    UpgSessionSync();
    UpgRecord* r = FindRecord(unit);
    return r ? r->count : -1;
}
int ScUpgQueueKindAt(DWORD unit, int i) {
    UpgSessionSync();
    UpgRecord* r = FindRecord(unit);
    if (!r || i < 0 || i >= r->count) return -1;
    return (int)r->items[i].kind;
}
int ScUpgQueueIdAt(DWORD unit, int i) {
    UpgSessionSync();
    UpgRecord* r = FindRecord(unit);
    if (!r || i < 0 || i >= r->count) return -1;
    return (int)r->items[i].id;
}
int ScUpgQueueTrackedBuildings(void) { UpgSessionSync(); return g_recCount; }
int ScUpgQueueStat(int which) {
    if (which < 0 || which >= SC_UPGQ_STAT__COUNT) return 0;
    return g_stat[which];
}

// ---------------------------------------------------------------------------
// Calling the engine
//
// None of these four conventions is expressible in C, and every one of them was read off
// cmdrecvUpgrade's / cmdrecvTech's own listing rather than guessed:
//
//   0x004C1B43  MOVZX BX,byte ptr [EAX+1]      the id, into BX
//   0x004C1B49  MOV EDI,[0x00512678]           the player, into EDI
//   0x004C1B4F  PUSH ESI                       the unit, on the stack
//   0x004C1B50  CALL upgradeGate               ... and no ADD ESP after it: __stdcall
//   0x004C1B61  MOV AL,[ECX+1]  / MOV ECX,ESI  startUpgrade: AL = id, ECX = unit
//   0x004C1BE1  MOV AL,[ECX+1]  / MOV EDX,ESI  startTech:    AL = id, EDX = unit
//   0x004C1B6F  MOV CL,0x4C     / (ESI = unit) afterAccept:  CL = order, ESI = unit
//
// Written as whole asm stubs rather than as inline-asm register constraints because a
// constraint list that has to pin EBX, ECX, EDX, ESI and EDI at once is exactly where a
// compiler quietly picks a register you also needed.
// ---------------------------------------------------------------------------

extern "C" DWORD ScUpgCallGate(void* fn, DWORD unit, DWORD id, DWORD player);
asm(".text\n"
    ".globl _ScUpgCallGate\n"
    "_ScUpgCallGate:\n"
    "  pushl %ebp\n"
    "  movl  %esp, %ebp\n"
    "  pushl %ebx\n"
    "  pushl %esi\n"
    "  pushl %edi\n"
    "  movl  16(%ebp), %ebx\n"      // id    -> EBX (the callee reads BX)
    "  movl  20(%ebp), %edi\n"      // player-> EDI
    "  movl   8(%ebp), %eax\n"      // fn
    "  pushl 12(%ebp)\n"            // unit, which the __stdcall callee pops
    "  call  *%eax\n"
    "  popl  %edi\n"
    "  popl  %esi\n"
    "  popl  %ebx\n"
    "  popl  %ebp\n"
    "  ret\n");

extern "C" DWORD ScUpgCallStartUpgrade(void* fn, DWORD unit, DWORD id);
asm(".text\n"
    ".globl _ScUpgCallStartUpgrade\n"
    "_ScUpgCallStartUpgrade:\n"
    "  pushl %ebp\n"
    "  movl  %esp, %ebp\n"
    "  pushl %ebx\n"
    "  pushl %esi\n"
    "  pushl %edi\n"
    "  movl   8(%ebp), %ebx\n"      // fn -> EBX, which the callee preserves
    "  movl  12(%ebp), %ecx\n"      // unit -> ECX
    "  movl  16(%ebp), %eax\n"      // id -> AL
    "  call  *%ebx\n"
    "  popl  %edi\n"
    "  popl  %esi\n"
    "  popl  %ebx\n"
    "  popl  %ebp\n"
    "  ret\n");

extern "C" DWORD ScUpgCallStartTech(void* fn, DWORD unit, DWORD id);
asm(".text\n"
    ".globl _ScUpgCallStartTech\n"
    "_ScUpgCallStartTech:\n"
    "  pushl %ebp\n"
    "  movl  %esp, %ebp\n"
    "  pushl %ebx\n"
    "  pushl %esi\n"
    "  pushl %edi\n"
    "  movl   8(%ebp), %ebx\n"      // fn
    "  movl  12(%ebp), %edx\n"      // unit -> EDX
    "  movl  16(%ebp), %eax\n"      // id -> AL
    "  call  *%ebx\n"
    "  popl  %edi\n"
    "  popl  %esi\n"
    "  popl  %ebx\n"
    "  popl  %ebp\n"
    "  ret\n");

extern "C" void ScUpgCallAfterAccept(void* fn, DWORD unit, DWORD order);
asm(".text\n"
    ".globl _ScUpgCallAfterAccept\n"
    "_ScUpgCallAfterAccept:\n"
    "  pushl %ebp\n"
    "  movl  %esp, %ebp\n"
    "  pushl %ebx\n"
    "  pushl %esi\n"
    "  pushl %edi\n"
    "  movl   8(%ebp), %ebx\n"      // fn
    "  movl  12(%ebp), %esi\n"      // unit -> ESI
    "  movl  16(%ebp), %ecx\n"      // order id -> CL
    "  call  *%ebx\n"
    "  popl  %edi\n"
    "  popl  %esi\n"
    "  popl  %ebx\n"
    "  popl  %ebp\n"
    "  ret\n");

// The card condition, called through its trampoline: __stdcall(unit) with CL = the
// button's conditionParam and EDX = the player, exactly as the layout function calls it.
extern "C" DWORD ScUpgCallCond(void* fn, DWORD unit, DWORD id, DWORD player);
asm(".text\n"
    ".globl _ScUpgCallCond\n"
    "_ScUpgCallCond:\n"
    "  pushl %ebp\n"
    "  movl  %esp, %ebp\n"
    "  pushl %ebx\n"
    "  pushl %esi\n"
    "  pushl %edi\n"
    "  movl   8(%ebp), %ebx\n"      // fn
    "  movl  16(%ebp), %ecx\n"      // id -> CL
    "  movl  20(%ebp), %edx\n"      // player -> EDX
    "  pushl 12(%ebp)\n"            // unit, popped by the __stdcall callee
    "  call  *%ebx\n"
    "  popl  %edi\n"
    "  popl  %esi\n"
    "  popl  %ebx\n"
    "  popl  %ebp\n"
    "  ret\n");

// ---------------------------------------------------------------------------
// Promotion
// ---------------------------------------------------------------------------

// cmdrecvUpgrade's own body, with the unit supplied by the plugin instead of by the
// selection. The gate runs first -- so requirements, ownership, the per-player
// in-progress bit and the level ceiling are all re-checked by the ENGINE at the moment
// the item starts, not at the moment it was queued -- and then the engine's own start
// pays for it and sets the field.
static int EngineStartItem(DWORD unit, int kind, unsigned id) {
    BYTE player = *(BYTE*)(unit + SC_CUNIT_OFF_PLAYER);
    bool tech = (kind == SC_UPGQ_KIND_TECH);

    DWORD gate = ScUpgCallGate(ScRuntimeAddr(tech ? SC_VA_TECH_GATE : SC_VA_UPGRADE_GATE),
                               unit, id, player);
    if (gate != 1) return -1;   // refused for a reason that will not fix itself

    DWORD ok = tech ? ScUpgCallStartTech(ScRuntimeAddr(SC_VA_START_TECH), unit, id)
                    : ScUpgCallStartUpgrade(ScRuntimeAddr(SC_VA_START_UPGRADE), unit, id);
    if (!ok) return 0;          // could not pay right now -- try again next tick

    ScUpgCallAfterAccept(ScRuntimeAddr(SC_VA_AFTER_ACCEPT), unit,
                         tech ? SC_ORDER_RESEARCH : SC_ORDER_UPGRADE);
    RequestRedraw();
    return 1;
}

// Hands the OLDEST held item to the engine. Three outcomes, all of them logged:
//   1  started -- the engine paid for it and the building is busy again
//   0  the player cannot pay yet -- the item STAYS at the head and is retried next tick
//  -1  the engine's own gate refused it -- dropped, because nothing will change its mind
static int PromoteOldest(UpgRecord* r) {
    UpgItem it = r->items[0];
    const char* kindName = it.kind == SC_UPGQ_KIND_TECH ? "tech" : "upgrade";

    // Ask before offering, so a queue waiting on income does not make the engine play its
    // "insufficient minerals" error once a frame. The engine checks again itself.
    if (!CanAfford(r->player, it.kind, it.id)) {
        ++g_stat[SC_UPGQ_STAT_WAITING_COST];
        return 0;
    }

    int rc = g_start(r->unit, (int)it.kind, (unsigned)it.id);
    if (rc == 1) {
        for (int i = 1; i < r->count; ++i) r->items[i - 1] = r->items[i];
        --r->count;
        ++g_stat[SC_UPGQ_STAT_PROMOTED];
        ScLog("UPGQEV promote unit=0x%08X kind=%s id=%u -> started, queuedLeft=%d "
              "minerals=%u gas=%u",
              (unsigned)r->unit, kindName, (unsigned)it.id, r->count,
              (unsigned)MineralsOf(r->player), (unsigned)GasOf(r->player));
        return 1;
    }
    if (rc < 0) {
        for (int i = 1; i < r->count; ++i) r->items[i - 1] = r->items[i];
        --r->count;
        ++g_stat[SC_UPGQ_STAT_REFUSED_GATE];
        ScLog("UPGQEV drop-gate unit=0x%08X kind=%s id=%u -- the engine's own gate refused "
              "it, queuedLeft=%d (nothing to refund)",
              (unsigned)r->unit, kindName, (unsigned)it.id, r->count);
        return -1;
    }
    ++g_stat[SC_UPGQ_STAT_WAITING_COST];
    return 0;
}

// ---------------------------------------------------------------------------
// Detours
// ---------------------------------------------------------------------------

static ScHook g_hkCondUpg;
static ScHook g_hkCondTech;
static ScHook g_hkCmdUpg;
static ScHook g_hkCmdTech;
static ScHook g_hkTickUpg;
static ScHook g_hkTickTech;
static ScHook g_hkCancelUpg;
static ScHook g_hkCancelTech;

typedef void (__attribute__((stdcall)) *CmdFn)(DWORD);

// WHICH SELECTION ARRAY THIS READS, and it is task 038's fix (sc_prodqueue.cpp), same
// shape here: both receive handlers reset selectionIterator (0x006284B6) and then require
// getActivePlayerNextSelection to yield exactly one unit. That function (0x0049A850) walks
// playersSelections (0x006284E8), indexed by the ACTIVE PLAYER -- not activePlayerSelection
// (0x006284B8), which is the CLIENT's own list. The two arrays ABUT
// (0x006284B8 + 12*4 == 0x006284E8) and hold the same thing whenever exactly one building
// is selected, which is every case this module's own suite exercised until now -- latent,
// per task 042, because no upgrade command is fanned out today and the client will not
// offer an upgrade button for a multi-building selection. The index arithmetic, quoted
// rather than guessed (research/production-queue.md 2.2):
//
//   0049a860  MOV  EAX,dword ptr [0x0051267C]          ; activePlayerId
//   0049a869  LEA  EAX,[EAX + EAX*2]                   ; player * 3
//   0049a86d  LEA  ESI,[ECX + EAX*4]                   ; iterator + player * 12
//   0049a870  MOV  EAX,dword ptr [ESI*4 + 0x006284E8]  ; playersSelections[player][iter]
static DWORD SoleSelectedUnit(void) {
    DWORD player = *(DWORD*)ScRuntimeAddr(SC_VA_ACTIVE_PLAYER_ID);
    if (player >= SC_MAX_PLAYERS) return 0;
    DWORD* sel = (DWORD*)ScRuntimeAddr(SC_VA_PLAYERS_SELECTIONS) + player * SC_SELECTION_SLOTS;
    DWORD u = sel[0];
    if (!u || sel[1]) return 0;
    return UnitPtrValid(u) ? u : 0;
}

DWORD ScUpgQueueSoleSelectedUnitForTest(void) { return SoleSelectedUnit(); }

// --- the card conditions -----------------------------------------------------
//
// Evaluate the ORIGINAL condition with the two in-progress bytes momentarily at their idle
// sentinels, then put them straight back. The clear/call/restore runs inside the same
// critical section the oracle takes, so the observer thread can never sample a building
// mid-lie and report it idle.
static DWORD CondCommon(ScHook* hook, int kind, DWORD unit, DWORD id, DWORD player) {
    if (!g_enabled || !unit) return ScUpgCallCond(hook->trampoline, unit, id, player);

    EnterCriticalSection(&g_lock);
    bool lie = ScUpgQueueShouldUnblock(unit);
    // The second, narrower lie: the per-player in-progress BIT, suppressed only for the
    // building that is already researching this very upgrade. See MaySuppressBusyBit.
    bool lieBit = lie && ScUpgQueueMaySuppressBusyBit(unit, kind, (unsigned)id);
    BYTE savedUpg = 0, savedTech = 0, savedBits = 0;
    BYTE* bitByte = NULL;
    if (lie) {
        savedUpg  = *(BYTE*)(unit + SC_CUNIT_OFF_UPGRADE_PROGRESS);
        savedTech = *(BYTE*)(unit + SC_CUNIT_OFF_TECH_PROGRESS);
        *(BYTE*)(unit + SC_CUNIT_OFF_UPGRADE_PROGRESS) = (BYTE)SC_UPGRADE_NONE;
        *(BYTE*)(unit + SC_CUNIT_OFF_TECH_PROGRESS)    = (BYTE)SC_TECH_NONE;
        ++g_stat[SC_UPGQ_STAT_UNBLOCKED];
    }
    BYTE* levelByte = NULL;
    BYTE savedLevel = 0;
    if (lieBit) {
        BYTE owner = *(BYTE*)(unit + SC_CUNIT_OFF_PLAYER);
        bitByte = UpgradeBusyByte(owner, id);
        savedBits = *bitByte;
        *bitByte = (BYTE)(savedBits & ~(1u << (id & 7)));
        // AND ASK ABOUT THE RIGHT LEVEL. An upgrade's requirements are per LEVEL: the
        // requirement interpreter's opcode 0xFF1F reads the player's current level and
        // jumps to that level's own requirement block, so evaluating the condition with
        // the level still at its present value asks "may level N+1 be researched?" and
        // gets level N's answer. The first in-game run paid for that: with Infantry
        // Weapons level 1 running, the card offered level 2 -- and the engine's own gate
        // then refused it at promotion, because level 2 needs a prerequisite building the
        // fixture did not have. Nothing was lost (a queued item is unpaid, and the drop is
        // logged), but the card had promised something it could not deliver.
        //
        // So the level array is raised to the level this press would be asking FOR, minus
        // one, for the length of the call. The engine then evaluates the requirement block
        // that will actually apply, and answers -1 (greyed) or 0 by itself.
        levelByte = UpgradeLevelByte(owner, id);
        savedLevel = *levelByte;
        DWORD want = WantedLevel(unit, FindRecord(unit), kind, id);
        *levelByte = (BYTE)(want > 0 ? want - 1 : 0);
        ++g_stat[SC_UPGQ_STAT_UNBLOCKED_LEVEL];
    }
    DWORD r = ScUpgCallCond(hook->trampoline, unit, id, player);
    if (levelByte) *levelByte = savedLevel;
    // Restored unconditionally and in the reverse order, before anything else on this
    // thread can look. Nothing between the two writes can yield: the game is
    // single-threaded here, and the observer thread's oracle takes this same lock.
    if (bitByte) *bitByte = savedBits;
    if (lie) {
        *(BYTE*)(unit + SC_CUNIT_OFF_UPGRADE_PROGRESS) = savedUpg;
        *(BYTE*)(unit + SC_CUNIT_OFF_TECH_PROGRESS)    = savedTech;
    }
    LeaveCriticalSection(&g_lock);
    return r;
}

extern "C" DWORD SC_GAME_ENTRY ScUpgCondUpgradeC(DWORD unit, DWORD id, DWORD player) {
    return CondCommon(&g_hkCondUpg, SC_UPGQ_KIND_UPGRADE, unit, id, player);
}
extern "C" DWORD SC_GAME_ENTRY ScUpgCondTechC(DWORD unit, DWORD id, DWORD player) {
    return CondCommon(&g_hkCondTech, SC_UPGQ_KIND_TECH, unit, id, player);
}

// __stdcall(unit) with CL = the button's conditionParam and EDX = the player, RET 4 --
// read off 0x00429450 / 0x00429500, which are byte-for-byte the same 20-byte wrapper.
extern "C" void ScUpgCondUpgradeThunk(void);
asm(".text\n"
    ".globl _ScUpgCondUpgradeThunk\n"
    "_ScUpgCondUpgradeThunk:\n"
    "  pushl %ebp\n"
    "  movl  %esp, %ebp\n"
    "  pushl %ebx\n"
    "  pushl %esi\n"
    "  pushl %edi\n"
    "  pushl %edx\n"                // player
    "  movzbl %cl, %eax\n"
    "  pushl %eax\n"                // id
    "  pushl 8(%ebp)\n"             // unit
    "  call  _ScUpgCondUpgradeC\n"
    "  addl  $12, %esp\n"
    "  popl  %edi\n"
    "  popl  %esi\n"
    "  popl  %ebx\n"
    "  popl  %ebp\n"
    "  ret   $4\n");

extern "C" void ScUpgCondTechThunk(void);
asm(".text\n"
    ".globl _ScUpgCondTechThunk\n"
    "_ScUpgCondTechThunk:\n"
    "  pushl %ebp\n"
    "  movl  %esp, %ebp\n"
    "  pushl %ebx\n"
    "  pushl %esi\n"
    "  pushl %edi\n"
    "  pushl %edx\n"
    "  movzbl %cl, %eax\n"
    "  pushl %eax\n"
    "  pushl 8(%ebp)\n"
    "  call  _ScUpgCondTechC\n"
    "  addl  $12, %esp\n"
    "  popl  %edi\n"
    "  popl  %esi\n"
    "  popl  %ebx\n"
    "  popl  %ebp\n"
    "  ret   $4\n");

// --- the receive handlers ----------------------------------------------------
//
// PRE-hook, and the skip is the point: neither startUpgrade nor startTech checks whether
// something is already running, so letting the engine's body run for a busy building would
// overwrite the running item AND pay for the new one.
static void __attribute__((stdcall)) SC_GAME_ENTRY HkCmdrecvUpgrade(DWORD cmd) {
    DWORD unit = SoleSelectedUnit();
    unsigned id = cmd ? *(BYTE*)(cmd + 1) : 0xFFu;
    g_deepGc = true;
    if (unit && ScUpgQueueOnCommand(unit, SC_UPGQ_KIND_UPGRADE, id)) return;
    ((CmdFn)g_hkCmdUpg.trampoline)(cmd);
}

static void __attribute__((stdcall)) SC_GAME_ENTRY HkCmdrecvTech(DWORD cmd) {
    DWORD unit = SoleSelectedUnit();
    unsigned id = cmd ? *(BYTE*)(cmd + 1) : 0xFFu;
    g_deepGc = true;
    if (unit && ScUpgQueueOnCommand(unit, SC_UPGQ_KIND_TECH, id)) return;
    ((CmdFn)g_hkCmdTech.trampoline)(cmd);
}

// --- the cancels -------------------------------------------------------------
//
// 0x33 Cancel Upgrade (0x004BFFC0) and 0x31 Cancel Tech (0x004C0070) both take NO
// arguments -- they resolve the building through the selection exactly as their positive
// counterparts do -- and both end in a bare RET, so the detour is a plain `void(void)`.
//
// TAIL FIRST. While the plugin holds anything, a cancel is the plugin's: the last item of
// the logical queue is the one the plugin is holding, so it is the correct owner. Once the
// plugin holds nothing the press falls through to vanilla, which stops the RUNNING item
// and refunds it exactly, out of the same tables it paid from. This module refunds
// nothing, ever, because it never paid for anything.
typedef void (*CancelFn)(void);

static void SC_GAME_ENTRY HkCmdrecvCancelUpgrade(void) {
    DWORD unit = SoleSelectedUnit();
    g_deepGc = true;
    if (unit && ScUpgQueueOnCancel(unit)) return;
    ((CancelFn)g_hkCancelUpg.trampoline)();
}

static void SC_GAME_ENTRY HkCmdrecvCancelTech(void) {
    DWORD unit = SoleSelectedUnit();
    g_deepGc = true;
    if (unit && ScUpgQueueOnCancel(unit)) return;
    ((CancelFn)g_hkCancelTech.trampoline)();
}

// --- the order handlers ------------------------------------------------------
//
// POST-hook: the frame the building goes idle is the frame the next item takes its place.
extern "C" void SC_GAME_ENTRY ScUpgTickUpgradeDetour(DWORD unit) {
    DWORD scratch;
    __asm__ __volatile__("calll *%[fn]" : "=a"(scratch)
                         : "0"(unit), [fn] "r"(g_hkTickUpg.trampoline)
                         : "ecx", "edx", "cc", "memory");
    (void)scratch;
    if (UnitPtrValid(unit)) ScUpgQueueOnTick(unit);
}

extern "C" void SC_GAME_ENTRY ScUpgTickTechDetour(DWORD unit) {
    DWORD scratch;
    __asm__ __volatile__("calll *%[fn]" : "=a"(scratch)
                         : "0"(unit), [fn] "r"(g_hkTickTech.trampoline)
                         : "ecx", "edx", "cc", "memory");
    (void)scratch;
    if (UnitPtrValid(unit)) ScUpgQueueOnTick(unit);
}

// Both order handlers take their only argument in EAX and no C calling convention says so,
// so each gets the same two-instruction thunk sc_prodqueue uses for productionTick.
extern "C" void ScUpgTickUpgradeThunk(void);
asm(".text\n"
    ".globl _ScUpgTickUpgradeThunk\n"
    "_ScUpgTickUpgradeThunk:\n"
    "  pushl %eax\n"
    "  call  _ScUpgTickUpgradeDetour\n"
    "  addl  $4, %esp\n"
    "  ret\n");

extern "C" void ScUpgTickTechThunk(void);
asm(".text\n"
    ".globl _ScUpgTickTechThunk\n"
    "_ScUpgTickTechThunk:\n"
    "  pushl %eax\n"
    "  call  _ScUpgTickTechDetour\n"
    "  addl  $4, %esp\n"
    "  ret\n");

// ---------------------------------------------------------------------------
// Verified prologues, from HookProbe over tools/ghidra/specs/upgrade-hooks.spec. Every
// window is ENTRY-POINT, relocation-safe (no PC-relative instruction inside it), and
// ScHookInstall refuses to patch if the running process disagrees.
// ---------------------------------------------------------------------------

//   00429450 / 00429500  55        PUSH EBP
//                        8B EC     MOV EBP,ESP
//                        8B 45 08  MOV EAX,dword ptr [EBP + 0x8]   -> 6 bytes, 3 instrs
static const BYTE kPrologueCond[]  = { 0x55, 0x8B, 0xEC, 0x8B, 0x45, 0x08 };
//   004C1B20 / 004C1BA0  55        PUSH EBP
//                        8B EC     MOV EBP,ESP
//                        56        PUSH ESI
//                        C6 05 ..  MOV byte ptr [0x006284B6],0x0   -> 11 bytes, 4 instrs
static const BYTE kPrologueCmd[]   = { 0x55, 0x8B, 0xEC, 0x56, 0xC6, 0x05,
                                       0xB6, 0x84, 0x62, 0x00, 0x00 };
//   004546A0 / 004548B0  55        PUSH EBP
//                        8B EC     MOV EBP,ESP
//                        83 EC 08  SUB ESP,0x8                     -> 6 bytes, 3 instrs
static const BYTE kPrologueTick[]  = { 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x08 };
//   004BFFC0 / 004C0070  56        PUSH ESI
//                        C6 05 ..  MOV byte ptr [0x006284B6],0x0   -> 8 bytes, 2 instrs
//   (cmdrecvCancelTech does hold a PC-relative JMP, at 0x004C00B9 -- well outside this
//   window, which is why HookProbe still reports the patch relocation-safe.)
static const BYTE kPrologueCancel[] = { 0x56, 0xC6, 0x05, 0xB6, 0x84, 0x62, 0x00, 0x00 };

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

bool ScUpgQueueEnabled(void) {
    char buf[16];
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_UPGQ", buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return false;
    return buf[0] == '1' || buf[0] == 'y' || buf[0] == 'Y';
}

static int ResolveMax(void) {
    char buf[16];
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_UPGQ_MAX", buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return SC_UPGQ_DEFAULT_MAX;
    int v = atoi(buf);
    if (v < SC_UPGQ_ENGINE_SLOTS) v = SC_UPGQ_ENGINE_SLOTS;
    if (v > SC_UPGQ_HARD_MAX) v = SC_UPGQ_HARD_MAX;
    return v;
}

static void EnsureLock(void) {
    if (!g_lockReady) { InitializeCriticalSection(&g_lock); g_lockReady = true; }
}

int ScUpgQueueInstall(BYTE* moduleBase) {
    ScEngineSetModuleBase(moduleBase);
    g_recCount = 0;
    g_deepGc = false;
    g_session = ScSessionEpoch();
    g_start = &EngineStartItem;
    memset(g_stat, 0, sizeof(g_stat));
    EnsureLock();

    if (!ScUpgQueueEnabled()) { g_enabled = false; return 0; }
    g_maxTotal = ResolveMax();

    int suspended = ScHookSuspendThreads();
    ScLog("UPGQ: suspended %d other thread(s) for the splice", suspended);

    int installed = 0;
    if (ScHookInstall(&g_hkCondUpg, "btnUpgradeCondition", ScRuntimeAddr(SC_VA_BTN_UPGRADE_COND),
                      (void*)&ScUpgCondUpgradeThunk, 6,
                      kPrologueCond, (int)sizeof(kPrologueCond))) ++installed;
    if (ScHookInstall(&g_hkCondTech, "btnTechCondition", ScRuntimeAddr(SC_VA_BTN_TECH_COND),
                      (void*)&ScUpgCondTechThunk, 6,
                      kPrologueCond, (int)sizeof(kPrologueCond))) ++installed;
    if (ScHookInstall(&g_hkCmdUpg, "cmdrecvUpgrade", ScRuntimeAddr(SC_VA_CMDRECV_UPGRADE),
                      (void*)&HkCmdrecvUpgrade, 11,
                      kPrologueCmd, (int)sizeof(kPrologueCmd))) ++installed;
    if (ScHookInstall(&g_hkCmdTech, "cmdrecvTech", ScRuntimeAddr(SC_VA_CMDRECV_TECH),
                      (void*)&HkCmdrecvTech, 11,
                      kPrologueCmd, (int)sizeof(kPrologueCmd))) ++installed;
    if (ScHookInstall(&g_hkTickUpg, "upgradeTick", ScRuntimeAddr(SC_VA_UPGRADE_TICK),
                      (void*)&ScUpgTickUpgradeThunk, 6,
                      kPrologueTick, (int)sizeof(kPrologueTick))) ++installed;
    if (ScHookInstall(&g_hkTickTech, "techTick", ScRuntimeAddr(SC_VA_TECH_TICK),
                      (void*)&ScUpgTickTechThunk, 6,
                      kPrologueTick, (int)sizeof(kPrologueTick))) ++installed;
    if (ScHookInstall(&g_hkCancelUpg, "cmdrecvCancelUpgrade", ScRuntimeAddr(SC_VA_CMDRECV_CANCEL_UPGRADE),
                      (void*)&HkCmdrecvCancelUpgrade, 8,
                      kPrologueCancel, (int)sizeof(kPrologueCancel))) ++installed;
    if (ScHookInstall(&g_hkCancelTech, "cmdrecvCancelTech", ScRuntimeAddr(SC_VA_CMDRECV_CANCEL_TECH),
                      (void*)&HkCmdrecvCancelTech, 8,
                      kPrologueCancel, (int)sizeof(kPrologueCancel))) ++installed;

    ScHookResumeThreads();

    if (installed != SC_UPGQ_HOOK_COUNT) {
        // Any partial set is worse than none. Unblocking without holding lets the engine
        // overwrite a running upgrade and pay for it twice; holding without promoting
        // strands the queue; promoting without unblocking never has anything to promote.
        ScLog("UPGQ: only %d of %d hooks installed -- ROLLING BACK, upgrades stay vanilla "
              "for this run", installed, SC_UPGQ_HOOK_COUNT);
        ScUpgQueueRemove();
        g_enabled = false;
        return 0;
    }

    g_enabled = true;
    ScLog("UPGQ config: enabled max=%d (the engine holds %d, the plugin holds up to %d per "
          "building, %d buildings) -- %%SCPLUGIN_UPGQ_MAX%%; the plugin never spends, the "
          "engine pays at start",
          g_maxTotal, SC_UPGQ_ENGINE_SLOTS, g_maxTotal - SC_UPGQ_ENGINE_SLOTS,
          SC_UPGQ_MAX_BUILDINGS);
    return installed;
}

void ScUpgQueueRemove(void) {
    // Nothing to give back: every held item is unpaid, so unloading mid-game costs the
    // player exactly nothing. This is the whole refund path, and it is the absence of one.
    if (g_lockReady) {
        EnterCriticalSection(&g_lock);
        g_recCount = 0;
        LeaveCriticalSection(&g_lock);
    }
    ScHookRemove(&g_hkCancelTech);
    ScHookRemove(&g_hkCancelUpg);
    ScHookRemove(&g_hkTickTech);
    ScHookRemove(&g_hkTickUpg);
    ScHookRemove(&g_hkCmdTech);
    ScHookRemove(&g_hkCmdUpg);
    ScHookRemove(&g_hkCondTech);
    ScHookRemove(&g_hkCondUpg);
    g_enabled = false;
}

void ScUpgQueueTestBegin(BYTE* fakeModuleBase, int maxTotal, ScUpgStartFn starter) {
    EnsureLock();
    ScEngineSetModuleBase(fakeModuleBase);
    g_enabled  = fakeModuleBase != NULL;
    g_testing  = fakeModuleBase != NULL;
    g_recCount = 0;
    g_deepGc   = false;
    g_session  = ScSessionEpoch();
    g_maxTotal = maxTotal > 0 ? maxTotal : SC_UPGQ_DEFAULT_MAX;
    g_start    = starter ? starter : &EngineStartItem;
    memset(g_stat, 0, sizeof(g_stat));
}
