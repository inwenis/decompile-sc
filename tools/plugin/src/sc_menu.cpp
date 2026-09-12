// sc_menu.cpp -- see sc_menu.h.

#include <windows.h>
#include <string.h>

#include "sc_menu.h"
#include "sc_addresses.h"
#include "sc_engine.h"
#include "sc_env.h"
#include "sc_hook.h"
#include "sc_log.h"
#include "sc_screen.h"
#include "sc_stormpresent.h"

#define SC_MENU_SENTINELS  8
// The composer runs ~18,000 times a second at a glue screen (CONSOLESTATS frames=322046
// over 18 s at the main menu), so everything here is gated on wall time, not on calls.
#define SC_MENU_PALETTE_MS 50   // palette poll: a fade takes ~0.5 s
#define SC_MENU_COPY_MS    15   // outside-rect present, ~60 Hz: the cursor over the stars
#define SC_MENU_LOG_REMAPS 20

typedef BOOL (__attribute__((stdcall)) *ScLockFn)(int surface, RECT* rect, BYTE** ptr, int* pitch, int flags);
typedef BOOL (__attribute__((stdcall)) *ScUnlockFn)(int surface, BYTE* ptr, int a, int b);
typedef void (__attribute__((stdcall)) *ScRestoreFn)(DWORD bitmap);

static bool     g_armed = false;
static bool     g_atMenu = false;
static int      g_w = 0, g_h = 0, g_dx = 0, g_dy = 0;
static BYTE*    g_levels = NULL;   // w*h star level ids
static BYTE*    g_mapped = NULL;   // w*h palette indices for the live palette
static BYTE     g_lut[SC_MENU_LEVELS];
static bool     g_lutValid = false;
static BYTE     g_pal[256 * 4];
static bool     g_palValid = false;
static SIZE_T   g_sentinel[SC_MENU_SENTINELS];
static int      g_sentinelN = 0;
static bool     g_needCopy = false;
static DWORD    g_lastPalMs = 0, g_lastCopyMs = 0;
static int      g_rows = -1;
static ScHook   g_hkRestore;
static unsigned g_fills = 0, g_copies = 0, g_remaps = 0, g_lockFails = 0, g_palFails = 0;

bool ScMenuWanted(void) { return ScEnvOptIn("SCPLUGIN_MENU_CENTRE"); }
bool ScMenuArmed(void)  { return g_armed; }
void ScMenuRequestCopy(void) { g_needCopy = true; }

void ScMenuOffset(int* dx, int* dy) {
    if (dx) *dx = (ScScreenTargetWidth()  - SC_SCREEN_W) / 2;
    if (dy) *dy = (ScScreenTargetHeight() - SC_SCREEN_H) / 2;
}

// Whole rows above and below the glue rect; beside it, the two side bands only.
static void CopyOutsideGlue(BYTE* dst, DWORD dstPitch, const BYTE* src, DWORD srcPitch, int rows) {
    const size_t right = (size_t)(g_w - g_dx - SC_SCREEN_W);
    for (int y = 0; y < rows; ++y) {
        BYTE* d = dst + (SIZE_T)y * dstPitch;
        const BYTE* s = src + (SIZE_T)y * srcPitch;
        if (y < g_dy || y >= g_dy + SC_SCREEN_H) {
            memcpy(d, s, (size_t)g_w);
        } else {
            memcpy(d, s, (size_t)g_dx);
            memcpy(d + g_dx + SC_SCREEN_W, s + g_dx + SC_SCREEN_W, right);
        }
    }
}

// The framebuffer, or NULL unless it is the preset's size: a buffer the table did not
// resize is 640 wide, and nothing here may write past it.
static BYTE* Buffer(void) {
    BYTE* desc = (BYTE*)ScRuntimeAddr(SC_VA_SCREEN_BITMAP);
    if (!ScReadableAt(desc, 8)) return NULL;
    if (*(WORD*)(desc + SC_BITMAP_OFF_WIDTH) != g_w || *(WORD*)(desc + SC_BITMAP_OFF_HEIGHT) != g_h)
        return NULL;
    return *(BYTE**)(desc + SC_BITMAP_OFF_DATA);
}

