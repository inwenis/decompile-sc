// sc_fanout.cpp -- see sc_fanout.h.
//
// HOW THE THREE PIECES FIT
//
//   1. sortOverflowHandler (0x0046F040) is called by the engine once for every unit
//      that passed every selection filter but did not fit in the 12 output slots.
//      That is the ONLY place the units the cap is about to throw away are
//      individually visible. Our hook records them -- and, because that handler can
//      also EVICT an already-stored unit and replace it, it snapshots the 12-slot
//      output array on every call, before the original runs. The union of those
//      snapshots plus the final output array is the complete pre-cap selection.
//
//   2. CMDACT_Select (0x004C0860) is the client's selection commit point: it is
//      handed the engine's final (truncated) list. Our hook takes that list as the
//      VISIBLE selection, unions it with whatever the overflow hook accumulated
//      since the last commit, and that union is the shadow list. The accumulator is
//      cleared on every commit, so it can only ever hold units from the input
//      operation being committed.
//
//   3. queueCommand (0x00485BD0) is the single funnel every outgoing command passes
//      through. Our hook watches the command id. For an order the shadow list is
//      bigger than 12, it SUPPRESSES the engine's own command and emits
//      ceil(overflow/12) + 1 Select+order pairs instead, through the trampoline.
//      The visible chunk is emitted LAST, so the sim-side selection is left exactly
//      as the player sees it -- the separate "restore Select" that
//      research/selection-cap.md 7 costs is folded into the final pair.
//
//      ONE EXCEPTION, since task 020 put a liveness gate on the emit path: if EVERY
//      unit of the visible chunk fails that gate, no Select is written for it and the
//      simulation is left holding the last OVERFLOW chunk instead. It needs all twelve
//      visible units to be inside the death/removal window at once, it self-heals on
//      the next order or selection commit, and the pre-020 behaviour was not better --
//      it emitted twelve tags the receive path then had to throw away. Stated here
//      because the invariant above is load-bearing everywhere else in this file.

#include <windows.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#include "sc_addresses.h"
#include "sc_circles.h"
#include "sc_fanout.h"
#include "sc_hook.h"
#include "sc_hudrow.h"
#include "sc_queueind.h"
#include "sc_log.h"
#include "sc_prodfan.h"
#include "sc_session.h"

// ---------------------------------------------------------------------------
// Tunables (all overridable by environment variable, all logged at attach)
// ---------------------------------------------------------------------------

#define SC_SHADOW_MAX       256   // wire ceiling is 255 units (count byte, unsigned)

// The longest command in the fan-out set is 11 bytes (0x15, Targeted Order). That is not
// a guess any more: research/data/command-opcodes.tsv carries the length the engine's own
// receive dispatcher (0x004865D0) consumes for every opcode it accepts, cross-checked
// against the command-length table at 0x005005F8, and the largest among the fan-out ids
// is 0x0B. 32 leaves room without letting a malformed command through.
#define SC_MAX_ORDER_BYTES   32

// Default per-turn byte budget. The replay format prefixes each frame's command
// block with a SINGLE byte (screp repparser.go:464-465), so everything every player
// does in one frame must fit in 255 bytes. 200 leaves room for the other commands
// in the same frame. selection-cap.md 6.2.
#define SC_DEFAULT_BUDGET   200

static ScMode  g_mode = SC_MODE_OBSERVE;
static BYTE*   g_base = NULL;
static int     g_budget = SC_DEFAULT_BUDGET;
static int     g_maxUnits = SC_SHADOW_MAX - 1;
static bool    g_verboseCmds = true;

static void* Rt(DWORD staticVa) {
    return (void*)(g_base + (staticVa - SC_PREFERRED_IMAGE_BASE));
}

// ---------------------------------------------------------------------------
// Which commands get fanned out
//
// ONE RULE, and it is a fact about the engine rather than a preference:
//
//     fan out a command  <=>  the engine's own handler for it applies it to EVERY
//                             unit in the receiving player's selection, AND the
//                             handler does not move the player's resources.
//
// The first half is why fan-out is semantics-preserving: for such a command the engine
// already does the thing to all twelve units it holds, so replaying it against the units
// the cap hid is the same operation over more units, not a new one. The second half is
// the safety margin: minerals and gas are a player-global resource, and a command that
// spends them is one the player issued once.
//
// Both halves are read out of this binary and tabulated per opcode in
// research/data/command-opcodes.tsv (built by tools/ghidra/build-opcode-policy.ps1) and
// written up in research/command-opcodes.md. `kOpcodes` below is that table's fan-out and
// length columns, transcribed; nothing here is a guess about what an id "probably means".
//
// The sharp case is the SINGLE-gated commands -- Train, Build, Research and friends do
// nothing at all unless EXACTLY ONE unit is selected. They look harmless to replay
// precisely because they are inert at twelve, but a fan-out chunk can be one unit long,
// so replaying one would make it fire where the player's own selection never could.
// They are passthrough.
//
// %SCPLUGIN_FANOUT_CMDS% (space/comma separated hex) replaces the set; the length check
// below still applies to whatever it names.
// ---------------------------------------------------------------------------

struct ScOpcode {
    BYTE id;
    signed char len;      // bytes the engine's dispatcher consumes; -1 = computed
    bool fanout;          // the policy from research/data/command-opcodes.tsv
};

// Every opcode the receive dispatcher at 0x004865D0 accepts. Ids absent from this table
// are not commands the engine takes, and an id whose length disagrees with the one here
// is never fanned out (see ScFanoutOnCommand).
static const ScOpcode kOpcodes[] = {
    { 0x05, 1, false }, { 0x06, -1, false }, { 0x07, -1, false }, { 0x08, 1, false },
    { 0x09, -1, false }, { 0x0A, -1, false }, { 0x0B, -1, false }, { 0x0C, 8, false },
    { 0x0D, 3, false }, { 0x0E, 5, false }, { 0x0F, 2, false }, { 0x10, 1, false },
    { 0x11, 1, false }, { 0x12, 5, false }, { 0x13, 3, false },
    { 0x14, 10, true },   // Right Click        -- applier 0x004560D0 loops the selection
    { 0x15, 11, true },   // Targeted Order     -- applier 0x0049AB00 loops the selection
    { 0x18, 1, false },   // SINGLE-gated, and refunds through 0x00468280
    { 0x19, 1, false },   // loops, but refunds through 0x00468280
    { 0x1A, 2, true },    // Stop               -- named in game, key S
    { 0x1B, 1, true }, { 0x1C, 1, true }, { 0x1D, 1, true }, { 0x1E, 2, true },
    { 0x1F, 3, false },   // SINGLE-gated and spends resources through 0x00467250
    { 0x20, 3, false },   // SINGLE-gated
    { 0x21, 2, true }, { 0x22, 2, true },
    { 0x23, 3, false },   // loops, but spends resources through 0x00467250
    { 0x25, 2, true }, { 0x26, 2, true },
    { 0x27, 1, false },   // loops, but spends resources through 0x00467250
    { 0x28, 2, true }, { 0x29, 3, false }, { 0x2A, 1, true },
    { 0x2B, 2, true },    // Hold Position      -- named in game, key H
    { 0x2C, 2, true }, { 0x2D, 2, true }, { 0x2E, 1, true },
    { 0x2F, 5, false }, { 0x30, 2, false }, { 0x31, 1, false }, { 0x32, 2, false },
    { 0x33, 1, false }, { 0x34, 1, false },
    { 0x35, 3, false },   // SINGLE-gated and spends resources through 0x00467250
    { 0x36, 1, true }, { 0x37, 7, false }, { 0x38, 1, false }, { 0x39, 1, false },
    { 0x3A, 2, false }, { 0x3B, 2, false }, { 0x55, 2, false }, { 0x56, 10, false },
    { 0x57, 2, false }, { 0x58, 5, false }, { 0x5A, 1, true }, { 0x5C, 82, false },
};

static BYTE g_fanoutCmds[64];
static int  g_fanoutCmdCount = 0;

static const ScOpcode* FindOpcode(BYTE id) {
    for (unsigned i = 0; i < sizeof(kOpcodes) / sizeof(kOpcodes[0]); ++i) {
        if (kOpcodes[i].id == id) return &kOpcodes[i];
    }
    return NULL;
}

static void SetDefaultFanoutCmds(void) {
    g_fanoutCmdCount = 0;
    for (unsigned i = 0; i < sizeof(kOpcodes) / sizeof(kOpcodes[0]) &&
                        g_fanoutCmdCount < (int)sizeof(g_fanoutCmds); ++i) {
        if (kOpcodes[i].fanout) g_fanoutCmds[g_fanoutCmdCount++] = kOpcodes[i].id;
    }
}

static void LoadFanoutCmds(void) {
    char buf[256];
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_FANOUT_CMDS", buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) { SetDefaultFanoutCmds(); return; }

    g_fanoutCmdCount = 0;
    const char* p = buf;
    while (*p && g_fanoutCmdCount < (int)sizeof(g_fanoutCmds)) {
        while (*p == ' ' || *p == ',' || *p == ';') ++p;
        if (!*p) break;
        char* end = NULL;
        long v = strtol(p, &end, 16);
        if (end == p) break;
        if (v >= 0 && v <= 0xFF) g_fanoutCmds[g_fanoutCmdCount++] = (BYTE)v;
        p = end;
    }
    if (g_fanoutCmdCount == 0) SetDefaultFanoutCmds();
}

static bool IsFanoutCmd(BYTE id) {
    for (int i = 0; i < g_fanoutCmdCount; ++i) if (g_fanoutCmds[i] == id) return true;
    return false;
}

// ---------------------------------------------------------------------------
// Shadow selection
// ---------------------------------------------------------------------------

struct ShadowUnit {
    DWORD ptr;
    BYTE  uniqueness;   // CUnit+0xA5, re-checked at emit time: the engine's own
                        // staleness test (binary-selection-map.md 6.1)
    BYTE  player;       // CUnit+0x4C
};

// The full pre-cap selection, VISIBLE UNITS LAST. `g_visibleCount` of the tail
// entries are the ones the engine (and the HUD) actually holds.
static ShadowUnit g_shadow[SC_SHADOW_MAX];
static int        g_shadowCount   = 0;
static int        g_visibleCount  = 0;

// Units seen by the overflow hook since the last selection commit.
static ShadowUnit g_accum[SC_SHADOW_MAX];
static int        g_accumCount = 0;

// Bumped on every selection commit and on the hotkey-recall shadow drop, so the
// HUD row (task 017) can detect "the selection changed" without diffing lists.
static unsigned   g_shadowVersion = 0;

static CRITICAL_SECTION g_lock;
static bool g_lockInit = false;

static bool ShadowContains(const ShadowUnit* arr, int n, DWORD ptr) {
    for (int i = 0; i < n; ++i) if (arr[i].ptr == ptr) return true;
    return false;
}

// IDENTITY, not address. A CUnit* is a slot in a fixed 1700-entry global that the engine
// reuses game after game, so a pointer alone does not name a unit -- it names a seat. The
// module's own notion of identity everywhere else (UnitLive, PassesGate) is the PAIR
// (pointer, CUnit+0xA5), and anything that decides "is this the same unit" has to use the
// pair or it is really asking "is this the same seat".
//
// This exists because the control-group code originally used ShadowContains for its
// containment check, and review pointed out the consequence: a record left over from a
// previous game whose slot is now occupied by a DIFFERENT live unit would compare equal,
// so the check that is supposed to detect a cross-session stale group would pass on
// exactly the input it exists to catch. The offline case that certified it happened to
// use disjoint slots (40..51 against a group of 0..35), which is the one shape where the
// two functions agree.
static bool ShadowContainsUnit(const ShadowUnit* arr, int n, const ShadowUnit* u) {
    for (int i = 0; i < n; ++i) {
        if (arr[i].ptr == u->ptr && arr[i].uniqueness == u->uniqueness) return true;
    }
    return false;
}

// Is this a pointer to a real slot of the unit array? The array is a fixed
// 1700-entry global, so an in-range pointer is always readable -- but the pointer
// itself has to be validated against the array's bounds and stride first, because a
// bad one would otherwise be dereferenced. Every deref in this file goes through
// here, including each link of the player-unit-list walk below.
static bool UnitPtrValid(DWORD ptr) {
    if (!ptr) return false;
    DWORD arrayBase = (DWORD)Rt(SC_VA_UNIT_ARRAY_BASE);
    if (ptr < arrayBase) return false;
    DWORD off = ptr - arrayBase;
    if (off % SC_CUNIT_SIZE != 0) return false;
    return (off / SC_CUNIT_SIZE + 1) <= SC_MAX_UNIT_INDEX;   // the wire index is 1-based
}

// Reads a unit's identity fields.
static bool ReadUnit(DWORD ptr, ShadowUnit* out) {
    if (!UnitPtrValid(ptr)) return false;
    out->ptr        = ptr;
    out->uniqueness = *(BYTE*)(ptr + SC_CUNIT_OFF_UNIQUENESS);
    out->player     = *(BYTE*)(ptr + SC_CUNIT_OFF_PLAYER);
    return true;
}

// index+uniqueness packed exactly as CMDACT_Select / the Right Click builder /
// the Targeted Order builder all do it. Returns 0 for anything out of range,
// which is what the engine encodes too.
static WORD UnitTag(DWORD ptr) {
    if (!UnitPtrValid(ptr)) return 0;
    DWORD index = (ptr - (DWORD)Rt(SC_VA_UNIT_ARRAY_BASE)) / SC_CUNIT_SIZE + 1;
    BYTE uniq = *(BYTE*)(ptr + SC_CUNIT_OFF_UNIQUENESS);
    return (WORD)(((WORD)uniq << 11) | (WORD)index);
}

// ---------------------------------------------------------------------------
// LIVENESS -- why one uniqueness comparison is not enough on THIS path
//
// The shadow list is captured at selection time and replayed, as unit TAGS, into a
// Select the engine's own receive path consumes. That receive path
// (CMDRECV_Select 0x004C2750 -> addUnitToSelectionSlot 0x0049AF80,
// binary-selection-map.md 5.1/5.2) validates a received entry with exactly:
// count <= 12, index/uniqueness decode, CUnit+0xA5 == the tag's uniqueness, a
// 12-bounded dedup, and `unit->id != 14`. Then it does this, unguarded:
//
//     if (*(byte*)(*(int*)(unit + 0x0C) + 0x0E) & 0x20) return 0;   // sprite->flags
//
// -- it DEREFERENCES CUnit+0x0C, the sprite pointer. There is no null check and no
// liveness check anywhere on that path: the engine trusts the sender, and on this
// path WE are the sender.
//
// CUnit+0xA5 does not cover that trust. It is written by ONE instruction in the whole
// binary, 0x004A03FD inside the unit (re)init 0x004A0320 -- so it moves on slot REUSE
// and NOT on death (selection-circles.md 4.5, byte-level verified by task 014). A unit
// that died a moment ago still carries the uniqueness we captured, so the tag we would
// replay still passes the engine's check, and the engine then follows a sprite pointer
// belonging to a unit that has been removed from play.
//
// So the emit-side gate supplies exactly what the receive side does not check:
//
//   engine checks (receive side)      |  this gate adds (send side)
//   ---------------------------------|-------------------------------------------
//   uniqueness  -> recycled slot      |  hitpoints != 0   -> DAMAGE DEATH
//   id != 14, dedup, count <= 12      |  in player list   -> REMOVED FROM PLAY
//                                     |  player unchanged -> OWNERSHIP CHANGE
//                                     |  sprite != NULL   -> the pointer it derefs
//
// Term by term, with what each one is for and what it costs:
//
//   1. uniqueness (CUnit+0xA5) -- the engine's own test, kept. Catches a RECYCLED
//      slot, and only that. One byte compare.
//   2. hitpoints (CUnit+0x08) != 0 -- catches a DAMAGE DEATH, the case (1) misses.
//      It is the field the engine's damage primitive 0x004797B0 drives to 0 on a
//      kill (command-opcodes.md 6), and nothing resets it until the slot is
//      re-inited, so it reads 0 for the whole dead-but-not-recycled window. This is
//      the same term task 017 put in sc_hudrow's UnitAlive. One dword compare.
//   3. player (CUnit+0x4C) unchanged -- the record says whose unit this was; a
//      mind-controlled unit relinks under a new owner and is no longer part of the
//      player's selection. (The engine would refuse it anyway -- 0x0049AF80 tests
//      `unit->playerId == ACTIVE_NATION_ID` for slot > 0 -- so this term is about
//      not emitting a tag we know is wrong, not about safety.) One byte compare.
//   4. sprite (CUnit+0x0C) != NULL -- the exact pointer 0x0049AF80 dereferences
//      without checking. Refusing a unit that has none costs one compare and cannot
//      cost a live unit: the unit (re)init 0x004A0320 gives every unit in play a
//      sprite.
//   5. reachable in playerUnitList[player] -- catches REMOVAL FROM PLAY by ANY path,
//      with no per-path detector: trigger RemoveUnit, archon-consumed, and the tail
//      of a death once 0x004A0740 has actually unlinked the unit. Terms 2 and 5
//      cover the two halves of a death between them -- HP goes to 0 first, while the
//      unit is still linked and playing its death animation; the unlink follows.
//
// WHY THE LIST WALK IS HERE AND NOT ONLY IN sc_hudrow.
//
// task 017 deliberately kept the walk OUT of its per-frame UnitAlive and used it only
// in the click gate (hud-selection-row.md 6.1), because the row had two structural
// backstops for every other removal path: a divergence latch that hands the row back
// to stock when the engine's own visible selection stops matching, and the click gate
// itself -- and it re-runs the check every frame, where a list walk per displayed unit
// per frame is a real cost.
//
// THE COMMAND PATH HAS NEITHER BACKSTOP. There is no per-frame comparison against the
// engine's selection, and there is no gate between the shadow list and the wire: what
// EmitSelect writes goes to the receive path. An archon merge or a trigger RemoveUnit
// leaves hitpoints and CUnit+0xA5 both untouched, so terms 1-4 would all pass and the
// tag would go out. The walk is what makes the gate complete rather than
// death-shaped, and the cost argument runs the other way too: this runs ONCE PER
// FANNED ORDER over at most ~250 units, not once per frame -- roughly the work of one
// frame's worth of the row's own per-unit reads, on a path the player triggers by
// hand. It is bounded by SC_MAX_UNITS_WALK and validates every link before following
// it, so a corrupt list fails closed instead of hanging or faulting.
//
// %SCPLUGIN_FANOUT_LIVENESS%=0 restores the pre-task-020 behaviour (term 1 alone).
// It exists so the same build can reproduce the defect on demand -- which is how the
// in-game regression assertion is shown to be capable of failing, and how the
// pre-fix receive-side behaviour was observed at all (research/fanout-liveness.md 4).
// ---------------------------------------------------------------------------

