// sc_menu.h -- the glue screens (menus, loading, score) on the wider screen.
//
// Stock draws every glue screen as a 640x480 root at (0,0), blitted straight to the
// primary; on a wider screen that is a picture in the top-left corner of a black frame.
// With %SCPLUGIN_MENU_CENTRE%=1, widescreen at stage 3 (the mouse must reach the centred
// menu) and the plugin allowed to write, while no game is being played:
//   1. every root is translated by ((W-640)/2, (H-480)/2) -- the bounds move the bottom
//      console gets in game (sc_console.cpp), so drawing and hit-testing follow together;
//   2. a night sky -- nebula and stars -- is written into the framebuffer outside that
//      centred rect;
//   3. the buffer outside the rect is copied to the primary from the cursor's
//      restore-under, the one moment the buffer holds the stars AND the cursor.
// Why the plugin presents at all: the engine presents the buffer only while a region
// built from the console art exists, so at the glue screens nothing outside a dialog ever
// reaches the screen -- not even the cursor (research/renderer-viewport.md 25).
#ifndef SC_MENU_H
#define SC_MENU_H

#include <windows.h>
#include <math.h>

bool ScMenuWanted(void);                // %SCPLUGIN_MENU_CENTRE% == 1
void ScMenuInstall(bool writeAllowed);  // arms it: wanted, writable, widescreen at stage 3
void ScMenuRemove(void);
bool ScMenuArmed(void);
void ScMenuOffset(int* dx, int* dy);    // ((W-640)/2, (H-480)/2) for the active preset

// Game thread, once per compose, from sc_console's dialog walk: whether a game is being
// played, and (at a glue screen) keeping the sky in the buffer. Cheap when idle.
void ScMenuOnFrame(bool atMenu);
// A glue root just moved: the primary still holds its art at the old place.
void ScMenuRequestCopy(void);
void ScMenuLogStats(void);

// The pure half, header-only so hooktest runs it with no game.
//
// The sky is a field of level ids, one per pixel; a palette change maps each level to an
// index once (ScMenuLevelsFor) and the field through that table, so no pixel is ever
// matched against the palette on its own. Levels 0..3 are the sky and three star
// brightnesses; the rest are the nebula's inks, a few steps of each layer's colour.
#define SC_MENU_STAR_LEVELS 4
#define SC_MENU_NEB_LAYERS  2
#define SC_MENU_NEB_INKS    8   // per layer: ink k of 8 is k/8 of the layer's colour
#define SC_MENU_LEVELS      (SC_MENU_STAR_LEVELS + SC_MENU_NEB_LAYERS * SC_MENU_NEB_INKS)
#define SC_MENU_FADE        140 // px from the glue rect to the nebula's full strength
#define SC_MENU_NEB_STEP    2   // the nebula is sampled every 2 px and dithered per pixel

// The nebula's layers. scale = noise cells across the long side, density lifts the
// noise before it is raised to `falloff`: a larger power means thinner, wispier cloud.
struct ScMenuNebLayer { int r, g, b; float scale, density; int falloff; float ox, oy; unsigned seed; };
static const ScMenuNebLayer kScMenuNebLayers[SC_MENU_NEB_LAYERS] = {
    {  70, 100, 185, 2.0f, 0.10f, 3,  0.0f, 0.0f, 7u },   // blue-violet, broad
    { 170,  45,  55, 3.0f, 0.02f, 4, 17.3f, 5.1f, 8u },   // dim red, patchy
};

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

