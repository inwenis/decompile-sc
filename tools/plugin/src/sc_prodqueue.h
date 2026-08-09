// sc_prodqueue.h -- more than five items in a building's production queue.
//
// THE MECHANISM (research/production-queue.md 5)
//   The engine's queue is a five-slot ring inside the CUnit (u16[5] at +0x98, head byte
//   at +0xA4) and the 5 is baked into unrolled and modulo-5 arithmetic in six functions
//   plus the building AI's mirror arrays. It cannot be widened in place, and this
//   plugin does not try. Instead it keeps a per-building OVERFLOW list of its own and
//   feeds the engine's five as slots free up -- the same shadow pattern the selection
//   fan-out uses, applied to production.
//
// THE RESOURCE RULE
//   A queued item is paid for EXACTLY ONCE, when it is accepted -- which is what
//   vanilla does, and is why cancelling refunds the right amount whether the item is
//   sitting in the engine's five or in ours:
//
//     accepted into the engine's five   -> the ENGINE pays (addToBuildQueue 0x00467250)
//     accepted into our overflow        -> WE pay, out of the same two cost tables the
//                                          engine's own refund reads back
//     promoted from overflow into a slot-> NOBODY pays; it is a bare `buildQueue[slot] =
//                                          type` store, because the item was paid for
//                                          when it was accepted
//
//   So the money moves once per item on the way in and once on the way out, and never
//   in between. Every path that can lose an overflow item -- an explicit cancel, the
//   building dying, the plugin unloading -- refunds it.
//
// WHAT THIS NEVER DOES
//   It never widens, relocates or re-strides the engine's array; the engine's own five
//   slots always hold exactly five real items, so the five icons the status area draws
//   stay truthful (they are the next five things this building will build). It installs
//   no hook and touches nothing at all unless %SCPLUGIN_PRODQ% asks for it, and it is
//   inert in `-Mode observe`, which stays the off switch for the whole plugin.

#ifndef SC_PRODQUEUE_H
#define SC_PRODQUEUE_H

#include <windows.h>

// Total logical queue length per building, engine's five included. Default 16; the
// launcher/env knob %SCPLUGIN_PRODQ_MAX% moves it inside [SC_BUILD_QUEUE_SLOTS, 24].
#define SC_PRODQ_DEFAULT_MAX 16
#define SC_PRODQ_HARD_MAX    24
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

// A Train command (0x1F) has just been handled by the engine for `unit`. `wasFull` is
// whether the queue was full BEFORE the engine ran; the caller samples it there because
// afterwards a successful enqueue is indistinguishable from a refused one.
void ScProdQueueOnTrain(DWORD unit, unsigned type, bool wasFull);

// The production tick has just run for `unit`. Promotes as many overflow items as there
// are free slots, and garbage-collects records whose building has gone.
void ScProdQueueOnTick(DWORD unit);

// A Cancel Train command (0x20) is about to be handled for `unit` with payload
// `payload`. Returns true when the plugin consumed it -- a "cancel the last queued
// item" that the plugin, not the engine, was holding -- and the caller must then SKIP
// the engine's handler.
bool ScProdQueueOnCancel(DWORD unit, unsigned payload);

// Test-only: point the core at a fake module image (see sc_fanout's ScFanoutTestBegin)
// and clear all state. NULL restores normal operation.
void ScProdQueueTestBegin(BYTE* fakeModuleBase, int maxTotal);

// Test-only read-back.
int  ScProdQueueOverflowCount(DWORD unit);   // -1 when the building is not tracked
int  ScProdQueueOverflowAt(DWORD unit, int i);
int  ScProdQueueTrackedBuildings(void);

// Test-only counters, in the same order ScProdQueueLogStats prints them.
enum ScProdQueueStat {
    SC_PRODQ_STAT_CAPTURED = 0,   // items accepted into overflow
    SC_PRODQ_STAT_PROMOTED = 1,   // items handed to a freed engine slot
    SC_PRODQ_STAT_CANCELLED = 2,  // items cancelled out of overflow by the player
    SC_PRODQ_STAT_REFUNDED = 3,   // items refunded because their building went away
    SC_PRODQ_STAT_REFUSED_FULL = 4,   // over SC_PRODQ max, or no record free
    SC_PRODQ_STAT_REFUSED_COST = 5,   // the player could not afford it
    SC_PRODQ_STAT_MINERALS_SPENT = 6,
    SC_PRODQ_STAT_MINERALS_REFUNDED = 7,
    SC_PRODQ_STAT_GAS_SPENT = 8,
    SC_PRODQ_STAT_GAS_REFUNDED = 9,
    SC_PRODQ_STAT__COUNT = 10
};
int ScProdQueueStat(int which);

#endif // SC_PRODQUEUE_H
