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

// ---------------------------------------------------------------------------
// The fan-out core, hook-free.
//
// The four detours below do nothing but marshal arguments into these three
// functions. Splitting them out means the interesting half -- chunking, tag
// encoding, emission order, staleness, the byte budget -- can be driven and
// asserted byte-for-byte from a test process with no StarCraft and no hooks
// (src/hooktest.cpp part [7]). What is left untestable offline is only whether the
// ENGINE obeys the commands, which is what the human test is for.
// ---------------------------------------------------------------------------

// Where emitted commands go. In the game this is the queueCommand trampoline; in a
// test it is a capture buffer.
typedef void (__attribute__((fastcall)) *ScQueueFn)(const void*, unsigned);

// One unit the 12-cap is discarding, plus the 12-slot array as it stands BEFORE the
// engine's handler runs (that handler can evict an entry, and the evicted unit would
// otherwise be lost from both the output and our record).
void ScFanoutOnOverflow(unsigned count, unsigned long* outList, unsigned long unit);

// The engine's final, truncated selection, at the moment it is committed.
void ScFanoutOnSelect(unsigned count, unsigned long* units);

// One outgoing command. Returns true if it was FANNED OUT and the caller must
// therefore suppress the engine's own copy.
bool ScFanoutOnCommand(const unsigned char* buf, unsigned len);

// Point the core at a fake module image and a capture function. Test-only; passing
// a NULL emit restores normal operation.
void ScFanoutTestBegin(unsigned char* fakeModuleBase, ScQueueFn emit, int budget);

#endif // SC_FANOUT_H
