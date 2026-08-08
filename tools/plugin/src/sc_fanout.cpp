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

#include <windows.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#include "sc_addresses.h"
#include "sc_circles.h"
#include "sc_fanout.h"
#include "sc_hook.h"
#include "sc_hudrow.h"
#include "sc_log.h"

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

// Reads a unit's identity fields. The unit array is a fixed 1700-entry global, so
// an in-range pointer is always readable -- but the pointer itself is validated
// against the array's bounds and stride first, because a bad one would otherwise
// be dereferenced.
static bool ReadUnit(DWORD ptr, ShadowUnit* out) {
    if (!ptr) return false;
    DWORD arrayBase = (DWORD)Rt(SC_VA_UNIT_ARRAY_BASE);
    if (ptr < arrayBase) return false;
    DWORD off = ptr - arrayBase;
    if (off % SC_CUNIT_SIZE != 0) return false;
    DWORD index = off / SC_CUNIT_SIZE + 1;     // the wire index is 1-based
    if (index > SC_MAX_UNIT_INDEX) return false;
    out->ptr        = ptr;
    out->uniqueness = *(BYTE*)(ptr + SC_CUNIT_OFF_UNIQUENESS);
    out->player     = *(BYTE*)(ptr + SC_CUNIT_OFF_PLAYER);
    return true;
}

// index+uniqueness packed exactly as CMDACT_Select / the Right Click builder /
// the Targeted Order builder all do it. Returns 0 for anything out of range,
// which is what the engine encodes too.
static WORD UnitTag(DWORD ptr) {
    if (!ptr) return 0;
    DWORD arrayBase = (DWORD)Rt(SC_VA_UNIT_ARRAY_BASE);
    if (ptr < arrayBase) return 0;
    DWORD off = ptr - arrayBase;
    if (off % SC_CUNIT_SIZE != 0) return 0;
    DWORD index = off / SC_CUNIT_SIZE + 1;
    if (index > SC_MAX_UNIT_INDEX) return 0;
    BYTE uniq = *(BYTE*)(ptr + SC_CUNIT_OFF_UNIQUENESS);
    return (WORD)(((WORD)uniq << 11) | (WORD)index);
}

// Still the same unit it was when we recorded it? Same test the engine applies to
// its own stored tags.
static bool StillAlive(const ShadowUnit* u) {
    if (!u->ptr) return false;
    return *(BYTE*)(u->ptr + SC_CUNIT_OFF_UNIQUENESS) == u->uniqueness;
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
static unsigned g_statStale      = 0;

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
    int        chunkCount;
    int        nextChunk;
};

static Plan g_plan;

static int ChunkBounds(const Plan* p, int chunk, int* start, int* len) {
    const int overflow = p->count - p->visibleCount;
    const int overflowChunks = (overflow + SC_SELECTION_SLOTS - 1) / SC_SELECTION_SLOTS;
    if (chunk < overflowChunks) {
        *start = chunk * SC_SELECTION_SLOTS;
        int remain = overflow - *start;
        *len = remain < SC_SELECTION_SLOTS ? remain : SC_SELECTION_SLOTS;
        return 1;
    }
    if (chunk == overflowChunks) {          // the visible chunk, always emitted last
        *start = overflow;
        *len   = p->visibleCount;
        return 1;
    }
    return 0;
}

