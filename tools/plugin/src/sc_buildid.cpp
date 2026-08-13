// sc_buildid.cpp -- see sc_buildid.h.

#include "sc_buildid.h"

// Both defines come from tools/plugin/build.ps1 as -DSC_BUILD_ID="..." /
// -DSC_BUILD_SRC="...". The fallbacks exist so a hand-compiled or IDE build
// still compiles -- NOT so it can pass for a real one. "UNSTAMPED" is not a hex
// digest, so it never matches a source digest, and both build.ps1 and
// run-with-plugin.ps1 reject it by name.
#ifndef SC_BUILD_ID
#define SC_BUILD_ID "UNSTAMPED"
#endif
#ifndef SC_BUILD_SRC
#define SC_BUILD_SRC "UNSTAMPED"
#endif

#define SC_BUILD_STAMP_PREFIX "SCPLUGIN_BUILD_ID="

// ONE literal, and everything else points into it. `used` keeps it in the image
// even when nothing references it -- the stamp has to be greppable out of a DLL
// that is sitting on disk, not merely reachable from code that runs.
__attribute__((used))
static const char g_scBuildStamp[] =
    SC_BUILD_STAMP_PREFIX SC_BUILD_ID " SRC=" SC_BUILD_SRC;

const char* ScBuildStamp(void) { return g_scBuildStamp; }

const char* ScBuildStampShort(void) {
    return g_scBuildStamp + (sizeof(SC_BUILD_STAMP_PREFIX) - 1);
}
