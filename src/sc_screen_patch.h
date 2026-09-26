// sc_screen_patch.h -- the record every generated widescreen table is made of, and the
// preset struct that pairs one table with its geometry. Hand-written: each generated
// sc_screen_patches_<W>x<H>.h includes it; sc_screen_presets.h lists the presets.
//
// A record longer than these arrays does not compile, so the caps here must be at least
// the generator's own (SC_MAX_PATCH_LEN / SC_MAX_CAVE_LEN in tools/renderer_patch_sites.py).

#ifndef SC_SCREEN_PATCH_H
#define SC_SCREEN_PATCH_H

#include <windows.h>

#define SC_WS_STOCK_W         640
#define SC_WS_STOCK_H         480
#define SC_WS_STOCK_GRID_VA   0x006CEFF8u
#define SC_WS_MAX_PATCH_LEN   32
#define SC_WS_MAX_CAVE_LEN    32
#define SC_WS_NO_FIXUP        0xFFu

typedef struct {
    DWORD       va;          // static VA, rebased by the plugin
    BYTE        len;
    BYTE        stage;       // 0..3 -- see research/renderer-viewport.md 9.3; 3 = console/input
    BYTE        fixupOff;    // SC_WS_NO_FIXUP, or the offset of a dword
    BYTE        caveLen;     // 0 = in-place rewrite; else `cave` holds the code the window jumps to
    DWORD       fixupAddend; // filled with (relocated grid base + this)
    BYTE        expect[SC_WS_MAX_PATCH_LEN];
    BYTE        patch[SC_WS_MAX_PATCH_LEN];  // a cave: jmp rel32 (filled at runtime) + NOPs
    BYTE        cave[SC_WS_MAX_CAVE_LEN];    // the re-encoded window; the plugin appends jmp back
    const char* name;
    const char* note;
} ScScreenPatch;

// One geometry preset: its numbers and its table. sc_screen_presets.h lists them.
typedef struct ScScreenGeometry {
    const char*          name;       // as %SCPLUGIN_WS_GEOMETRY% spells it, e.g. "1280x880"
    int                  w, h;       // the screen
    int                  pfW, pfH;   // the playfield (the console takes the rest)
    int                  gridCols, gridRows, gridBytes;
    int                  terrainPitch, terrainSize, terrainRows;
    int                  consoleShiftY;   // PF_H - 400; 0 at the stock playfield height
    const ScScreenPatch* patches;
    size_t               patchCount;
} ScScreenGeometry;

#endif  // SC_SCREEN_PATCH_H
