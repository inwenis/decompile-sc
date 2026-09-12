// sc_stormpresent.h -- the storm-side of the buffer->glass present.
//
// The exe renders 800 columns of fogged map into its framebuffer (0x6CEFF4) but
// only 640 reach the window: storm keeps its OWN virtual-screen width at
// [storm+0x5A7C4] = 640, and the per-frame present is ord350 (lock, builds the
// flip clip from that width) -> ord432 (copy buffer->locked via region) ->
// ord356 (unlock/flip, Blts the clip). See research/renderer-viewport.md 19.8.
//
// The mode: probe is the read-only instrument that decides which present path is live;
// widen hooks the present copy (ord432) and copies the x=640..799 strip from the
// 800-wide buffer to the primary after the engine's own copy, so all 800 columns reach
// the glass -- it writes game memory, so observe refuses it like every other writer.
//
// Every storm address is resolved from the LOADED module (GetModuleHandleA), never
// from the preferred base -- storm.dll's base is not fixed (research/pe-anatomy.md).

#ifndef SC_STORMPRESENT_H
#define SC_STORMPRESENT_H

#include <windows.h>

enum ScStormMode { SC_STORM_OFF = 0, SC_STORM_PROBE = 1, SC_STORM_WIDEN = 2 };

// Parse %SCPLUGIN_STORM_PRESENT%: 0/no -> OFF, "probe" -> PROBE, 1/y/widen -> WIDEN;
// unset -> WIDEN only once the widescreen playfield is live (stage >= 2), else OFF.
ScStormMode ScStormPresentModeWanted(void);

// exeBase is StarCraft.exe's load base, needed for the exe's own Ordinal_529
// region thunk; writeAllowed is false in observe mode and gates the widen.
void ScStormPresentInstall(BYTE* exeBase, bool writeAllowed);

// Read-only dump on the marker channel, safe from the observer's PollMarker.
void ScStormPresentLog(const char* tag);

// Restore anything the widen changed; log the run's counters.
void ScStormPresentRemove(void);
void ScStormPresentLogStats(void);

// The primary's live palette, 256 x {r,g,b,flags} (IDirectDrawSurface::GetPalette +
// IDirectDrawPalette::GetEntries on storm's primary), and its row count
// (GetSurfaceDesc; 0 when unreadable). For sc_menu.cpp, which presents at the glue
// screens where no ord432 call ever runs.
bool ScStormReadPalette(BYTE* out1024);
int  ScStormReadPrimaryRows(void);

#endif
