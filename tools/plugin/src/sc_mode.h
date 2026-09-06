// sc_mode.h -- %SCPLUGIN_MODE%, the plugin's whole-program permission level.
//
// This lived in sc_fanout.h because the fan-out was the first thing a mode gated. It is
// not the fan-out's: sc_screen and sc_console ask it too, and sc_screen.h was pulling a
// 235-line header in for a six-line enum -- which every file that includes sc_screen.h
// then inherited.

#ifndef SC_MODE_H
#define SC_MODE_H

#include "sc_env.h"

enum ScMode {
    SC_MODE_OBSERVE  = 0,  // task 008 behaviour: read-only, no hooks, no writes
    // Stage A: ONE hook (queueCommand), logs only, no behaviour change. The
    // %SCPLUGIN_MODE% string for it is still "hooktest", which is a launcher flag
    // in ten .ps1 files and cannot move -- but it has nothing to do with
    // hooktest.exe, the OFFLINE unit test that runs with no game at all.
    SC_MODE_LOGONLY  = 1,
    SC_MODE_SHADOW   = 2,  // stage B: capture the untruncated selection, log it
    SC_MODE_FANOUT   = 3   // stage C: fan orders out across the whole shadow list
};

// The name this mode goes into the log under. FROZEN: run-with-plugin.ps1 validates the
// set and the suites match on it.
static inline const char* ScModeName(ScMode m) {
    switch (m) {
        case SC_MODE_OBSERVE:  return "observe";
        case SC_MODE_LOGONLY:  return "hooktest";   // the frozen launcher spelling
        case SC_MODE_SHADOW:   return "shadow";
        case SC_MODE_FANOUT:   return "fanout";
    }
    return "?";
}

// Reads %SCPLUGIN_MODE%. Unset or unrecognised -> SC_MODE_OBSERVE, which is the off
// switch: in that mode nothing writes to game memory.
static inline ScMode ScModeResolve(void) {
    char buf[SC_ENV_MAX];
    if (!ScEnvRead("SCPLUGIN_MODE", buf, sizeof(buf))) return SC_MODE_OBSERVE;
    if (lstrcmpiA(buf, "hooktest") == 0) return SC_MODE_LOGONLY;   // the launcher spelling
    if (lstrcmpiA(buf, "logonly")  == 0) return SC_MODE_LOGONLY;   // what it actually is
    if (lstrcmpiA(buf, "shadow")   == 0) return SC_MODE_SHADOW;
    if (lstrcmpiA(buf, "fanout")   == 0) return SC_MODE_FANOUT;
    return SC_MODE_OBSERVE;
}

#endif // SC_MODE_H
