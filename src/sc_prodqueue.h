// sc_prodqueue.h -- more than five items in a building's production queue.
// The engine's queue is a five-slot ring in the CUnit (u16[5] at +0x98, head byte at
// +0xA4); the 5 is baked into unrolled/modulo-5 arithmetic in six functions plus the
// building AI's mirror arrays, so it cannot be widened, relocated or re-strided in place
// and this plugin never tries (research/production-queue.md 5). It keeps a per-building
// OVERFLOW list instead and holds the engine's ring one slot BELOW its cap
// (SC_PRODQ_ENGINE_HOLD) by taking the newest item back out after every accept. The ring
// still holds real types in player order, so the status-area icons stay truthful, just
// fewer than the logical queue (research/production-queue.md 7).
//
// THE RESOURCE RULE: the engine pays for every item exactly once, in its own
// addToBuildQueue (0x00467250), which also checks affordability; moving an item out of the
// ring and back is a bare `buildQueue[slot] = type` store touching no resource global. The
// plugin's only resource writes are refunds of held items that are lost (cancel, building
// dying, plugin unload), out of the cost tables the engine's own refund reads.

#ifndef SC_PRODQUEUE_H
#define SC_PRODQUEUE_H

#include <windows.h>

// Total logical queue length per building, engine's five included. Default 16; the
// launcher/env knob %SCPLUGIN_PRODQ_MAX% moves it inside [SC_BUILD_QUEUE_SLOTS, 24].
#define SC_PRODQ_DEFAULT_MAX 16
#define SC_PRODQ_HARD_MAX    24
// How many items the engine's ring may hold while the plugin manages this building: FOUR,
// one below the engine's five, because with five queued the client puts NOTHING on the
// wire for a sixth press (measured: five `CMD id=0x1F` at the press cadence, then silence
// for seven more presses) and draws the Train button dark, so the plugin cannot wait for
// an over-cap command. One slot short keeps the button live and the client sending. Not a
// cap on anything the player sees: the logical queue is this plus what the plugin holds.
#define SC_PRODQ_ENGINE_HOLD 4
// How many buildings can hold overflow at once. Beyond this a new building is refused
// (and says so in the log) rather than evicting one that has already been paid for.
#define SC_PRODQ_MAX_BUILDINGS 32

// Reads %SCPLUGIN_PRODQ%. Unset/0 -> disabled, which is the off switch: nothing in this
// file runs, no hook is installed and no game memory is written.
bool ScProdQueueEnabled(void);

// Installs the three detours under its own thread suspension: the fan-out's splice is
// already made and resumed by then, and a second short suspension is cheaper than threading
// this feature through sc_fanout.cpp. Returns the number installed (0 or 3); a partial
// install rolls itself back and disables the feature.
int  ScProdQueueInstall(BYTE* moduleBase);
void ScProdQueueRemove(void);

// One line per tracked building, for the observer's marker channel. This is the test
// oracle: it prints the ENGINE's own five slots read out of CUnit+0x98 alongside the
// plugin's overflow, so an unattended run asserts on the building's memory rather than
// on the screen.
void ScProdQueueLogState(const char* tag);
// One STATS line, written on both detach paths.
void ScProdQueueLogStats(void);

// The core, hook-free -- driven byte-for-byte from hooktest.exe with no StarCraft in
// sight (src/hooktest.cpp part [11]). The three detours only marshal arguments into these.

// A Train command (0x1F) has just been handled by the engine for `unit`: it accepted and
// paid for the item, or refused it. Rebalances the building: takes the newest items back
// out of the ring until it is down to SC_PRODQ_ENGINE_HOLD, and promotes if the ring is
// under it. `wasFull` is whether the ring was full BEFORE the engine ran, sampled there
// because afterwards a successful enqueue and a refused one look the same; that state only
// arises once the logical queue is at its maximum and the plugin has stopped making room,
// so it counts as a refusal.
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

// Test-only: the building a production RECEIVE handler acts on, resolved the way
// getActivePlayerNextSelection (0x0049A850) does (its five instructions are quoted at
// SoleSelectedUnit()): the SIMULATION's selection for the active player (playersSelections
// 0x006284E8, row activePlayerId), which the engine's own gate reads. Do not read the
// client's activePlayerSelection just in front of it: it agrees only while ONE building is
// selected, the fan-out (sc_prodfan) replays one Select+Train pair per building so the two
// disagree by design, and reading it made this feature do nothing at all for a group. The
// offline suite asserts on exactly that state. 0 = no single selected building.
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
    // Do not add "spent" or "refused for cost" counters here: nothing in the plugin can
    // increment them (no spend path, no cost refusal), so an `== 0` assertion on them reads
    // the zero-initialiser. MEASURED: hooktest built from a tree with a real spend added at
    // the capture site and such counters left alone -- 28 balance checks FAILED while every
    // `spent NOTHING` counter check still PASSED. The engine's own resource globals,
    // asserted at the same sites, are the oracle. Refund() is this module's only resource
    // write and it only adds; that is what the two REFUNDED counters count.
    SC_PRODQ_STAT_MINERALS_REFUNDED = 5,
    SC_PRODQ_STAT_GAS_REFUNDED = 6,
    // Where the detours exited, one counter per exit. "No log line appeared" and "the
    // function returned false" look identical in a quiet log (AGENTS.md § Your DIAGNOSTICS
    // are under the same rule as your assertions): a Train detour that runs three times per
    // click and finds no building every time is observable only as a queue that stops at
    // five. A counter per exit makes such a run say WHICH term refused.
    SC_PRODQ_STAT_TRAIN_SEEN = 7,      // cmdrecvTrain detours entered
    SC_PRODQ_STAT_TRAIN_NO_UNIT = 8,   // ...that found no single selected building
    SC_PRODQ_STAT_CANCEL_SEEN = 9,     // cmdrecvCancelTrain detours entered
    SC_PRODQ_STAT_CANCEL_NO_UNIT = 10, // ...that found no single selected building
    // Items dropped because their record was made in a DIFFERENT game (sc_session.h). Its
    // own counter, NOT folded into REFUNDED, because the two are opposites: a building that
    // dies gives its minerals back; a record from another game must not, since those
    // minerals were spent in a game that has ended and crediting them here would pay the
    // player for it. Incremented on the only path that can produce it and asserted NON-zero
    // in hooktest part [22] (`four items counted against the epoch, by name`), an assertion
    // watched failing with the epoch pinned.
    SC_PRODQ_STAT_STALE_SESSION = 11,
    SC_PRODQ_STAT__COUNT = 12
};
int ScProdQueueStat(int which);

#endif // SC_PRODQUEUE_H
