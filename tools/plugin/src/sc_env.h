// sc_env.h -- reading %SCPLUGIN_*%, once.
//
// Every feature in this plugin has an off switch and most have a cap, and each one
// grew its own four-line copy of "GetEnvironmentVariableA into a stack buffer, refuse
// an unset or over-long value, interpret the first character". There were eleven of
// them, spelling the same three rules.
//
// The rules themselves stay exactly as they were, because .ps1 suites set these:
//
//   ScEnvOptIn   OFF unless the value starts 1/y/Y. The default for anything that
//                writes to game memory or costs a scan per frame.
//   ScEnvFlag    ON unless the value starts 0/n/N, with the caller choosing what an
//                UNSET variable means. The default for something already shipped.
//   ScEnvInt     a clamped integer; an unset, over-long or unparseable value is the
//                caller's default.
//
// Header-only: three small reads, no state, nothing to add to a build list.

#ifndef SC_ENV_H
#define SC_ENV_H

#include <windows.h>
#include <stdlib.h>

// The longest value any of these takes is a small integer or a word like "widen".
#define SC_ENV_MAX 32

static inline bool ScEnvRead(const char* name, char* out, DWORD outLen) {
    const DWORD n = GetEnvironmentVariableA(name, out, outLen);
    if (n == 0 || n >= outLen) { out[0] = '\0'; return false; }
    return true;
}

static inline bool ScEnvOptIn(const char* name) {
    char buf[SC_ENV_MAX];
    if (!ScEnvRead(name, buf, sizeof(buf))) return false;
    return buf[0] == '1' || buf[0] == 'y' || buf[0] == 'Y';
}

static inline bool ScEnvFlag(const char* name, bool whenUnset) {
    char buf[SC_ENV_MAX];
    if (!ScEnvRead(name, buf, sizeof(buf))) return whenUnset;
    return !(buf[0] == '0' || buf[0] == 'n' || buf[0] == 'N');
}

static inline int ScEnvInt(const char* name, int def, int lo, int hi) {
    char buf[SC_ENV_MAX];
    if (!ScEnvRead(name, buf, sizeof(buf))) return def;
    int v = atoi(buf);
    if (v < lo) v = lo;
    if (v > hi) v = hi;
    return v;
}

#endif // SC_ENV_H
