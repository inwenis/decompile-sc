// sc_mode.h -- %SCPLUGIN_MODE%, the plugin's whole-program permission level.
//
// Stands apart from sc_fanout.h: sc_screen.h and scplugin.cpp need the mode too, and a
// six-line enum must not drag the whole fan-out header into every file that includes
// sc_screen.h.

#ifndef SC_MODE_H
#define SC_MODE_H

#include "sc_env.h"

enum ScMode {
    SC_MODE_OBSERVE  = 0,  // read-only: no hooks, no writes
    // Stage A: ONE hook (queueCommand), logs only, no behaviour change. Its
    // %SCPLUGIN_MODE% spelling is "hooktest" -- a frozen launcher flag across the .ps1
    // suites, unrelated to hooktest.exe, the OFFLINE unit test that runs with no game.
    SC_MODE_LOGONLY  = 1,
    SC_MODE_SHADOW   = 2,  // stage B: capture the untruncated selection, log it
    SC_MODE_FANOUT   = 3   // stage C: fan orders out across the whole shadow list
};

// The name this mode goes into the log under. FROZEN: run-with-plugin.ps1 validates the
// set and the suites match on it.
static inline const char* ScModeName(ScMode m) {
    switch (m) {
        case SC_MODE_OBSERVE:  return "observe";
        case SC_MODE_LOGONLY:  return "hooktest";
        case SC_MODE_SHADOW:   return "shadow";
        case SC_MODE_FANOUT:   return "fanout";
    }
    return "?";
}

// Unset or unrecognised -> SC_MODE_OBSERVE, the off switch: in that mode nothing
// writes to game memory.
static inline ScMode ScModeResolve(void) {
    char buf[SC_ENV_MAX];
    if (!ScEnvRead("SCPLUGIN_MODE", buf, sizeof(buf))) return SC_MODE_OBSERVE;
    if (lstrcmpiA(buf, "hooktest") == 0) return SC_MODE_LOGONLY;
    if (lstrcmpiA(buf, "logonly")  == 0) return SC_MODE_LOGONLY;
    if (lstrcmpiA(buf, "shadow")   == 0) return SC_MODE_SHADOW;
    if (lstrcmpiA(buf, "fanout")   == 0) return SC_MODE_FANOUT;
    return SC_MODE_OBSERVE;
}

#endif // SC_MODE_H
