// sc_upgrades.h -- queue more than one upgrade or research at a building.
//
// THE MECHANISM (research/upgrade-queue.md 7)
//   A building researches one thing at a time because it has ONE FIELD for it: CUnit+0xC9
//   is the upgrade in progress (61 = none) and CUnit+0xC8 the tech (44 = none). There is
//   no array to widen and no spare byte to widen into, so this plugin does not try. It
//   holds a per-building QUEUE of its own and hands items to the engine one at a time.
//
//   THE CLIENT REFUSES TO SEND THE SECOND COMMAND, and it refuses harder than task 025's
//   Train button did. Measured in a live game (probe-upgrade-wire.ps1): with an upgrade
//   running, six presses of the two upgrade buttons put ZERO commands on the wire, and the
//   card read out of memory shows those buttons not greyed but GONE -- shown=1, the whole
//   card replaced by Cancel Upgrade. The refusal is requirement opcode 0xFF0A inside the
//   interpreter 0x0046D610: `if (unit->0xC9 != 61) { reason = 5; return 0; }`, and 0 (as
//   opposed to -1) is what makes the card layout skip the button entirely.
//
//   So 025's inversion cannot transfer -- the engine's capacity is ONE, and keeping it
//   free means nothing is ever researched -- and a receive-side handler alone cannot work
//   either, because the command never arrives. This module does three things instead:
//
//     UNBLOCK   detour the two CARD button conditions (0x00429450 upgrade, 0x00429500
//               tech) and, when this building is busy and the queue has room, evaluate the
//               ORIGINAL condition with 0xC9/0xC8 momentarily at their idle sentinels.
//               The button comes back and the client starts sending again. The GATES
//               themselves are deliberately NOT hooked: the building AI calls them too,
//               and a computer player told a busy building is free would start an upgrade
//               on top of the running one.
//     HOLD      detour cmdrecvUpgrade (0x004C1B20) / cmdrecvTech (0x004C1BA0) at entry.
//               Building already researching -> append the id to this building's record
//               and DO NOT run the engine's body. That skip is not optional: neither
//               startUpgrade nor startTech checks whether something is already running,
//               so the engine's body would overwrite the running item and pay for it.
//     PROMOTE   detour the order handlers upgradeTick (0x004546A0) / techTick
//               (0x004548B0). Run the original; if the building has just gone idle, pop
//               the oldest held item and run THE ENGINE'S OWN accept path on it --
//               gate, then startUpgrade/startTech, then the accept tail.
//
//   At the cap the plugin simply stops unblocking. The condition tells the truth, the
//   layout hides the button, and the client refuses on its own -- the cap is vanilla's
//   own mechanism, exactly as in task 025.
//
// THE RESOURCE RULE
//   THE PLUGIN NEVER TOUCHES A RESOURCE GLOBAL, IN EITHER DIRECTION.
//
//     queued        -> nobody pays. A held item is one id and a kind; it carries no money.
//     promoted      -> the ENGINE pays, inside startUpgrade/startTech, from its own cost
//                      tables, at the moment the item actually begins.
//     cancelled     -> nothing to refund, because nothing was paid.
//     building dies -> nothing to refund, same reason. Vanilla refunds the RUNNING item
//                      itself, on its own death path, untouched by this module.
//
//   That is a deliberate divergence from vanilla unit training, which charges at queue
//   time (research/production-queue.md 4.2). Pay-at-start makes double payment
//   structurally impossible rather than merely avoided, and it deletes the whole refund
//   surface. Approved as the design before this file existed.
//
//   The module DOES read the engine's cost tables and the two resource globals -- to
//   decide whether the player can afford an item before offering it to the engine, so the
//   engine is not asked to play its "insufficient minerals" error once a frame while the
//   queue waits for income. A comparison, not a transaction. Both SPENT counters in the
//   stats line are asserted to be flat ZERO for the life of a run.
//
// WHAT THIS NEVER DOES
//   It never writes an upgrade or tech id into a building except through the engine's own
//   start function. It never clears the per-player in-progress bitfields (0x0058F3E0 /
//   0x0058F230), which is why two buildings still cannot research the same upgrade and why
//   level N+1 cannot be queued behind level N -- a stated limitation, not an oversight.
//   It installs no hook and touches nothing at all unless %SCPLUGIN_UPGQ% asks for it, and
//   it is inert in `-Mode observe`, which stays the off switch for the whole plugin.

