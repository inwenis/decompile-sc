// sc_prodfan.h -- one Train click queues a unit at EVERY selected production building.
//
// Train is wire command 0x1F (research/command-opcodes.md). Its receive handler
// `cmdrecvTrain` (0x004C1C20) is SINGLE-gated: it acts only when a second
// `getActivePlayerNextSelection` returns null -- exactly one unit selected -- so a building
// group gains nothing from a stock Train click. The simulation refuses a building every
// selection slot but slot 0 (research/building-groups.md 3), so `simSlots` is 1 and a
// building-group fan-out chunk is always exactly ONE unit -- precisely what that gate wants.
// research/command-opcodes.md 3.2 keeps 0x1F off the replay list because a one-unit chunk
// "would make it fire where the player's own selection never could": true of a >12 UNIT
// selection, whose tail chunk of 1 trains alone; untrue of a BUILDING GROUP, whose chunks
// are all 1. The guard below is that distinction, not a softening of the rule.
//
// THE ENGINE PAYS FOR EVERY ITEM AND THE PLUGIN NEVER SPENDS A MINERAL: a replayed Train
// reaches cmdrecvTrain, which runs its own tech gate and calls addToBuildQueue (0x00467250)
// -- the affordability check and the deduction both -- and this file writes no resource
// global on any path. A building that cannot afford, cannot build, or is already full is
// refused by the engine for free, so nothing here counts cost or queue room per building.

#ifndef SC_PRODFAN_H
#define SC_PRODFAN_H

#include <windows.h>

// Reads %SCPLUGIN_PRODFAN%. Unset/0 -> disabled, and with it disabled sc_fanout keeps
// 0x1F on the passthrough list exactly as research/command-opcodes.md 5.1 has it.
bool ScProdFanEnabled(void);

// Called once at attach, before anything reads game memory. `enabled` is resolved by the
// caller so observe mode can refuse the feature without this file knowing about modes.
void ScProdFanInit(BYTE* moduleBase, bool enabled);

// THE ORACLE, deliberately independent of the feature: one line per building in the CURRENT
// shadow selection, each carrying that building's own five queue slots read straight out of
// its CUnit+0x98, plus a summary line carrying minerals and gas from the resource globals.
// Every asserted number therefore comes from game memory -- never from the screen, never
// from a counter this plugin maintains.
//
// It runs whether or not the feature is enabled and whatever the mode, because the baseline
// "with N buildings selected, how many gain an item in a STOCK game" is measured with it,
// and an oracle that only exists in the treatment arm proves nothing about the control arm.
// Read-only, observer thread.
void ScProdFanLogState(const char* tag);

// One STATS line, written on the detach paths beside the other subsystems'.
void ScProdFanLogStats(void);

// THE ONE PATCH: a detour on the Train button's condition (0x00428E60), so the button is
// DRAWN for a same-type building group -- without it there is no command to fan out,
// because the client never emits one (measured: with several buildings selected the button
// is absent from the card entirely). A failed install DISABLES the feature rather than
// leaving it half-armed. No-op unless enabled.
int  ScProdFanInstall(void);
void ScProdFanRemove(void);

// ---------------------------------------------------------------------------
// The policy, hook-free -- driven from hooktest.exe with no StarCraft in sight.
// ---------------------------------------------------------------------------

// Why a Train command was, or was not, fanned out across the selection. Ordered so that the
// log line and the offline test can name the exact term that decided it, rather than an
// undifferentiated "it did not fan out" -- an absence assertion has to name what it is the
// absence of (AGENTS.md § "Oracles: absence and defect-era checks").
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
// per selected building, in shadow order; `simSlots` is sc_fanout's own chunk size. Pure:
// no game memory, no globals beyond the enable flag.
int ScProdFanDecide(const WORD* types, int count, int simSlots, unsigned cmdLen);

// Test-only: drive the enable flag directly, so the offline suite can exercise both arms
// without touching the environment.
void ScProdFanTestSetEnabled(bool on);

// The counters the STATS line and the oracle summary print; sc_fanout bumps the fan-out
// ones from the command path.
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
