// sc_upgrades.h -- queue more than one upgrade or research at a building.
//
// A building researches one thing at a time because it has ONE FIELD for it: CUnit+0xC9 is
// the upgrade in progress (61 = none), CUnit+0xC8 the tech (44 = none). There is no array to
// widen and no spare byte to widen into, so this module keeps a per-building queue of its own
// and hands items to the engine one at a time (research/upgrade-queue.md 7).
//
// The client will not send the second command by itself. The refusal is requirement opcode
// 0xFF0A inside the interpreter 0x0046D610: `if (unit->0xC9 != 61) { reason = 5; return 0; }`,
// and 0 rather than -1 makes the card layout skip the button entirely instead of greying it
// -- measured with an upgrade running, six presses of the two upgrade buttons put ZERO
// commands on the wire. So the two CARD conditions (0x00429450 upgrade, 0x00429500 tech) are
// detoured to answer as if the building were idle. The GATES are deliberately NOT hooked: the
// building AI calls them too, and a computer player told a busy building is free would start
// an upgrade on top of the running one.

#ifndef SC_UPGRADES_H
#define SC_UPGRADES_H

#include <windows.h>

// Total logical queue length per building, the engine's ONE included; the launcher/env knob
// %SCPLUGIN_UPGQ_MAX% moves it inside [1, SC_UPGQ_HARD_MAX].
//
// 8 because an upgrade is minutes long and expensive: seven held items at an Engineering Bay
// is more upgrades than the building has distinct level-1s to offer, deep enough to walk away
// from and not an amount anyone queues by accident. Memory is not the constraint here -- a
// record is about 40 bytes.
#define SC_UPGQ_DEFAULT_MAX 8
#define SC_UPGQ_HARD_MAX    16
// What the engine itself can hold. One -- named so the arithmetic below reads as arithmetic
// rather than as magic.
#define SC_UPGQ_ENGINE_SLOTS 1
// How many buildings may hold a queue at once. Beyond this a new one is refused and logged,
// rather than evicting somebody else's queue.
#define SC_UPGQ_MAX_BUILDINGS 32

// Which command an item came from. Both kinds share one list per building, in the order the
// player pressed them, because a building that offers both (an Academy) should run them in
// that order. `kind` travels as an int (and as a BYTE inside a record, and as -1 from the
// out-of-range accessors), so the signatures below say int rather than this enum.
enum ScUpgQueueKind {
    SC_UPGQ_KIND_UPGRADE = 0,   // wire 0x32
    SC_UPGQ_KIND_TECH    = 1    // wire 0x30
};

// Reads %SCPLUGIN_UPGQ%. Unset/0 -> disabled, which is the off switch: nothing in this file
// runs, no hook is installed and no game memory is written. `-Mode observe` is a second,
// plugin-wide off switch on top of it: the caller skips the install even when this answers
// true.
bool ScUpgQueueEnabled(void);

// Eight detours: two card conditions, two receive handlers, two order handlers, two
// cancels.
#define SC_UPGQ_HOOK_COUNT 8

// Installs them all under one thread suspension. Returns the number installed (0 or
// SC_UPGQ_HOOK_COUNT); a partial install rolls itself back and disables the feature, because
// unblocking without holding lets the engine overwrite a running upgrade, and holding without
// promoting strands the queue.
int  ScUpgQueueInstall(BYTE* moduleBase);
void ScUpgQueueRemove(void);

// One line per tracked building plus one for the sole selected building, for the observer's
// marker channel. THIS IS THE TEST ORACLE: it prints the building's own
// CUnit+0xC8/0xC9/0xC6/0xCD alongside the plugin's queue, so an unattended run asserts on the
// building's memory rather than on the screen.
void ScUpgQueueLogState(const char* tag);
// One STATS line, written on both detach paths.
void ScUpgQueueLogStats(void);

// ---------------------------------------------------------------------------
// The core is hook-free so it can be driven byte-for-byte from hooktest.exe with no
// StarCraft in sight: the eight detours do nothing but marshal registers into these.
// ---------------------------------------------------------------------------

// A 0x32 / 0x30 command has arrived for `unit`, from cmdrecvUpgrade (0x004C1B20) /
// cmdrecvTech (0x004C1BA0). Returns true when the plugin consumed it -- the building is
// already researching and the queue had room -- and the caller must then SKIP the engine's
// handler entirely. That skip is not optional: neither startUpgrade nor startTech checks
// whether something is already running, so the engine's body would overwrite the running item
// and pay for it.
bool ScUpgQueueOnCommand(DWORD unit, int kind, unsigned id);

// An order handler -- upgradeTick (0x004546A0) / techTick (0x004548B0) -- has just run for
// `unit`. If it has gone idle and the plugin holds items, the oldest is handed to the
// engine's own accept path: gate, then startUpgrade/startTech, then the accept tail. Also
// garbage-collects.
//
// Promotion is the only moment anything is paid for: the ENGINE pays, inside
// startUpgrade/startTech from its own cost tables, so a held item carries no money and this
// module never writes a resource global in either direction -- a claim checked against the
// engine's own resource globals, which the offline and live suites both read. Vanilla unit
// training charges at queue time instead (research/production-queue.md 4.2); paying at start
// makes double payment structurally impossible rather than merely avoided. The cost tables
// and the two globals are read only to compare, so the engine is not asked to replay
// "insufficient minerals" once a frame while the queue waits for income.
void ScUpgQueueOnTick(DWORD unit);

