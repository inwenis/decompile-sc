// sc_buildid.h -- what commit and what source bytes this DLL was built from.
//
// Issue #73 / task 056. Before this, two DLLs from different commits were
// indistinguishable: no log, transcript or frame could name the build that
// produced it, and answering "which build is the user running" took twenty
// minutes of hashing files and comparing mtimes against commit timestamps
// (2026-08-12) -- a question a version string answers instantly.
//
// The values are stamped in by tools/plugin/build.ps1 (-DSC_BUILD_ID /
// -DSC_BUILD_SRC). A build that did NOT go through build.ps1 compiles fine and
// reports "UNSTAMPED", which is a value no gate accepts -- an unstamped DLL is
// unknown, and unknown is never treated as current.

#ifndef SC_BUILDID_H
#define SC_BUILDID_H

#ifdef __cplusplus
extern "C" {
#endif

// The whole embedded string: "SCPLUGIN_BUILD_ID=<id> SRC=<digest>".
// tools/plugin/sc-build-id.ps1 finds this exact literal in the file's bytes,
// which is how a DLL nobody is running still says what it is.
const char* ScBuildStamp(void);

// The same string with the "SCPLUGIN_BUILD_ID=" prefix skipped, for logging:
// "<id> SRC=<digest>". A POINTER INTO the same literal, deliberately -- not a
// second copy that could drift from the one the file carries, so what the ATTACH
// banner prints and what a reader greps out of the DLL cannot disagree.
const char* ScBuildStampShort(void);

#ifdef __cplusplus
}
#endif

#endif  // SC_BUILDID_H
