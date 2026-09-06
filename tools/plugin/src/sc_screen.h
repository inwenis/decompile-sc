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

// The stage column of sc_screen_patches.h runs 0..3 (tools/renderer_patch_sites.py,
// research/renderer-viewport.md 9.3). These name the three the code branches on, so
// a table that grows a stage 4 moves one line rather than three bare digits.
#define SC_WS_STAGE_MAX           3   // console + input, task 071: the top stage there is
#define SC_WS_STAGE_GRID          1   // at and above this the dirty grid is relocated
#define SC_WS_STAGE_SCROLL_CLAMP  3   // scroll.clamp.x.tiles (0x0049BBE6) is a stage-3 site

// %SCPLUGIN_WIDESCREEN% -- '1' turns the feature on. Off by default.
bool ScScreenWidescreenWanted(void);

// The highest 9.3 stage to apply, from %SCPLUGIN_WS_STAGE% (default 1).
// Stage 0 is the display mode alone; stage 1 adds the screen surface; stage 2
// adds the playfield geometry; stage 3 (task 071) widens the window-proc mouse
// clamps so posted/real input can REACH x=640..799 -- without it every mouse x
// past 639 is clamped to 639, so the right 160 columns are unclickable. This is
// what task 070's cnc-ddraw presentation needed and had no owner for. Moving the
// console INTO that region is a separate feature and now a shipped one -- see
// sc_console.h, %SCPLUGIN_CONSOLE_EDGE%, which found that 071's "the pixels do not
// follow" was really "nothing dirtied the rect".
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

// The viewport width in tiles the camera's scroll clamp is built from: 20 stock,
// SC_WS_SCREEN_W/32 once stage 3's scroll.clamp.x.tiles is live (0x0049BBE6).
// Read-only observers that PREDICT the clamp must ask this, or their "match"
// column lies the moment the geometry moves.
int ScScreenViewportTilesX(void);

// The geometry the table was generated for (SC_WS_SCREEN_W/H), for modules that
// must not pull the whole generated table into their own object file.
int ScScreenTargetWidth(void);
int ScScreenTargetHeight(void);

// The code-cave writer, exposed for hooktest: overwrite the `len`-byte window at
// `at` with `jmp cave` + NOPs, the cave holding `code` followed by `jmp at+len`.
// Both rel32s are computed here; a wrong one is a crash in the game, which is
// why the offline test executes a caved window before the game ever does.
bool ScScreenApplyCaveAt(BYTE* at, int len, const BYTE* code, int codeLen);

#endif  // SC_SCREEN_MOD_H
