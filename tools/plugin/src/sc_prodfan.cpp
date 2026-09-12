// sc_prodfan.cpp -- one Train click queues a unit at EVERY selected production building.
//
// Read sc_prodfan.h first: it states the mechanism, the resource rule, and why the guard
// is a distinction rather than a softening. The evidence for every address and every
// constant is research/production-queue.md and research/command-opcodes.md.
//
// THREADING. ScProdFanLogState runs on the OBSERVER thread, off the marker channel, and
// never writes. ScProdFanDecide is pure and is called from the game thread inside
// sc_fanout's queueCommand detour. The only write to game memory is the one-byte
// selection-count swap in ScProdFanCondAllow, on the game thread, restored before return.

#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "sc_addresses.h"
#include "sc_engine.h"
#include "sc_env.h"
#include "sc_fanout.h"
#include "sc_hook.h"
#include "sc_log.h"
#include "sc_prodfan.h"
#include "sc_queueind.h"   // ScQueueIndReadRing -- the phantom window's coherent ring read
#include "sc_unit.h"

static bool  g_enabled = false;
static bool  g_inited  = false;
static int   g_stat[SC_PRODFAN_STAT__COUNT] = { 0 };

// WHERE THE BUTTON-CONDITION DETOUR RETURNED, counted per term and printed by the oracle.
// "The button is still not drawn" names none of the six tests that could have refused,
// and one blind guess costs a whole game launch; a counter per exit makes the run an
// answer whichever way it goes.
enum CondExit {
    COND_OFF = 0,        // the feature is not enabled
    COND_SINGLE,         // clientSelectionCount <= 1: the stock condition allows anyway
    COND_NOT_TRAIN,      // the button's param is not a unit type (so: an addon button)
    COND_BAD_UNIT,       // the portrait unit did not validate
    COND_NOT_GROUP,      // ScProdFanDecide said no -- its own verdict is logged too
    COND_TYPE_MISMATCH,  // the card's unit is not of the group's type
    COND_HANDLED,        // we called the stock condition and returned its answer
    COND_REENTERED,      // nested inside our own call: take the stock path
    COND__COUNT
};
static int g_condExit[COND__COUNT] = { 0 };
static int g_condCalls = 0;
static int g_condLogged = 0;

static int CondReturn(int which) { ++g_condExit[which]; return 0; }

// How many buildings one oracle line may describe. A group is bounded by the fan-out's
// shadow list; 64 is past anything a box produces, at the cost of stack in a function
// that runs once per marker.
#define SC_PRODFAN_MAX_SHADOW 64

// The engine's own movability predicate (0x0047B770, ECX = CUnit*). It is what makes a
// selection a BUILDING group: the simulation refuses a non-movable unit every selection
// slot but slot 0 (research/building-groups.md 3-4). Called rather than re-implemented --
// four of its terms are per-UNIT, not per-type, so asking about the type once would be a
// different question from the one the engine asks.
typedef int (__attribute__((fastcall)) *ScMovableFn)(DWORD unit);
static bool UnitMovable(DWORD unit) {
    ScMovableFn f = (ScMovableFn)ScRuntimeAddr(SC_VA_UNIT_IS_STANDARD_AND_MOVABLE);
    return f(unit) != 0;
}

bool ScProdFanEnabled(void) {
    if (g_inited) return g_enabled;
    return ScEnvFlag("SCPLUGIN_PRODFAN", false);
}

void ScProdFanInit(BYTE* moduleBase, bool enabled) {
    ScEngineSetModuleBase(moduleBase);
    g_enabled = enabled;
    g_inited  = true;
    ScLog("PRODFAN: %s (%%SCPLUGIN_PRODFAN%%). The oracle runs either way; only the "
          "fan-out of command 0x1F is gated on this.", enabled ? "ENABLED" : "disabled");
}

void ScProdFanTestSetEnabled(bool on) { g_enabled = on; g_inited = true; }

