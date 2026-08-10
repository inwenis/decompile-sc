// sc_prodfan.h -- one Train click queues a unit at EVERY selected production building.
//
// Task 030, from the user's words: "can i also queu units when i have several building
// selected?" Task 024 made a drag box select all your Barracks; task 025 made one
// building hold more than five. Nobody joined them up.
//
// THE MECHANISM, and why it is small
//   Train is wire command 0x1F (research/command-opcodes.md). Its receive handler
//   `cmdrecvTrain` (0x004C1C20) is SINGLE-gated: it resets selectionIterator, calls
//   getActivePlayerNextSelection twice, and does nothing at all unless the SECOND call
//   returns null -- i.e. unless exactly one unit is selected. That is why a group of
//   buildings gains nothing today.
//
//   The fan-out already emits one Select+order pair per building for a building group:
//   the simulation refuses a building every selection slot but slot 0
//   (`addUnitToSelectionSlot`, research/building-groups.md 3), so `simSlots` is 1 and
//   every chunk of a building-group plan is exactly ONE unit long. A chunk of one is
//   precisely what cmdrecvTrain's gate wants. So the feature is not new machinery: it is
//   letting 0x1F ride the plan that task 024 already builds, under a guard.
//
//   research/command-opcodes.md 3.2 is the reason 0x1F is passthrough today, and it is
//   worth quoting because this file inverts it: "a fan-out chunk can be one unit long, so
//   replaying one would make it fire where the player's own selection never could." For a
//   >12 UNIT selection that is a real hazard -- 13 units means a chunk of 12 and a chunk
//   of 1, and the 13th unit would train alone, which the player never asked for. For a
//   BUILDING GROUP every chunk is 1, uniformly, so "one per chunk" is exactly "one per
//   building", which is what the player asked for. The guard below is that distinction
//   turned into a condition, not a softening of the rule.
//
// THE RESOURCE RULE, inherited from task 025 and not weakened
//   THE ENGINE PAYS FOR EVERY ITEM AND THE PLUGIN NEVER SPENDS A MINERAL. Each replayed
//   Train reaches the engine's own cmdrecvTrain, which runs its own tech gate and calls
//   addToBuildQueue (0x00467250) -- the function that checks affordability and deducts the
//   cost. The plugin writes no resource global on any path in this file; it emits
//   commands and reads memory. So "N buildings means N x cost, paid by the engine, once
//   each" is a property of the shape rather than of bookkeeping, and a building that
//   cannot afford, cannot build, or is already full is refused by the engine for free.
//
// WHAT THIS NEVER DOES
//   It installs no hook of its own -- the fan-out's existing queueCommand detour is the
//   only thing involved -- and it writes no game memory at all. Off unless
//   %SCPLUGIN_PRODFAN% asks for it; inert in `-Mode observe`, which stays the whole
//   plugin's read-only off switch.

#ifndef SC_PRODFAN_H
#define SC_PRODFAN_H

#include <windows.h>

// Reads %SCPLUGIN_PRODFAN%. Unset/0 -> disabled, and with it disabled sc_fanout keeps
// 0x1F on the passthrough list exactly as research/command-opcodes.md 5.1 has it.
bool ScProdFanEnabled(void);

// Called once at attach, before anything reads game memory. `enabled` is resolved by the
// caller so that observe mode can refuse the feature without this file having to know
// about modes.
void ScProdFanInit(BYTE* moduleBase, bool enabled);

// THE ORACLE, and it is deliberately independent of the feature.
//
// One line per building in the CURRENT shadow selection, each carrying that building's
// own five queue slots read straight out of its CUnit+0x98, plus a summary line carrying
// the player's minerals and gas from the resource globals. This is what acceptance
// criteria 3 and 4 are asserted from: each building's queue length comes from that
// building's memory, and the resource reconciliation comes from the globals, neither
// from the screen and neither from a counter this plugin maintains.
//
// It runs whether or not the feature is enabled and whether or not the mode is observe,
// because the baseline measurement -- "with N buildings selected, how many gain an item
// in a STOCK game" -- is taken with it, and an oracle that only exists in the treatment
// arm can prove nothing about the control arm. Read-only, observer thread.
void ScProdFanLogState(const char* tag);

// One STATS line, written on the detach paths beside the other subsystems'.
void ScProdFanLogStats(void);

// THE ONE PATCH. Installs the detour on the Train button's condition (0x00428E60) so the
// button is DRAWN for a same-type building group -- without it there is no command to fan
// out, because the client never emits one (measured: the button is absent from the card
// entirely with several buildings selected). Returns 1 on success, 0 on failure, and a
// failure DISABLES the feature rather than leaving it half-armed. No-op unless enabled.
int  ScProdFanInstallGate(void);
void ScProdFanRemoveGate(void);

// ---------------------------------------------------------------------------
// The policy, hook-free -- driven from hooktest.exe with no StarCraft in sight.
// ---------------------------------------------------------------------------

// Why a Train command was, or was not, fanned out across the selection. Ordered so that
// the log line and the offline test can name the exact term that decided it, rather than
// reporting an undifferentiated "it did not fan out" (AGENTS.md: an absence assertion has
// to name what it is the absence of).
enum ScProdFanVerdict {
    SC_PRODFAN_OK          = 0,  // fan it out: a same-type building group, chunk size 1
    SC_PRODFAN_OFF         = 1,  // %SCPLUGIN_PRODFAN% is not set
    SC_PRODFAN_NOT_GROUP   = 2,  // simSlots != 1 -- this is a unit selection, not a
                                 // building group, so a chunk could be >1 or a lone tail
    SC_PRODFAN_ONE_BUILDING = 3, // only one building selected: vanilla already handles it
    SC_PRODFAN_MIXED_TYPES = 4,  // the group holds more than one building type
    SC_PRODFAN_BAD_LEN     = 5   // not the 3 bytes the dispatcher consumes for 0x1F
};

const char* ScProdFanVerdictName(int v);

// The decision, given the shadow list the fan-out is holding. `types` is one unit-type id
// per selected building, in shadow order; `simSlots` is sc_fanout's own chunk size.
// Pure: no game memory, no globals beyond the enable flag.
int ScProdFanDecide(const WORD* types, int count, int simSlots, unsigned cmdLen);

// Test-only: drive the enable flag directly, so the offline suite can exercise both arms
// without touching the environment.
void ScProdFanTestSetEnabled(bool on);

// Test-only counters.
enum ScProdFanStat {
    SC_PRODFAN_STAT_FANNED = 0,     // Train commands fanned out across a group
    SC_PRODFAN_STAT_REFUSED = 1,    // Train commands seen with a group up, and refused
    SC_PRODFAN_STAT_BUILDINGS = 2,  // buildings those fanned commands reached
    SC_PRODFAN_STAT_LIT = 3,        // times the button condition was relaxed for a group
    SC_PRODFAN_STAT__COUNT = 4
};
int  ScProdFanStat(int which);
void ScProdFanCountFanout(int buildings);
void ScProdFanCountRefusal(void);

#endif // SC_PRODFAN_H
