// sc_session.h -- the game-session epoch: the one discriminator that tells a record
// from a dead game apart from a record in the game being played.
//
// Records that outlive a frame are keyed on things the engine reuses: a CUnit* is a
// seat in a fixed 1700-entry global array, a save restores the 336 bytes of that seat
// -- uniqueness byte, player, hitpoints -- VERBATIM into it, and a CSprite* is a heap
// address the allocator hands out again. So "is the unit at this address still the same
// unit?" answers YES in a game the record does not belong to, and no per-unit check can
// fix it. The discriminator has to be something the unit does not carry: one counter,
// bumped by the ENGINE's own game start, that no save restores and no unit can imitate.
//
// Adoption is per module, never by registration: each module keeps its own `g_session`
// and calls its own SessionSync() at the top of every entry point it has, INCLUDING its
// read-backs, so no path can use a record without first passing the epoch test and no
// list can be one entry short. This file calls nothing and knows no other module.

#ifndef SC_SESSION_H
#define SC_SESSION_H

#include <windows.h>

// A record from a dead game is DROPPED, never REFUNDED: crediting minerals spent in a
// game that has ended to the game the player is in now turns a stale-state bug into a
// resource exploit. That is the opposite of what a module does when a BUILDING dies, so
// the two paths stay distinguishable -- hence a separate counter per module.
// The epoch is checked BEFORE the record's pointers are dereferenced: a CSprite* held
// across a game end is a freed heap address, and heap reuse makes it compare equal to a
// live one.

// The current game-session epoch. Starts at 1 and increases; 0 is never returned, so a
// module can use 0 for "never synced" without ambiguity. Safe to call from any thread
// and in any mode -- with no hook installed it never changes, which is correct, because
// in observe mode no module holds anything.
unsigned ScSessionEpoch(void);

// Splices the epoch bump into the engine's game start. `enabled` is false in observe
// mode, where the whole plugin writes nothing to game memory; the epoch then stays 1.
// Returns the number of hooks installed (0, 1 or 2 -- see ScSessionLogState).
//
// The bump rides gameStartClear (0x004EEC30), the function that zeroes selectionHotkeys
// and recentSelectionTimes at the start of a game, and that the engine runs on a LOAD as
// well as on a new game: scanning every E8/E9 rel32 in .text gives gameStartClear,
// startOrLoadGame (0x004EED10) and loadSavedGame (0x004CFEF0) exactly one caller each, so
// startGame (0x004EF100) always reaches the bump at 0x004EF27A before the save is read at
// 0x004EED48 (reached through the call at 0x004EF32B), and startGame's only early returns
// are at 0x004EF182 (before the bump) and 0x004EF305/0x004EF318 (after the load call). The
// epoch is therefore strictly older than every unit a load restores. The engine says the
// same in its own code: 0x004EEC61 reads the load-game FILE* (0x006D1218) and skips that
// hotkey clear when a load is pending, a branch that exists only because this function
// runs on the load path.
//
// The detour is spliced at 0x004EEC37 (B8FFFF0000, MOV EAX,0xFFFF -- a self-contained
// 5 bytes), not at the entry: an entry window would straddle the PC-relative CALL at
// 0x004EEC32, and sc_hook.cpp copies stolen bytes VERBATIM, having no relocator by
// design. Nothing branches into the body, so the splice is reached once per call,
// exactly as often as the entry.
int  ScSessionInstall(BYTE* moduleBase, bool enabled);
void ScSessionRemove(void);

// One line for the observer's marker channel and for the detach paths. It prints the
// LOAD WITNESS beside the epoch because "the epoch bumped" and "a save was actually
// deserialised" are separate observations: a run with the second and not the first is
// exactly the failure this mechanism must not have, and counting bumps alone leaves it
// indistinguishable from a run in which no load was attempted
// (AGENTS.md § "Oracles: absence and defect-era checks").
void ScSessionLogState(const char* tag);

enum ScSessionStat {
    SC_SESSION_STAT_STARTS = 0,   // gameStartClear detours entered == epoch bumps
    SC_SESSION_STAT_LOADS  = 1,   // loadSavedGame detours entered (the witness)
    SC_SESSION_STAT__COUNT = 2
};
unsigned ScSessionStat(int which);

// The epoch the most recent save load was observed in. 0 = no load has been seen.
// A load whose epoch is not the current one would mean the bump did not precede it.
unsigned ScSessionEpochAtLastLoad(void);

// --- test seam (hooktest); no hook and no game involved ---------------------
void ScSessionTestBegin(void);     // back to epoch 1, counters zeroed
void ScSessionTestNewGame(void);   // exactly what the detour does: bump
void ScSessionTestLoad(void);      // exactly what the load witness does

#endif // SC_SESSION_H
