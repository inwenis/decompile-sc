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
    // Stage A: ONE hook (queueCommand), logs only, no behaviour change. The
    // %SCPLUGIN_MODE% string for it is still "hooktest", which is a launcher flag
    // in ten .ps1 files and cannot move -- but it has nothing to do with
    // hooktest.exe, the OFFLINE unit test that runs with no game at all.
    SC_MODE_LOGONLY  = 1,
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

// ---------------------------------------------------------------------------
// Same-type building groups (task 024: a drag box over N buildings selects all N)
//
// The client-side half is hook-free for the same reason the rest of the core is:
// "what does a box full of buildings turn into" is decidable from the candidate list
// and the engine's 12-slot output alone, so it is driven and asserted offline.
// ---------------------------------------------------------------------------

// The engine's unit_IsStandardAndMovable (0x0047B770) -- ECX = CUnit*, returns 0/1.
typedef int (__attribute__((fastcall)) *ScMovablePredicate)(unsigned long unit);

// Given SortAllUnits' own arguments and the count it returned, the count the engine
// should use instead. Returns `ret` unchanged unless this is a drag box (clicked == 0)
// whose result is the engine's one-building fallback, in which case it appends the rest
// of that building's same-type same-owner group to `out` (max 12) and puts any beyond
// the twelfth into the overflow accumulator.
unsigned ScFanoutGrowBuildingGroup(unsigned long* candidates, unsigned long* out,
                                   unsigned long clicked, unsigned ret);

// Test-only: supply the movable predicate instead of calling into the game. A test
// process has no engine code at 0x0047B770 -- only a fake image -- so every test that
// drives the core sets this. Passing NULL restores "call the engine".
void ScFanoutTestSetMovable(ScMovablePredicate f);

// Test-only: drive %SCPLUGIN_BUILDING_GROUPS% directly, so the OFF arm can be asserted
// offline as well as in game. ScFanoutTestBegin leaves it ON, the shipped default.
void ScFanoutTestSetBuildingGroups(bool on);

// Test-only: how many units of the current selection the simulation will hold at once,
// which is also the fan-out's chunk size. 12 for units, 1 for a building group.
int ScFanoutSimSlots(void);

// ---------------------------------------------------------------------------
// EXTENDING a building group (task 036: shift-click, shift+box, shift+ctrl-click)
//
// The paths that extend a selection rather than replace it do not go through
// SortAllUnits at all -- one is a basic block inside the click handler, the other has a
// register-passed destination list -- so what is detoured is the PREDICATE they both
// consult, scoped to the four instruction addresses that consult it on their behalf
// (sc_addresses.h SC_RET_MOVABLE_*). This is the decision half, callable with no hook
// installed and no game in the process.
//
//   unit     the CUnit* the engine asked about (its ECX).
//   retAddr  where the CALL would have returned to. Anything outside the four
//            allowlisted sites gets `verdict` back untouched -- there is no other
//            consumer of this override anywhere in the binary.
//   verdict  what the engine's own predicate answered.
//
// Returns what the caller should see. It differs from `verdict` only when the lead of
// the selection being extended (activePlayerSelection[0]) is a BUILDING -- the case in
// which vanilla refuses the whole operation one call site earlier -- and then the answer
// is "same type and same owner as that lead, and alive".
extern "C" int ScFanoutMovableDecide(unsigned long unit, unsigned long retAddr, int verdict);

// Test-only: stand in for CreateNewUnitSelectionsFromList (0x0049AE40), which a control
// group of buildings is re-installed into the engine's client selection with. A test
// process has no engine code there, only a fake image. NULL restores "call the engine".
typedef void (*ScCreateSelectionsFn)(unsigned long* list, int count);
void ScFanoutTestSetCreateSelections(ScCreateSelectionsFn f);

// Test-only: the extend override's own counters -- calls that reached one of the four
// sites with a building lead, and how that split into allow/refuse.
enum ScExtendStat { SC_EXTEND_SEEN = 0, SC_EXTEND_ALLOW = 1, SC_EXTEND_REFUSE = 2 };
int ScFanoutExtendStat(int which);

// Test-only: units the building-group append refused, by ScFanoutDrop reason. Counted
// apart from ScFanoutDroppedFor because they are refused a place in the SELECTION, not
// a place on the wire -- they never reach a fan-out plan at all.
int ScFanoutGroupRefusedFor(int why);

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
    SC_GROUPSTAT_RESET   = 5,   // groups dropped because the engine restarted a game
    // Task 054: times the GAME-SESSION EPOCH (sc_session.h) threw this module's
    // cross-frame state away. Separate from RESET because RESET is an INFERENCE from
    // the engine's own hotkey row being empty, and a save/load restores that row
    // NON-empty with the same pointers in it -- so RESET cannot fire on the one case
    // this counter exists for.
    SC_GROUPSTAT_SESSION = 6
};

// Test-only: units the plugin holds for control group `group` (0..9), or -1 if that
// group has never been stored in this session (which is NOT the same as holding 0).
int ScFanoutGroupCount(int group);
int ScFanoutGroupStat(int which);

// Test-only: the shadow list's shape right now -- total, and how many of the TAIL
// entries the engine itself holds.
int ScFanoutShadowCount(void);
int ScFanoutVisibleCount(void);

// Test-only: is a fan-out still part-emitted, waiting for the next command to finish it
// (issue #67 item 2)? 1 = yes. Exposed for task 054, because "the deferred plan does not
// cross into another game" is a claim about a state the emitted bytes cannot show:
// a plan that never drains and a plan that was dropped both emit nothing.
int ScFanoutPlanActiveForTest(void);

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