int  ScProdFanStat(int which) {
    return (which >= 0 && which < SC_PRODFAN_STAT__COUNT) ? g_stat[which] : 0;
}
void ScProdFanCountFanout(int buildings) {
    ++g_stat[SC_PRODFAN_STAT_FANNED];
    g_stat[SC_PRODFAN_STAT_BUILDINGS] += buildings;
}
void ScProdFanCountRefusal(void) { ++g_stat[SC_PRODFAN_STAT_REFUSED]; }

const char* ScProdFanVerdictName(int v) {
    switch (v) {
        case SC_PRODFAN_OK:           return "ok";
        case SC_PRODFAN_OFF:          return "off";
        case SC_PRODFAN_NOT_GROUP:    return "not-a-building-group";
        case SC_PRODFAN_ONE_BUILDING: return "one-building";
        case SC_PRODFAN_MIXED_TYPES:  return "mixed-building-types";
        case SC_PRODFAN_BAD_LEN:      return "bad-length";
        default:                      return "?";
    }
}

int ScProdFanDecide(const WORD* types, int count, int simSlots, unsigned cmdLen) {
    if (!ScProdFanEnabled()) return SC_PRODFAN_OFF;

    // The dispatcher consumes exactly 3 bytes for 0x1F (research/command-opcodes.md 1.2).
    // sc_fanout checks this too; it is repeated here so the pure policy is decidable on
    // its own in the offline suite rather than only in combination with its caller.
    if (cmdLen != 3) return SC_PRODFAN_BAD_LEN;

    // simSlots == 1 is "the simulation will hold ONE of these at a time", which for the
    // engine means "these are buildings" (addUnitToSelectionSlot refuses a building every
    // slot but slot 0 -- research/building-groups.md 3). It is the whole safety argument:
    // with it EVERY chunk of the plan is exactly one building; without it a chunk could be
    // twelve units, the hazard command-opcodes.md 3.2 keeps 0x1F passthrough for.
    if (simSlots != 1) return SC_PRODFAN_NOT_GROUP;

    // One building selected is vanilla's own case and the engine already handles it. Not
    // fanning out here is not an optimisation: it keeps the single-building path
    // byte-identical to stock, which is what makes it a usable control arm.
    if (count < 2) return SC_PRODFAN_ONE_BUILDING;

    // MIXED TYPES: refuse the whole command. The engine's own gate,
    // `FUN_0046E1C0(type, activePlayerId)`, is the PLAYER's tech/requirement check -- the
    // same one the Train button's condition calls. Whether it also refuses a building that
    // is the wrong KIND of producer is not established by this repo's evidence, and the
    // failure it would cause is the expensive kind: a Marine queued at a Factory, paid for,
    // buildable nowhere the player meant. Refusing the WHOLE command rather than the odd
    // building is the conservative half: a partial fan-out spends the player's minerals on
    // a subset they never chose.
    for (int i = 1; i < count; ++i) {
        if (types[i] != types[0]) return SC_PRODFAN_MIXED_TYPES;
    }

    return SC_PRODFAN_OK;
}

