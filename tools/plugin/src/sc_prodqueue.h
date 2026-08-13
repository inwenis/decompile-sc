// sc_prodqueue.h -- more than five items in a building's production queue.
//
// THE MECHANISM (research/production-queue.md 5)
//   The engine's queue is a five-slot ring inside the CUnit (u16[5] at +0x98, head byte
//   at +0xA4) and the 5 is baked into unrolled and modulo-5 arithmetic in six functions
//   plus the building AI's mirror arrays. It cannot be widened in place, and this plugin
//   does not try. It keeps a per-building OVERFLOW list of its own instead.
//
//   WHICH END OF THE QUEUE THE PLUGIN HOLDS IS THE WHOLE DESIGN, and the first in-game
//   run settled it. The plugin cannot wait for an over-cap command to arrive, because
//   THE CLIENT NEVER SENDS ONE: with five items queued, the sixth press puts nothing on
//   the wire at all (measured -- five `CMD id=0x1F` at the press cadence and then silence
//   for seven more presses) and the Train button is drawn dark. So the plugin keeps the
//   engine's ring one slot BELOW its cap (SC_PRODQ_ENGINE_HOLD) by taking the newest item
//   back out of it after every accept. The button stays live, the client keeps sending,
//   and everything past the hold waits in the plugin's list, in order.
//
//   WHICH BUILDING a Train command is for is the OTHER half of that, and task 038 had to
//   correct it: it comes from the SIMULATION's selection for the active player
//   (playersSelections 0x006284E8, row activePlayerId), which is what the engine's own gate
//   reads -- not from the client's activePlayerSelection, which sits immediately in front of
//   it and holds the same thing only while ONE building is selected. With several selected
//   the fan-out (sc_prodfan) replays one Select+Train pair per building, the two lists
//   disagree by design, and reading the client's one made this feature do nothing at all for
//   a group. The five instructions that settle it are quoted at SoleSelectedUnit().
//
// THE RESOURCE RULE
//   THE ENGINE PAYS FOR EVERY ITEM, EXACTLY ONCE, AND THE PLUGIN NEVER SPENDS A MINERAL.
//   Every item is accepted by the engine's own addToBuildQueue (0x00467250), which is
//   also where the engine checks affordability and deducts the cost. Moving an item out
//   of the ring afterwards, and moving it back later, are bare `buildQueue[slot] = type`
//   stores that touch no resource global:
//
//     accepted into the ring         -> the ENGINE pays, and checks the player can
//     held back by the plugin        -> nobody pays; the item is already paid for
//     promoted back into a free slot -> nobody pays, for the same reason
//     cancelled or lost while held   -> the PLUGIN refunds, out of the same two cost
//                                       tables the engine's own refund reads
//
//   So the plugin's only resource writes are refunds, and `mineralsSpent` in its stats
//   line is expected to stay 0 for the life of a run -- that is an assertion, not a
//   coincidence. Every path that can lose a held item -- an explicit cancel, the building
//   dying, the plugin unloading -- refunds it.
//
// WHAT THIS NEVER DOES
//   It never widens, relocates or re-strides the engine's array. The slots it does write
//   hold real types the engine put there, in the order the player asked for, so the icons
//   the status area draws stay truthful -- there are just fewer of them than the logical
//   queue holds (the known limitation, research/production-queue.md 7). It installs no
//   hook and touches nothing at all unless %SCPLUGIN_PRODQ% asks for it, and it is inert
//   in `-Mode observe`, which stays the off switch for the whole plugin.

#ifndef SC_PRODQUEUE_H
#define SC_PRODQUEUE_H

#include <windows.h>

// Total logical queue length per building, engine's five included. Default 16; the
// launcher/env knob %SCPLUGIN_PRODQ_MAX% moves it inside [SC_BUILD_QUEUE_SLOTS, 24].
#define SC_PRODQ_DEFAULT_MAX 16
#define SC_PRODQ_HARD_MAX    24
// How many items the engine's own ring is allowed to hold while the plugin is managing
// this building. FOUR, i.e. one below the engine's five, because the client stops sending
// Train commands at five (see the mechanism note above) and a queue nobody can add to is
// the bug this feature exists to remove. It is not a cap on anything the player sees:
// the logical queue is this plus whatever the plugin holds.
#define SC_PRODQ_ENGINE_HOLD 4
// How many buildings can hold overflow at once. Beyond this a new building is refused
// (and says so in the log) rather than evicting one that has already been paid for.
#define SC_PRODQ_MAX_BUILDINGS 32

// Reads %SCPLUGIN_PRODQ%. Unset/0 -> disabled, which is the off switch: nothing in this
// file runs, no hook is installed and no game memory is written.
bool ScProdQueueEnabled(void);

// Installs the three detours under its own thread suspension (the fan-out's splice has
// already been made and resumed by then, and a second short suspension is cheaper than
// threading this feature through sc_fanout.cpp, which task 024 is editing concurrently).
// Returns the number installed (0 or 3); a partial install rolls itself back and
// disables the feature.
int  ScProdQueueInstall(BYTE* moduleBase);
void ScProdQueueRemove(void);