enum ScDropWhy {
    SC_LIVE_OK = 0,
    SC_DROP_RECYCLED,     // CUnit+0xA5 moved: the slot is a different unit now
    SC_DROP_DEAD,         // hitpoints == 0
    SC_DROP_FOREIGN,      // CUnit+0x4C changed: no longer this player's unit
    SC_DROP_NOSPRITE,     // CUnit+0x0C == 0: nothing for the receive path to deref
    SC_DROP_REMOVED,      // not reachable from playerUnitList[player]
    SC_DROP_NOTAG         // the pointer does not encode to a wire tag
};

// The header publishes the same set for hooktest to assert on; the two must agree
// numerically, and a mismatch would silently turn a "dropped for the right reason"
// assertion into a coincidence.
static_assert((int)SC_DROP_RECYCLED == (int)SC_FANOUT_RECYCLED, "drop reason drift");
static_assert((int)SC_DROP_DEAD     == (int)SC_FANOUT_DEAD,     "drop reason drift");
static_assert((int)SC_DROP_FOREIGN  == (int)SC_FANOUT_FOREIGN,  "drop reason drift");
static_assert((int)SC_DROP_NOSPRITE == (int)SC_FANOUT_NOSPRITE, "drop reason drift");
static_assert((int)SC_DROP_REMOVED  == (int)SC_FANOUT_REMOVED,  "drop reason drift");
static_assert((int)SC_DROP_NOTAG    == (int)SC_FANOUT_NOTAG,    "drop reason drift");

static const char* DropWhyName(int why) {
    switch (why) {
        case SC_LIVE_OK:        return "live";
        case SC_DROP_RECYCLED:  return "recycled";
        case SC_DROP_DEAD:      return "hp0";
        case SC_DROP_FOREIGN:   return "foreign";
        case SC_DROP_NOSPRITE:  return "nosprite";
        case SC_DROP_REMOVED:   return "removed";
        case SC_DROP_NOTAG:     return "notag";
    }
    return "?";
}

// Term 1 alone: the engine's own stale-tag test, and the whole of what this module
// checked before task 020. Kept as its own function because it is still reported --
// `uniqOnly=` in the UNITSTATE line is what a test compares against `live=` to show
// the added terms firing.
static bool SameUnit(const ShadowUnit* u) {
    if (!u->ptr) return false;
    return *(BYTE*)(u->ptr + SC_CUNIT_OFF_UNIQUENESS) == u->uniqueness;
}

// Is `unit` reachable from its owning player's unit list? A unit in play is
// head-inserted into playerUnitList[player] (0x006283F8) by the unit (re)init
// 0x004A0320 and threaded through CUnit+0x6C; the removal path 0x004A0740 UNLINKS a
// unit removed from play (sc_addresses.h, hud-selection-row.md 6.1). Every link is
// bounds/stride-validated before it is followed, and the walk is bounded, so a torn
// or corrupt list fails closed rather than faulting or hanging.
static bool InPlayerUnitList(DWORD unit) {
    if (!unit) return false;
    BYTE player = *(BYTE*)(unit + SC_CUNIT_OFF_PLAYER);
    if (player >= SC_MAX_PLAYERS) return false;
    DWORD u = ((DWORD*)Rt(SC_VA_PLAYER_UNIT_LIST))[player];
    for (int guard = 0; u && guard < SC_MAX_UNITS_WALK; ++guard) {
        if (!UnitPtrValid(u)) return false;
        if (u == unit) return true;
        u = *(DWORD*)(u + SC_CUNIT_OFF_LIST_NEXT);
    }
    return false;
}

// ---------------------------------------------------------------------------
// SAME-TYPE BUILDING GROUPS (task 024)
//
// Vanilla selects ONE building per drag box, and the reason is a single predicate --
// unit_IsStandardAndMovable (0x0047B770) -- consulted on both sides of the selection
// path. sc_addresses.h quotes both call sites with their instruction addresses; the
// short version is:
//
//   client  SortAllUnits drops every candidate that fails the predicate, then, if
//           that emptied the list, substitutes the LAST one it dropped and returns 1.
//   sim     addUnitToSelectionSlot refuses any slot > 0 to a unit that fails it, so
//           playersSelections[player] -- the array every order applier iterates --
//           can hold exactly one building no matter what arrives on the wire.
//
// This module relaxes the CLIENT gate (see ScFanoutGrowBuildingGroup) and leaves the
// SIM gate alone: its first five bytes contain a short JZ and ScHookInstall copies
// prologue bytes verbatim with no relocation, so a detour there would corrupt the
// trampoline. Instead the sim gate becomes a NUMBER -- how many of the current
// selection the simulation will hold at once -- and the fan-out already knows how to
// deliver an order to more units than the sim can hold: it chunks. For units that
// number is 12 and nothing changes; for a building group it is 1, so a rally to six
// Supply Depots goes out as six Select(1)+RightClick pairs.
// ---------------------------------------------------------------------------

// The engine's own predicate, called (never patched). Test builds point it at a stub
// instead: in hooktest every static VA resolves into a fake image with no code in it.
typedef int (__attribute__((fastcall)) *ScMovableFn)(DWORD unit);
static ScMovableFn g_movableFn = NULL;   // NULL -> call the engine
static bool        g_buildingGroups = true;   // %SCPLUGIN_BUILDING_GROUPS%

// The test default (see ScFanoutTestBegin): no engine code exists at 0x0047B770 in a
// test process, so a test that has not said otherwise gets the pre-task-024 answer.
static int __attribute__((fastcall)) ScTestAllMovable(DWORD unit) { (void)unit; return 1; }

// Task 036 installs a detour on 0x0047B770 (see the EXTENDING A BUILDING GROUP block
// below), and this is its trampoline. Everything in this plugin asks the ENGINE'S OWN
// answer through it, never the detoured entry point: the detour exists to change what
// four named instruction addresses in the GAME see, and letting our own reasoning read
// the changed answer would make the override argue with itself (its very first act is to
// ask this question about the selection's lead).
extern "C" void* g_scMovableTrampoline;

static bool UnitIsStandardAndMovable(DWORD unit) {
    if (!unit) return false;
    ScMovableFn f = g_movableFn ? g_movableFn
                  : g_scMovableTrampoline ? (ScMovableFn)g_scMovableTrampoline
                                          : (ScMovableFn)Rt(SC_VA_UNIT_IS_STANDARD_AND_MOVABLE);
    return f(unit) != 0;
}

// How many units of the CURRENT selection the simulation will hold at once, i.e. the
// fan-out's chunk size. 12 normally; 1 when the selection is made of units the sim
// gate refuses a second slot to. Recomputed at every selection commit, never guessed.
static int g_simSlots = SC_SELECTION_SLOTS;

// units.dat prototype flags for a type, read only so a log line can say WHICH bit the
// gate objected to. Returns 0 for a type id outside the table's addressable range.
static DWORD UnitsDatFlags(WORD unitType) {
    return ((DWORD*)Rt(SC_VA_UNITS_DAT_FLAGS))[unitType];
}

// "Is this unit a BUILDING?" -- the units.dat prototype flag, bit 0x01, which is the
// FIRST term unit_IsStandardAndMovable tests (`TEST DL,0x1 / JNZ` at 0x0047B77E).
//
// Task 036 asks this in addition to the predicate wherever it widens a behaviour, and
// the two are NOT the same question: the predicate also fails for a "single entity"
// type, for four PER-UNIT fields (CUnit+0xDC bit 0x400, +0x117, +0x119, +0x124) and for
// a list of ids -- so an ordinary UNIT can fail it too, transiently, and a feature named
// "building groups" has no business widening anything for those. The conductor's review
// asked for exactly this narrowing: the sim gate exists for units as well, and its
// refusing must not be read as "this is a building group".
static bool UnitIsBuilding(DWORD unit) {
    if (!unit) return false;
    return (UnitsDatFlags(*(WORD*)(unit + SC_CUNIT_OFF_UNIT_ID))
            & SC_UNITSDAT_FLAG_BUILDING) != 0;
}

// Recompute the chunk size from the selection the engine just committed.
//
// The FIRST visible unit decides it, and that is not a shortcut: the sim gate lets slot
// 0 hold anything and refuses a non-movable unit every later slot, so whether a second
// unit of this kind can ever join is a property of the kind, and every unit of a
// same-type group answers identically. An empty selection resets to the default rather
// than keeping a building group's 1 -- a stale 1 would make the next 12-unit selection
// fan out one unit at a time.
//
// Deliberately NOT gated on %SCPLUGIN_BUILDING_GROUPS%: this number is a fact about the
// ENGINE (addUnitToSelectionSlot really does refuse a building every slot but the
// first), not about our feature, and reporting it honestly in the off arm is what lets
// that arm assert the vanilla shape rather than our absence. With the feature off the
// shadow list never holds more than one building, so `shadowCount > simSlots` is false
// and nothing is fanned out.
static void UpdateSimSlots(const ShadowUnit* visible, int visibleCount) {
    if (visibleCount <= 0 || !visible[0].ptr) {
        g_simSlots = SC_SELECTION_SLOTS;
        return;
    }
    g_simSlots = UnitIsStandardAndMovable(visible[0].ptr) ? SC_SELECTION_SLOTS : 1;
}

static bool g_liveness = true;    // %SCPLUGIN_FANOUT_LIVENESS%

// The full test. `why` (optional) gets the first term that failed, so a log line can
// say WHICH removal this was rather than just "stale". This function does NOT consult
// the %SCPLUGIN_FANOUT_LIVENESS% switch: the verdict is always computed, so a run with
// the gate turned off still REPORTS what it is about to do (see PassesGate).
static bool UnitLive(const ShadowUnit* u, int* why) {
    int w = SC_LIVE_OK;
    if (!u->ptr) w = SC_DROP_NOTAG;
    else if (*(BYTE*)(u->ptr + SC_CUNIT_OFF_UNIQUENESS) != u->uniqueness) w = SC_DROP_RECYCLED;
    else if (*(DWORD*)(u->ptr + SC_CUNIT_OFF_HITPOINTS) == 0) w = SC_DROP_DEAD;
    else if (*(BYTE*)(u->ptr + SC_CUNIT_OFF_PLAYER) != u->player) w = SC_DROP_FOREIGN;
    else if (*(DWORD*)(u->ptr + SC_CUNIT_OFF_SPRITE) == 0) w = SC_DROP_NOSPRITE;
    else if (!InPlayerUnitList(u->ptr)) w = SC_DROP_REMOVED;
    if (why) *why = w;
    return w == SC_LIVE_OK;
}

// What actually DECIDES. Normally the full test; with the gate switched off, the
// pre-task-020 test (uniqueness alone). Split from UnitLive on purpose: the defect
// arm of an A/B run must still be able to say "the unit I am about to replay is dead
// and here is its sprite pointer", which is the whole of the measurement in
// research/fanout-liveness.md 4.
// `why` always carries the TRUE verdict, even when the pre-020 gate is about to let
// the unit through anyway -- that is the whole point of the split, and clobbering it
// with SC_LIVE_OK on the allowed path is what an earlier version of this function did,
// which silently cost the defect arm its measurement.
static bool PassesGate(const ShadowUnit* u, int* why) {
    const bool live = UnitLive(u, why);
    if (g_liveness) return live;
    if (SameUnit(u)) return true;
    if (why) *why = SC_DROP_RECYCLED;
    return false;
}

// ONE forensics line per unit per selection, not per unit per ORDER.
//
// The shadow list deliberately keeps corpses until the next selection commit, so the
// same dead unit is re-judged by every fanned order until the player re-selects. Left
// unguarded, each of those re-judgements wrote a line -- and ScLog flushes the file
// handle synchronously, on the game thread, under our lock. After a real battle that
// is a growing pile of identical lines on every right-click, in the SHIPPED default.
//
// Keyed on the shadow VERSION, which sc_fanout already bumps on every commit (and on
// the hotkey-recall drop), so a genuinely new selection reports afresh. The list is
// small and linear-scanned: it only ever holds units that failed the gate, and a
// selection with hundreds of those has bigger problems than a log line.
//
// CONSEQUENCE FOR THE COUNTERS, stated because it is easy to misread: g_statStale and
// g_statDrop still count drop EVENTS (every order, every unit), not distinct units.
// They are throughput counters, not a population. `staleSkipped` is therefore also
// sticky for the session -- once anything has been dropped it never returns to 0.
static DWORD    g_loggedPtr[64];
static int      g_loggedCount = 0;
static unsigned g_loggedVersion = 0;
static bool     g_loggedValid = false;

static bool ShouldLogForensics(DWORD unit) {
    if (!g_loggedValid || g_loggedVersion != g_shadowVersion) {
        g_loggedVersion = g_shadowVersion;
        g_loggedCount = 0;
        g_loggedValid = true;
    }
    for (int i = 0; i < g_loggedCount; ++i) if (g_loggedPtr[i] == unit) return false;
    // Full table: report it. Repeating beats silently dropping evidence, and the only
    // way to get here is a selection with 64+ distinct failing units.
    if (g_loggedCount < (int)(sizeof(g_loggedPtr) / sizeof(g_loggedPtr[0]))) {
        g_loggedPtr[g_loggedCount++] = unit;
    }
    return true;
}

// The fields the engine's receive path would use for this unit, logged as one line.
// The sprite pointer and its flag byte are what addUnitToSelectionSlot 0x0049AF80
// dereferences; the flags are read only after VirtualQuery says the page is committed
// and readable, so reporting on a freed sprite cannot itself fault. `-1` for the flags
// means "the pointer is not readable memory" -- which is itself the answer.
static void LogUnitForensics(const char* what, const ShadowUnit* u, int why) {
    if (!ShouldLogForensics(u->ptr)) return;
    DWORD sprite = u->ptr ? *(DWORD*)(u->ptr + SC_CUNIT_OFF_SPRITE) : 0;
    int   sflags = -1;
    if (sprite) {
        MEMORY_BASIC_INFORMATION mbi;
        if (VirtualQuery((LPCVOID)(sprite + SC_CSPRITE_OFF_FLAGS), &mbi, sizeof(mbi))
                == sizeof(mbi) && mbi.State == MEM_COMMIT &&
            !(mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD))) {
            sflags = *(BYTE*)(sprite + SC_CSPRITE_OFF_FLAGS);
        }
    }
    ScLog("%s: unit=0x%08X tag=%04X why=%s hp=%u uniq=%u/%u player=%u/%u "
          "sprite=0x%08X spriteFlags=%d inList=%d",
          what, (unsigned)u->ptr, UnitTag(u->ptr), DropWhyName(why),
          u->ptr ? *(unsigned*)(u->ptr + SC_CUNIT_OFF_HITPOINTS) : 0,
          u->ptr ? *(BYTE*)(u->ptr + SC_CUNIT_OFF_UNIQUENESS) : 0, u->uniqueness,
          u->ptr ? *(BYTE*)(u->ptr + SC_CUNIT_OFF_PLAYER) : 0, u->player,
          (unsigned)sprite, sflags, (u->ptr && InPlayerUnitList(u->ptr)) ? 1 : 0);
}

// ---------------------------------------------------------------------------
// Hook plumbing
// ---------------------------------------------------------------------------

static ScHook g_hkQueue;
static ScHook g_hkSelect;
static ScHook g_hkSort;
static ScHook g_hkOverflow;

typedef void     (__attribute__((stdcall)) *CmdactSelectFn)(unsigned, DWORD*);
typedef unsigned (__attribute__((stdcall)) *SortAllUnitsFn)(DWORD*, DWORD*, DWORD);

// Where emitted commands go: the queueCommand trampoline in the game, a capture
// buffer under test. Never the hooked entry point -- that would re-enter our detour.
static ScQueueFn g_emit = NULL;

// Verified prologues -- ScHookInstall refuses to patch if memory disagrees.
// Bytes taken from work/scratch/hookprobe/*.asm (Ghidra, this binary); the
// disassembly for each is quoted in research/command-path.md.
static const BYTE kPrologueQueue[]    = { 0x55, 0x8B, 0xEC, 0x51, 0xA1, 0xA0, 0x4A, 0x65, 0x00 };
static const BYTE kPrologueSelect[]   = { 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x5C };
static const BYTE kPrologueSort[]     = { 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x08 };
static const BYTE kPrologueOverflow[] = { 0x55, 0x8B, 0xEC, 0x53, 0x56 };