void ScProdFanLogState(const char* tag) {
    if (!ScEngineModuleBase()) return;
    const char* t = tag ? tag : "-";

    ScShadowInfo shadow[SC_PRODFAN_MAX_SHADOW];
    int visible = 0;
    unsigned version = 0;
    int n = ScFanoutCopyShadow(shadow, SC_PRODFAN_MAX_SHADOW, &visible, &version);

    int buildings = 0;
    int totalQueued = 0;
    BYTE player = 0;
    bool havePlayer = false;

    for (int i = 0; i < n; ++i) {
        DWORD u = shadow[i].unit;
        if (!ScUnitPtrValid(u)) {
            ScLog("PRODFAN [%s] i=%d/%d unit=0x%08X INVALID (not a live CUnit slot)",
                  t, i, n, (unsigned)u);
            continue;
        }
        // The staleness test the fan-out itself uses: a moved uniqueness byte means this
        // CUnit slot was recycled and the pointer names a different unit
        // (research/binary-selection-map.md 6.1). Reported rather than skipped, so "the
        // selection went stale" stays distinguishable from "the queue is empty".
        BYTE uniq = ScUnitUniqueness(u);
        BYTE owner = ScUnitPlayer(u);
        WORD type = *(WORD*)(u + SC_CUNIT_OFF_UNIT_ID);
        // ONE coherent snapshot for engineLen AND engine=[]: two raw passes caught the
        // queue indicator's phantom slot in one and not the other (engineLen=4 printed
        // beside five occupied slots).
        WORD ring[SC_BUILD_QUEUE_SLOTS];
        BYTE head = 0;
        int ringStable = ScQueueIndReadRing(u, &head, ring);
        int len = ScRingLength(ring);
        char eng[96];
        ScRingFormat(ring, eng, (int)sizeof(eng));

        if (!havePlayer && owner < SC_MAX_PLAYERS) { player = owner; havePlayer = true; }
        ++buildings;
        totalQueued += len;

        // engine=[] is the five ring slots at CUnit+0x98 in SLOT order, printed beside
        // their head, so a reader sees the raw memory rather than the display order the
        // head rotates it into.
        // buildState / buildUnit are what a PLAYER can see: a building with an incomplete
        // unit at CUnit+0xEC draws a production progress bar. The status area only ever
        // draws the primary selection's queue, so this separates "four buildings are
        // working" from "the screen shows one".
        ScLog("PRODFAN [%s] i=%d/%d unit=0x%08X type=0x%03X player=%u head=%u "
              "engineLen=%d engine=[%s] buildState=%u buildUnit=0x%08X ringStable=%d%s",
              t, i, n, (unsigned)u, (unsigned)type, (unsigned)owner,
              (unsigned)head, len, eng,
              (unsigned)*(BYTE*)(u + SC_CUNIT_OFF_BUILD_STATE),
              (unsigned)*(DWORD*)(u + SC_CUNIT_OFF_BUILD_UNIT), ringStable,
              uniq != shadow[i].uniqueness ? " STALE(uniqueness moved)" : "");
    }

    // THE CLIENT'S OWN SELECTION, the array the button decision is made from -- printed so
    // 0x00597208 is a reading rather than a named address. It must agree with the
    // per-building lines above for a boxed group; disagreement is the finding.
    {
        DWORD* sel = (DWORD*)ScRuntimeAddr(SC_VA_CLIENT_SELECTION_GROUP);
        unsigned cn = *(BYTE*)ScRuntimeAddr(SC_VA_CLIENT_SELECTION_COUNT);
        if (cn > SC_SELECTION_SLOTS) cn = SC_SELECTION_SLOTS;
        char units[256]; units[0] = '\0';
        int used = 0;
        int slots = SC_SELECTION_SLOTS;
        bool haveFirst = false;
        for (unsigned i = 0; i < cn && used + 24 < (int)sizeof(units); ++i) {
            DWORD u = sel[i];
            if (!ScUnitPtrValid(u)) {
                used += _snprintf(units + used, sizeof(units) - used, "%s(bad)", i ? "," : "");
                continue;
            }
            if (!haveFirst) { slots = UnitMovable(u) ? SC_SELECTION_SLOTS : 1; haveFirst = true; }
            used += _snprintf(units + used, sizeof(units) - used, "%s0x%08X/0x%03X",
                              i ? "," : "", (unsigned)u,
                              (unsigned)*(WORD*)(u + SC_CUNIT_OFF_UNIT_ID));
        }
        if (cn == 0) lstrcpynA(units, "(empty)", (int)sizeof(units));
        ScLog("PRODFAN clientsel [%s] n=%u slots=%d units=[%s]", t, cn, slots, units);
    }

    // Where the button-condition detour has been returning. BEFORE the summary, because
    // the summary is the line a reader waits for to know the whole answer has landed.
    ScLog("PRODFAN cond [%s] calls=%d off=%d single=%d notTrain=%d badUnit=%d "
          "notGroup=%d typeMismatch=%d handled=%d reentered=%d",
          t, g_condCalls, g_condExit[COND_OFF], g_condExit[COND_SINGLE],
          g_condExit[COND_NOT_TRAIN], g_condExit[COND_BAD_UNIT],
          g_condExit[COND_NOT_GROUP], g_condExit[COND_TYPE_MISMATCH],
          g_condExit[COND_HANDLED], g_condExit[COND_REENTERED]);

    // ALWAYS a summary line, even with an empty selection -- an absence has to be
    // positively reported, or "the oracle did not run" and "nothing is selected" read
    // identically (AGENTS.md § "Oracles: absence and defect-era checks"). clientCount sits
    // beside the selection size so 0x0059723D, named for what it gates, becomes a reading
    // the suite asserts rather than a label taken on trust.
    ScLog("PRODFAN [%s] buildings=%d selected=%d visible=%d simSlots=%d clientCount=%u "
          "totalQueued=%d minerals=%u gas=%u enabled=%d fanned=%d refused=%d reached=%d "
          "lit=%d",
          t, buildings, n, visible, ScFanoutSimSlots(),
          (unsigned)*(BYTE*)ScRuntimeAddr(SC_VA_CLIENT_SELECTION_COUNT), totalQueued,
          havePlayer ? (unsigned)*ScPlayerMinerals(player) : 0u,
          havePlayer ? (unsigned)*ScPlayerGas(player) : 0u,
          ScProdFanEnabled() ? 1 : 0,
          g_stat[SC_PRODFAN_STAT_FANNED], g_stat[SC_PRODFAN_STAT_REFUSED],
          g_stat[SC_PRODFAN_STAT_BUILDINGS], g_stat[SC_PRODFAN_STAT_LIT]);
}

