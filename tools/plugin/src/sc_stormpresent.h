// sc_stormpresent.h -- task 074. The storm-side of the buffer->glass present.
//
// research/renderer-viewport.md 19.8 left the last widescreen wall inside
// storm.dll: the exe computes 800 columns of fogged map into its framebuffer
// (0x6CEFF4) and the window shows 640. The exe's per-frame present is
//   storm ord350 (lock) -> ord432 (copy buffer->locked via region) -> ord356 (unlock/flip)
// and storm holds its OWN virtual-screen width at [storm+0x5A7C4] = 640, from
// which ord350 builds the flip clip and ord356 Blts it. See sc_stormpresent.cpp.
//
// Two things this module can do, chosen by %SCPLUGIN_STORM_PRESENT%:
//   probe  -- READ-ONLY: log storm's live geometry, the flip clip, the fallback
//             lock pointer, the surface table and the per-frame region rect count,
//             on the marker channel. Works in any mode; writes nothing to game
//             memory. This is the instrument that decides which present path is live.
//   1/widen-- coerce storm's virtual screen to the widescreen width so the present
//             carries all 800 columns. Writes game memory, so it is refused in
//             observe exactly like every other writer.
//
// Every storm address is resolved from the LOADED module (GetModuleHandleA), never
// from the preferred base -- storm.dll's base is not fixed (research/pe-anatomy.md).

#ifndef SC_STORMPRESENT_H
#define SC_STORMPRESENT_H

#include <windows.h>

enum ScStormMode { SC_STORM_OFF = 0, SC_STORM_PROBE = 1, SC_STORM_WIDEN = 2 };

// Parse %SCPLUGIN_STORM_PRESENT%: unset/0/no -> OFF, "probe" -> PROBE,
// 1/y/widen -> WIDEN.
ScStormMode ScStormPresentModeWanted(void);

// exeBase is StarCraft.exe's load base (for the exe's own Ordinal_529 region
// thunk). writeAllowed is false in observe mode. Resolves storm's base and logs
// what it found; installs the widen only when the mode is WIDEN and writes are
// allowed.
void ScStormPresentInstall(BYTE* exeBase, bool writeAllowed);

// Read-only dump on the marker channel (called from the observer's PollMarker).
void ScStormPresentLog(const char* tag);

// Restore anything the widen changed; log the run's counters.
void ScStormPresentRemove(void);
void ScStormPresentLogStats(void);

#endif