static void TakePalette(const BYTE* pal) {
    if (g_palValid && memcmp(g_pal, pal, sizeof(g_pal)) == 0) return;
    memcpy(g_pal, pal, sizeof(g_pal));
    g_palValid = true;
    BYTE lut[SC_MENU_LEVELS];
    ScMenuLevelsFor(g_pal, lut);
    if (g_lutValid && memcmp(lut, g_lut, sizeof(lut)) == 0) return;
    memcpy(g_lut, lut, sizeof(lut));
    g_lutValid = true;
    const SIZE_T n = (SIZE_T)g_w * (SIZE_T)g_h;
    for (SIZE_T i = 0; i < n; ++i) g_mapped[i] = g_lut[g_levels[i]];
    if (++g_remaps <= SC_MENU_LOG_REMAPS)
        ScLog("MENU palette: star levels -> indices %u %u %u %u = rgb (%u,%u,%u) (%u,%u,%u)",
              g_lut[0], g_lut[1], g_lut[2], g_lut[3],
              g_pal[g_lut[0] * 4], g_pal[g_lut[0] * 4 + 1], g_pal[g_lut[0] * 4 + 2],
              g_pal[g_lut[3] * 4], g_pal[g_lut[3] * 4 + 1], g_pal[g_lut[3] * 4 + 2]);
}

void ScMenuOnFrame(bool atMenu) {
    g_atMenu = g_armed && atMenu;
    if (!g_atMenu) return;
    // The cursor must be in the buffer when the restore-under runs. Bit 0x20 is sticky
    // (only the layer-table init clears it), so this writes once, not every frame.
    BYTE* cursor = (BYTE*)ScRuntimeAddr(SC_VA_GRAPHIC_LAYERS + SC_LAYER_CURSOR * SC_LAYER_STRIDE +
                                        SC_LAYER_OFF_FLAGS);
    if (!(*cursor & SC_LAYER_FLAG_ALWAYS_DRAW)) *cursor |= SC_LAYER_FLAG_ALWAYS_DRAW;

    const DWORD now = GetTickCount();
    if (!g_palValid || now - g_lastPalMs >= SC_MENU_PALETTE_MS) {
        g_lastPalMs = now;
        BYTE pal[256 * 4];
        if (ScStormReadPalette(pal)) TakePalette(pal);
        else ++g_palFails;
    }
    if (!g_lutValid) return;
    BYTE* buf = Buffer();
    if (!buf) return;
    // Refill when a sentinel star is not what the live palette wants: after a palette
    // change, and after the composer's whole-screen clear. The buffer is cursor-free here
    // (the previous compose restored under it), so a star can only differ for those.
    for (int i = 0; i < g_sentinelN; ++i) {
        if (buf[g_sentinel[i]] != g_mapped[g_sentinel[i]]) {
            CopyOutsideGlue(buf, (DWORD)g_w, g_mapped, (DWORD)g_w, g_h);
            ++g_fills;
            g_needCopy = true;
            return;
        }
    }
}

static void Present(void) {
    const DWORD now = GetTickCount();
    if (!g_needCopy && now - g_lastCopyMs < SC_MENU_COPY_MS) return;
    BYTE* buf = Buffer();
    if (!buf || !g_lutValid) return;
    if (g_rows < 0) {
        const int r = ScStormReadPrimaryRows();
        g_rows = (r > 0 && r < g_h) ? r : g_h;
    }
    BYTE* ptr = NULL;
    int pitch = 0;
    if (!((ScLockFn)ScRuntimeAddr(SC_VA_STORM_LOCK_THUNK))(0, NULL, &ptr, &pitch, 0) || !ptr) {
        ++g_lockFails;
        return;
    }
    if (pitch >= g_w) {
        CopyOutsideGlue(ptr, (DWORD)pitch, buf, (DWORD)g_w, g_rows);
        ++g_copies;
    }
    ((ScUnlockFn)ScRuntimeAddr(SC_VA_STORM_UNLOCK_THUNK))(0, ptr, 0, 0);
    g_lastCopyMs = now;
    g_needCopy = false;
}