void ScProdFanLogStats(void) {
    ScLog("PRODFAN STATS: fanned=%d refused=%d buildingsReached=%d lit=%d enabled=%d",
          g_stat[SC_PRODFAN_STAT_FANNED], g_stat[SC_PRODFAN_STAT_REFUSED],
          g_stat[SC_PRODFAN_STAT_BUILDINGS], g_stat[SC_PRODFAN_STAT_LIT],
          ScProdFanEnabled() ? 1 : 0);
}

// ---------------------------------------------------------------------------
// THE CLIENT GATE. Measured in game: with four buildings selected the Train button is not
// drawn AT ALL -- condition 0x00428E60 refuses on `clientSelectionCount > 1` and the card
// layout leaves a refused control with no Button record. A fan-out cannot help: there is
// no command to fan out, because the player has no button to press.
//
// The detour relaxes that one clause, for one shape of selection, and keeps everything
// else the function does -- above all its tail call into the requirement gate, the
// engine's own answer to "may this player build this thing at THIS building", which is
// not skipped, weakened or re-implemented here.
//
// It cannot fire where the fan-out would not act, by construction: the test below is
// `ScProdFanDecide`, the same predicate that decides whether the command is fanned out.
// `simSlots == 1` is what makes a selection a building group at all, and sc_fanout
// computes it from the engine's own movability predicate, so with
// `%SCPLUGIN_BUILDING_GROUPS%=0` a box selects one building, the count is 1, and this
// detour returns "not ours" first.
// ---------------------------------------------------------------------------

static ScHook g_hkCond;
static void*  g_condTrampoline = NULL;
extern "C" { void* g_scProdFanCondTramp = NULL; }   // read by the asm thunk

// The button condition's own prologue, from this binary (sc_addresses.h quotes the whole
// listing): PUSH EBP / MOV EBP,ESP / MOV EAX,ECX -- three whole instructions, five bytes,
// none of them PC-relative, so they relocate into the trampoline unchanged.
static const BYTE kPrologueCond[] = { 0x55, 0x8B, 0xEC, 0x8B, 0xC1 };