// One line per tracked building, for the observer's marker channel. This is the test
// oracle: it prints the ENGINE's own five slots read out of CUnit+0x98 alongside the
// plugin's overflow, so an unattended run asserts on the building's memory rather than
// on the screen.
void ScProdQueueLogState(const char* tag);
// One STATS line, written on both detach paths.
void ScProdQueueLogStats(void);

// ---------------------------------------------------------------------------
// The core, hook-free -- driven byte-for-byte from hooktest.exe with no StarCraft in
// sight (src/hooktest.cpp part [11]). The three detours do nothing but marshal
// arguments into these.
// ---------------------------------------------------------------------------

// A Train command (0x1F) has just been handled by the engine for `unit`: it has accepted
// the item and paid for it, or refused it. Rebalances the building -- takes the newest
// items back out of the ring until it is down to SC_PRODQ_ENGINE_HOLD, and promotes if
// the ring is under it. `wasFull` is whether the ring was full BEFORE the engine ran,
// sampled there because afterwards a successful enqueue and a refused one look the same;
// with this design that only happens once the logical queue has reached its maximum and
// the plugin has stopped making room, so it counts as a refusal.
void ScProdQueueOnTrain(DWORD unit, unsigned type, bool wasFull);

// The production tick has just run for `unit`. Rebalances the same way: the frame a slot
// frees is the frame the oldest held item takes it. Also garbage-collects records whose
// building has gone.
void ScProdQueueOnTick(DWORD unit);

// A Cancel Train command (0x20) is about to be handled for `unit` with payload
// `payload`. Returns true when the plugin consumed it -- a "cancel the last queued
// item" that the plugin, not the engine, was holding -- and the caller must then SKIP
// the engine's handler.
bool ScProdQueueOnCancel(DWORD unit, unsigned payload);

// Test-only: point the core at a fake module image (see sc_fanout's ScFanoutTestBegin)
// and clear all state. NULL restores normal operation.
void ScProdQueueTestBegin(BYTE* fakeModuleBase, int maxTotal);

// Test-only: the building a production RECEIVE handler will act on, resolved the way
// getActivePlayerNextSelection (0x0049A850) resolves it -- playersSelections indexed by
// activePlayerId, NOT the client's own activePlayerSelection. Exposed so the offline suite
// can prove the plugin follows the ENGINE's array with the two arrays disagreeing, which
// is exactly the state a fanned-out Select+Train pair creates (task 038). 0 = "not a
// single selected building", i.e. the plugin has no business in this command.
DWORD ScProdQueueSoleSelectedUnitForTest(void);

// Test-only read-back.
int  ScProdQueueOverflowCount(DWORD unit);   // -1 when the building is not tracked
int  ScProdQueueOverflowAt(DWORD unit, int i);
int  ScProdQueueTrackedBuildings(void);

// Test-only counters, in the same order ScProdQueueLogStats prints them.
enum ScProdQueueStat {
    SC_PRODQ_STAT_CAPTURED = 0,   // items taken back out of the ring and held
    SC_PRODQ_STAT_PROMOTED = 1,   // items handed to a freed engine slot
    SC_PRODQ_STAT_CANCELLED = 2,  // items cancelled out of overflow by the player
    SC_PRODQ_STAT_REFUNDED = 3,   // items refunded because their building went away
    SC_PRODQ_STAT_REFUSED_FULL = 4,   // a Train command arrived with the ring already full
    // Always 0, and kept in the line so that stays visible: affordability is the ENGINE's
    // check now, made before the plugin sees anything, so an item the player cannot afford
    // is never offered to it. Same for the two SPENT counters below -- the plugin's own
    // spend is expected to be flat zero for the life of a run, and both suites assert it.
    SC_PRODQ_STAT_REFUSED_COST = 5,
    SC_PRODQ_STAT_MINERALS_SPENT = 6,
    SC_PRODQ_STAT_MINERALS_REFUNDED = 7,
    SC_PRODQ_STAT_GAS_SPENT = 8,
    SC_PRODQ_STAT_GAS_REFUNDED = 9,
    // WHERE THE DETOURS WENT, counted per exit. Task 038's bug was invisible for exactly
    // the reason AGENTS.md gives ("No log line appeared" and "the function returned false"
    // look identical in a quiet log): the Train detour ran three times per click and found
    // no building to act on every time, and the only observable was a queue that stopped
    // at five. A counter per exit makes the next such run say WHICH term refused.
    SC_PRODQ_STAT_TRAIN_SEEN = 10,      // cmdrecvTrain detours entered
    SC_PRODQ_STAT_TRAIN_NO_UNIT = 11,   // ...that found no single selected building
    SC_PRODQ_STAT_CANCEL_SEEN = 12,     // cmdrecvCancelTrain detours entered
    SC_PRODQ_STAT_CANCEL_NO_UNIT = 13,  // ...that found no single selected building
    // Task 054 / issue #63. Items dropped because their record was made in a DIFFERENT
    // game (sc_session.h). Deliberately its own counter and NOT folded into REFUNDED,
    // because the two are opposites: a building that dies gives its minerals back, and
    // a record from another game must not -- those minerals were spent in a game that
    // no longer exists, and crediting them here would pay the player for it.
    SC_PRODQ_STAT_STALE_SESSION = 14,
    SC_PRODQ_STAT__COUNT = 15
};
int ScProdQueueStat(int which);

#endif // SC_PRODQUEUE_H