// A 0x33 / 0x31 cancel is about to be handled for `unit`. Returns true when the plugin
// consumed it -- it dropped its own most recently queued item, which is the tail of the
// logical queue and therefore the plugin's to cancel -- and the caller must skip the
// engine's handler. Nothing is refunded because nothing was paid.
bool ScUpgQueueOnCancel(DWORD unit);

// A click on the queue icon drawing held item `index` (0 = promoted next) has arrived as a
// {0x20, k} Cancel Train whose ring slot is empty. Drops that one item and returns true;
// false when the building holds no such item, so the caller can say so. Nothing is
// refunded because nothing was paid.
bool ScUpgQueueCancelAt(DWORD unit, int index);

// Should the card offer research buttons at `unit` even though it is busy? True only when the
// feature is on, the unit is a completed building that is researching, and the logical queue
// is below the maximum. At the cap this simply answers false: the condition then tells the
// truth, the layout hides the button and the client refuses on its own, so the cap is
// enforced by vanilla's own mechanism rather than by anything here.
bool ScUpgQueueShouldUnblock(DWORD unit);

// ONE ENTRY PER RESEARCH PER BUILDING. True when `unit` already holds this id (any position
// of its held queue). The card condition answers 0 -- hidden, exactly vanilla's answer for
// the item that is RUNNING -- and the receive path refuses the command. The running item
// itself needs no help: the engine's own per-player in-progress bit hides its button.
bool ScUpgQueueHolds(DWORD unit, int kind, unsigned id);

// The promotion seam, and the only way an upgrade or tech id ever reaches a building: the
// real one calls the engine's own start function, hooktest replaces it because there is no
// engine in a test process. Returns 1 when the item was started.
typedef int (*ScUpgStartFn)(DWORD unit, int kind, unsigned id);

// Test-only: point the core at a fake module image and a fake starter, and clear all
// state. NULL restores normal operation.
void ScUpgQueueTestBegin(BYTE* fakeModuleBase, int maxTotal, ScUpgStartFn starter);

// Test-only: the building a research RECEIVE handler will act on, resolved the way
// getActivePlayerNextSelection (0x0049A850) resolves it -- playersSelections indexed by
// activePlayerId, NOT the client's own activePlayerSelection. Exposed so the offline suite can
// prove the plugin follows the ENGINE's array with the two arrays disagreeing (same shape as
// sc_prodqueue's ScProdQueueSoleSelectedUnitForTest). 0 = "not a single selected building",
// i.e. the plugin has no business in this command.
DWORD ScUpgQueueSoleSelectedUnitForTest(void);

// Test-only read-back.
int  ScUpgQueueCount(DWORD unit);          // -1 when the building is not tracked
int  ScUpgQueueKindAt(DWORD unit, int i);  // -1 out of range
int  ScUpgQueueIdAt(DWORD unit, int i);    // -1 out of range
int  ScUpgQueueTrackedBuildings(void);

// Test-only counters, in the same order ScUpgQueueLogStats prints them. No spend counter
// belongs among them: this module only ever reads the two resource globals -- to compare and
// to log -- so a spend counter here could only ever read back its own zero initialiser. The
// pay-at-start claim is checked where it can actually fail, against the engine's own resource
// globals: hooktest and test-upgrade-queue.ps1 read them, and those balance checks have been
// watched failing with a spend deliberately injected into the queue path while every
// counter-based `spent nothing` check stayed green.
enum ScUpgQueueStat {
    SC_UPGQ_STAT_QUEUED = 0,        // commands the plugin held instead of the engine
    SC_UPGQ_STAT_PROMOTED = 1,      // items handed to the engine's own accept path
    SC_UPGQ_STAT_CANCELLED = 2,     // items dropped by a player cancel
    SC_UPGQ_STAT_DROPPED = 3,       // items dropped because their building went away
    SC_UPGQ_STAT_REFUSED_FULL = 4,  // a command arrived with the queue already at maximum
    SC_UPGQ_STAT_REFUSED_GATE = 5,  // the engine's own gate refused an item at promotion
    SC_UPGQ_STAT_WAITING_COST = 6,  // promotions deferred because the player cannot pay yet
    SC_UPGQ_STAT_UNBLOCKED = 7,     // card conditions answered as if the building were idle
    // Card conditions answered 0 (hidden) for an id the building already holds: the
    // one-entry rule, counted apart from UNBLOCKED so a run can say how often it bit.
    SC_UPGQ_STAT_HIDDEN_HELD = 8,
    // Items dropped because their record was made in a DIFFERENT game (sc_session.h). Kept
    // apart from DROPPED for the same reason sc_prodqueue keeps its own apart: "the building
    // died" and "this record belongs to a game that ended" are different events with
    // different correct responses, and a single counter for both would hide whichever is
    // rarer. hooktest asserts this non-zero with the epoch pinned, so the assertion has been
    // watched failing rather than reading its answer out of the zero-initialiser.
    SC_UPGQ_STAT_STALE_SESSION = 9,
    // A 0x32/0x30 for an id the building is already running or holding. The card hides
    // that button, so this is reachable only from a replay or a peer; refused rather than
    // queued twice, and consumed so the engine's body cannot start it over the running one.
    SC_UPGQ_STAT_REFUSED_DUP = 10,
    SC_UPGQ_STAT__COUNT = 11
};
int ScUpgQueueStat(int which);

#endif // SC_UPGRADES_H