#ifndef SC_UPGRADES_H
#define SC_UPGRADES_H

#include <windows.h>

// Total logical queue length per building, the engine's ONE included. Default 8; the
// launcher/env knob %SCPLUGIN_UPGQ_MAX% moves it inside [1, SC_UPGQ_HARD_MAX].
//
// Why 8. An upgrade is minutes long and expensive, so a deep queue is a bigger commitment
// than a deep unit queue: seven held items at an Engineering Bay is more upgrades than the
// building has distinct level-1s to offer, which makes it comfortably "walk away and do
// something else" without being an amount anyone would queue by accident. It is also not a
// memory decision -- a record is about 40 bytes.
#define SC_UPGQ_DEFAULT_MAX 8
#define SC_UPGQ_HARD_MAX    16
// What the engine itself can hold. One. This is the whole reason the module exists, and
// naming it makes the arithmetic below read as arithmetic rather than as magic.
#define SC_UPGQ_ENGINE_SLOTS 1
// How many buildings may hold a queue at once. Beyond this a new one is refused, and says
// so in the log, rather than evicting somebody else's queue.
#define SC_UPGQ_MAX_BUILDINGS 32

// Which command an item came from. The two are queued in one list per building, in the
// order the player pressed them, because a building that offers both (an Academy) should
// run them in that order.
#define SC_UPGQ_KIND_UPGRADE 0   // wire 0x32
#define SC_UPGQ_KIND_TECH    1   // wire 0x30

// Reads %SCPLUGIN_UPGQ%. Unset/0 -> disabled, which is the off switch: nothing in this
// file runs, no hook is installed and no game memory is written.
bool ScUpgQueueEnabled(void);

// Eight detours: two card conditions, two receive handlers, two order handlers, two
// cancels.
#define SC_UPGQ_HOOK_COUNT 8

// Installs them all under one thread suspension. Returns the number installed (0 or
// SC_UPGQ_HOOK_COUNT); a partial install rolls itself back and disables the feature,
// because a partial set is worse than none -- unblocking without holding lets the engine
// overwrite a running upgrade, and holding without promoting strands the queue.
int  ScUpgQueueInstall(BYTE* moduleBase);
void ScUpgQueueRemove(void);

// One line per tracked building plus one for the sole selected building, for the
// observer's marker channel. THIS IS THE TEST ORACLE: it prints the building's own
// CUnit+0xC8/0xC9/0xC6/0xCD alongside the plugin's queue, so an unattended run asserts on
// the building's memory rather than on the screen.
void ScUpgQueueLogState(const char* tag);
// One STATS line, written on both detach paths.
void ScUpgQueueLogStats(void);

// ---------------------------------------------------------------------------
// The core, hook-free -- driven byte-for-byte from hooktest.exe with no StarCraft in
// sight. The six detours do nothing but marshal registers into these.
// ---------------------------------------------------------------------------

// A 0x32 / 0x30 command has arrived for `unit`. Returns true when the plugin consumed it
// -- the building is already researching and the queue had room -- and the caller must
// then SKIP the engine's handler entirely.
bool ScUpgQueueOnCommand(DWORD unit, int kind, unsigned id);

// An order handler has just run for `unit`. If it has gone idle and the plugin holds
// items, the oldest is handed to the engine's own accept path. Also garbage-collects.
void ScUpgQueueOnTick(DWORD unit);