// The CLIENT's own selection, read at the moment it is asked about: `CUnit*[12]` at
// 0x00597208 with its count in the byte at 0x0059723D -- the very byte the button
// condition tests, five bytes past the end of the array it belongs to.
//
// Do not read the fan-out's shadow list on the button path. The card is laid out as part
// of the selection changing and the fan-out captures its shadow list on the same event;
// which runs first is not this plugin's to decide, so the shadow list may still be empty
// -- and a button correct one frame too late is never drawn, because the layout does not
// run again until the selection changes. The client's array is what the card is drawn FOR,
// so it is correct by definition when the layout consults a condition about it. The
// predicate applied to it is still ScProdFanDecide, so both paths agree on WHAT a fannable
// selection is; they differ only in where they read the selection from.
static int CollectClientSelection(WORD* types, int max, int* outSlots) {
    *outSlots = SC_SELECTION_SLOTS;
    DWORD* sel = (DWORD*)ScRuntimeAddr(SC_VA_CLIENT_SELECTION_GROUP);
    unsigned n = *(BYTE*)ScRuntimeAddr(SC_VA_CLIENT_SELECTION_COUNT);
    if (n > SC_SELECTION_SLOTS) n = SC_SELECTION_SLOTS;
    int k = 0;
    bool haveFirst = false;
    for (unsigned i = 0; i < n && k < max; ++i) {
        DWORD u = sel[i];
        if (!ScUnitPtrValid(u)) continue;
        if (!haveFirst) { *outSlots = UnitMovable(u) ? SC_SELECTION_SLOTS : 1; haveFirst = true; }
        types[k++] = *(WORD*)(u + SC_CUNIT_OFF_UNIT_ID);
    }
    return k;
}

// Calls the STOCK condition through the trampoline, with its own calling convention:
// `__stdcall(CUnit* unit)` with ECX = the button's type param and EDX = the player. The
// trampoline is the relocated prologue plus a jump back to target+5, so this is the
// original function in every respect, including its RET 4 -- which is why the pushed
// argument is not cleaned up here.
//
// Do not reproduce the condition's allow path instead. Hand-writing those ten instructions
// and calling the requirement gate with ESI and EAX set by hand installs, runs and counts
// four allowed buttons -- while the button is still not drawn, because the hand-made
// register state does not match what the gate wants. Calling the engine's own code leaves
// no convention for this plugin to get wrong, and the tech rules stay the engine's.
static int CallStockCondition(DWORD type, DWORD unit, DWORD player) {
    int ret = 0;
    void* fn = g_condTrampoline;
    if (!fn) return 0;
    __asm__ __volatile__("pushl %[unit]\n\t"
                         "calll *%[fn]"
                         : "=a"(ret)
                         : "c"(type), "d"(player), [unit] "m"(unit), [fn] "r"(fn)
                         : "cc", "memory");
    return ret;
}

// The value the condition returns when we handle it. The card layout reads the result as a
// TRI-STATE (research/command-card.md 4.1): > 0 shows the button, 0 skips it entirely and
// advances the layout's button cursor, < 0 shows it GREYED. The game thread is the only
// writer and reader, between the thunk's call and its return, so one slot is enough.
static int g_condResult = 0;
extern "C" { int g_scProdFanResult = 0; }

