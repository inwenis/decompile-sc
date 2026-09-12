// sc_menu.h -- the glue screens (menus, loading, score) on the wider screen.
//
// Stock draws every glue screen as a 640x480 root at (0,0), blitted straight to the
// primary; on a wider screen that is a picture in the top-left corner of a black frame.
// With %SCPLUGIN_MENU_CENTRE%=1, widescreen at stage 3 (the mouse must reach the centred
// menu) and the plugin allowed to write, while no game is being played:
//   1. every root is translated by ((W-640)/2, (H-480)/2) -- the bounds move the bottom
//      console gets in game (sc_console.cpp), so drawing and hit-testing follow together;
//   2. a starfield is written into the framebuffer outside that centred rect;
//   3. the buffer outside the rect is copied to the primary from the cursor's
//      restore-under, the one moment the buffer holds the stars AND the cursor.
// Why the plugin presents at all: the engine presents the buffer only while a region
// built from the console art exists, so at the glue screens nothing outside a dialog ever
// reaches the screen -- not even the cursor (research/renderer-viewport.md 25).
#ifndef SC_MENU_H
#define SC_MENU_H

#include <windows.h>

bool ScMenuWanted(void);                // %SCPLUGIN_MENU_CENTRE% == 1
void ScMenuInstall(bool writeAllowed);  // arms it: wanted, writable, widescreen at stage 3
void ScMenuRemove(void);
bool ScMenuArmed(void);
void ScMenuOffset(int* dx, int* dy);    // ((W-640)/2, (H-480)/2) for the active preset

// Game thread, once per compose, from sc_console's dialog walk: whether a game is being
// played, and (at a glue screen) keeping the stars in the buffer. Cheap when idle.
void ScMenuOnFrame(bool atMenu);
// A glue root just moved: the primary still holds its art at the old place.
void ScMenuRequestCopy(void);
void ScMenuLogStats(void);

// The pure half, header-only so hooktest runs it with no game.
#define SC_MENU_LEVELS 4

// Nearest of 256 palette entries {r,g,b,flags} to an RGB.
static inline int ScMenuNearestIndex(const BYTE* e, int r, int g, int b) {
    int best = 0;
    long bestD = 0x7FFFFFFFL;
    for (int i = 0; i < 256; ++i) {
        const long dr = (long)e[i * 4] - r, dg = (long)e[i * 4 + 1] - g, db = (long)e[i * 4 + 2] - b;
        const long d = dr * dr + dg * dg + db * db;
        if (d < bestD) { bestD = d; best = i; }
    }
    return best;
}

// The four star levels -- sky, dim, mid, bright -- as indices into `pal`. The targets
// scale with the palette's brightest component, so a palette fading to black maps to the
// same entries at every step and the stars fade with the menu instead of popping.
static inline void ScMenuLevelsFor(const BYTE* pal, BYTE* lut) {
    static const int kRgb[SC_MENU_LEVELS][3] = {
        { 0, 0, 0 }, { 70, 70, 80 }, { 140, 140, 150 }, { 230, 230, 240 }
    };
    int top = 0;
    for (int i = 0; i < 256 * 4; ++i)
        if ((i & 3) != 3 && pal[i] > top) top = pal[i];
    for (int l = 0; l < SC_MENU_LEVELS; ++l)
        lut[l] = (BYTE)ScMenuNearestIndex(pal, kRgb[l][0] * top / 255,
                                          kRgb[l][1] * top / 255, kRgb[l][2] * top / 255);
}

// A w x h field of level ids 0..3 into `levels` (zeroed by the caller), deterministic so
// two runs differ only in the game: one star per ~900 cells, 80% dim, 17% mid, 3% a
// bright plus with dim corners. Returns the lit cell count.
static inline int ScMenuBuildStars(BYTE* levels, int w, int h) {
    unsigned s = 1161u;
    int lit = 0;
    const int stars = (int)(((long long)w * h) / 900);
    for (int i = 0; i < stars; ++i) {
        s = s * 1664525u + 1013904223u; const int x = (int)((s >> 8) % (unsigned)w);
        s = s * 1664525u + 1013904223u; const int y = (int)((s >> 8) % (unsigned)h);
        s = s * 1664525u + 1013904223u; const unsigned roll = (s >> 8) % 100u;
        const int bright = roll >= 97;
        for (int yy = y - bright; yy <= y + bright; ++yy) {
            for (int xx = x - bright; xx <= x + bright; ++xx) {
                if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
                BYTE* p = levels + (size_t)yy * (size_t)w + (size_t)xx;
                const BYTE lv = !bright ? (roll < 80 ? 1 : 2) : ((xx == x || yy == y) ? 3 : 1);
                if (!*p) ++lit;
                if (*p < lv) *p = lv;
            }
        }
    }
    return lit;
}

#endif  // SC_MENU_H