// A 0x33 / 0x31 cancel is about to be handled for `unit`. Returns true when the plugin
// consumed it -- it dropped its own most recently queued item, which is the tail of the
// logical queue and therefore the plugin's to cancel -- and the caller must skip the
// engine's handler. Nothing is refunded because nothing was paid.
bool ScUpgQueueOnCancel(DWORD unit);

// Should the card offer research buttons at `unit` even though it is busy? True only when
// the feature is on, the unit is a completed building that is researching, and the logical
// queue is below the maximum.
bool ScUpgQueueShouldUnblock(DWORD unit);

// May the card also be shown the RUNNING upgrade's own button, so its next level can be
// queued behind it? True only for the building whose CUnit+0xC9 already holds this very
// id, and only while a level is left after everything running and queued -- which is what
// keeps a SECOND building from being offered the same upgrade and the pair from paying
// twice for one level. Exposed so a test can assert that guard directly.
bool ScUpgQueueMaySuppressBusyBit(DWORD unit, int kind, unsigned id);

// The promotion seam. The real one calls into the engine; hooktest replaces it, because
// there is no engine in a test process. Returns 1 when the item was started.
typedef int (*ScUpgStartFn)(DWORD unit, int kind, unsigned id);

// Test-only: point the core at a fake module image and a fake starter, and clear all
// state. NULL restores normal operation.
void ScUpgQueueTestBegin(BYTE* fakeModuleBase, int maxTotal, ScUpgStartFn starter);

// Test-only: the building a research RECEIVE handler will act on, resolved the way
// getActivePlayerNextSelection (0x0049A850) resolves it -- playersSelections indexed by
// activePlayerId, NOT the client's own activePlayerSelection. Exposed so the offline suite
// can prove the plugin follows the ENGINE's array with the two arrays disagreeing (task 042,
// same shape as sc_prodqueue's ScProdQueueSoleSelectedUnitForTest, task 038). 0 = "not a
// single selected building", i.e. the plugin has no business in this command.
DWORD ScUpgQueueSoleSelectedUnitForTest(void);

// Test-only read-back.
int  ScUpgQueueCount(DWORD unit);          // -1 when the building is not tracked
int  ScUpgQueueKindAt(DWORD unit, int i);  // -1 out of range
int  ScUpgQueueIdAt(DWORD unit, int i);    // -1 out of range
int  ScUpgQueueTrackedBuildings(void);

// Test-only counters, in the same order ScUpgQueueLogStats prints them.
enum ScUpgQueueStat {
    SC_UPGQ_STAT_QUEUED = 0,        // commands the plugin held instead of the engine
    SC_UPGQ_STAT_PROMOTED = 1,      // items handed to the engine's own accept path
    SC_UPGQ_STAT_CANCELLED = 2,     // items dropped by a player cancel
    SC_UPGQ_STAT_DROPPED = 3,       // items dropped because their building went away
    SC_UPGQ_STAT_REFUSED_FULL = 4,  // a command arrived with the queue already at maximum
    SC_UPGQ_STAT_REFUSED_GATE = 5,  // the engine's own gate refused an item at promotion
    SC_UPGQ_STAT_WAITING_COST = 6,  // promotions deferred because the player cannot pay yet
    SC_UPGQ_STAT_UNBLOCKED = 7,     // card conditions answered as if the building were idle
    // Both always 0, and kept in the line so that stays visible: the ENGINE pays for every
    // item, at start, and this module never moves a resource. Both suites assert them.
    SC_UPGQ_STAT_MINERALS_SPENT = 8,
    SC_UPGQ_STAT_GAS_SPENT = 9,
    // The narrower, level-stacking lie: how often the per-player in-progress BIT was
    // suppressed as well, which only ever happens for the building already running that
    // exact upgrade. Counted separately from UNBLOCKED so a run can say which of the two
    // lies it needed.
    SC_UPGQ_STAT_UNBLOCKED_LEVEL = 10,
    SC_UPGQ_STAT__COUNT = 11
};
int ScUpgQueueStat(int which);

#endif // SC_UPGRADES_H