// ---------------------------------------------------------------------------
// Statistics, so one user-run answers "did it work and how"
// ---------------------------------------------------------------------------

static unsigned g_statCommands   = 0;
static unsigned g_statSelects    = 0;
static unsigned g_statOverflow   = 0;
static unsigned g_statFanouts    = 0;
static unsigned g_statPairs      = 0;
static unsigned g_statDeferred   = 0;
static unsigned g_statStale      = 0;   // units DROPPED from an emitted Select, all reasons
// The same total, split by which term rejected the unit. `hp0` is the task-020
// case -- a unit killed by damage whose slot has not been recycled, which term 1
// alone (uniqueness) cannot see.
static unsigned g_statDrop[SC_DROP_NOTAG + 1] = { 0 };
// Task 024, counted SEPARATELY from g_statDrop on purpose. These units were refused a
// place in a building GROUP at selection time -- they never reached a plan, so folding
// them into the emit-side counters would change what "dropped from an emitted Select"
// means for every test that already asserts on it.
static unsigned g_statBGroupRefused[SC_DROP_NOTAG + 1] = { 0 };
// Task 036: the predicate override at the four extend sites. `seen` counts calls that
// arrived at one of those sites with a BUILDING lead -- i.e. the cases vanilla was about
// to refuse outright -- and the other two count what this plugin answered instead. Kept
// apart from every other counter because they describe a decision, not a drop.
static unsigned g_statExtendSeen    = 0;
static unsigned g_statExtendAllow   = 0;
static unsigned g_statExtendRefuse  = 0;

// ---------------------------------------------------------------------------
// The deferred plan
//
// A fan-out that does not fit the per-turn byte budget is finished on the next
// command the player issues. selection-cap.md 6.2 sizes this: a 100-unit intent is
// ~350 bytes and does not fit a 255-byte replay frame block, so the pairs have to
// spill across frames. For a 36-unit selection (3 pairs, ~141 bytes) nothing ever
// defers.
// ---------------------------------------------------------------------------

struct Plan {
    bool       active;
    BYTE       order[SC_MAX_ORDER_BYTES];
    int        orderLen;
    ShadowUnit units[SC_SHADOW_MAX];
    int        count;
    int        visibleCount;
    int        slots;        // how many the sim holds at once == this plan's chunk size
    int        chunkCount;
    int        nextChunk;
};

static Plan g_plan;

// Chunk `chunk` of the plan: overflow units first, the engine's VISIBLE units last, so
// the simulation is left holding what the player can see.
//
// `slots` is the only thing that changed for task 024, and it changed from a constant
// into a field. With slots == 12 this is byte-for-byte the previous behaviour: the
// visible part is at most 12 units, so it is exactly one trailing chunk. With slots ==
// 1 (a building group, which the sim will not hold two of) BOTH regions split one unit
// per chunk, which is what makes a rally reach every building.
static int ChunkBounds(const Plan* p, int chunk, int* start, int* len) {
    const int slots = p->slots > 0 ? p->slots : SC_SELECTION_SLOTS;
    const int overflow = p->count - p->visibleCount;
    const int overflowChunks = (overflow + slots - 1) / slots;
    if (chunk < overflowChunks) {
        *start = chunk * slots;
        int remain = overflow - *start;
        *len = remain < slots ? remain : slots;
        return 1;
    }
    const int visibleChunks = (p->visibleCount + slots - 1) / slots;
    if (chunk < overflowChunks + visibleChunks) {
        // The visible chunks are walked BACKWARDS, so the very last Select this plan
        // emits carries the FIRST visible unit -- the one the engine itself put in slot
        // 0, and the one its own Select would have left the simulation holding.
        // With slots == 12 there is exactly one visible chunk and this is a no-op; it
        // only bites when the sim holds fewer than the player can see, i.e. a building
        // group, where "leave the simulation holding what the player can see" has to
        // become "leave it holding the one the engine chose".
        const int i = visibleChunks - 1 - (chunk - overflowChunks);
        *start = overflow + i * slots;
        int remain = p->visibleCount - i * slots;
        *len = remain < slots ? remain : slots;
        return 1;
    }
    return 0;
}

static int PlanChunkCount(int count, int visibleCount, int slots) {
    if (slots <= 0) slots = SC_SELECTION_SLOTS;
    const int overflow = count - visibleCount;
    return (overflow + slots - 1) / slots + (visibleCount + slots - 1) / slots;
}

// Queues one vanilla Select (0x09) for the given units. Returns bytes queued, or 0
// if nothing survived the liveness gate.
//
// THIS IS THE GATE. Every tag this module ever puts on the wire is written here, so
// a unit that fails UnitLive is a unit the engine's receive path never sees -- which
// is the whole of the task-020 fix. The dropped ones are logged individually, with
// the fields the receive path would have used, because "which unit, and why" is the
// evidence an in-game run needs and a counter alone cannot give.
static int EmitSelect(const ShadowUnit* units, int n) {
    BYTE buf[2 + SC_SELECTION_SLOTS * 2];
    char tagText[SC_SELECTION_SLOTS * 5 + 4];
    int  live = 0, dropped = 0, used = 0;
    tagText[0] = '\0';
    for (int i = 0; i < n && live < SC_SELECTION_SLOTS; ++i) {
        int why = SC_LIVE_OK;
        WORD tag = 0;
        bool allow = PassesGate(&units[i], &why);
        if (allow) {
            tag = UnitTag(units[i].ptr);
            if (!tag) { allow = false; why = SC_DROP_NOTAG; }
        }
        if (!allow) {
            ++g_statStale;
            ++g_statDrop[why];
            ++dropped;
            LogUnitForensics("FANOUT stale drop", &units[i], why);
            continue;
        }
        if (why != SC_LIVE_OK) {
            // Only reachable with %SCPLUGIN_FANOUT_LIVENESS%=0: the pre-task-020 gate
            // is about to put a unit the full test rejects on the wire. Logged as
            // loudly as it deserves, with the pointer the receive path is about to
            // follow -- this line IS the defect-arm measurement.
            LogUnitForensics("FANOUT REPLAYING A STALE UNIT (gate off)", &units[i], why);
        }
        buf[2 + live * 2]     = (BYTE)(tag & 0xFF);
        buf[2 + live * 2 + 1] = (BYTE)(tag >> 8);
        used += _snprintf(tagText + used, sizeof(tagText) - used, "%s%04X",
                          live ? " " : "", tag);
        ++live;
    }
    // Logged even when nothing was dropped: this line is the wire-level read-back an
    // in-game test asserts on ("the dead unit's tag is in no emitted Select"), and a
    // line that only appeared on the interesting runs could not carry that claim.
    ScLog("FANOUT select: in=%d out=%d dropped=%d tags=[%s]", n, live, dropped, tagText);
    if (live == 0) return 0;
    buf[0] = SC_CMD_SELECT;
    buf[1] = (BYTE)live;
    const int len = 2 + live * 2;
    if (g_emit) g_emit(buf, (unsigned)len);
    return len;
}

static void EmitRaw(const BYTE* buf, int len) {
    if (g_emit) g_emit(buf, (unsigned)len);
}

// Emits as many of the plan's remaining chunks as the budget allows.
// Returns how many Select+order pairs actually went out.
static int DrainPlan(void) {
    if (!g_plan.active) return 0;

    // How much room is left in the engine's own turn buffer this turn? queueCommand
    // silently DROPS a command on two of its overflow paths, so never push past it.
    DWORD inQueue = *(DWORD*)Rt(SC_VA_BYTES_IN_CMD_QUEUE);
    DWORD maxQueue = *(DWORD*)Rt(SC_VA_MAX_CMD_QUEUE_BYTES);
    int   room = (int)maxQueue - (int)inQueue - 8;   // 8B margin for the engine
    int   budget = g_budget < room ? g_budget : room;

    int spent = 0;
    int pairs = 0;
    while (g_plan.nextChunk < g_plan.chunkCount) {
        int start = 0, len = 0;
        if (!ChunkBounds(&g_plan, g_plan.nextChunk, &start, &len)) break;
        if (len <= 0) { ++g_plan.nextChunk; continue; }

        const int cost = (2 + len * 2) + g_plan.orderLen;
        if (spent + cost > budget) break;

        int wrote = EmitSelect(&g_plan.units[start], len);
        if (wrote > 0) {
            EmitRaw(g_plan.order, g_plan.orderLen);
            spent += wrote + g_plan.orderLen;
            ++g_statPairs;
            ++pairs;
        }
        ++g_plan.nextChunk;
    }

    if (g_plan.nextChunk >= g_plan.chunkCount) {
        g_plan.active = false;
        ScLog("FANOUT done: %d/%d chunks emitted, %d bytes this turn",
              g_plan.chunkCount, g_plan.chunkCount, spent);
    } else {
        ++g_statDeferred;
        ScLog("FANOUT defer: %d/%d chunks emitted (%d bytes, budget %d) -- the rest "
              "go out with the next command", g_plan.nextChunk, g_plan.chunkCount,
              spent, budget);
    }
    return pairs;
}

// Returns false if NOT ONE pair went out -- the caller must then let the engine's
// own command through instead of suppressing it. Without this, a turn buffer that
// is already nearly full (negative budget) or a selection whose units all died
// would turn a suppressed order into an order that reaches nobody: the player's
// click would do nothing at all, which is worse than fanning out badly.
static bool StartFanout(const BYTE* order, int orderLen) {
    if (g_plan.active) {
        ScLog("FANOUT: a previous plan was still pending (%d/%d chunks) -- dropping it",
              g_plan.nextChunk, g_plan.chunkCount);
    }
    memset(&g_plan, 0, sizeof(g_plan));
    memcpy(g_plan.order, order, (size_t)orderLen);
    g_plan.orderLen     = orderLen;
    memcpy(g_plan.units, g_shadow, sizeof(ShadowUnit) * (size_t)g_shadowCount);
    g_plan.count        = g_shadowCount;
    g_plan.visibleCount = g_visibleCount;
    g_plan.slots        = g_simSlots;

    const int overflow = g_plan.count - g_plan.visibleCount;
    g_plan.chunkCount = PlanChunkCount(g_plan.count, g_plan.visibleCount, g_plan.slots);
    g_plan.nextChunk  = 0;
    g_plan.active     = true;
    ++g_statFanouts;

    ScLog("FANOUT start: cmd=0x%02X len=%d units=%d (visible %d + overflow %d) "
          "slots=%d -> %d Select+order pairs",
          order[0], orderLen, g_plan.count, g_plan.visibleCount, overflow,
          g_plan.slots, g_plan.chunkCount);

    if (DrainPlan() > 0) return true;

    ScLog("FANOUT abandoned: no pair could be emitted (turn buffer full, or every "
          "captured unit is stale) -- letting the engine's own command through");
    g_plan.active = false;
    return false;
}

// ---------------------------------------------------------------------------
// SHADOW CONTROL GROUPS (task 021)
//
// THE PROBLEM. Ctrl+1 on a 24-unit selection stored 12, and 1 brought 12 back --
// and the pre-021 plugin made that worse rather than better: seeing command 0x13 it
// DROPPED the shadow list outright (the `SHADOW dropped: hotkey command 0x13` line
// this block replaces), because a recall rebuilds the selection without ever calling
// CMDACT_Select, so the list would otherwise have gone stale. Correct, and it left
// the player with 12.
//
// WHAT THE ENGINE ACTUALLY DOES, read out of this binary by task 021 and written up
// with the disassembly in research/control-groups.md:
//
//   storage   selectionHotkeys 0x0057FE60, [8][18][12] u32 StoredUnit tags
//             ((uniqueness << 11) | unitIndex). Groups 0..9 are Ctrl+N; 10..17 are
//             the engine's own alt-click recent-selection ring. Exactly SEVEN
//             functions touch it and NONE of them is on the save/load path, so
//             vanilla control groups are memory-only too.
//   command   0x13 is 3 bytes, built at 0x004C07BF:
//                 [0] = 0x13   [1] = action   [2] = group
//             action 0 = ASSIGN (clear the group, then fill), 1 = RECALL,
//             2 = ADD (append at the first free slot). The key dispatcher
//             0x004846E0 carries three families of ten sites, one family per action.
//   capacity  12, twice over: the store loop at 0x004965D0 returns once it has
//             written 12 tags, and its source playersSelections[player] is 12 slots.
//
// THE SEAM. Both halves land in the queueCommand hook we already have, because the
// client does its own work BEFORE it queues the command:
//
//   store   (13 00 g / 13 02 g)  the key dispatcher queues these inline and changes
//           no selection state, so the shadow list is still the player's current
//           selection at that instant. Snapshot (assign) or union (add) it.
//   recall  (13 01 g)            the client handler 0x00496B40 calls
//           CreateNewUnitSelectionsFromList (0x0049AE40) FIRST -- that is what fills
//           activePlayerSelection (0x006284B8) with the engine's new <=12 -- and only
//           then calls CMDACT_HotkeyUnit, whose first act is queueCommand. So by the
//           time we see the command, the engine's post-recall visible list is sitting
//           in activePlayerSelection, and we rebuild the shadow list around it.
//
// So this feature adds NO hook and patches NO new byte of the game.
//
// WHERE UNITS 13..N LIVE: here, in plugin memory, as the same
// (CUnit*, CUnit+0xA5, CUnit+0x4C) triple the shadow list already uses. They are
// never written into selectionHotkeys, playersSelections or activePlayerSelection.
// That is what keeps this clear of the selectionIndex hazard: all four readers of
// CSprite+0x0B are gated on sprite flag 0x08, the engine sets 0x08 itself inside
// 0x004E6180 for exactly the units it puts in activePlayerSelection, and units
// 13..N are never in that array (research/selection-circles.md 4).
//
// STALENESS, and why it is safe rather than merely unlikely. These groups are
// memory-only, so a save/load can leave them describing a previous game. Two
// independent gates, neither of them a probability argument:
//
//   1. every entry is re-run through task 020's five-term liveness gate at recall
//      (PassesGate) -- reused, not reinvented, so a dead or removed unit is dropped;
//   2. CONTAINMENT: the engine's own post-recall list must be a subset of the plugin
//      group. Store and add maintain that by construction (we store a superset of
//      what the engine stores, and the engine's recall can only ever drop entries),
//      so a violation MEANS the group is stale or foreign -- we discard it and fall
//      back to pre-021 behaviour (shadow = the engine's 12) rather than guessing.
//      After a load the engine's own group is either empty -- in which case
//      0x00496B40 returns before queueing anything and this path never runs at all --
//      or holds units of the loaded game, which cannot be contained in a group
//      recorded in a different session.
// ---------------------------------------------------------------------------

#define SC_HOTKEY_GROUPS 10   // the Ctrl+N groups. 10..17 are the engine's own
                              // recent-selection ring and are not ours to mirror.

// SC_HOTKEY_ASSIGN / _RECALL / _ADD are in sc_addresses.h with the disassembly of the
// dispatch they come from -- they are facts about the binary, not choices made here.

struct ShadowGroup {
    ShadowUnit units[SC_SHADOW_MAX];
    int        count;
    bool       stored;   // false = we have never recorded this group in this session
};

static ShadowGroup g_group[SC_HOTKEY_GROUPS];

static unsigned g_statGroupAssign  = 0;
static unsigned g_statGroupAdd     = 0;
static unsigned g_statGroupRecall  = 0;
static unsigned g_statGroupWide    = 0;   // recalls that put MORE than 12 back
static unsigned g_statGroupDiscard = 0;   // recalls that failed the containment check
static unsigned g_statGroupReset   = 0;   // groups dropped because the engine restarted
// Task 054: how many times the epoch test below actually threw something away. Counted
// apart from RESET, which is the pre-existing INFERENCE ("the engine's row for this
// group is empty, so a new game must have cleared it") -- an inference that a save/load
// defeats outright, because the load restores a NON-EMPTY row holding the same pointers.
static unsigned g_statSessionDrop  = 0;

// ---------------------------------------------------------------------------
// THE EPOCH TEST (sc_session.h) -- issue #67 items 2, 3, 4 and 5 in one place
//
// Which GAME everything in this file's cross-frame state belongs to: the shadow list,
// the overflow accumulator, the deferred plan and the ten control groups. 0 = never
// synced; real epochs start at 1.
//
// Why each of the four needs it, and why none of the existing defences reaches them:
//
//  * g_plan -- a fan-out deferred for the turn-buffer budget keeps RAW ORDER BYTES and
//    captured unit records, and nothing bounded the drain to the same game. The first
//    command after a load would replay the previous game's order.
//  * g_shadow / g_accum -- cleared only on the next selection COMMIT, so between a load
//    and the player's first click they are the previous game's units.
//  * g_shadowVersion -- see the bump at the end of this function.
//  * g_group[10] -- ResetGroupIfEngineRowEmpty and the containment check are inferences
//    from the ENGINE's state, and a save/load restores a non-empty hotkey row holding
//    the same CUnit*s. Containment therefore PASSES on exactly the input it exists to
//    catch, and a pre-save group of >12 is re-injected into the loaded game.
// ---------------------------------------------------------------------------
static unsigned g_session = 0;