// Returns non-zero to mean "we are handling this call; return g_scProdFanResult". Called
// from the thunk with the three values the condition received: ECX (the button's type
// param), its stack argument (the unit the card is drawn for) and EDX (the player). Runs
// on the GAME thread, once per gated button per card relayout.
extern "C" int ScProdFanCondAllow(DWORD type, DWORD unit, DWORD player) {
    ++g_condCalls;
    // The first few calls verbatim, whatever they do. Rate-limited because the card is
    // laid out many times a second; eight is enough to see one selection's worth.
    if (g_condLogged < 8) {
        ++g_condLogged;
        ScLog("PRODFAN cond: call#%d type=0x%03X unit=0x%08X player=%u clientCount=%u "
              "simSlots=%d shadow=%d",
              g_condCalls, (unsigned)type, (unsigned)unit, (unsigned)player,
              ScEngineModuleBase() ? (unsigned)*(BYTE*)ScRuntimeAddr(SC_VA_CLIENT_SELECTION_COUNT) : 0u,
              ScFanoutSimSlots(), ScFanoutShadowCount());
    }
    if (!g_enabled || !ScEngineModuleBase()) return CondReturn(COND_OFF);

    // THE BUTTON PARAM IS A u16, AND ECX ARRIVES WITH A DIRTY UPPER HALF. Measured:
    // `type=0x510007`, `0x51006B`, `0x51006C` -- the Train button and the two addon
    // buttons, each carrying `0x0051` in its high half. The engine never sees it:
    // `0x00428E60` does `MOV EAX,ECX` and the requirement interpreter reads **AX**, so only
    // the low sixteen bits are the type (research/command-card.md: `Button+0x0C
    // conditionParam (u16)`). Comparing all thirty-two against 0x6A makes every button look
    // like an addon and refuses the lot.
    type &= 0xFFFFu;

    // Only when the engine would actually refuse. At a count of 1 the original allows
    // anyway, so returning 0 here keeps the single-building path byte-for-byte stock --
    // which is what makes it usable as the control arm.
    if (*(BYTE*)ScRuntimeAddr(SC_VA_CLIENT_SELECTION_COUNT) <= 1) return CondReturn(COND_SINGLE);

    // TRAIN BUTTONS ONLY. This condition also gates the two ADDON buttons (measured:
    // slots 7 and 8 of the Command Center card, params 107 and 108, action 0x00423D10).
    // Their param is a BUILDING type; a Train button's is a unit type below the very
    // bound cmdrecvTrain itself applies. Lighting an addon button for a group is the
    // accident this line prevents -- nothing fans 0x35 out, so it would be a button that
    // looks live and does nothing.
    if (type >= SC_TRAIN_TYPE_LIMIT) return CondReturn(COND_NOT_TRAIN);

    if (!ScUnitPtrValid(unit)) return CondReturn(COND_BAD_UNIT);

    WORD types[SC_PRODFAN_MAX_SHADOW];
    int slots = SC_SELECTION_SLOTS;
    int n = CollectClientSelection(types, SC_PRODFAN_MAX_SHADOW, &slots);
    // THE SHARED PREDICATE: the same function the command path decides the fan-out with.
    int verdict = ScProdFanDecide(types, n, slots, 3);
    if (verdict != SC_PRODFAN_OK) {
        static int lastVerdict = -1;
        if (verdict != lastVerdict) {
            ScLog("PRODFAN cond: refused for the card -- %d selected, slots=%d : %s",
                  n, slots, ScProdFanVerdictName(verdict));
            lastVerdict = verdict;
        }
        return CondReturn(COND_NOT_GROUP);
    }

    // And the button's own building must be one of the group -- the card is drawn for the
    // primary selection, so this should always hold; asserting it costs one load and
    // stops a card drawn for something else from lighting a button on this group's back.
    if (*(WORD*)(unit + SC_CUNIT_OFF_UNIT_ID) != types[0]) return CondReturn(COND_TYPE_MISMATCH);

    // THE WHOLE RELAXATION, and it is three lines. The stock condition refuses on one
    // clause -- `clientSelectionCount > 1` -- so it is shown a count of 1 for the length
    // of one call and then handed its own value straight back. Everything else the
    // function does, above all its tail call into the requirement interpreter, runs
    // unmodified and with the register state the engine itself set up. So the answer to
    // "may this player build this type at this building" stays entirely the engine's; the
    // only thing this plugin changes is that the question gets asked at all.
    //
    // ABOUT THE WRITE:
    //
    //  * It is restored on EVERY path out of here. There is no return, no throw and no
    //    early exit between the two stores -- the only thing between them is the call --
    //    and anything added later must keep that true. It is a byte in this process's own
    //    memory, not persistent user state (AGENTS.md § "Hard rules"), and it moves no
    //    resource.
    //  * RE-ENTRANCY. The trampoline enters the original at target+5, so the stock
    //    condition can never re-enter this detour for its own function. The depth guard
    //    makes that a property of the code instead of an argument about the engine: a
    //    nested call takes the stock path and the outer call still restores exactly what
    //    it saved. The game thread is the only caller, so the counter needs no interlock.
    //  * If the process is torn down inside the call the restore is skipped. That is
    //    acceptable: the address space is going away with it.
    static int depth = 0;
    if (depth != 0) return CondReturn(COND_REENTERED);
    BYTE* countPtr = (BYTE*)ScRuntimeAddr(SC_VA_CLIENT_SELECTION_COUNT);
    BYTE savedCount = *countPtr;
    ++depth;
    *countPtr = 1;
    int r = CallStockCondition(type, unit, player);
    *countPtr = savedCount;
    --depth;
    DWORD reason = *(DWORD*)ScRuntimeAddr(SC_VA_CARD_REFUSE_REASON);

    // Logged once per DISTINCT answer, not once per relayout: the card is laid out many
    // times a second and an unconditional line here would bury the log. The verdict and
    // the engine's own refusal code are both printed, because "the button did not appear"
    // and "the button did not appear FOR THIS REASON" are different findings, and only the
    // second one survives the run without another launch.
    static int lastR = 0x7FFFFFFF;
    static DWORD lastReason = 0xFFFFFFFF;
    if (r != lastR || reason != lastReason) {
        ScLog("PRODFAN gate: type=0x%03X unit=0x%08X player=%u -> %d (reason=%u) : %s",
              (unsigned)type, (unsigned)unit, (unsigned)player, r, (unsigned)reason,
              r > 0 ? "SHOW" : (r < 0 ? "GREYED" : "skipped -- the button will not be drawn"));
        lastR = r;
        lastReason = reason;
    }

    g_condResult = r;
    g_scProdFanResult = r;
    if (r > 0) ++g_stat[SC_PRODFAN_STAT_LIT];
    (void)g_condResult;
    ++g_condExit[COND_HANDLED];
    return 1;
}

