// sc_fanout.h -- shadow selection + command fan-out.
//
// The mechanism (research/selection-cap.md 7, candidate #1): keep a plugin-side
// selection list of arbitrary size, captured before the engine's 12-cap discards
// the rest; when the player issues an order, emit it as a series of
// Select(<=12) + order pairs. The engine's own cap is never raised.

#ifndef SC_FANOUT_H
#define SC_FANOUT_H

#include <windows.h>

enum ScMode {
    SC_MODE_OBSERVE  = 0,  // task 008 behaviour: read-only, no hooks, no writes
    SC_MODE_HOOKTEST = 1,  // stage A: ONE hook (queueCommand), logs only
    SC_MODE_SHADOW   = 2,  // stage B: capture the untruncated selection, log it
    SC_MODE_FANOUT   = 3   // stage C: fan orders out across the whole shadow list
};

// Reads %SCPLUGIN_MODE%. Unset or unrecognised -> SC_MODE_OBSERVE, which is the
// off switch: in that mode nothing in this file runs and no game memory is written.
ScMode      ScFanoutResolveMode(void);
const char* ScModeName(ScMode m);

// Installs the hooks the mode calls for. Returns the number installed.
// `moduleBase` is StarCraft.exe's actual load address.
int  ScFanoutInstall(BYTE* moduleBase, ScMode mode);
void ScFanoutRemove(void);

// One line describing the current shadow list, for the observer's log.
void ScFanoutLogState(void);

// One line describing what the SHADOW UNITS ARE DOING: a histogram of their current
// order ids and how many are in the burrowed/submerged state. This is the oracle for
// "did the order actually reach all 36 of them" -- the log tells the test what every
// unit's order byte is, so an unattended run can assert on all of them without seeing
// the screen. `tag` is echoed into the line so a run can be read back case by case.
void ScFanoutLogUnitStates(const char* tag);

// One STATS line. Written on BOTH detach paths -- including process exit, where the
// hooks are deliberately left spliced (the address space is going away) but the run's
// counters are still the thing a reader needs.
void ScFanoutLogStats(void);

// ---------------------------------------------------------------------------
// The fan-out core, hook-free.
//
// The four detours below do nothing but marshal arguments into these three
// functions. Splitting them out means the interesting half -- chunking, tag
// encoding, emission order, staleness, the byte budget -- can be driven and
// asserted byte-for-byte from a test process with no StarCraft and no hooks
// (src/hooktest.cpp part [7]). What is left untestable offline is only whether the
// ENGINE obeys the commands, which is what the human test is for.
// ---------------------------------------------------------------------------

// Where emitted commands go. In the game this is the queueCommand trampoline; in a
// test it is a capture buffer.
typedef void (__attribute__((fastcall)) *ScQueueFn)(const void*, unsigned);

// One unit the 12-cap is discarding, plus the 12-slot array as it stands BEFORE the
// engine's handler runs (that handler can evict an entry, and the evicted unit would
// otherwise be lost from both the output and our record).
void ScFanoutOnOverflow(unsigned count, unsigned long* outList, unsigned long unit);

// The engine's final, truncated selection, at the moment it is committed.
void ScFanoutOnSelect(unsigned count, unsigned long* units);

// One outgoing command. Returns true if it was FANNED OUT and the caller must
// therefore suppress the engine's own copy.
bool ScFanoutOnCommand(const unsigned char* buf, unsigned len);

// Point the core at a fake module image and a capture function. Test-only; passing
// a NULL emit restores normal operation. Resets the liveness switch to its shipped
// default (ON) and zeroes the drop counters.
void ScFanoutTestBegin(unsigned char* fakeModuleBase, ScQueueFn emit, int budget);

// Why a unit was refused a place in an emitted Select. Mirrors ScDropWhy in
// sc_fanout.cpp; hooktest asserts on the individual reasons so "it was dropped"
// and "it was dropped for the right reason" are different failures.
enum ScFanoutDrop {
    SC_FANOUT_LIVE     = 0,
    SC_FANOUT_RECYCLED = 1,   // CUnit+0xA5 moved -- the slot holds a different unit
    SC_FANOUT_DEAD     = 2,   // hitpoints == 0 -- a damage death, slot not recycled
    SC_FANOUT_FOREIGN  = 3,   // CUnit+0x4C changed -- no longer this player's unit
    SC_FANOUT_NOSPRITE = 4,   // CUnit+0x0C == 0 -- nothing for the receive path to deref
    SC_FANOUT_REMOVED  = 5,   // not reachable from playerUnitList[player]
    SC_FANOUT_NOTAG    = 6    // the pointer does not encode to a wire tag
};

// Test-only: drive %SCPLUGIN_FANOUT_LIVENESS% directly. `false` is the pre-task-020
// gate (uniqueness alone) and is a known-bad configuration -- it exists so the
// defect can be reproduced deliberately.
void ScFanoutTestSetLiveness(bool on);

// Test-only counters: units dropped from emitted Selects, in total and by reason.
int ScFanoutStaleSkipped(void);
int ScFanoutDroppedFor(int why);

// ---------------------------------------------------------------------------
// Shadow control groups (task 021: Ctrl+N stores more than 12, N brings them back)
//
// There is no install/enable entry point here on purpose: the feature lives entirely
// inside ScFanoutOnCommand's handling of wire command 0x13, so it adds no hook, patches
// no game code, and writes no byte of the engine's own control-group storage. It only
// READS selectionHotkeys (0x0057FE60), to notice that the engine has restarted a game
// underneath it. The mechanism, and the evidence for every address, is in
// research/control-groups.md.
// ---------------------------------------------------------------------------

// Which group counter ScFanoutGroupStat returns.
enum ScGroupStat {
    SC_GROUPSTAT_ASSIGN  = 0,   // Ctrl+N stores
    SC_GROUPSTAT_ADD     = 1,   // shift-adds into a group
    SC_GROUPSTAT_RECALL  = 2,   // N recalls
    SC_GROUPSTAT_WIDE    = 3,   // recalls that put back MORE than the engine's 12
    SC_GROUPSTAT_DISCARD = 4,   // recalls whose group failed the containment check
    SC_GROUPSTAT_RESET   = 5    // groups dropped because the engine restarted a game
};

// Test-only: units the plugin holds for control group `group` (0..9), or -1 if that
// group has never been stored in this session (which is NOT the same as holding 0).
int ScFanoutGroupCount(int group);
int ScFanoutGroupStat(int which);

// Test-only: the shadow list's shape right now -- total, and how many of the TAIL
// entries the engine itself holds.
int ScFanoutShadowCount(void);
int ScFanoutVisibleCount(void);

// ---------------------------------------------------------------------------
// Shadow-list snapshot (task 017: the HUD row pages through this list)
// ---------------------------------------------------------------------------

struct ScShadowInfo {
    unsigned long unit;         // CUnit*, bounds/stride-validated at capture time
    unsigned char uniqueness;   // CUnit+0xA5 at capture -- the staleness test
    unsigned char player;       // CUnit+0x4C at capture
};

// Copies the current shadow list under the fan-out lock: OVERFLOW UNITS FIRST,
// the engine's visible (<=12) units LAST -- the same order sc_fanout stores it.
// Returns the number copied; *visibleCount gets how many of the TAIL entries the
// engine actually holds; *version gets a counter that increments on every
// selection commit (and on the hotkey-recall shadow drop), so a caller can detect
// "the selection changed" without diffing lists.
int ScFanoutCopyShadow(ScShadowInfo* out, int maxOut, int* visibleCount,
                       unsigned* version);

#endif // SC_FANOUT_H