static void FanoutSessionSync(void) {
    const unsigned now = ScSessionEpoch();
    if (g_session == now) return;

    int groups = 0;
    for (int i = 0; i < SC_HOTKEY_GROUPS; ++i) if (g_group[i].stored) ++groups;
    const int  shadow = g_shadowCount;
    const int  accum  = g_accumCount;
    const bool plan   = g_plan.active;
    if (groups || shadow || accum || plan) {
        ScLog("SHADOW session %u -> %u: dropping %d shadow unit(s), %d accumulated, "
              "%d stored control group(s)%s -- every one of them describes a game that "
              "has ended",
              g_session, now, shadow, accum, groups,
              plan ? " and a deferred fan-out plan (its raw order bytes with it)" : "");
        ++g_statSessionDrop;
    }

    g_shadowCount  = 0;
    g_visibleCount = 0;
    g_accumCount   = 0;
    memset(&g_plan, 0, sizeof(g_plan));
    memset(g_group, 0, sizeof(g_group));

    // ISSUE #67 ITEM 4, and it is the subtle one. sc_hudrow's ONLY signal that the
    // selection changed is this counter, and a counter cannot express "a different
    // game": across a load it simply does not move, which the HUD row reads as "same
    // selection" and keeps the previous game's page and list until the first commit.
    //
    // A version number and an epoch are DIFFERENT THINGS and this line does not
    // conflate them -- the epoch is what decided a change happened, and the bump is
    // only how that decision is published to a consumer whose contract is "watch this
    // number". sc_hudrow separately runs its own epoch test, so the row is correct even
    // if it stops reading this counter altogether.
    ++g_shadowVersion;

    g_session = now;
}

// Is the engine's OWN row for this group holding anything? A direct read of
// selectionHotkeys[activePlayerId][group], 12 dwords.
//
// The player index is the one the STORE uses -- hotkeySaveOrAdd computes its row as
// `group + DAT_0051267C * 0x12` (0x004965DF..0x004965E9), i.e. SC_VA_ACTIVE_PLAYER_ID.
// binary-selection-map.md 7 note 7 warns that THREE player-id globals are in play in
// this subsystem and conflating them produces bugs, so this reads the one that indexes
// the array being read, and DisagreeingPlayerIds() below reports it if the three ever
// diverge rather than letting a wrong row pass silently.
static bool EngineGroupNonEmpty(int group) {
    const BYTE player = *(BYTE*)Rt(SC_VA_ACTIVE_PLAYER_ID);
    if (player >= SC_MAX_PLAYERS) return false;   // fail-closed, as everywhere here
    const DWORD* row = (const DWORD*)Rt(SC_VA_SELECTION_HOTKEYS)
                     + (size_t)(player * SC_HOTKEY_GROUPS_PER_PLAYER + group)
                       * SC_HOTKEY_SLOTS_PER_GROUP;
    for (int i = 0; i < SC_HOTKEY_SLOTS_PER_GROUP; ++i) if (row[i]) return true;
    return false;
}

static bool DisagreeingPlayerIds(void) {
    const BYTE a = *(BYTE*)Rt(SC_VA_ACTIVE_PLAYER_ID);
    const BYTE b = *(BYTE*)Rt(SC_VA_PLAYER_ID_512688);
    const BYTE c = *(BYTE*)Rt(SC_VA_PLAYER_ID_512678);
    return !(a == b && b == c);
}

// AN ADD INTO AN EMPTY ENGINE ROW IS AN ASSIGN. That one rule is the whole of the
// stale-group defence for the ADD path, and it is a MIRROR of the engine rather than a
// guess about the player.
//
// What it is for. 0x004EEC30 (and 0x004965A0) zero the WHOLE hotkey array at game start,
// so after starting a second mission in the same process our groups describe units that
// no longer exist while the engine's own are empty. RECALL is already safe -- an empty
// engine group makes the client handler 0x00496B40 return before it queues anything, so
// our recall path never runs at all, and a non-empty one is covered by the containment
// check. ADD is the exposed one: `13 02 g` into a group the player never re-assigned in
// the new game would union fresh units into the previous game's records, and every later
// containment check would then be maintained against a poisoned baseline.
//
// Why mirroring the engine is the right rule rather than a heuristic: hotkeySaveOrAdd's
// ADD branch (0x004965D0 with param 0) scans for the first FREE slot, so on an empty row
// it starts writing at index 0 -- an add into an empty group IS an assign, in the engine.
// Doing the same thing is therefore not a policy this plugin invented; it is the engine's
// own behaviour, applied to a bigger list.
//
// AN EARLIER VERSION OF THIS GOT IT WRONG and the review caught it, so the trap is
// written down here. It tried to be cleverer -- "the row is empty now AND I have
// previously observed it non-empty" -- to avoid resetting on the legitimate sequence
// `Ctrl+N` then shift-add before the assign has executed (the assign is queued, not
// applied, so the row is still legitimately zero). But the store is receive-side, so on a
// FIRST Ctrl+N the row is always still empty at that instant and the observation was
// never recorded: a group used exactly once was permanently immune to the reset, which is
// ordinary play, not a corner. The rule below has no memory to get wrong.
//
// WHAT IT COSTS, stated because it is a real behaviour difference and not nothing: if the
// player queues `Ctrl+N` and shift-add in the SAME turn AND changes the selection between
// them, the engine ends up with sel1 + sel2 while this plugin keeps only sel2. Nothing is
// corrupted -- the next recall's containment check sees the engine hand back units the
// group does not hold, discards the group and falls back to the engine's own twelve. It
// is a lost >12 group in a case that needs two hotkey commands inside one turn, not a
// wrong one.
static bool ResetGroupIfEngineRowEmpty(int group) {
    if (EngineGroupNonEmpty(group)) return false;
    if (!g_group[group].stored) return false;
    ScLog("GROUP reset: shift-add into group %d while the engine's own row for it is "
          "EMPTY -- either a new game cleared it under us (0x004EEC30) or it was never "
          "assigned. hotkeySaveOrAdd starts an add at slot 0 on an empty row, so this "
          "add becomes an assign here too, dropping the %d unit(s) held from before.",
          group, g_group[group].count);
    g_group[group].count  = 0;
    g_group[group].stored = false;
    ++g_statGroupReset;
    return true;
}

// The engine's own visible selection, as the recall left it. activePlayerSelection is
// written by CreateNewUnitSelectionsFromList (0x0049AE40), which fills it densely from
// slot 0 and whose own clear loop terminates on the first NULL -- so stopping at a NULL
// is the engine's own termination rule, not an assumption about the array.
static int ReadEngineVisible(ShadowUnit* out, int maxOut) {
    DWORD* arr = (DWORD*)Rt(SC_VA_ACTIVE_PLAYER_SELECTION);
    int n = 0;
    for (int i = 0; i < SC_SELECTION_SLOTS && n < maxOut; ++i) {
        if (!arr[i]) break;
        ShadowUnit u;
        if (!ReadUnit(arr[i], &u)) break;   // bounds/stride-validated, like every deref here
        out[n++] = u;
    }
    return n;
}

// Task 014's circles over the current overflow. Factored out of ScFanoutOnSelect
// because a recall has to do exactly the same thing at exactly the same point in the
// sequence: after the engine has finished attaching its own graphics for the new
// selection (0x0049AE40 has already run on both paths), and after our matching detach
// fired from that same function's pre-hook.
static void ShowOverflowCircles(void) {
    const int overflow = g_shadowCount - g_visibleCount;
    if (!ScCirclesEnabled() || overflow <= 0) return;
    ScCircleUnit circ[SC_SHADOW_MAX];
    int n = 0;
    for (int i = 0; i < overflow && n < SC_SHADOW_MAX; ++i) {
        circ[n].unit       = g_shadow[i].ptr;
        circ[n].sprite     = 0;      // filled in by ScCirclesShow
        circ[n].uniqueness = g_shadow[i].uniqueness;
        circ[n].player     = g_shadow[i].player;
        ++n;
    }
    ScCirclesShow(circ, n);
}

// CreateNewUnitSelectionsFromList (0x0049AE40) -- EAX = CUnit**, one stdcall argument
// (count), RET 4. No C calling convention describes that, so it goes through a two-line
// asm shim. It is the engine's own "replace the whole client selection" funnel: it
// detaches the selection graphics of everything currently in activePlayerSelection and
// attaches them to the list it is given, writing the (possibly subunit-substituted)
// result back into that same array -- so `list` must be the caller's own scratch.
//
// The count is a MEMORY operand and the function pointer a REGISTER one, deliberately:
// `pushl` reads its source before ESP moves, but the `calll` runs after, so an
// ESP-relative operand there would be four bytes off.
//
// g_createSelFn is the test seam. In a test process 0x0049AE40 is a fake image with no
// code in it, exactly as with the movable predicate.
typedef void (*ScCreateSelectionFn)(DWORD* list, int count);
static ScCreateSelectionFn g_createSelFn = NULL;

static void CallCreateNewUnitSelections(DWORD* list, int count) {
    if (g_createSelFn) { g_createSelFn(list, count); return; }
    void* fn = Rt(SC_VA_CREATE_NEW_UNIT_SELECTIONS);
    __asm__ __volatile__("pushl %[n]\n\t"
                         "calll *%[fn]"
                         : "+a"(list)
                         : [n] "m"(count), [fn] "r"(fn)
                         : "ecx", "edx", "cc", "memory");
}

// Ctrl+N / shift-add. `add` false = the engine's ASSIGN (replace), true = its ADD.
//
// Units are gated on the way IN as well as on the way out. The shadow list
// deliberately keeps corpses until the next selection commit (see ShouldLogForensics),
// and a group is a longer-lived thing than a selection -- there is no reason to record
// a unit we already know is dead.
static void GroupStore(int group, bool add) {
    if (group < 0 || group >= SC_HOTKEY_GROUPS) return;
    ShadowGroup* g = &g_group[group];

    // An ADD into an engine row that is empty is an ASSIGN -- the engine's own rule; see
    // ResetGroupIfEngineRowEmpty. Checked before `before` is read so the log line reports
    // what this command actually started from.
    if (add) ResetGroupIfEngineRowEmpty(group);

    if (!add || !g->stored) { g->count = 0; }
    const int before = g->count;

    int skipped = 0;
    for (int i = 0; i < g_shadowCount && g->count < g_maxUnits; ++i) {
        if (!PassesGate(&g_shadow[i], NULL)) { ++skipped; continue; }
        if (ShadowContainsUnit(g->units, g->count, &g_shadow[i])) continue;
        g->units[g->count++] = g_shadow[i];
    }
    g->stored = true;
    if (add) ++g_statGroupAdd; else ++g_statGroupAssign;

    ScLog("GROUP %s: group=%d now holds %d unit(s) (was %d, shadow had %d, %d skipped "
          "as not live) -- the engine stores at most %d of them",
          add ? "add" : "assign", group, g->count, before, g_shadowCount, skipped,
          SC_SELECTION_SLOTS);
}

// Press N. Called with the engine's client-side recall already done, so
// activePlayerSelection holds what the player is about to see.
static void GroupRecall(int group) {
    ++g_statGroupRecall;

    ShadowUnit visible[SC_SELECTION_SLOTS];
    const int visibleCount = ReadEngineVisible(visible, SC_SELECTION_SLOTS);

    // THE ORDERING CLAIM, LOGGED AS A RAW OBSERVATION -- the conductor's second
    // addition to the design, and the one thing here that is a claim about RUNTIME
    // rather than about code. The whole design rests on 0x00496B40 having already
    // called CreateNewUnitSelectionsFromList (0x0049AE40) by the time it queues
    // `13 01 g`, i.e. on activePlayerSelection ALREADY holding the post-recall units at
    // this instant. This line is what an unattended run reads back to check that: the
    // tags below must be the group's units, not the selection the player had a moment
    // ago. It is written unconditionally, including on the empty case, so a line that
    // says `visible=0` is evidence rather than an absence of evidence.
    {
        char tags[SC_SELECTION_SLOTS * 5 + 4];
        int used = 0;
        tags[0] = '\0';
        for (int i = 0; i < visibleCount; ++i) {
            used += _snprintf(tags + used, sizeof(tags) - used, "%s%04X",
                              i ? " " : "", UnitTag(visible[i].ptr));
        }
        ScLog("GROUP recall enter: group=%d activePlayerSelection holds visible=%d [%s] "
              "(read at queueCommand time, BEFORE anything of ours runs)",
              group, visibleCount, tags);
    }

    ShadowGroup* g = (group >= 0 && group < SC_HOTKEY_GROUPS) ? &g_group[group] : NULL;

    // CONTAINMENT (see this section's header): every unit the engine recalled must be
    // one this group recorded. Anything else means the group does not describe this
    // selection -- a different session after a load, or a group the engine holds and we
    // never saw stored -- and the only safe reading of it is none.
    bool contained = (g != NULL) && g->stored;
    int  foreign = 0;
    if (contained) {
        for (int i = 0; i < visibleCount; ++i) {
            // The PAIR, not the pointer: a record from a previous game whose slot now
            // holds a different live unit must read as foreign, which is the whole point
            // of this check (see ShadowContainsUnit).
            if (!ShadowContainsUnit(g->units, g->count, &visible[i])) { ++foreign; }
        }
        contained = (foreign == 0);
    }

    if (g && g->stored && !contained) {
        ++g_statGroupDiscard;
        ScLog("GROUP discard: group=%d held %d unit(s) but %d of the %d the engine just "
              "recalled are not among them -- the group does not describe this selection "
              "(stale after a load, or stored before we were watching). Falling back to "
              "the engine's own %d.", group, g->count, foreign, visibleCount, visibleCount);
        g->count  = 0;
        g->stored = false;
    }

    // A BUILDING GROUP RECALLS AS A GROUP (task 036).
    //
    // The engine can only ever hand back ONE building here, and that is not a fault in
    // its recall: hotkeySaveOrAdd fills the engine's group row from playersSelections,
    // which the SIM gate has already capped at one building (research/building-groups.md
    // 3), and the client recall keeps a predicate-failing entry only while the row holds
    // exactly one (`CMP ESI,0x1 / JLE` at 0x00496BEE). So the row holds one, the recall
    // returns one, and the STOCK STATUS ROW -- which draws clientSelectionGroup, copied
    // from activePlayerSelection, and NOT this plugin's shadow list -- shows one. That is
    // the "it only shows 1 in the row after I press the group number" the user reported:
    // the group was there in plugin memory the whole time and no engine-visible surface
    // was carrying it.
    //
    // So the group is put back into the ENGINE's own client selection, with the engine's
    // own function -- CreateNewUnitSelectionsFromList, the very call 0x00496B40 made a
    // few instructions ago, with our list instead of its one. Everything downstream is
    // then engine code: it attaches each unit's selection graphics itself, the status row
    // fills from the dirty flags 0x00496B40 has ALREADY set (0x0059723C / 0x0068C1F8 and
    // friends, written before it queued this command), and the command card sees a real
    // multi-selection instead of a single building.
    //
    // NOT done by writing selectionHotkeys instead, which looks like the tidier fix and
    // is not: a row holding N buildings is emptied by the client recall's own gate (with
    // N > 1 every building fails it), and the receive-side recall 0x00496940 COMPACTS the
    // row in place as it validates -- so the injection would be destroyed permanently
    // rather than merely ignored, and the player would lose the group entirely.
    //
    // Deliberately NOT extended to unit groups: for those the engine already hands back
    // its own twelve and task 021's arrangement is proven at 36 units. This branch runs
    // only when the engine's own predicate says the recalled lead is a building.
    // Both tests, for the reason spelled out at UnitIsBuilding: the sim gate refuses a
    // second slot to plenty of things that are not buildings (a "single entity" type, a
    // unit with any of four per-unit fields set), and this branch must not read one of
    // those as a building group and re-select twelve of them.
    const bool buildingGroup = g_buildingGroups && g_mode == SC_MODE_FANOUT &&
                               contained && visibleCount > 0 &&
                               !UnitIsStandardAndMovable(visible[0].ptr) &&
                               UnitIsBuilding(visible[0].ptr);

    g_shadowCount = 0;
    int restored = 0, dropped = 0, reinstalled = 0;

    if (buildingGroup) {
        // One pass over the group IN ITS OWN ORDER, so the engine gets a prefix of it and
        // the shadow list can still be assembled overflow-first / visible-last.
        ShadowUnit kept[SC_SHADOW_MAX];
        int keptN = 0;
        for (int i = 0; i < g->count && keptN < g_maxUnits; ++i) {
            int why = SC_LIVE_OK;
            if (!PassesGate(&g->units[i], &why)) {
                ++dropped;
                LogUnitForensics("GROUP recall drop", &g->units[i], why);
                continue;
            }
            kept[keptN++] = g->units[i];
        }
        const int want = keptN < SC_SELECTION_SLOTS ? keptN : SC_SELECTION_SLOTS;
        DWORD list[SC_SELECTION_SLOTS];
        for (int i = 0; i < want; ++i) list[i] = kept[i].ptr;
        CallCreateNewUnitSelections(list, want);

        // Read the engine BACK rather than assuming it took what it was given: the
        // invariant this module rests on is "the tail of the shadow list is what the
        // engine holds", and the only honest source for that is the array the engine
        // just wrote. It also substitutes subunit parents on the way through, which a
        // list of ours would not reflect.
        ShadowUnit now[SC_SELECTION_SLOTS];
        const int nowN = ReadEngineVisible(now, SC_SELECTION_SLOTS);
        reinstalled = nowN;
        for (int i = 0; i < keptN && g_shadowCount < g_maxUnits; ++i) {
            if (ShadowContainsUnit(now, nowN, &kept[i])) continue;
            g_shadow[g_shadowCount++] = kept[i];
            ++restored;
        }
        for (int i = 0; i < nowN && g_shadowCount < SC_SHADOW_MAX; ++i) {
            g_shadow[g_shadowCount++] = now[i];
        }
        g_visibleCount = nowN;
        UpdateSimSlots(now, nowN);
        ScLog("GROUP recall reinstall: the engine handed back %d of the %d building(s) this "
              "group holds (its own row is filled from playersSelections, which the sim gate "
              "caps at one) -- CreateNewUnitSelectionsFromList re-selected %d of them, so the "
              "status row and the engine's own circles now carry the group",
              visibleCount, g->count, reinstalled);
    }
    else {
        // Rebuild: overflow FIRST, the engine's visible units LAST -- the invariant the
        // whole module rests on (the final Select+order pair of a fan-out must leave the
        // simulation holding exactly what the player can see).
        if (contained) {
            for (int i = 0; i < g->count && g_shadowCount < g_maxUnits; ++i) {
                if (ShadowContainsUnit(visible, visibleCount, &g->units[i])) continue;
                int why = SC_LIVE_OK;
                if (!PassesGate(&g->units[i], &why)) {
                    ++dropped;
                    LogUnitForensics("GROUP recall drop", &g->units[i], why);
                    continue;
                }
                g_shadow[g_shadowCount++] = g->units[i];
                ++restored;
            }
        }
        for (int i = 0; i < visibleCount && g_shadowCount < SC_SHADOW_MAX; ++i) {
            g_shadow[g_shadowCount++] = visible[i];
        }
        g_visibleCount = visibleCount;
        // A recall is a selection change like any other, so the chunk size is recomputed
        // here too. Without this a group recalled after a building group would inherit
        // simSlots=1 and fan an ordinary 12-unit order out one unit at a time.
        UpdateSimSlots(visible, visibleCount);
    }
    ++g_shadowVersion;
    if (g_shadowCount > SC_SELECTION_SLOTS) ++g_statGroupWide;

    // Compact the group to what actually came back, so a unit that died between two
    // recalls is not re-judged (and re-logged) on every later one.
    if (contained) {
        int keep = 0;
        for (int i = 0; i < g_shadowCount; ++i) g->units[keep++] = g_shadow[i];
        g->count = keep;
    }

    ScLog("GROUP recall: group=%d -> %d unit(s) (%d visible from the engine + %d restored "
          "past the cap, %d dropped as not live)",
          group, g_shadowCount, visibleCount, restored, dropped);

    ShowOverflowCircles();

    // A recall is a new selection: a pending fan-out would command units the player has
    // moved on from. Same reasoning as ScFanoutOnSelect.
    if (g_plan.active) {
        ScLog("FANOUT: control group recalled with %d/%d chunks pending -- plan dropped",
              g_plan.nextChunk, g_plan.chunkCount);
        g_plan.active = false;
    }
}

