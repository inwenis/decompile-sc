// sc_screen.h -- the wider playfield.
//
// research/renderer-viewport.md 9.3 stages a wider screen; this executes it. It is
// OFF unless %SCPLUGIN_WIDESCREEN% asks for it, and ignored in -Mode observe, the
// plugin's off switch.
//
// The work is instruction-operand rewrites in the running process -- StarCraft.exe
// on disk is never touched -- plus one relocation: the dirty-block grid at
// 0x006CEFF8 is a fixed u8[30][40] boxed in by a live neighbour, so it lives in
// plugin-owned memory and every absolute reference to it is re-pointed. The
// rewrite table is GENERATED and signature-checked; see sc_screen_patches.h and
// tools/renderer_patch_sites.py.

#ifndef SC_SCREEN_MOD_H
#define SC_SCREEN_MOD_H

#include <windows.h>

#include "sc_mode.h"

// The stage column of sc_screen_patches.h runs 0..3 (research/renderer-viewport.md
// 9.3); naming the three stages the code branches on keeps a table that grows a
// stage 4 to one edit rather than three bare digits.
#define SC_WS_STAGE_MAX           3   // highest stage the generated table defines
#define SC_WS_STAGE_GRID          1   // at and above this the dirty grid is relocated
#define SC_WS_STAGE_SCROLL_CLAMP  3   // scroll.clamp.x.tiles (0x0049BBE6) is a stage-3 site

// %SCPLUGIN_WIDESCREEN% -- '1' turns the feature on. Off by default.
bool ScScreenWidescreenWanted(void);

// The highest 9.3 stage to apply, from %SCPLUGIN_WS_STAGE% (default 1).
// Stage 0 is the display mode alone; stage 1 adds the screen surface; stage 2
// adds the playfield geometry; stage 3 widens the window-proc mouse clamps so
// posted/real input can REACH x=640..799 -- without it every mouse x past 639 is
// clamped to 639 and the right 160 columns are unclickable. Stage 3 buys input
// reach only: pixels in that band repaint only when something marks the rect
// dirty (sc_console.h, %SCPLUGIN_CONSOLE_EDGE%).
int ScScreenStageWanted(void);

// Must run BEFORE the game's video init, so the plugin has to be injected early
// (scinject --early); refuses and changes nothing once the framebuffer exists.
void ScScreenInstall(BYTE* base, ScMode mode);

// Restores every byte this module wrote; the FreeLibrary detach path only, like
// the detour engine's own removal.
void ScScreenRemove(void);

void ScScreenLogStats(void);

// True once the patches are in -- both the arm a read-back's log names and the
// gate for work that only makes sense on the wider screen (sc_console.h's edge move).
bool ScScreenActive(void);

// The viewport width in tiles the camera's scroll clamp is built from: 20 stock,
// SC_WS_SCREEN_W/32 once stage 3's scroll.clamp.x.tiles (0x0049BBE6) is live.
// Observers that PREDICT the clamp must ask this, or their "match" column lies.
int ScScreenViewportTilesX(void);

// The geometry the table targets (SC_WS_SCREEN_W/H), for modules that must not
// pull the whole generated table into their own object file.
int ScScreenTargetWidth(void);
int ScScreenTargetHeight(void);

// The code-cave writer, exposed for hooktest: overwrite the `len`-byte window at
// `at` with `jmp cave` + NOPs, the cave holding `code` then `jmp at+len`. Both
// rel32s are computed here and a wrong one crashes the game, so the offline test
// executes a caved window before the game ever does.
bool ScScreenApplyCaveAt(BYTE* at, int len, const BYTE* code, int codeLen);

#endif  // SC_SCREEN_MOD_H
