// sc_screen_presets.h -- the geometry presets the plugin ships, one generated table each.
//
// %SCPLUGIN_WS_GEOMETRY% names one ("1280x880"); unset means the first. To add a preset:
//   1. python tools/renderer_patch_sites.py --width W --height H   (playfield = H - 80)
//   2. include the file below and add its SC_WS_GEOM_ to the list and the max
//   3. prove it in game: $env:SCPLUGIN_WS_GEOMETRY='WxH' then test-widescreen.ps1
//      off-screen. The generator checks bytes against the binary, never the picture.
// Width is constrained: W + 32 must be a sum of exactly three powers of two (the
// terrain pitch's shift decomposition); the generator refuses others. Height is free.

#ifndef SC_SCREEN_PRESETS_H
#define SC_SCREEN_PRESETS_H

#include "sc_screen_patches_1280x880.h"
#include "sc_screen_patches_1280x720.h"
#include "sc_screen_patches_1536x864.h"

static const ScScreenGeometry* const SC_WS_PRESETS[] = {
    &SC_WS_GEOM_1280x880,   // default: 2x wide, 2x tall playfield (1280x800)
    &SC_WS_GEOM_1280x720,   // 16:9 -- 1.5x fills a 1080p screen with no side bars
    &SC_WS_GEOM_1536x864,   // 16:9 -- 1.25x on 1080p: more map, smaller UI
};
#define SC_WS_PRESET_COUNT (sizeof(SC_WS_PRESETS) / sizeof(SC_WS_PRESETS[0]))

// The largest table, for statics sized by the table (sc_screen.cpp's saved originals).
#define SC_WS_MAX2(a, b) ((a) > (b) ? (a) : (b))
#define SC_WS_PATCH_COUNT_MAX \
    SC_WS_MAX2(SC_WS_PATCH_COUNT_1280x880, \
               SC_WS_MAX2(SC_WS_PATCH_COUNT_1280x720, SC_WS_PATCH_COUNT_1536x864))

#endif  // SC_SCREEN_PRESETS_H