// The whole 0x13 decision, split out so hooktest can drive it and so the command hook
// stays readable. Returns true if the command was one we understood.
static bool OnHotkeyCommand(const BYTE* buf, unsigned len) {
    // The engine's dispatcher consumes exactly 3 bytes for 0x13 and its group guard is
    // `CMP AL,0x12 / JA` (0x004C2873) -- unsigned, so it passes 0..18. We only mirror
    // the ten Ctrl+N groups; 10..17 are the engine's own recent-selection ring, and 18
    // is the vanilla off-by-one binary-selection-map.md 6.4 flags. Anything outside
    // 0..9 is left entirely to the engine.
    if (len != 3) {
        ScLog("GROUP: hotkey command arrived with len=%u, the dispatcher consumes 3 -- "
              "ignored", len);
        return false;
    }
    const BYTE action = buf[1];
    const int  group  = (int)buf[2];

    if (group < 0 || group >= SC_HOTKEY_GROUPS) {
        ScLog("GROUP: hotkey action=%u group=%d is not one of the ten Ctrl+N groups -- "
              "left to the engine", action, group);
        return false;
    }

    if (DisagreeingPlayerIds()) {
        // Never seen; logged rather than assumed away, because every row index in this
        // block comes from one of the three (binary-selection-map.md 7 note 7).
        ScLog("GROUP WARNING: the three player-id globals disagree (%u/%u/%u) -- the "
              "engine row this block reads may not be the one the store writes",
              *(BYTE*)Rt(SC_VA_ACTIVE_PLAYER_ID), *(BYTE*)Rt(SC_VA_PLAYER_ID_512688),
              *(BYTE*)Rt(SC_VA_PLAYER_ID_512678));
    }
    switch (action) {
        case SC_HOTKEY_ASSIGN: GroupStore(group, false); return true;
        case SC_HOTKEY_ADD:    GroupStore(group, true);  return true;
        case SC_HOTKEY_RECALL: GroupRecall(group);       return true;
        default:
            ScLog("GROUP: hotkey action=%u is not one CMDRECV_Hotkey dispatches "
                  "(0/1/2) -- ignored", action);
            return false;
    }
}

// ---------------------------------------------------------------------------
// Hook: queueCommand -- __fastcall(ECX = bytes, EDX = len)
// ---------------------------------------------------------------------------

static volatile LONG g_inFanout = 0;

// force_align_arg_pointer on every entry point the GAME calls:
// GCC at -O2 assumes the incoming stack is 16-byte aligned and will happily emit
// aligned SSE spills on that assumption. StarCraft is a 1998-era VC6-class build
// that guarantees 4-byte alignment and nothing more, so without this a detour can
// fault on a `movaps` with no other symptom than the game vanishing. The attribute
// makes each of these functions realign ESP itself.
#define SC_GAME_ENTRY __attribute__((force_align_arg_pointer))

// The decision half, callable without any hook installed.
bool ScFanoutOnCommand(const BYTE* buf, unsigned len) {
    if (!buf || len == 0) return false;

    const BYTE id = buf[0];
    ++g_statCommands;
    if (g_verboseCmds) {
        // The payload, not just the id. Two ids carry everything the command card can
        // send -- 0x15 is Attack, Patrol and Move alike, told apart only by the order
        // byte at offset 9 -- so an id-only log cannot say which button was pressed.
        // research/command-opcodes.md 4 names ids from exactly these lines.
        char hex[3 * 24 + 4];
        unsigned show = len < 24 ? len : 24;
        unsigned used = 0;
        for (unsigned i = 0; i < show; ++i) {
            used += (unsigned)_snprintf(hex + used, sizeof(hex) - used, "%s%02X",
                                        i ? " " : "", buf[i]);
        }
        if (show < len) _snprintf(hex + used, sizeof(hex) - used, " ...");
        ScLog("CMD id=0x%02X len=%u bytes=[%s]", id, len, hex);
    }

    InterlockedExchange(&g_inFanout, 1);
    EnterCriticalSection(&g_lock);
    // FIRST, ahead of the control-group handling below: the recall path's containment
    // check is exactly the defence a save/load defeats (#67 item 5), so the epoch has
    // to have thrown the group away before that check is asked anything.
    FanoutSessionSync();

    // Control groups (task 021). A recall rebuilds the selection without ever going
    // through CMDACT_Select, so before this task the shadow list was DROPPED here --
    // correct at the time, and the reason Ctrl+1 on 24 units gave you 12 back. The
    // shadow-group block above now stores and restores the whole selection instead.
    //
    // A command we do NOT understand (wrong length, a group outside 0..9, an action
    // CMDRECV_Hotkey does not dispatch) falls back to exactly the old behaviour: drop
    // the over-cap part rather than fan out a list the player is no longer holding.
    if (id == SC_CMD_HOTKEY) {
        if (!OnHotkeyCommand(buf, len) && g_shadowCount > g_visibleCount) {
            ScLog("SHADOW dropped: hotkey command 0x13 we did not understand rebuilds "
                  "the selection elsewhere");
            g_shadowCount = g_visibleCount;
            ++g_shadowVersion;
        }
    }

    // Finish any plan left over from a previous turn before adding to the buffer.
    DrainPlan();

    bool suppress = false;

    // Task 030 -- the ONE opcode that becomes eligible without being in kOpcodes' fan-out
    // column. Train (0x1F) is passthrough there for two good reasons (it is SINGLE-gated
    // and it spends: research/command-opcodes.md 3.2, 3.3), and neither is being waved
    // away. What changes is that for a same-type BUILDING group every chunk of the plan
    // is exactly ONE building -- simSlots is 1 because the simulation refuses a building
    // every slot but slot 0 -- so "one item per chunk" IS "one item per building", which
    // is what the player asked for, and each item still enters through the engine's own
    // cmdrecvTrain and is paid for by the engine's own addToBuildQueue. The whole
    // argument and the refusal cases live in sc_prodfan.cpp; this is the wiring.
    bool prodFanTrain = false;
    if (id == SC_CMD_TRAIN && !IsFanoutCmd(id) && g_mode == SC_MODE_FANOUT &&
        g_visibleCount > 0 && g_shadowCount > 0) {
        WORD types[SC_SHADOW_MAX];
        int n = 0;
        for (int i = 0; i < g_shadowCount && n < SC_SHADOW_MAX; ++i) {
            if (!g_shadow[i].ptr) continue;
            types[n++] = *(WORD*)(g_shadow[i].ptr + SC_CUNIT_OFF_UNIT_ID);
        }
        int verdict = ScProdFanDecide(types, n, g_simSlots, len);
        if (verdict == SC_PRODFAN_OK) {
            prodFanTrain = true;
        } else if (verdict != SC_PRODFAN_OFF && verdict != SC_PRODFAN_ONE_BUILDING) {
            // Logged and counted, never silent: a refusal the player cannot see is
            // indistinguishable from a feature that quietly did nothing.
            ScLog("PRODFAN refused: cmd 0x1F with %d building(s) selected, simSlots=%d "
                  "-- %s; the engine's own single-building handling runs untouched",
                  n, g_simSlots, ScProdFanVerdictName(verdict));
            ScProdFanCountRefusal();
        }
    }

    // `> g_simSlots`, not `> 12`: the fan-out exists because the SIMULATION cannot hold
    // the whole selection, and how many it holds is 12 for units and 1 for a same-type
    // building group (task 024). For units this is the same condition it always was.
    if (g_mode == SC_MODE_FANOUT &&
        (IsFanoutCmd(id) || prodFanTrain) &&
        g_shadowCount > g_simSlots &&
        g_visibleCount > 0 &&
        len <= SC_MAX_ORDER_BYTES) {
        // The length the ENGINE will consume for this id, from its own dispatcher. A
        // command whose length disagrees is not the command this id is supposed to be:
        // replaying it would hand the receive loop a byte count it did not expect and
        // desynchronise everything behind it in the same turn buffer. Refuse and let the
        // engine's own command through untouched.
        const ScOpcode* op = FindOpcode(id);
        if (!op || op->len < 0 || (unsigned)op->len != len) {
            ScLog("FANOUT refused: cmd 0x%02X arrived with len=%u, the dispatcher consumes "
                  "%d -- passing it through untouched", id, len, op ? op->len : -1);
        } else {
            // Suppress only if at least one Select+order pair really went out; the
            // first pair already carried this exact order.
            suppress = StartFanout(buf, (int)len);
            // Counted only when a pair actually went out, so `reached` is buildings the
            // wire really carried an order to -- not buildings that were selected.
            if (prodFanTrain && suppress) ScProdFanCountFanout(g_plan.chunkCount);
        }
    }

    LeaveCriticalSection(&g_lock);
    InterlockedExchange(&g_inFanout, 0);
    return suppress;
}

static void __attribute__((fastcall)) SC_GAME_ENTRY
HkQueueCommand(const void* buf, unsigned len) {
    // Re-entrancy: everything we emit goes through the TRAMPOLINE, not through the
    // hooked entry point, so this guard only matters when the engine itself
    // re-enters -- which it does, via the turn flush emitting a sync command from
    // inside our own emission.
    if (InterlockedCompareExchange(&g_inFanout, 0, 0)) {
        ((ScQueueFn)g_hkQueue.trampoline)(buf, len);
        return;
    }
    if (!ScFanoutOnCommand((const BYTE*)buf, len)) {
        ((ScQueueFn)g_hkQueue.trampoline)(buf, len);
    }
}

// ---------------------------------------------------------------------------
// Hook: CMDACT_Select -- __stdcall(count, CUnit** units); the commit point
// ---------------------------------------------------------------------------

void ScFanoutOnSelect(unsigned count, DWORD* units) {
    EnterCriticalSection(&g_lock);
    FanoutSessionSync();
    ++g_statSelects;

    ShadowUnit visible[SC_SELECTION_SLOTS];
    int visibleCount = 0;
    if (units) {
        for (unsigned i = 0; i < count && visibleCount < SC_SELECTION_SLOTS; ++i) {
            ShadowUnit u;
            if (ReadUnit(units[i], &u)) visible[visibleCount++] = u;
        }
    }

    // The accumulator only matters when the engine actually truncated: a commit of
    // fewer than 12 units cannot have discarded anything.
    int added = 0;
    g_shadowCount = 0;
    if (visibleCount >= SC_SELECTION_SLOTS && g_accumCount > 0) {
        for (int i = 0; i < g_accumCount && g_shadowCount < g_maxUnits; ++i) {
            if (ShadowContains(visible, visibleCount, g_accum[i].ptr)) continue;
            if (ShadowContains(g_shadow, g_shadowCount, g_accum[i].ptr)) continue;
            // Same gate as the emit path: a unit that is already dead when the
            // selection commits has no business entering the shadow list at all.
            if (!PassesGate(&g_accum[i], NULL)) continue;
            if (visibleCount > 0 && g_accum[i].player != visible[0].player) continue;
            g_shadow[g_shadowCount++] = g_accum[i];
            ++added;
        }
    }
    // Visible units go LAST, so the final Select+order pair of a fan-out leaves the
    // simulation holding exactly what the player can see -- unless the liveness gate
    // refuses all twelve of them, in which case that pair is not written at all (see
    // the exception in this file's header comment).
    for (int i = 0; i < visibleCount && g_shadowCount < SC_SHADOW_MAX; ++i) {
        g_shadow[g_shadowCount++] = visible[i];
    }
    g_visibleCount = visibleCount;
    UpdateSimSlots(visible, visibleCount);
    ++g_shadowVersion;

    if (added > 0) {
        ScLog("SHADOW captured: %d units (%d visible + %d beyond the cap) "
              "[accum had %d] simSlots=%d",
              g_shadowCount, visibleCount, added, g_accumCount, g_simSlots);
    } else if (g_simSlots != SC_SELECTION_SLOTS) {
        // A building group commits with no overflow at all when it fits in twelve, so
        // the line above would never fire for the case task 024 is about. This one
        // reports the shape that matters: how many were selected, and how many of them
        // the simulation will actually hold.
        ScLog("SHADOW captured: %d units (%d visible + 0 beyond the cap) simSlots=%d "
              "-- the sim holds %d of them at a time",
              g_shadowCount, visibleCount, g_simSlots, g_simSlots);
    } else if (g_verboseCmds) {
        ScLog("SELECT commit: %u units (no overflow captured)", count);
    }

    g_accumCount = 0;

    // Task 014: put a selection circle under the units the cap threw away.
    //
    // Here and not earlier, for two reasons. First, this is the moment the shadow
    // list exists -- the overflow accumulator and the engine's final list have just
    // been unioned. Second, the engine has ALREADY finished attaching its own
    // graphics for this selection: CreateNewUnitSelectionsFromList (0x0049AE40) runs
    // before CMDACT_Select on every path into here (0x0049AEF0 calls them in that
    // order; so does the click handler 0x0046FB40). Attaching now therefore cannot
    // collide with the engine's own attach pass, and our matching detach already ran
    // from the 0x0049AE40 pre-hook a moment ago.
    //
    // The overflow units are the FRONT of g_shadow -- visible units are stored last
    // so the final Select+order pair of a fan-out leaves the simulation holding what
    // the player can see (with the all-twelve-dead exception in the file header).
    //
    // Task 021 moved the body of this into ShowOverflowCircles() because a control-group
    // recall reaches the same point by a different route and has to do the identical
    // thing; the timing argument above holds for both, since 0x0049AE40 has already run
    // on each path.
    ShowOverflowCircles();

    // A new selection invalidates a pending fan-out: those pairs would command units
    // the player has moved on from. The engine's own Select is about to be queued
    // right behind us, so the simulation selection ends up correct either way.
    if (g_plan.active) {
        ScLog("FANOUT: selection changed with %d/%d chunks pending -- plan dropped",
              g_plan.nextChunk, g_plan.chunkCount);
        g_plan.active = false;
    }

    LeaveCriticalSection(&g_lock);
}

static void __attribute__((stdcall)) SC_GAME_ENTRY
HkCmdactSelect(unsigned count, DWORD* units) {
    ScFanoutOnSelect(count, units);
    // Deliberately outside the lock: the original queues its Select through the
    // hooked queueCommand, which takes the same lock.
    ((CmdactSelectFn)g_hkSelect.trampoline)(count, units);
}