static void __attribute__((stdcall)) SC_GAME_ENTRY HkRestoreUnder(DWORD bitmap) {
    if (g_atMenu && bitmap == ScRuntimeVa(SC_VA_SCREEN_BITMAP) && ScScreenActive()) Present();
    ((ScRestoreFn)g_hkRestore.trampoline)(bitmap);
}

// 0x0041DEB0 opens PUSH EBP / MOV EBP,ESP / SUB ESP,0xC: 6 bytes, 3 whole instructions,
// none PC-relative (the frame composer's shape, one immediate apart).
static const BYTE kPrologueRestore[] = { 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x0C };

void ScMenuInstall(bool writeAllowed) {
    g_armed = g_atMenu = false;
    g_lutValid = g_palValid = g_needCopy = false;
    g_fills = g_copies = g_remaps = g_lockFails = g_palFails = 0;
    g_rows = -1;
    memset(&g_hkRestore, 0, sizeof(g_hkRestore));
    if (!ScMenuWanted()) return;
    if (!writeAllowed) {
        ScLog("MENU: %%SCPLUGIN_MENU_CENTRE%% set but the mode is observe -- IGNORED. "
              "Observe writes nothing to game memory.");
        return;
    }
    if (!ScScreenWidescreenWanted() || ScScreenStageWanted() < SC_WS_STAGE_MAX) {
        ScLog("MENU: %%SCPLUGIN_MENU_CENTRE%% needs -Widescreen 1 at stage 3 (the mouse must "
              "reach a centred menu) -- IGNORED.");
        return;
    }
    g_w = ScScreenTargetWidth();
    g_h = ScScreenTargetHeight();
    ScMenuOffset(&g_dx, &g_dy);
    const SIZE_T n = (SIZE_T)g_w * (SIZE_T)g_h;
    if (!g_levels) g_levels = (BYTE*)VirtualAlloc(NULL, n, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!g_mapped) g_mapped = (BYTE*)VirtualAlloc(NULL, n, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!g_levels || !g_mapped) {
        ScLog("MENU: starfield allocation (%dx%d) failed -- IGNORED.", g_w, g_h);
        return;
    }
    memset(g_levels, 0, n);
    const int lit = ScMenuBuildStars(g_levels, g_w, g_h);
    // Sentinels: the first lit cell outside the glue rect after each 1/8 of the field.
    g_sentinelN = 0;
    for (int k = 0; k < SC_MENU_SENTINELS; ++k) {
        for (SIZE_T j = (SIZE_T)k * n / SC_MENU_SENTINELS; j < n; ++j) {
            const int x = (int)(j % (SIZE_T)g_w), y = (int)(j / (SIZE_T)g_w);
            const bool inside = x >= g_dx && x < g_dx + SC_SCREEN_W && y >= g_dy && y < g_dy + SC_SCREEN_H;
            if (g_levels[j] && !inside) { g_sentinel[g_sentinelN++] = j; break; }
        }
    }
    if (!ScHookInstall(&g_hkRestore, "restoreUnder", ScRuntimeAddr(SC_VA_RESTORE_UNDER),
                       (void*)&HkRestoreUnder, (int)sizeof(kPrologueRestore),
                       kPrologueRestore, (int)sizeof(kPrologueRestore))) {
        ScLog("MENU: restore-under hook failed to install -- IGNORED.");
        return;
    }
    g_armed = true;
    ScLog("MENU: ON -- at the glue screens every root moves by (%d,%d); a %dx%d starfield "
          "(%d lit cells, %d sentinels) fills the buffer outside the glue rect and is "
          "copied to the primary from the restore-under at 0x0041DEB0",
          g_dx, g_dy, g_w, g_h, lit, g_sentinelN);
}

void ScMenuRemove(void) {
    ScHookRemove(&g_hkRestore);
    g_armed = g_atMenu = false;
}

void ScMenuLogStats(void) {
    if (!g_armed) return;
    ScLog("MENUSTATS fills=%u copies=%u remaps=%u lockFails=%u palFails=%u",
          g_fills, g_copies, g_remaps, g_lockFails, g_palFails);
}
