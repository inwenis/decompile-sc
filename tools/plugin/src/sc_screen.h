// sc_screen.h -- task 034, the wider playfield.
//
// research/renderer-viewport.md 9.3 stages a wider screen; this is the code that
// executes it. Everything here is OFF unless %SCPLUGIN_WIDESCREEN% asks for it,
// and ignored outright in -Mode observe, which stays the plugin's off switch.
//
// The work is a set of instruction-operand rewrites in the running process --
// StarCraft.exe on disk is never touched -- plus one relocation: the dirty-block
// grid at 0x006CEFF8 is a fixed u8[30][40] boxed in by a live neighbour, so it
// moves into plugin-owned memory and every absolute reference to it is
// re-pointed. The table of rewrites is GENERATED and signature-checked; see
// sc_screen_patches.h and tools/renderer_patch_sites.py.

#ifndef SC_SCREEN_MOD_H
#define SC_SCREEN_MOD_H

#include <windows.h>

#include "sc_fanout.h"   // ScMode

// %SCPLUGIN_WIDESCREEN% -- '1' turns the feature on. Off by default.
bool ScScreenWidescreenWanted(void);

// The highest 9.3 stage to apply, from %SCPLUGIN_WS_STAGE% (default 1).
// Stage 0 is the display mode alone; stage 1 adds the screen surface; stage 2
// adds the playfield geometry.
int ScScreenStageWanted(void);

// Applies the patch table. Must run BEFORE the game's video init, which means
// the plugin has to be injected early (scinject --early); the install refuses
// and changes nothing if it finds the framebuffer already allocated.
void ScScreenInstall(BYTE* base, ScMode mode);

// Restores every byte this module wrote. Called on the FreeLibrary detach path
// only, like the detour engine's own removal.
void ScScreenRemove(void);

// One summary line for the run's log.
void ScScreenLogStats(void);

// True once the patches are in. Used by the read-back so a log can say which
// arm it was taken in.
bool ScScreenActive(void);

#endif  // SC_SCREEN_MOD_H