// ---------------------------------------------------------------------------
// Hook: sortOverflowHandler -- EAX = count, ECX = CUnit** out12,
//                              stack [+4] = unit, [+8] = clicked, RET 8
//
// No C calling convention describes that, so the detour is an explicit thunk that
// saves every register, hands the four values to a normal C function, restores, and
// jumps to the trampoline. Offsets are worked out in the comment beside each push.
// ---------------------------------------------------------------------------

extern "C" void ScOverflowObserve(unsigned count, DWORD* outList, DWORD unit, DWORD clicked);

extern "C" void ScOverflowThunk(void);
asm(
    ".text\n"
    ".globl _ScOverflowThunk\n"
"_ScOverflowThunk:\n"
    "  pushal\n"                    // -32 : EAX ECX EDX EBX ESP EBP ESI EDI
    "  pushfl\n"                    // -4  : esp is now entry-36
    "  pushl 44(%esp)\n"            // clicked : entry+8  == esp+44
    "  pushl 44(%esp)\n"            // unit    : entry+4  == esp+44 (esp moved -4)
    "  pushl 36(%esp)\n"            // outList : saved ECX == esp+36 (esp moved -8)
    "  pushl 44(%esp)\n"            // count   : saved EAX == esp+44 (esp moved -12)
    "  call _ScOverflowObserve\n"
    "  addl $16, %esp\n"            // cdecl: caller cleans
    "  popfl\n"
    "  popal\n"
    "  jmp *_g_overflowTrampoline\n"
);

extern "C" void* g_overflowTrampoline;
void* g_overflowTrampoline = NULL;

extern "C" void SC_GAME_ENTRY
ScOverflowObserve(unsigned count, DWORD* outList, DWORD unit, DWORD clicked) {
    (void)clicked;   // the clicked unit is already in outList when it matters
    ScFanoutOnOverflow(count, outList, unit);
}

void ScFanoutOnOverflow(unsigned count, DWORD* outList, DWORD unit) {
    EnterCriticalSection(&g_lock);
    FanoutSessionSync();
    ++g_statOverflow;

    // Snapshot the 12 slots BEFORE the original runs: this handler can replace an
    // entry, and the unit it replaces would otherwise be lost from both the output
    // array and our accumulator.
    if (outList) {
        unsigned n = count < SC_SELECTION_SLOTS ? count : SC_SELECTION_SLOTS;
        for (unsigned i = 0; i < n; ++i) {
            ShadowUnit u;
            if (!ReadUnit(outList[i], &u)) continue;
            if (ShadowContains(g_accum, g_accumCount, u.ptr)) continue;
            if (g_accumCount < SC_SHADOW_MAX) g_accum[g_accumCount++] = u;
        }
    }

    ShadowUnit u;
    if (ReadUnit(unit, &u) && !ShadowContains(g_accum, g_accumCount, u.ptr) &&
        g_accumCount < SC_SHADOW_MAX) {
        g_accum[g_accumCount++] = u;
    }

    LeaveCriticalSection(&g_lock);
}

// ---------------------------------------------------------------------------
// Hook: SortAllUnits -- __stdcall(candidates, out12, clicked) -> count
// Evidence only: it logs how many units the box actually contained, which is the
// number the 12-cap is measured against.
// ---------------------------------------------------------------------------

// The hook-free half: given the candidate list the engine was handed and the 12-slot
// output it produced, grow a one-building result into the whole same-type group.
//
// WHEN IT DOES NOTHING, which is nearly always:
//   * building groups are switched off (%SCPLUGIN_BUILDING_GROUPS%=0), or the mode is
//     not fanout -- `shadow` mode's contract is "capture and log, change nothing", and
//     this changes what the player has selected;
//   * the engine returned anything other than exactly 1 -- more than one means the
//     movable path found real units and no fallback was involved;
//   * that one unit passes unit_IsStandardAndMovable -- i.e. it is an ordinary unit
//     the engine selected on its own merits.
//
// TASK 036 REMOVED THE `clicked == 0` CONDITION, and the reason it is safe to is a fact
// about the callers rather than a judgement. SortAllUnits has three call sites:
// 0x0046FA40 (the drag box, `clicked = 0`) and 0x0046FB40 twice, at 0x0046FCAD and
// 0x0046FE41 -- and BOTH of those are the ctrl-click / double-click "select all of this
// type on screen" branches, whose candidate list is a scan of the screen rect. A PLAIN
// click and a SHIFT-click never reach this function at all: the plain click calls
// 0x0049AE40(1) and CMDACT_Select(1) directly, and shift-click has its own inline
// add/remove block (sc_addresses.h SC_VA_CLICK_SELECT_HANDLER, with the branch table).
// So `clicked != 0` here means exactly "ctrl-click or double-click", which is the input
// the user asked for, and the click paths that must stay stock cannot arrive here.
//
// The signature is the same on both. With `clicked != 0` the engine seeds `out[0] =
// clicked` and starts its count at 1 (0x0046F0F5..0x0046F103) before the filter loop, so
// a screen full of buildings still leaves `ret == 1` with the clicked building in slot 0
// -- the identical shape the box's "last rejected candidate" fallback produces.
//
// WHAT IT THEN DOES. It keeps the engine's own choice of lead -- the building vanilla
// would have selected alone -- and appends every other candidate of the SAME TYPE and
// the SAME OWNER. Keeping vanilla's lead is deliberate: a box holding four Supply
// Depots and three Barracks already picks one building in vanilla, and picking a
// different one here would be a second arbitrary rule on top of the engine's. So a
// mixed-BUILDING box selects the group of whichever type vanilla was already going to
// select, and a mixed unit/building box is untouched (the engine returns the units).
//
// The output array belongs to the caller and holds 12 slots (`local_34[12]` in
// 0x0046FA40), so at most 12 are written; the rest go to the overflow accumulator the
// shadow list is built from, exactly where sortOverflowHandler would have put them.
// Every appended unit passes task 020's liveness gate first, so a building that is
// already dead never enters the selection or the shadow list.
unsigned ScFanoutGrowBuildingGroup(DWORD* candidates, DWORD* out, DWORD clicked,
                                   unsigned ret) {
    if (!g_buildingGroups || g_mode != SC_MODE_FANOUT) return ret;
    if (ret != 1 || !out || !candidates) return ret;

    const DWORD lead = out[0];
    if (!UnitPtrValid(lead)) return ret;
    // Both tests, same reason as everywhere else in task 036 (see UnitIsBuilding): the
    // predicate failing is not by itself "this is a building". Task 024 shipped with the
    // predicate alone, which was safe while `clicked == 0` also had to hold -- a box that
    // selected exactly one thing that was not a building was already a vanishing case --
    // and is not, now that every ctrl-click and double-click arrives here too.
    if (UnitIsStandardAndMovable(lead) || !UnitIsBuilding(lead)) return ret;

    const WORD leadType  = *(WORD*)(lead + SC_CUNIT_OFF_UNIT_ID);
    const BYTE leadOwner = *(BYTE*)(lead + SC_CUNIT_OFF_PLAYER);

    EnterCriticalSection(&g_lock);
    FanoutSessionSync();

    int n = 1;              // out[0] is the lead the engine already chose
    int beyond = 0, refused = 0;
    for (int i = 0; candidates[i] != 0 && i < SC_MAX_UNITS_WALK; ++i) {
        const DWORD c = candidates[i];
        if (c == lead) continue;
        if (!UnitPtrValid(c)) continue;
        if (*(WORD*)(c + SC_CUNIT_OFF_UNIT_ID) != leadType) continue;
        if (*(BYTE*)(c + SC_CUNIT_OFF_PLAYER) != leadOwner) continue;
        // Fail closed. Same type as a unit that failed the gate cannot pass it, but a
        // future type whose gate verdict depends on per-unit state (0x0047B770 reads
        // CUnit+0x117/+0x119/+0x124 as well as the type) would, and a movable unit has
        // no business being added by THIS path.
        if (UnitIsStandardAndMovable(c)) continue;

        bool dup = false;
        for (int j = 0; j < n; ++j) if (out[j] == c) { dup = true; break; }
        if (dup) continue;

        ShadowUnit u;
        int why = SC_LIVE_OK;
        if (!ReadUnit(c, &u)) continue;
        if (!PassesGate(&u, &why)) {
            ++refused;
            if (why >= 0 && why <= SC_DROP_NOTAG) ++g_statBGroupRefused[why];
            LogUnitForensics("BGROUP refused", &u, why);
            continue;
        }

        if (n < SC_SELECTION_SLOTS) {
            out[n++] = c;
        } else if (!ShadowContains(g_accum, g_accumCount, u.ptr) &&
                   g_accumCount < SC_SHADOW_MAX) {
            // Past the engine's twelve: the same place sortOverflowHandler puts a unit,
            // so the shadow list, the overflow circles and the fan-out all pick these
            // up with no further special-casing.
            g_accum[g_accumCount++] = u;
            ++beyond;
        }
    }

    LeaveCriticalSection(&g_lock);

    if (n > 1 || beyond > 0 || refused > 0) {
        // `via` names the INPUT, from SortAllUnits' own third argument -- the one fact
        // that separates the drag box from the two type-match click paths, and the field
        // an unattended run asserts a double click on rather than inferring it.
        ScLog("BGROUP %s: lead=0x%08X type=%u owner=%u flags=0x%08X -> selected %d "
              "(+%d beyond the cap, %d refused by the liveness gate)",
              clicked ? "click" : "box",
              (unsigned)lead, leadType, leadOwner, (unsigned)UnitsDatFlags(leadType),
              n, beyond, refused);
    }
    return (unsigned)n;
}

// ---------------------------------------------------------------------------
// EXTENDING A BUILDING GROUP -- shift-click, shift+box, shift+ctrl-click (task 036)
//
// Growing SortAllUnits' result covers the two paths that REPLACE the selection (the drag
// box, and ctrl-click / double-click). The paths that EXTEND one do not go through it:
//
//   shift-click ADD  is an inline block in the click handler. It asks
//                    unit_IsStandardAndMovable about the existing selection's lead
//                    (CALL at 0x0046FD27) and about the clicked unit (0x0046FD44), and
//                    returns without appending if either says no.
//   shift+box and    go through combineSelectionsLists (0x0046F290), which asks the same
//   shift+ctrl-click question about the incoming list's lead (0x0046F2C8) and the existing
//                    list's lead (0x0046F2E8) and, on either failure, returns the EXISTING
//                    count untouched -- so the merge simply does not happen.
//
// Neither is a function this plugin can wrap: one is a basic block in the middle of a
// 900-byte handler, the other has a register-passed destination list. So the thing that
// is detoured is the PREDICATE, and it is scoped by the RETURN ADDRESS -- it answers
// differently at exactly the four instruction addresses above (sc_addresses.h,
// SC_RET_MOVABLE_*) and hands back the engine's own verdict everywhere else in the
// binary. There is no other consumer to disturb, because there is no other call site in
// the allowlist.
//
// THE RULE, and why it cannot regress anything a player could see today:
//
//     When the LEAD of the selection being extended is a building, membership at these
//     four sites becomes "same type and same owner as that lead". Otherwise the engine's
//     own answer stands, unchanged.
//
// The lead being a building is precisely the case in which vanilla refuses the whole
// operation -- the lead's OWN call site returns 0 and the handler bails -- so every
// outcome under the rule replaces "nothing happens" with something. That is also why the
// rule may safely REFUSE where vanilla would have allowed: a Marine shift-clicked onto a
// building group is refused here, and vanilla refused it too, one call site earlier.
//
// A building group therefore stays ONE TYPE on every path: the box is same-type by
// construction (task 024), double-click and ctrl-click are same-type by the engine's own
// filter, and this is what makes shift agree with them. A mixed building+unit or
// building+building selection is refused, and that is the answer to "what does a mixed
// selection do" rather than an omission -- research/building-groups.md 9.
//
// WHERE THE LEAD COMES FROM. activePlayerSelection[0]. At the shift-click sites the
// handler has copied that array into a local a few instructions earlier; both callers of
// combineSelectionsLists copy it into a local too (0x0046FA40's 12-dword loop,
// 0x0046FC9A's `LEA EDI,[EBP-0x6c]` + `MOVSD.REP`), and the merge appends to that copy
// without touching slot 0. So one read answers all four sites and none of them needs the
// plugin to remember anything between calls.
// ---------------------------------------------------------------------------

extern "C" int ScFanoutMovableDecide(DWORD unit, DWORD retAddr, int verdict);
extern "C" void ScFanoutMovableThunk(void);
extern "C" void* g_scMovableTrampoline;
void* g_scMovableTrampoline = NULL;

// ECX = CUnit*, no stack arguments, plain RET. The thunk keeps ECX for the original,
// then hands (unit, returnAddress, the original's verdict) to a normal C function whose
// return value becomes the caller's EAX. EBX/ESI/EDI are untouched by construction (GCC
// preserves them across the C call), and the flags the game TESTs are set by its own
// `TEST EAX,EAX` after the call, not by us.
asm(
    ".text\n"
    ".globl _ScFanoutMovableThunk\n"
"_ScFanoutMovableThunk:\n"
    "  pushl %ecx\n"                     // [esp]=unit, [esp+4]=the game's return address
    "  call *_g_scMovableTrampoline\n"   // ECX still = unit; EAX = the engine's verdict
    "  pushl %edx\n"                     // caller-saved, preserved anyway
    "  pushl %ecx\n"
    "  pushl %eax\n"                     // arg3: verdict
    "  pushl 16(%esp)\n"                 // arg2: return address  (esp+16 == entry esp)
    "  pushl 16(%esp)\n"                 // arg1: unit            (esp+16 == entry esp-4)
    "  call _ScFanoutMovableDecide\n"
    "  addl $12, %esp\n"                 // cdecl: caller cleans the three arguments
    "  popl %ecx\n"
    "  popl %edx\n"
    "  addl $4, %esp\n"                  // drop the saved unit
    "  ret\n"
);

// The four allowlisted return addresses, relocated to this process's load address. A
// static VA would be wrong under any base other than 0x00400000, and the plugin already
// relocates every other address it uses.
static bool IsExtendSite(DWORD retAddr) {
    return retAddr == (DWORD)(DWORD_PTR)Rt(SC_RET_MOVABLE_SHIFT_LEAD)
        || retAddr == (DWORD)(DWORD_PTR)Rt(SC_RET_MOVABLE_SHIFT_CLICKED)
        || retAddr == (DWORD)(DWORD_PTR)Rt(SC_RET_MOVABLE_COMBINE_NEW)
        || retAddr == (DWORD)(DWORD_PTR)Rt(SC_RET_MOVABLE_COMBINE_OLD);
}

static const char* ExtendSiteName(DWORD retAddr) {
    if (retAddr == (DWORD)(DWORD_PTR)Rt(SC_RET_MOVABLE_SHIFT_LEAD))    return "shift-click/lead";
    if (retAddr == (DWORD)(DWORD_PTR)Rt(SC_RET_MOVABLE_SHIFT_CLICKED)) return "shift-click/clicked";
    if (retAddr == (DWORD)(DWORD_PTR)Rt(SC_RET_MOVABLE_COMBINE_NEW))   return "combine/new-list";
    if (retAddr == (DWORD)(DWORD_PTR)Rt(SC_RET_MOVABLE_COMBINE_OLD))   return "combine/existing";
    return "?";
}

extern "C" int SC_GAME_ENTRY
ScFanoutMovableDecide(DWORD unit, DWORD retAddr, int verdict) {
    if (!g_buildingGroups || g_mode != SC_MODE_FANOUT) return verdict;
    if (!IsExtendSite(retAddr)) return verdict;

    const DWORD lead = *(DWORD*)Rt(SC_VA_ACTIVE_PLAYER_SELECTION);
    if (!UnitPtrValid(lead)) return verdict;
    // Not a building group -> the engine decides, exactly as it does today. This is the
    // branch every ordinary unit selection takes, so shift-clicking Marines is untouched.
    //
    // BOTH tests, not just the predicate. The predicate also fails for a "single entity"
    // type and for four per-unit fields, so an ordinary UNIT can fail it -- and this
    // feature is called building groups. Requiring the units.dat Building bit as well
    // keeps every widening here to the thing it is named after.
    if (UnitIsStandardAndMovable(lead) || !UnitIsBuilding(lead)) return verdict;

    ++g_statExtendSeen;
    if (!UnitPtrValid(unit)) { ++g_statExtendRefuse; return 0; }

    const WORD leadType  = *(WORD*)(lead + SC_CUNIT_OFF_UNIT_ID);
    const BYTE leadOwner = *(BYTE*)(lead + SC_CUNIT_OFF_PLAYER);
    const WORD type      = *(WORD*)(unit + SC_CUNIT_OFF_UNIT_ID);
    const BYTE owner     = *(BYTE*)(unit + SC_CUNIT_OFF_PLAYER);

    int  why  = SC_LIVE_OK;
    bool live = true;
    ShadowUnit u;
    if (!ReadUnit(unit, &u)) { live = false; why = SC_DROP_NOTAG; }
    else live = PassesGate(&u, &why);

    const bool allow = (type == leadType) && (owner == leadOwner) && live;
    if (allow) ++g_statExtendAllow; else ++g_statExtendRefuse;

    // One line per call, and it names WHICH test decided -- task 030's rule. Four calls
    // per shift-click at most, and only ever when the lead is a building, so this cannot
    // grow into the per-order pile ShouldLogForensics exists to prevent.
    ScLog("BGROUP extend [%s]: lead=0x%08X type=%u owner=%u | unit=0x%08X type=%u owner=%u "
          "live=%d(%s) engineSaid=%d -> %s",
          ExtendSiteName(retAddr), (unsigned)lead, leadType, leadOwner,
          (unsigned)unit, type, owner, live ? 1 : 0, DropWhyName(why), verdict,
          allow ? "ALLOW" : "refuse");
    return allow ? 1 : 0;
}