// The thunk. The condition is entered BEFORE its own prologue, so at this point
// ECX = the type, EDX = the player, [ESP] = return address and [ESP+4] = the unit, and
// the function owes the caller a RET 4.
//
// PUSHAD stores EAX ECX EDX EBX ESP EBP ESI EDI from high address to low, so with entry
// ESP called E the saved EAX is at E-4 and the saved ECX at E-8. Every offset below is
// derived from that and noted beside its push.
extern "C" void ScProdFanCondThunk(void);
asm(
    ".text\n"
    ".globl _ScProdFanCondThunk\n"
"_ScProdFanCondThunk:\n"
    "  pushal\n"                     // -32 : esp = E-32
    "  pushfl\n"                     // -4  : esp = E-36
    "  pushl 24(%esp)\n"             // player : saved EDX == E-12 == esp+24
    "  pushl 44(%esp)\n"             // unit   : entry+4 == E+4 == esp+44 (esp moved -4)
    "  pushl 36(%esp)\n"             // type   : saved ECX == E-8 == esp+36 (esp moved -8)
    "  call  _ScProdFanCondAllow\n"
    "  addl  $12, %esp\n"            // esp = E-36 again
    "  movl  %eax, 32(%esp)\n"       // the HANDLED flag into the saved-EAX slot (E-4)...
    "  popfl\n"
    "  popal\n"                      // ...so popal restores it as EAX, regs otherwise intact
    "  testl %eax, %eax\n"
    "  jz    1f\n"
    // --- ours: return the verdict the C side got from the engine's own gate ---
    "  movl  _g_scProdFanResult, %eax\n"
    "  ret   $4\n"
    // --- not ours: stock, with every register and the stack exactly as they arrived ---
"1:\n"
    "  jmp   *_g_scProdFanCondTramp\n"
);

int ScProdFanInstall(void) {
    if (!g_enabled || !ScEngineModuleBase()) return 0;
    int suspended = ScHookSuspendThreads();
    bool ok = ScHookInstall(&g_hkCond, "btnTrainCondition", ScRuntimeAddr(SC_VA_BTN_TRAIN_CONDITION),
                            (void*)&ScProdFanCondThunk, 5,
                            kPrologueCond, (int)sizeof(kPrologueCond));
    if (ok) {
        g_condTrampoline = g_hkCond.trampoline;
        g_scProdFanCondTramp = g_condTrampoline;
    }
    ScHookResumeThreads();
    (void)suspended;
    if (!ok) {
        // Fail CLOSED. Without the button there is nothing to fan out, so a half-armed
        // feature would be a plugin that changes command handling for a command the
        // player can never issue.
        g_enabled = false;
        ScLog("PRODFAN: the button-condition detour did NOT install -- the feature is "
              "disabled for this run rather than left half-armed.");
        return 0;
    }
    return 1;
}

void ScProdFanRemove(void) {
    if (g_hkCond.installed) ScHookRemove(&g_hkCond);
    g_condTrampoline = NULL;
    g_scProdFanCondTramp = NULL;
}