// Every level -- sky, dim, mid and bright star, then each layer's inks -- as indices
// into `pal`. The targets scale with the palette's brightest component, so a palette
// fading to black maps to the same entries at every step and the sky fades with the menu
// instead of popping.
static inline void ScMenuLevelsFor(const BYTE* pal, BYTE* lut) {
    static const int kStarRgb[SC_MENU_STAR_LEVELS][3] = {
        { 0, 0, 0 }, { 70, 70, 80 }, { 140, 140, 150 }, { 230, 230, 240 }
    };
    int top = 0;
    for (int i = 0; i < 256 * 4; ++i)
        if ((i & 3) != 3 && pal[i] > top) top = pal[i];
    for (int l = 0; l < SC_MENU_LEVELS; ++l) {
        int r, g, b;
        if (l < SC_MENU_STAR_LEVELS) {
            r = kStarRgb[l][0]; g = kStarRgb[l][1]; b = kStarRgb[l][2];
        } else {
            const ScMenuNebLayer& L = kScMenuNebLayers[(l - SC_MENU_STAR_LEVELS) / SC_MENU_NEB_INKS];
            const int k = (l - SC_MENU_STAR_LEVELS) % SC_MENU_NEB_INKS + 1;
            r = L.r * k / SC_MENU_NEB_INKS; g = L.g * k / SC_MENU_NEB_INKS; b = L.b * k / SC_MENU_NEB_INKS;
        }
        lut[l] = (BYTE)ScMenuNearestIndex(pal, r * top / 255, g * top / 255, b * top / 255);
    }
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

// Perlin noise in 0..1 on an integer-hashed lattice of 16 gradient directions.
static inline unsigned ScMenuHash(int x, int y, unsigned seed) {
    unsigned h = (unsigned)x * 374761393u + (unsigned)y * 668265263u + seed * 144269504u;
    h = (h ^ (h >> 13)) * 1274126177u;
    return h ^ (h >> 16);
}

static inline float ScMenuPerlin01(float x, float y, unsigned seed) {
    static const float kGrad[16][2] = {
        { 1.0f, 0.0f }, { 0.924f, 0.383f }, { 0.707f, 0.707f }, { 0.383f, 0.924f },
        { 0.0f, 1.0f }, { -0.383f, 0.924f }, { -0.707f, 0.707f }, { -0.924f, 0.383f },
        { -1.0f, 0.0f }, { -0.924f, -0.383f }, { -0.707f, -0.707f }, { -0.383f, -0.924f },
        { 0.0f, -1.0f }, { 0.383f, -0.924f }, { 0.707f, -0.707f }, { 0.924f, -0.383f },
    };
    int ix = (int)x, iy = (int)y;   // floor, without a libm call per sample
    if (x < (float)ix) --ix;
    if (y < (float)iy) --iy;
    const float fx = x - (float)ix, fy = y - (float)iy;
    float dots[4];
    for (int c = 0; c < 4; ++c) {
        const int cx = c & 1, cy = c >> 1;
        const float* gr = kGrad[ScMenuHash(ix + cx, iy + cy, seed) & 15];
        dots[c] = gr[0] * (fx - (float)cx) + gr[1] * (fy - (float)cy);
    }
    const float u = fx * fx * fx * (fx * (fx * 6.0f - 15.0f) + 10.0f);
    const float v = fy * fy * fy * (fy * (fy * 6.0f - 15.0f) + 10.0f);
    const float a = dots[0] + (dots[1] - dots[0]) * u;
    const float b = dots[2] + (dots[3] - dots[2]) * u;
    return (a + (b - a) * v) * 0.5f + 0.5f;
}

// wwwtyro/space-2d's nebula noise (Unlicense): five octaves, finest first, each one's
// value displacing the next, the last displacing a single coarse sample.
static inline float ScMenuWarpedNoise(float x, float y, unsigned seed) {
    float scale = 32.0f, d = 0.0f;
    for (int i = 0; i < 5; ++i) {
        d = ScMenuPerlin01(x * scale + d, y * scale + d, seed);
        scale *= 0.5f;
    }
    return ScMenuPerlin01(x + d, y + d, seed);
}

// The nebula into every sky cell (level 0) of a w x h field, around the 640x480 glue rect
// at (gx, gy): black next to the rect, full strength SC_MENU_FADE px away. Each layer's
// strength is quantised to its inks with an 8x8 ordered dither, and a second dither
// offset picks which layer's ink a cell shows in proportion to their strengths, so two
// colours mix without an ink for every blend. Cells inside the rect are left alone (the
// menu covers them). Deterministic; returns the cells it lit.
static inline int ScMenuBuildNebula(BYTE* levels, int w, int h, int gx, int gy) {
    static const BYTE kBayer[64] = {
         0, 32,  8, 40,  2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26,
        12, 44,  4, 36, 14, 46,  6, 38, 60, 28, 52, 20, 62, 30, 54, 22,
         3, 35, 11, 43,  1, 33,  9, 41, 51, 19, 59, 27, 49, 17, 57, 25,
        15, 47,  7, 39, 13, 45,  5, 37, 63, 31, 55, 23, 61, 29, 53, 21,
    };
    const float span = (float)(w > h ? w : h);
    int lit = 0;
    for (int cy = 0; cy < h; cy += SC_MENU_NEB_STEP) {
        for (int cx = 0; cx < w; cx += SC_MENU_NEB_STEP) {
            const int ox = cx < gx ? gx - cx : (cx > gx + 639 ? cx - (gx + 639) : 0);
            const int oy = cy < gy ? gy - cy : (cy > gy + 479 ? cy - (gy + 479) : 0);
            if (!ox && !oy) continue;
            float t = sqrtf((float)(ox * ox + oy * oy)) / (float)SC_MENU_FADE;
            if (t > 1.0f) t = 1.0f;
            const float fade = t * t * (3.0f - 2.0f * t);
            float n[SC_MENU_NEB_LAYERS], sum = 0.0f;
            for (int l = 0; l < SC_MENU_NEB_LAYERS; ++l) {
                const ScMenuNebLayer& L = kScMenuNebLayers[l];
                float v = ScMenuWarpedNoise((float)cx * L.scale / span + L.ox,
                                            (float)cy * L.scale / span + L.oy, L.seed) + L.density;
                v = v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v);
                float p = fade;
                for (int k = 0; k < L.falloff; ++k) p *= v;
                n[l] = p;
                sum += n[l];
            }
            if (sum <= 0.0f) continue;
            const float strength = sum > 1.0f ? 1.0f : sum;
            for (int y = cy; y < cy + SC_MENU_NEB_STEP && y < h; ++y) {
                for (int x = cx; x < cx + SC_MENU_NEB_STEP && x < w; ++x) {
                    BYTE* p = levels + (size_t)y * (size_t)w + (size_t)x;
                    if (*p) continue;
                    const float b1 = ((float)kBayer[(y & 7) * 8 + (x & 7)] + 0.5f) / 64.0f;
                    const float b2 = ((float)kBayer[((y + 3) & 7) * 8 + ((x + 5) & 7)] + 0.5f) / 64.0f;
                    int layer = 0;
                    float share = n[0] / sum;
                    while (layer < SC_MENU_NEB_LAYERS - 1 && b2 > share) share += n[++layer] / sum;
                    int k = (int)(strength * (float)SC_MENU_NEB_INKS + b1);
                    if (k > SC_MENU_NEB_INKS) k = SC_MENU_NEB_INKS;
                    if (k <= 0) continue;
                    *p = (BYTE)(SC_MENU_STAR_LEVELS + layer * SC_MENU_NEB_INKS + k - 1);
                    ++lit;
                }
            }
        }
    }
    return lit;
}

#endif  // SC_MENU_H