static ScHook g_hkMovable;

// Verified prologue -- ScHookInstall refuses to patch if memory disagrees. Two whole
// instructions, seven bytes, neither PC-relative (sc_addresses.h SC_MOVABLE_PATCH_LEN):
//     0047B770  66 8B 41 64   MOV AX,word ptr [ECX + 0x64]
//     0047B774  0F B7 D0      MOVZX EDX,AX
static const BYTE kPrologueMovable[] = { 0x66, 0x8B, 0x41, 0x64, 0x0F, 0xB7, 0xD0 };

static unsigned __attribute__((stdcall)) SC_GAME_ENTRY
HkSortAllUnits(DWORD* candidates, DWORD* out, DWORD clicked) {
    int candCount = 0;
    if (candidates) {
        while (candidates[candCount] != 0 && candCount < 4096) ++candCount;
    }
    unsigned ret = ((SortAllUnitsFn)g_hkSort.trampoline)(candidates, out, clicked);
    unsigned grown = ScFanoutGrowBuildingGroup(candidates, out, clicked, ret);
    // `clicked` is the discriminator between the two input paths that reach here and it
    // is logged, not inferred: 0x0046FA40 (the DRAG BOX) is the only caller that passes
    // 0, and 0x0046FB40's two call sites (0x0046FCAD, 0x0046FE41) pass the unit under
    // the cursor -- they are the ctrl-click / double-click "select all of this type on
    // screen" paths. research/building-groups.md 2.3 and 8.1. Without this field a log
    // reading `candidates=37 -> selected=1` cannot say WHICH path refused.
    ScLog("SORT candidates=%d clicked=0x%08X -> engine=%u selected=%u%s "
          "(accumulated beyond the cap: %d)",
          candCount, (unsigned)clicked, ret, grown,
          grown != ret ? " [building group]" : "", g_accumCount);
    return grown;
}

// ---------------------------------------------------------------------------
// Mode + install
// ---------------------------------------------------------------------------

const char* ScModeName(ScMode m) {
    switch (m) {
        case SC_MODE_OBSERVE:  return "observe";
        case SC_MODE_HOOKTEST: return "hooktest";
        case SC_MODE_SHADOW:   return "shadow";
        case SC_MODE_FANOUT:   return "fanout";
    }
    return "?";
}

ScMode ScFanoutResolveMode(void) {
    char buf[32];
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_MODE", buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return SC_MODE_OBSERVE;
    if (lstrcmpiA(buf, "hooktest") == 0) return SC_MODE_HOOKTEST;
    if (lstrcmpiA(buf, "shadow")   == 0) return SC_MODE_SHADOW;
    if (lstrcmpiA(buf, "fanout")   == 0) return SC_MODE_FANOUT;
    return SC_MODE_OBSERVE;
}