// Queues one vanilla Select (0x09) for the given units. Returns bytes queued, or 0
// if nothing survived the staleness check.
static int EmitSelect(const ShadowUnit* units, int n) {
    BYTE buf[2 + SC_SELECTION_SLOTS * 2];
    int  live = 0;
    for (int i = 0; i < n && live < SC_SELECTION_SLOTS; ++i) {
        if (!StillAlive(&units[i])) { ++g_statStale; continue; }
        WORD tag = UnitTag(units[i].ptr);
        if (!tag) { ++g_statStale; continue; }
        buf[2 + live * 2]     = (BYTE)(tag & 0xFF);
        buf[2 + live * 2 + 1] = (BYTE)(tag >> 8);
        ++live;
    }
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

    const int overflow = g_plan.count - g_plan.visibleCount;
    g_plan.chunkCount = (overflow + SC_SELECTION_SLOTS - 1) / SC_SELECTION_SLOTS + 1;
    g_plan.nextChunk  = 0;
    g_plan.active     = true;
    ++g_statFanouts;

    ScLog("FANOUT start: cmd=0x%02X len=%d units=%d (visible %d + overflow %d) "
          "-> %d Select+order pairs",
          order[0], orderLen, g_plan.count, g_plan.visibleCount, overflow,
          g_plan.chunkCount);

    if (DrainPlan() > 0) return true;

    ScLog("FANOUT abandoned: no pair could be emitted (turn buffer full, or every "
          "captured unit is stale) -- letting the engine's own command through");
    g_plan.active = false;
    return false;
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

    // A control-group recall rebuilds the selection on the receiving side without
    // going through CMDACT_Select, so our shadow list would silently go stale.
    // Drop it rather than fan out something the player is no longer holding.
    if (id == SC_CMD_HOTKEY && g_shadowCount > g_visibleCount) {
        ScLog("SHADOW dropped: hotkey command 0x13 rebuilds the selection elsewhere");
        g_shadowCount = g_visibleCount;
        ++g_shadowVersion;
    }

    // Finish any plan left over from a previous turn before adding to the buffer.
    DrainPlan();

    bool suppress = false;
    if (g_mode == SC_MODE_FANOUT &&
        IsFanoutCmd(id) &&
        g_shadowCount > SC_SELECTION_SLOTS &&
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
            if (!StillAlive(&g_accum[i])) continue;
            if (visibleCount > 0 && g_accum[i].player != visible[0].player) continue;
            g_shadow[g_shadowCount++] = g_accum[i];
            ++added;
        }
    }
    // Visible units go LAST, so the final Select+order pair of a fan-out leaves the
    // simulation holding exactly what the player can see.
    for (int i = 0; i < visibleCount && g_shadowCount < SC_SHADOW_MAX; ++i) {
        g_shadow[g_shadowCount++] = visible[i];
    }
    g_visibleCount = visibleCount;
    ++g_shadowVersion;

    if (added > 0) {
        ScLog("SHADOW captured: %d units (%d visible + %d beyond the cap) "
              "[accum had %d]", g_shadowCount, visibleCount, added, g_accumCount);
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
    // the player can see.
    {
        const int overflow = g_shadowCount - g_visibleCount;
        if (ScCirclesEnabled() && overflow > 0) {
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
    }

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

static unsigned __attribute__((stdcall)) SC_GAME_ENTRY
HkSortAllUnits(DWORD* candidates, DWORD* out, DWORD clicked) {
    int candCount = 0;
    if (candidates) {
        while (candidates[candCount] != 0 && candCount < 4096) ++candCount;
    }
    unsigned ret = ((SortAllUnitsFn)g_hkSort.trampoline)(candidates, out, clicked);
    ScLog("SORT candidates=%d -> selected=%u (accumulated beyond the cap: %d)",
          candCount, ret, g_accumCount);
    return ret;
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

    g_budget      = EnvInt("SCPLUGIN_FANOUT_BUDGET", SC_DEFAULT_BUDGET, 40, 480);
    g_maxUnits    = EnvInt("SCPLUGIN_MAX_UNITS", SC_SHADOW_MAX - 1, 12, SC_SHADOW_MAX - 1);
    g_verboseCmds = EnvInt("SCPLUGIN_LOG_COMMANDS", 1, 0, 1) != 0;
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

    char cmds[192];
    int used = 0;
    cmds[0] = '\0';
    for (int i = 0; i < g_fanoutCmdCount && used + 5 < (int)sizeof(cmds); ++i) {
        used += _snprintf(cmds + used, sizeof(cmds) - used, "%s0x%02X",
                          i ? " " : "", g_fanoutCmds[i]);
    }
    ScLog("FANOUT config: mode=%s budget=%dB maxUnits=%d logCommands=%d circles=%d "
          "hudrow=%d cmds=[%s]",
          ScModeName(mode), g_budget, g_maxUnits, g_verboseCmds ? 1 : 0,
          circles ? 1 : 0, hudrow ? 1 : 0, cmds);

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
    }

    // Task 014's one extra hook. It goes in under the same suspension as the rest so
    // a half-installed set is never observable.
    if (circles && ScCirclesInstallHook()) ++installed;

    // Task 017's one dispatcher detour, same suspension. ScHudRowInstallHooks
    // returns 0 or 1.
    if (hudrow) installed += ScHudRowInstallHooks();

    ScHookResumeThreads();

    // A partial install is not a working plugin: the queueCommand hook without the
    // selection hooks would fan out a shadow list nothing ever fills. Roll back.
    // The circle hook counts too -- without it our circles would never come off, and
    // stale circles under units the player has deselected is worse than none. The
    // HUD-row dispatcher detour is one hook.
    const int expected = ((mode >= SC_MODE_SHADOW) ? 4 : 1) + (circles ? 1 : 0)
                       + (hudrow ? 1 : 0);
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
    memset(&g_plan, 0, sizeof(g_plan));
}

// Task 017: snapshot for the HUD row. Same order as storage -- overflow first,
// visible last. Under the lock so a mid-commit copy can never mix two selections.
int ScFanoutCopyShadow(ScShadowInfo* out, int maxOut, int* visibleCount,
                       unsigned* version) {
    if (!g_lockInit) { InitializeCriticalSection(&g_lock); g_lockInit = true; }
    EnterCriticalSection(&g_lock);
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
          "deferred=%u staleSkipped=%u",
          ScModeName(g_mode), g_statCommands, g_statSelects, g_statOverflow,
          g_statFanouts, g_statPairs, g_statDeferred, g_statStale);
    ScCirclesLogStats();
    ScHudRowLogStats();
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

    WORD     orderKey[32], order2Key[32], typeKey[32];
    unsigned orderCnt[32], order2Cnt[32], typeCnt[32];
    int      orderN = 0, order2N = 0, typeN = 0;
    int      live = 0, burrowed = 0;
    int      orderOverflow = 0, order2Overflow = 0, typeOverflow = 0;

    // One accumulator, used twice: histogram `key` into (keys, counts, n).
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
        if (!StillAlive(&g_shadow[i])) continue;
        ++live;
        DWORD flags = *(DWORD*)(g_shadow[i].ptr + SC_CUNIT_OFF_FLAGS);
        if (flags & SC_UNIT_FLAG_BURROWED) ++burrowed;
        Hist::Add(*(BYTE*)(g_shadow[i].ptr + SC_CUNIT_OFF_ORDER_ID),
                  orderKey, orderCnt, &orderN, 32, &orderOverflow);
        Hist::Add(*(BYTE*)(g_shadow[i].ptr + SC_CUNIT_OFF_ORDER2_ID),
                  order2Key, order2Cnt, &order2N, 32, &order2Overflow);
        Hist::Add(*(WORD*)(g_shadow[i].ptr + SC_CUNIT_OFF_UNIT_ID),
                  typeKey, typeCnt, &typeN, 32, &typeOverflow);
    }

    char orders[256], orders2[256], types[256];
    int used = Hist::Format(orders, (int)sizeof(orders), orderKey, orderCnt, orderN);
    if (orderOverflow) _snprintf(orders + used, sizeof(orders) - used, " +%d-more", orderOverflow);
    used = Hist::Format(orders2, (int)sizeof(orders2), order2Key, order2Cnt, order2N);
    if (order2Overflow) _snprintf(orders2 + used, sizeof(orders2) - used, " +%d-more", order2Overflow);
    used = Hist::Format(types, (int)sizeof(types), typeKey, typeCnt, typeN);
    if (typeOverflow) _snprintf(types + used, sizeof(types) - used, " +%d-more", typeOverflow);

    ScLog("UNITSTATE [%s] n=%d live=%d visible=%d overflow=%d orders=[%s] orders2=[%s] "
          "types=[%s] burrowed=%d/%d",
          tag ? tag : "-", g_shadowCount, live, g_visibleCount,
          g_shadowCount - g_visibleCount, orders, orders2, types, burrowed, live);

    LeaveCriticalSection(&g_lock);
}

void ScFanoutLogState(void) {
    if (g_mode == SC_MODE_OBSERVE) return;
    ScLog("SHADOW state: %d units (%d visible) accum=%d planActive=%d | "
          "commands=%u selects=%u overflowCalls=%u fanouts=%u pairs=%u",
          g_shadowCount, g_visibleCount, g_accumCount, g_plan.active ? 1 : 0,
          g_statCommands, g_statSelects, g_statOverflow, g_statFanouts, g_statPairs);
}
