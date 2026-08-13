// sc_session.h -- the GAME-SESSION EPOCH.
//
// WHAT THIS IS FOR (issue #67, and #63 as its first instance)
//   Every module in this plugin keeps records that outlive a frame -- held production
//   items, upgrade records, a deferred fan-out plan, a shadow selection, control
//   groups, selection circles. Every one of them is keyed on things the ENGINE
//   legitimately reuses: a CUnit* is a seat in a fixed 1700-entry global array, the
//   uniqueness byte, the player and the hitpoints all live inside the 336 bytes a
//   save file restores VERBATIM into that same seat, and a CSprite* is a heap address
//   the allocator hands out again.
//
//   So the question every module was asking -- "is the unit at this address still the
//   same unit?" -- has the answer YES in a game the record does not belong to. No
//   per-unit check can fix that; the discriminator has to be something the unit does
//   not carry. This is that discriminator: one counter, bumped by the ENGINE's own
//   game start, that no save file can restore and no unit can imitate.
//
// THE CLOCK, and why it fires on a LOAD as well as a new game
//   The bump rides `gameStartClear` (0x004EEC30), the function that zeroes
//   selectionHotkeys and recentSelectionTimes at the start of a game. That it also
//   covers loads is not an assumption -- it is forced by the engine's own call graph,
//   in which each of these functions has EXACTLY ONE caller (counted by scanning every
//   E8/E9 rel32 in .text, work/scratch/054/scdis.py):
//
//     0x004EF100  startGame          <- the only caller of all three below
//       0x004EF27A  call 0x004EEC30    gameStartClear      [we bump here]
//       0x004EF27F  call 0x004EEE00    (rest of the game init)
//       0x004EF32B  call 0x004EED10    startOrLoadGame
//                     0x004EED48  call 0x004CFEF0  loadSavedGame  <- the save is read HERE
//
//   0x004CFEF0 has one caller (0x004EED48). 0x004EED10 has one caller (0x004EF32B).
//   0x004EEC30 has one caller (0x004EF27A) and it PRECEDES 0x004EF32B on the straight
//   line through startGame -- the only early returns in that function are at
//   0x004EF182 (before our site) and 0x004EF305/0x004EF318 (after it). So a save can
//   only be deserialised by a call chain that has already run our bump, and the epoch
//   is therefore strictly older than every unit the load restores.
//
//   The engine agrees in its own code: 0x004EEC62 reads `pendingSaveName`
//   (0x006D1218) and SKIPS the hotkey clear when a load is pending -- a branch that
//   only exists because this function runs on the load path too.
//
//   Live corroboration is in the PR body: SESSION lines from a real run that starts a
//   game and then loads a save from the in-game menu.
//
// WHERE THE PATCH GOES, and why it is not byte 0 of the function
//   0x004EEC30's first three instructions are `PUSH EBX; PUSH EDI; CALL 0x0049BB90`,
//   and a 5-byte window at the entry would have to relocate that CALL -- which
//   sc_hook.cpp copies VERBATIM and therefore cannot do (it has no relocator, by
//   design). The next instruction is a self-contained five bytes:
//
//     0x004EEC30  53              PUSH EBX
//     0x004EEC31  57              PUSH EDI
//     0x004EEC32  E859CFFAFF      CALL 0x0049BB90        <- PC-relative, not relocatable
//     0x004EEC37  B8FFFF0000      MOV EAX,0xFFFF         <- the patch window, exactly 5B
//     0x004EEC3C  66A3D2F15700    MOV word ptr [0x57F1D2],AX
//
//   so the detour is spliced at 0x004EEC37. Nothing branches into the function body,
//   so this is reached on exactly the same occasions as the entry: once per call.
//
// HOW A MODULE ADOPTS IT
//   Not by having the epoch reach into it -- this file calls nothing and knows about no
//   other module. Each module keeps its own `g_session` and calls its own two-line
//   SessionSync() at the top of every entry point it has, INCLUDING its read-backs.
//   That way no path can observe or use a record without first passing the epoch test,
//   and there is no registration list to be one entry short of.
//
//   THE RULE FOR THE DROP: a record from another game is dropped, never REFUNDED.
//   Its minerals were spent in a game that no longer exists, and crediting them to the
//   game the player is now in would turn a stale-state bug into a resource exploit.
//   That is the opposite of what these modules do when a BUILDING dies, so the two
//   paths have to stay distinguishable -- hence a separate counter per module.
//
//   AND THE ORDERING RULE, which sc_circles is the reason for: the epoch is checked
//   BEFORE the record's pointers are dereferenced. A CSprite* held across a game end
//   is a freed heap address, and heap reuse makes it compare equal to a live one.

#ifndef SC_SESSION_H
#define SC_SESSION_H

#include <windows.h>

// The current game-session epoch. Starts at 1 and increases; 0 is never returned, so a
// module can use 0 for "never synced" without ambiguity. Safe to call from any thread
// and in any mode -- with no hook installed it simply never changes, which is correct,
// because in observe mode no module holds anything.
unsigned ScSessionEpoch(void);

// Splices the epoch bump into the engine's game start. `enabled` is false in observe
// mode, where the whole plugin writes nothing to game memory; the epoch then stays 1.
// Returns the number of hooks installed (0, 1 or 2 -- see ScSessionLogState).
int  ScSessionInstall(BYTE* moduleBase, bool enabled);
void ScSessionRemove(void);

// One line for the observer's marker channel and for the detach paths.
//
// It prints the LOAD WITNESS beside the epoch, and that pairing is the point: "the
// epoch bumped" and "a save was actually deserialised" are separate observations, and
// a run in which the second happened without the first is exactly the failure this
// mechanism must not have. Counting only bumps would leave that indistinguishable
// from a run in which no load was attempted (AGENTS.md, task 030).
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