static int EnvInt(const char* name, int def, int lo, int hi) {
    char buf[32];
    DWORD n = GetEnvironmentVariableA(name, buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return def;
    int v = atoi(buf);
    if (v < lo) v = lo;
    if (v > hi) v = hi;
    return v;
}

int ScFanoutInstall(BYTE* moduleBase, ScMode mode) {
    g_mode = mode;
    g_base = moduleBase;
    if (mode == SC_MODE_OBSERVE) return 0;

    if (!g_lockInit) { InitializeCriticalSection(&g_lock); g_lockInit = true; }

    g_session = ScSessionEpoch();
    g_budget      = EnvInt("SCPLUGIN_FANOUT_BUDGET", SC_DEFAULT_BUDGET, 40, 480);
    g_maxUnits    = EnvInt("SCPLUGIN_MAX_UNITS", SC_SHADOW_MAX - 1, 12, SC_SHADOW_MAX - 1);
    g_verboseCmds = EnvInt("SCPLUGIN_LOG_COMMANDS", 1, 0, 1) != 0;
    // Task 020's liveness gate, ON by default. Setting it to 0 restores the
    // uniqueness-only test the fan-out shipped with, which is a KNOWN-BAD
    // configuration -- it exists so an A/B run can show the defect and so the
    // in-game regression assertion can be shown to be capable of failing.
    g_liveness    = EnvInt("SCPLUGIN_FANOUT_LIVENESS", 1, 0, 1) != 0;
    // Task 024's same-type building groups. Its own off switch on top of the mode, so
    // a run can prove the STOCK one-building behaviour with the same binary -- an
    // "it selected four" assertion is only worth something next to an arm where the
    // same box selects one.
    g_buildingGroups = EnvInt("SCPLUGIN_BUILDING_GROUPS", 1, 0, 1) != 0;
    g_movableFn      = NULL;    // in the game, ask the engine
    g_simSlots       = SC_SELECTION_SLOTS;
    LoadFanoutCmds();

    // Task 014's selection circles. Only in fanout mode -- `shadow` mode's contract is
    // "capture and log, change nothing", and drawing a circle is a change. %SCPLUGIN_CIRCLES%
    // is its own off switch on top of the mode, so a fan-out run can be compared with and
    // without the visuals without rebuilding anything.
    const bool circles = (mode == SC_MODE_FANOUT) && EnvInt("SCPLUGIN_CIRCLES", 1, 0, 1) != 0;
    ScCirclesInit(moduleBase, circles);

    // Task 017's HUD-row paging. Same shape as the circles: fanout mode only
    // (shadow mode's contract is "capture and log, change nothing"), with
    // %SCPLUGIN_HUDROW% as its own off switch so the row can be compared stock
    // and paged without rebuilding anything.
    const bool hudrow = (mode == SC_MODE_FANOUT) && EnvInt("SCPLUGIN_HUDROW", 1, 0, 1) != 0;
    ScHudRowInit(moduleBase, hudrow);

    // Task 033's queue-overflow indicator, with %SCPLUGIN_QUEUEIND% as its own off switch.
    //
    // The mode gate is NOT "fanout only" like the two above, and the difference is the
    // contract rather than the feature: `observe` writes nothing to game memory at all and
    // `shadow` promises "capture and log, change nothing" -- drawing is a change, so both
    // refuse it. `hooktest` makes no such promise (task 025's production queue, which moves
    // a player's RESOURCES, runs in it), and it is the mode a production run wants, because
    // it puts no selection machinery in the picture. What this indicator reports is a
    // production queue, so it has to exist there.
    //
    // It goes in here rather than in scplugin.cpp so its one detour lands under the SAME
    // thread suspension as the others.
    const bool queueind = (mode == SC_MODE_FANOUT || mode == SC_MODE_HOOKTEST) &&
                          ScQueueIndEnabled();
    ScQueueIndInit(moduleBase, queueind);

    char cmds[192];
    int used = 0;
    cmds[0] = '\0';
    for (int i = 0; i < g_fanoutCmdCount && used + 5 < (int)sizeof(cmds); ++i) {
        used += _snprintf(cmds + used, sizeof(cmds) - used, "%s0x%02X",
                          i ? " " : "", g_fanoutCmds[i]);
    }
    ScLog("FANOUT config: mode=%s budget=%dB maxUnits=%d logCommands=%d circles=%d "
          "hudrow=%d queueind=%d liveness=%d buildingGroups=%d cmds=[%s]",
          ScModeName(mode), g_budget, g_maxUnits, g_verboseCmds ? 1 : 0,
          circles ? 1 : 0, hudrow ? 1 : 0, queueind ? 1 : 0, g_liveness ? 1 : 0,
          g_buildingGroups ? 1 : 0, cmds);
    if (!g_liveness) {
        ScLog("FANOUT WARNING: %%SCPLUGIN_FANOUT_LIVENESS%%=0 -- the emit gate is the "
              "pre-task-020 uniqueness test ALONE. A unit killed by damage will be "
              "replayed into a Select and the engine will follow its sprite pointer. "
              "This configuration exists only to reproduce that defect on demand.");
    }

    // One suspension for all hooks: the game is quiescent for microseconds instead
    // of once per hook, and a partially installed set is never observable.
    int suspended = ScHookSuspendThreads();
    ScLog("HOOK: suspended %d other thread(s) for the splice", suspended);

    int installed = 0;

    if (ScHookInstall(&g_hkQueue, "queueCommand", Rt(SC_VA_QUEUE_COMMAND),
                      (void*)&HkQueueCommand, 9,
                      kPrologueQueue, (int)sizeof(kPrologueQueue))) ++installed;

    if (mode >= SC_MODE_SHADOW) {
        if (ScHookInstall(&g_hkSelect, "CMDACT_Select", Rt(SC_VA_CMDACT_SELECT),
                          (void*)&HkCmdactSelect, 6,
                          kPrologueSelect, (int)sizeof(kPrologueSelect))) ++installed;

        if (ScHookInstall(&g_hkOverflow, "sortOverflowHandler", Rt(SC_VA_SORT_OVERFLOW),
                          (void*)&ScOverflowThunk, 5,
                          kPrologueOverflow, (int)sizeof(kPrologueOverflow))) {
            g_overflowTrampoline = g_hkOverflow.trampoline;
            ++installed;
        }

        if (ScHookInstall(&g_hkSort, "SortAllUnits", Rt(SC_VA_SORT_ALL_UNITS),
                          (void*)&HkSortAllUnits, 6,
                          kPrologueSort, (int)sizeof(kPrologueSort))) ++installed;

        // Task 036. Installed in shadow mode too, like the four above, and INERT there:
        // ScFanoutMovableDecide returns the engine's own verdict unless the mode is
        // fanout AND %SCPLUGIN_BUILDING_GROUPS% is on AND the call came from one of four
        // named instruction addresses. So the stock arm runs with the detour spliced and
        // still behaves exactly like vanilla, which is what makes that arm's "one
        // building" mean something about the FEATURE rather than about the hooks.
        if (ScHookInstall(&g_hkMovable, "unit_IsStandardAndMovable",
                          Rt(SC_VA_UNIT_IS_STANDARD_AND_MOVABLE),
                          (void*)&ScFanoutMovableThunk, SC_MOVABLE_PATCH_LEN,
                          kPrologueMovable, (int)sizeof(kPrologueMovable))) {
            g_scMovableTrampoline = g_hkMovable.trampoline;
            ++installed;
        }
    }

    // Task 014's one extra hook. It goes in under the same suspension as the rest so
    // a half-installed set is never observable.
    if (circles && ScCirclesInstallHook()) ++installed;

    // Task 017's one dispatcher detour, same suspension. ScHudRowInstallHooks
    // returns 0 or 1.
    if (hudrow) installed += ScHudRowInstallHooks();

    // Task 033's one HUD-driver detour, same suspension, same 0-or-1 contract.
    if (queueind) installed += ScQueueIndInstallHooks();

    ScHookResumeThreads();

    // A partial install is not a working plugin: the queueCommand hook without the
    // selection hooks would fan out a shadow list nothing ever fills. Roll back.
    // The circle hook counts too -- without it our circles would never come off, and
    // stale circles under units the player has deselected is worse than none. The
    // HUD-row dispatcher detour is one hook, and so is task 033's HUD driver.
    //
    // The shadow-mode count is FIVE, not four: queueCommand, CMDACT_Select,
    // sortOverflowHandler, SortAllUnits, and task 036's unit_IsStandardAndMovable.
    // Both halves of this expression moved at once (033 added the queueind term while
    // 036 bumped the base), so it is spelled out rather than merged by shape.
    const int expected = ((mode >= SC_MODE_SHADOW) ? 5 : 1) + (circles ? 1 : 0)
                       + (hudrow ? 1 : 0) + (queueind ? 1 : 0);
    if (installed != expected) {
        ScLog("HOOK: only %d of %d hooks installed -- ROLLING BACK, the plugin is "
              "passive for this run", installed, expected);
        ScFanoutRemove();
        g_mode = SC_MODE_OBSERVE;
        return 0;
    }

    // Emissions go through the trampoline, never the hooked entry point.
    g_emit = (ScQueueFn)g_hkQueue.trampoline;

    ScLog("HOOK: %d/%d installed, mode=%s", installed, expected, ScModeName(mode));
    return installed;
}

// Test-only: point the core at a fake module image and a capture function, with no
// hooks anywhere. src/hooktest.cpp part [7] uses this to drive a whole 36-unit
// fan-out and assert the emitted bytes.
void ScFanoutTestBegin(BYTE* fakeModuleBase, ScQueueFn emit, int budget) {
    if (!g_lockInit) { InitializeCriticalSection(&g_lock); g_lockInit = true; }
    g_base   = fakeModuleBase;
    g_emit   = emit;
    g_mode   = emit ? SC_MODE_FANOUT : SC_MODE_OBSERVE;
    g_budget = budget;
    g_maxUnits = SC_SHADOW_MAX - 1;
    g_verboseCmds = false;
    // Circles OFF for the fan-out tests: ScFanoutOnSelect would otherwise call the
    // engine's sprite primitives, and in a test process those addresses are a fake
    // module image. sc_circles has its own tests, with its own fake primitives.
    ScCirclesInit(fakeModuleBase, false);
    // HUD row likewise inert here; hooktest part [10] drives it with its own fakes.
    ScHudRowInit(fakeModuleBase, false);
    SetDefaultFanoutCmds();
    g_shadowCount = 0;
    g_visibleCount = 0;
    g_accumCount = 0;
    g_shadowVersion = 0;
    g_liveness = true;              // the shipped default; [7] flips it explicitly
    // Task 024. The predicate defaults to "everything is movable" in a test process:
    // there is no engine code at 0x0047B770 in the fake image, and every pre-existing
    // part drives the core with ordinary units, so this keeps them byte-identical.
    // The building-group part overrides it.
    g_buildingGroups = true;
    g_movableFn      = &ScTestAllMovable;
    g_simSlots       = SC_SELECTION_SLOTS;
    g_statStale = 0;
    memset(g_statDrop, 0, sizeof(g_statDrop));
    memset(g_statBGroupRefused, 0, sizeof(g_statBGroupRefused));
    memset(&g_plan, 0, sizeof(g_plan));
    // Task 021: the shadow control groups are session state, so a test that begins a
    // fresh scenario must not inherit the previous one's groups.
    memset(g_group, 0, sizeof(g_group));
    g_statGroupAssign = g_statGroupAdd = g_statGroupRecall = 0;
    g_statGroupWide = g_statGroupDiscard = g_statGroupReset = 0;
    // Task 054: adopt whatever epoch the test harness is currently at, so a part that
    // begins a fresh scenario does not immediately log a drop of the state it just
    // cleared -- and so a part that WANTS a game change asks for one explicitly.
    g_session = ScSessionEpoch();
    g_statSessionDrop = 0;
    // Task 036: the extend override's counters and its engine-call seam. The seam is
    // cleared rather than kept, so a part that forgets to set it faults loudly on the
    // fake image instead of silently reusing the previous part's recorder.
    g_statExtendSeen = g_statExtendAllow = g_statExtendRefuse = 0;
    g_createSelFn = NULL;
}

// Test-only: how many units the plugin holds for a control group, and the module's
// group counters. hooktest part [11] asserts on these so "the group holds 36" and
// "the recall put 36 back" are separate claims.
int ScFanoutGroupCount(int group) {
    if (group < 0 || group >= SC_HOTKEY_GROUPS) return -1;
    FanoutSessionSync();
    return g_group[group].stored ? g_group[group].count : -1;
}

int ScFanoutGroupStat(int which) {
    switch (which) {
        case SC_GROUPSTAT_ASSIGN:  return (int)g_statGroupAssign;
        case SC_GROUPSTAT_ADD:     return (int)g_statGroupAdd;
        case SC_GROUPSTAT_RECALL:  return (int)g_statGroupRecall;
        case SC_GROUPSTAT_WIDE:    return (int)g_statGroupWide;
        case SC_GROUPSTAT_DISCARD: return (int)g_statGroupDiscard;
        case SC_GROUPSTAT_RESET:   return (int)g_statGroupReset;
        case SC_GROUPSTAT_SESSION: FanoutSessionSync(); return (int)g_statSessionDrop;
    }
    return -1;
}

// Test-only: the shadow list's shape, so a test can assert "the recall put N back and
// the engine still holds only 12" without going through the log.
int ScFanoutShadowCount(void)  { FanoutSessionSync(); return g_shadowCount; }
int ScFanoutVisibleCount(void) { FanoutSessionSync(); return g_visibleCount; }
int ScFanoutPlanActiveForTest(void) { FanoutSessionSync(); return g_plan.active ? 1 : 0; }

// Test-only: drive the %SCPLUGIN_FANOUT_LIVENESS% switch without an environment.
// hooktest part [7] uses it to prove that the pre-task-020 gate really does replay a
// damage-killed unit -- an assertion that cannot fail is not evidence that the fixed
// one works.
void ScFanoutTestSetLiveness(bool on) { g_liveness = on; }

// Test-only: supply the movable predicate (task 024). NULL restores "call the engine".
void ScFanoutTestSetMovable(ScMovablePredicate f) { g_movableFn = (ScMovableFn)f; }

void ScFanoutTestSetBuildingGroups(bool on) { g_buildingGroups = on; }

void ScFanoutTestSetCreateSelections(ScCreateSelectionsFn f) {
    g_createSelFn = (ScCreateSelectionFn)f;
}

int ScFanoutExtendStat(int which) {
    switch (which) {
        case SC_EXTEND_SEEN:   return (int)g_statExtendSeen;
        case SC_EXTEND_ALLOW:  return (int)g_statExtendAllow;
        case SC_EXTEND_REFUSE: return (int)g_statExtendRefuse;
        default: return -1;
    }
}

// Test-only: the current chunk size == how many the simulation holds at once.
int ScFanoutSimSlots(void) { return g_simSlots; }

// Test-only: units the building-group append refused, by reason. Separate from
// ScFanoutDroppedFor: that one counts units kept off the WIRE, this one counts units
// kept out of the SELECTION.
int ScFanoutGroupRefusedFor(int why) {
    if (why < 0 || why > SC_DROP_NOTAG) return 0;
    return (int)g_statBGroupRefused[why];
}

// Test-only: how many units the emit gate has dropped, and how many for `why`.
int ScFanoutStaleSkipped(void) { return (int)g_statStale; }
int ScFanoutDroppedFor(int why) {
    if (why < 0 || why > SC_DROP_NOTAG) return 0;
    return (int)g_statDrop[why];
}

// Task 017: snapshot for the HUD row. Same order as storage -- overflow first,
// visible last. Under the lock so a mid-commit copy can never mix two selections.
int ScFanoutCopyShadow(ScShadowInfo* out, int maxOut, int* visibleCount,
                       unsigned* version) {
    if (!g_lockInit) { InitializeCriticalSection(&g_lock); g_lockInit = true; }
    EnterCriticalSection(&g_lock);
    // The HUD row's snapshot syncs too, so the row can never be handed a list from a
    // game that has ended -- and the `version` it reads back below is the one the sync
    // bumps, which is what makes the change visible to a consumer that only watches it.
    FanoutSessionSync();
    int n = g_shadowCount < maxOut ? g_shadowCount : maxOut;
    for (int i = 0; i < n; ++i) {
        out[i].unit       = g_shadow[i].ptr;
        out[i].uniqueness = g_shadow[i].uniqueness;
        out[i].player     = g_shadow[i].player;
    }
    if (visibleCount) *visibleCount = g_visibleCount;
    if (version)      *version      = g_shadowVersion;
    LeaveCriticalSection(&g_lock);
    return n;
}

void ScFanoutRemove(void) {
    if (g_mode == SC_MODE_OBSERVE && !g_hkQueue.installed) return;

    // NOTE: our circles are deliberately NOT taken off here.
    //
    // This runs on the FreeLibrary path, on the UNLOADER's thread. The engine is alive
    // -- which is why an earlier draft called ScCirclesHide() here -- but "alive" is a
    // liveness answer to a concurrency question. 0x004975D0 unlinks an image from the
    // sprite's overlay list and pushes it onto the image free list, and the game's own
    // thread may be walking exactly those lists to render the frame. Worse, the
    // 0x0049AE40 hook is still installed at this point, so the game thread can be
    // inside ScCirclesHide() concurrently with this one.
    //
    // Everything in sc_circles.cpp is therefore GAME-THREAD-ONLY, and unloading the
    // plugin mid-game is documented as unsupported (tools/plugin/README.md, off switch
    // 3). The circles that stay behind are self-healing rather than permanent: the
    // engine's own unit-removal path calls 0x004975D0 on death
    // (research/selection-circles.md 4.5), and 0x00497620 takes the circle off the next
    // time that unit is selected and deselected.
    ScLog("CIRCLES: %d circle(s) left attached -- unloading mid-game does not remove "
          "them (see tools/plugin/README.md, off switch 3)", ScCirclesCount());

    ScHookSuspendThreads();
    ScQueueIndRemoveHooks();
    ScHudRowRemoveHooks();
    ScCirclesRemoveHook();
    ScHookRemove(&g_hkSort);
    ScHookRemove(&g_hkOverflow);
    ScHookRemove(&g_hkSelect);
    ScHookRemove(&g_hkQueue);
    ScHookResumeThreads();
}

void ScFanoutLogStats(void) {
    if (g_mode == SC_MODE_OBSERVE) return;
    ScLog("STATS mode=%s commands=%u selects=%u overflowCalls=%u fanouts=%u pairs=%u "
          "deferred=%u staleSkipped=%u (recycled=%u hp0=%u foreign=%u nosprite=%u "
          "removed=%u notag=%u) liveness=%d",
          ScModeName(g_mode), g_statCommands, g_statSelects, g_statOverflow,
          g_statFanouts, g_statPairs, g_statDeferred, g_statStale,
          g_statDrop[SC_DROP_RECYCLED], g_statDrop[SC_DROP_DEAD],
          g_statDrop[SC_DROP_FOREIGN], g_statDrop[SC_DROP_NOSPRITE],
          g_statDrop[SC_DROP_REMOVED], g_statDrop[SC_DROP_NOTAG], g_liveness ? 1 : 0);
    // Task 021's control groups, on their own line so the STATS line above keeps the
    // shape every existing reader was written against.
    {
        char held[SC_HOTKEY_GROUPS * 8 + 4];
        int used = 0;
        held[0] = '\0';
        for (int i = 0; i < SC_HOTKEY_GROUPS; ++i) {
            used += _snprintf(held + used, sizeof(held) - used, "%s%d:%d",
                              i ? " " : "", i, g_group[i].stored ? g_group[i].count : -1);
        }
        ScLog("GROUPSTATS assign=%u add=%u recall=%u wide=%u discarded=%u reset=%u "
              "held=[%s]  (held -1 = never stored this session)",
              g_statGroupAssign, g_statGroupAdd, g_statGroupRecall, g_statGroupWide,
              g_statGroupDiscard, g_statGroupReset, held);
    }
    ScCirclesLogStats();
    ScHudRowLogStats();
    ScQueueIndLogStats();
}

// The oracle for "did the order reach every unit". Walks the shadow list -- which is the
// whole pre-cap selection, not the twelve the engine holds -- and reports what each unit
// is actually doing, as a histogram so one line covers any group size.
//
// READS ONLY. It runs on the observer thread, not the game thread, so it must not touch
// anything the game could be mid-write on: the two fields it reads are single bytes/dwords
// of unit state, and a torn read would at worst mis-bucket one unit in one line. Nothing
// here is on the game's own code path.
void ScFanoutLogUnitStates(const char* tag) {
    if (g_mode == SC_MODE_OBSERVE) return;
    if (!g_lockInit) return;

    EnterCriticalSection(&g_lock);
    // The oracle syncs too. It walks the shadow list and dereferences every entry, so
    // a stale list here would be a read through pointers belonging to another game --
    // and it is also the line a suite reads to decide what the plugin is holding.
    FanoutSessionSync();

    WORD     orderKey[32], order2Key[32], typeKey[32];
    unsigned orderCnt[32], order2Cnt[32], typeCnt[32];
    int      orderN = 0, order2N = 0, typeN = 0;
    int      live = 0, burrowed = 0, uniqOnly = 0, circled = 0;
    int      orderOverflow = 0, order2Overflow = 0, typeOverflow = 0;
    // Task 022. A cost-bearing ability is a two-sided claim -- every unit gains the
    // effect AND every unit pays -- so the oracle has to carry both halves per unit,
    // over the same shadow walk. Histograms, not sums: "the group lost 240 HP" is
    // satisfied by one unit losing 240, and that is exactly the confusion this line
    // exists to rule out.
    //   hp     CUnit+0x08, the field the damage primitive 0x004797B0 subtracts from
    //          (sc_addresses.h). 32-bit: a 2500-HP building overflows a WORD key.
    //   stim   CUnit+0x115, set to 0x25 by the 0x36 handler 0x004C2F30 (task 022,
    //          research/ability-semantics.md 2).
    //   energy CUnit+0xA2, the field 0x00491B30 deducts from for the 0x21 family.
    //   rally  CUnit+0xF8/+0xFA packed (x << 16) | y -- a building's rally point, the
    //          one order a plain right-click gives a building (task 024). 32-bit for
    //          the same reason: two 16-bit map coordinates do not fit a WORD key.
    DWORD    hpKey[32], rallyKey[32];
    unsigned hpCnt[32], rallyCnt[32];
    int      hpN = 0, hpOverflow = 0;
    int      rallyN = 0, rallyOverflow = 0;
    WORD     stimKey[32], energyKey[32];
    unsigned stimCnt[32], energyCnt[32];
    int      stimN = 0, energyN = 0, stimOverflow = 0, energyOverflow = 0;
    int      stimmed = 0;
    int      why[SC_DROP_NOTAG + 1];
    for (int i = 0; i <= SC_DROP_NOTAG; ++i) why[i] = 0;

    // Two accumulators, same shape: histogram `key` into (keys, counts, n). The 32-bit
    // one exists only because hit points do not fit a WORD key -- a 2500-hit-point
    // building reads 0xA0000 -- and silently truncating them would merge units that are
    // not in the same state.
    struct Hist32 {
        static void Add(DWORD key, DWORD* keys, unsigned* counts, int* n, int cap, int* overflow) {
            for (int j = 0; j < *n; ++j) if (keys[j] == key) { ++counts[j]; return; }
            if (*n >= cap) { ++*overflow; return; }
            keys[*n] = key;
            counts[*n] = 1;
            ++*n;
        }
        static int Format(char* out, int cap, const DWORD* keys, const unsigned* counts, int n) {
            int used = 0;
            out[0] = '\0';
            for (int j = 0; j < n && used + 20 < cap; ++j) {
                used += _snprintf(out + used, (size_t)(cap - used), "%s0x%X:%u",
                                  j ? " " : "", (unsigned)keys[j], counts[j]);
            }
            return used;
        }
    };

    struct Hist {
        static void Add(WORD key, WORD* keys, unsigned* counts, int* n, int cap, int* overflow) {
            for (int j = 0; j < *n; ++j) if (keys[j] == key) { ++counts[j]; return; }
            if (*n >= cap) { ++*overflow; return; }
            keys[*n] = key;
            counts[*n] = 1;
            ++*n;
        }
        static int Format(char* out, int cap, const WORD* keys, const unsigned* counts, int n) {
            int used = 0;
            out[0] = '\0';
            for (int j = 0; j < n && used + 14 < cap; ++j) {
                used += _snprintf(out + used, (size_t)(cap - used), "%s0x%02X:%u",
                                  j ? " " : "", keys[j], counts[j]);
            }
            return used;
        }
    };

    for (int i = 0; i < g_shadowCount; ++i) {
        // BOTH numbers, from the same read of the same list: `uniqOnly` is what the
        // pre-task-020 test (CUnit+0xA5 alone) would have said, `live` is what the
        // gate says now. A damage death separates them, and that gap is the oracle
        // the in-game fixture asserts on.
        //
        // The per-reason counters below are FIRST-FAILING-TERM, not independent: a
        // unit that is both dead and already unlinked is charged to `hp0`, because
        // hitpoints is tested first. So `removed=0` next to `hp0=1` does NOT mean the
        // unit is still in its player's list -- read the per-unit `FANOUT stale drop`
        // line for that (it reports every field).
        if (SameUnit(&g_shadow[i])) ++uniqOnly;
        int w = SC_LIVE_OK;
        if (!UnitLive(&g_shadow[i], &w)) { ++why[w]; continue; }
        ++live;
        DWORD flags = *(DWORD*)(g_shadow[i].ptr + SC_CUNIT_OFF_FLAGS);
        if (flags & SC_UNIT_FLAG_BURROWED) ++burrowed;
        // Task 024: does this unit have a SELECTION CIRCLE right now? Sprite flag 0x01
        // means "a circle image (0x231..0x23A) is attached to this sprite" -- the engine
        // sets it for the units it selected and sc_circles sets it for the ones past the
        // cap, so ONE count covers both and a >12 building group can assert that every
        // building is circled rather than only that our own share of them is. The unit
        // passed UnitLive above, so its sprite pointer is non-NULL.
        if (*(BYTE*)(*(DWORD*)(g_shadow[i].ptr + SC_CUNIT_OFF_SPRITE) + SC_CSPRITE_OFF_FLAGS)
                & SC_SPRITE_FLAG_SEL_CIRCLE) ++circled;
        BYTE stim = *(BYTE*)(g_shadow[i].ptr + SC_CUNIT_OFF_STIM_TIMER);
        if (stim) ++stimmed;
        Hist32::Add(*(DWORD*)(g_shadow[i].ptr + SC_CUNIT_OFF_HITPOINTS),
                    hpKey, hpCnt, &hpN, 32, &hpOverflow);
        Hist::Add(stim, stimKey, stimCnt, &stimN, 32, &stimOverflow);
        Hist::Add(*(WORD*)(g_shadow[i].ptr + SC_CUNIT_OFF_ENERGY),
                  energyKey, energyCnt, &energyN, 32, &energyOverflow);
        Hist::Add(*(BYTE*)(g_shadow[i].ptr + SC_CUNIT_OFF_ORDER_ID),
                  orderKey, orderCnt, &orderN, 32, &orderOverflow);
        Hist::Add(*(BYTE*)(g_shadow[i].ptr + SC_CUNIT_OFF_ORDER2_ID),
                  order2Key, order2Cnt, &order2N, 32, &order2Overflow);
        Hist::Add(*(WORD*)(g_shadow[i].ptr + SC_CUNIT_OFF_UNIT_ID),
                  typeKey, typeCnt, &typeN, 32, &typeOverflow);
        // Task 024: the RALLY POINT, packed (x << 16) | y so one histogram bucket
        // means "every one of these units is rallied to the same map point". That is
        // the oracle for "a building-valid order reached all N": the Right Click
        // applier 0x004560D0 writes CUnit+0xF8/+0xFA per building, and a fan-out that
        // reached only some of them shows up as two buckets, not as a smaller total.
        Hist32::Add(((DWORD)*(WORD*)(g_shadow[i].ptr + SC_CUNIT_OFF_RALLY_X) << 16) |
                    (DWORD)*(WORD*)(g_shadow[i].ptr + SC_CUNIT_OFF_RALLY_Y),
                    rallyKey, rallyCnt, &rallyN, 32, &rallyOverflow);
    }

    char orders[256], orders2[256], types[256];
    int used = Hist::Format(orders, (int)sizeof(orders), orderKey, orderCnt, orderN);
    if (orderOverflow) _snprintf(orders + used, sizeof(orders) - used, " +%d-more", orderOverflow);
    used = Hist::Format(orders2, (int)sizeof(orders2), order2Key, order2Cnt, order2N);
    if (order2Overflow) _snprintf(orders2 + used, sizeof(orders2) - used, " +%d-more", order2Overflow);
    used = Hist::Format(types, (int)sizeof(types), typeKey, typeCnt, typeN);
    if (typeOverflow) _snprintf(types + used, sizeof(types) - used, " +%d-more", typeOverflow);

    char hp[320], stims[256], energies[256], rally[320];
    used = Hist32::Format(hp, (int)sizeof(hp), hpKey, hpCnt, hpN);
    if (hpOverflow) _snprintf(hp + used, sizeof(hp) - used, " +%d-more", hpOverflow);
    used = Hist32::Format(rally, (int)sizeof(rally), rallyKey, rallyCnt, rallyN);
    if (rallyOverflow) _snprintf(rally + used, sizeof(rally) - used, " +%d-more", rallyOverflow);
    used = Hist::Format(stims, (int)sizeof(stims), stimKey, stimCnt, stimN);
    if (stimOverflow) _snprintf(stims + used, sizeof(stims) - used, " +%d-more", stimOverflow);
    used = Hist::Format(energies, (int)sizeof(energies), energyKey, energyCnt, energyN);
    if (energyOverflow) _snprintf(energies + used, sizeof(energies) - used, " +%d-more", energyOverflow);

    // The trailing fields are appended, never inserted: drive-game.ps1's parser
    // matches the leading run of fields and is not anchored at the end, so a reader
    // written against the task-015 line still works.
    ScLog("UNITSTATE [%s] n=%d live=%d visible=%d overflow=%d orders=[%s] orders2=[%s] "
          "types=[%s] burrowed=%d/%d uniqOnly=%d recycled=%d hp0=%d foreign=%d "
          "nosprite=%d removed=%d staleSkipped=%u liveness=%d stimmed=%d/%d "
          "hp=[%s] stim=[%s] energy=[%s] simSlots=%d rally=[%s] circled=%d/%d",
          tag ? tag : "-", g_shadowCount, live, g_visibleCount,
          g_shadowCount - g_visibleCount, orders, orders2, types, burrowed, live,
          uniqOnly, why[SC_DROP_RECYCLED], why[SC_DROP_DEAD], why[SC_DROP_FOREIGN],
          why[SC_DROP_NOSPRITE], why[SC_DROP_REMOVED], g_statStale, g_liveness ? 1 : 0,
          stimmed, live, hp, stims, energies, g_simSlots, rally, circled, live);

    LeaveCriticalSection(&g_lock);
}

void ScFanoutLogState(void) {
    if (g_mode == SC_MODE_OBSERVE) return;
    ScLog("SHADOW state: session=%u %d units (%d visible) accum=%d planActive=%d | "
          "commands=%u selects=%u overflowCalls=%u fanouts=%u pairs=%u sessionDrops=%u",
          g_session, g_shadowCount, g_visibleCount, g_accumCount, g_plan.active ? 1 : 0,
          g_statCommands, g_statSelects, g_statOverflow, g_statFanouts, g_statPairs,
          g_statSessionDrop);
}
