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
    SC_MODE_HOOKTEST = 1,  // stage A: ONE hook (queueCommand), logs only
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

// One STATS line. Written on BOTH detach paths -- including process exit, where the
// hooks are deliberately left spliced (the address space is going away) but the run's
// counters are still the thing a reader needs.
void ScFanoutLogStats(void);

#endif // SC_FANOUT_H
