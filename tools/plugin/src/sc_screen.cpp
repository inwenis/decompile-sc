// sc_screen.cpp -- see sc_screen.h.
//
// The playfield's size is stored nowhere: it is an immediate in every function
// that clips to it (research/renderer-viewport.md), so widening the screen is a
// few dozen operand rewrites -- no variable to set, no hook to install. Three
// rules make hand-derived writes into game code trustworthy:
//   1. tools/renderer_patch_sites.py generates the table from the same
//      StarCraft.exe: it locates the old value inside the disassembled
//      instruction and refuses any site whose bytes disagree with the map.
//   2. Every site is re-verified in the live process and the whole table is
//      refused on the first mismatch: a half-applied geometry does not fail, it
//      corrupts.
//   3. The install refuses once the framebuffer pointer (0x006CEFF4) is non-zero
//      -- repitching a buffer already allocated at the old size is a heap
//      overrun, so a widescreen run must inject early.

#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "sc_screen.h"
#include "sc_addresses.h"
#include "sc_engine.h"
#include "sc_env.h"
#include "sc_log.h"
#include "sc_screen_patches.h"

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

static bool   g_active = false;
static int    g_stage = 1;
static BYTE*  g_grid = NULL;          // the relocated dirty grid (data start)
static BYTE*  g_gridRegion = NULL;    // the guarded allocation base (g_grid - GUARD)
static int    g_applied = 0;
// Two different refusals, kept apart because they mean different things to a
// reader of the stats line. Each pre-flight check RETURNS, so the install veto
// and the per-patch failure count are never both non-zero.
static bool   g_installRefused = false;   // a pre-flight check said no; nothing written
static int    g_writeFailures = 0;        // patches that failed their own write

// Guard padding around the relocated grid. The engine's UNCLAMPED grid consumers
// -- 0x0041DE20 tests a dialog rect's cells with a SIGNED column (x1>>4) and
// never clamps x1<0 the way the WRITE path 0x0041E0D0 does -- read a neighbouring
// byte when a control sits a few pixels off an edge, which faults nowhere only
// because the stock grid at 0x006CEFF8 is boxed in by live globals on both sides
// (research/renderer-viewport.md 5). On a bare page a dialog at x=-1..-16 makes
// 0x0041DE84 `mov dl,[ebx]` read grid-1 and hit unmapped memory, so re-create the
// box: committed GUARD bytes each side turn a small out-of-range index into
// harmless zeroed scratch.
// ponytail: fixed 64KB each side covers any near-screen
// dialog coordinate (col +/-, row*stride); a wildly out-of-range coord would
// have faulted stock too. If a real consumer ever needs more, clamp it instead.
#define SC_WS_GRID_GUARD 0x10000

// Saved originals, so a FreeLibrary detach can put the process back. Sized by
// the table, never a fixed cap: a cap below the patch count stops saving
// mid-table in silence and leaves detach unable to restore the rest.
#define SC_WS_MAX_SAVED SC_WS_PATCH_COUNT
static struct {
    void* addr;
    BYTE  len;
    BYTE  bytes[SC_WS_MAX_PATCH_LEN];
} g_saved[SC_WS_MAX_SAVED];
static int g_savedCount = 0;

// CODE CAVES. A value that fits no encoding of the instruction's own length --
// the fog cell stride at 1280 wide is 168, and all six of its sites are
// sign-extended imm8/disp8 -- needs a WINDOW of whole instructions replaced by
// `jmp cave` + NOPs, the cave holding those instructions re-encoded with 32-bit
// fields and a `jmp` back. The generator picks the windows (>= 5 bytes, no
// PC-relative operand, nothing branches into them) and carries the cave code;
// this side owns only the two rel32s, which need the cave's runtime address.
// One RWX page, bump-allocated, leaked on remove like a trampoline: a game
// thread may be executing inside it.
#define SC_WS_CAVE_POOL 4096
static BYTE*  g_cavePool = NULL;
static SIZE_T g_caveUsed = 0;

static BYTE* EmitCave(const BYTE* code, int codeLen, const BYTE* back) {
    const SIZE_T need = (SIZE_T)codeLen + 5;
    if (!g_cavePool) {
        g_cavePool = (BYTE*)VirtualAlloc(NULL, SC_WS_CAVE_POOL, MEM_COMMIT | MEM_RESERVE,
                                         PAGE_EXECUTE_READWRITE);
        if (!g_cavePool) return NULL;
    }
    if (g_caveUsed + need > SC_WS_CAVE_POOL) return NULL;
    BYTE* cave = g_cavePool + g_caveUsed;
    memcpy(cave, code, (size_t)codeLen);
    cave[codeLen] = 0xE9;
    const DWORD rel = (DWORD)(DWORD_PTR)(back - (cave + codeLen + 5));
    memcpy(cave + codeLen + 1, &rel, 4);
    g_caveUsed += need;
    FlushInstructionCache(GetCurrentProcess(), cave, need);
    return cave;
}

// Fill the window's own `jmp rel32` toward `cave`. `window` is the image about
// to be written at `at` (E9 + 4 zero bytes + NOPs, from the generator).
static void PointWindowAt(BYTE* window, const BYTE* at, const BYTE* cave) {
    window[0] = 0xE9;
    const DWORD rel = (DWORD)(DWORD_PTR)(cave - (at + 5));
    memcpy(window + 1, &rel, 4);
}

bool ScScreenApplyCaveAt(BYTE* at, int len, const BYTE* code, int codeLen) {
    if (len < 5 || len > SC_WS_MAX_PATCH_LEN || codeLen <= 0 || codeLen > SC_WS_MAX_CAVE_LEN)
        return false;
    BYTE* cave = EmitCave(code, codeLen, at + len);
    if (!cave) return false;
    BYTE window[SC_WS_MAX_PATCH_LEN];
    memset(window, 0x90, sizeof(window));
    PointWindowAt(window, at, cave);
    DWORD oldProtect = 0;
    if (!VirtualProtect(at, (SIZE_T)len, PAGE_EXECUTE_READWRITE, &oldProtect)) return false;
    memcpy(at, window, (size_t)len);
    FlushInstructionCache(GetCurrentProcess(), at, (SIZE_T)len);
    DWORD ignore = 0;
    VirtualProtect(at, (SIZE_T)len, oldProtect, &ignore);
    return true;
}

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------

bool ScScreenWidescreenWanted(void) {
    return ScEnvOptIn("SCPLUGIN_WIDESCREEN");
}

int ScScreenStageWanted(void) {
    return ScEnvInt("SCPLUGIN_WS_STAGE", 1, 0, SC_WS_STAGE_MAX);
}

// %SCPLUGIN_WS_ONLY% -- comma-separated NAME PREFIXES, a bisector for stage 2: it
// lands as one lump of hundreds of sites whose damage cannot be attributed from
// outside the process. A patch at the TOP stage is written only if its name starts
// with one of them; every lower stage is written in full, because a stage is the
// base a selection sits on.
//
// COUPLING WARNING. research/renderer-viewport.md 12.5: the terrain blitter walks
// the dirty grid LINEARLY, one byte per column, never re-basing per row -- so the
// grid's stride and the blitter's column count must move TOGETHER or they
// desynchronise by (stride - columns) bytes every row. Selecting `terrain`
// without `grid` gives a DIFFERENTLY broken picture, not a partial fix, and
// reading it as "terrain is the culprit" is a wrong finding manufactured by the
// tool. Only coherent subsets mean anything: {grid, terrain, dirty} move as one.
static char g_only[256];
static bool g_onlySet = false;

static void LoadOnlyFilter(void) {
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_WS_ONLY", g_only, sizeof(g_only));
    g_onlySet = (n > 0 && n < sizeof(g_only));
    if (!g_onlySet) g_only[0] = '\0';
}

static bool NameSelected(const char* name) {
    if (!g_onlySet) return true;
    const char* p = g_only;
    while (*p) {
        while (*p == ' ' || *p == ',') ++p;
        if (!*p) break;
        const char* comma = strchr(p, ',');
        size_t len = comma ? (size_t)(comma - p) : strlen(p);
        while (len && p[len - 1] == ' ') --len;
        if (len && strncmp(name, p, len) == 0) return true;
        if (!comma) break;
        p = comma + 1;
    }
    return false;
}

bool ScScreenActive(void) { return g_active; }
int  ScScreenTargetWidth(void)  { return SC_WS_SCREEN_W; }
int  ScScreenTargetHeight(void) { return SC_WS_SCREEN_H; }
int  ScScreenPlayfieldHeight(void) { return SC_WS_PLAYFIELD_H; }
int  ScScreenConsoleShiftY(void)  { return SC_WS_CONSOLE_SHIFT_Y; }

int ScScreenViewportTilesX(void) {
    // scroll.clamp.x.tiles is a stage-3 site; below that, or with the table
    // refused, the engine still clamps the camera at the stock 20 tiles.
    return (g_active && g_stage >= SC_WS_STAGE_SCROLL_CLAMP)
        ? (SC_WS_SCREEN_W / 32) : SC_VIEWPORT_TILES_X;
}

// The console is 80 rows of the stock screen; the playfield is the rest.
#define SC_STOCK_PLAYFIELD_H (SC_WS_STOCK_H - 80)

int ScScreenViewportTilesY(void) {
    return (g_active && g_stage >= SC_WS_STAGE_SCROLL_CLAMP)
        ? (SC_WS_PLAYFIELD_H / 32) : SC_VIEWPORT_TILES_Y;
}

int ScScreenScrollBiasY(void) {
    const int pfH = (g_active && g_stage >= SC_WS_STAGE_SCROLL_CLAMP) ? SC_WS_PLAYFIELD_H : SC_STOCK_PLAYFIELD_H;
    return ScScreenViewportTilesY() * 32 - (pfH - 24);
}

// ---------------------------------------------------------------------------
// The gate: has the video init already run? 0x006CEFF4 is the framebuffer
// pointer; it lives in BSS and is zero until FUN_004DB060 (or one of its two
// twins) calls SMemAlloc. A non-zero value means the buffer exists at the OLD
// size, and every pitch this table rewrites would then be a promise the
// allocation cannot keep. Read it defensively: a wrong static address must
// produce a refusal, never a fault inside the game.
// ---------------------------------------------------------------------------

static bool VideoAlreadyUp(DWORD* dataOut, unsigned* wOut, unsigned* hOut) {
    const BYTE* desc = (const BYTE*)ScRuntimeAddr(SC_VA_SCREEN_BITMAP);
    DWORD data = 0;
    WORD w = 0, h = 0;
    if (!ScReadableAt(desc, 8)) return false;   // unreadable -> not up yet
    memcpy(&w, desc + SC_BITMAP_OFF_WIDTH, 2);
    memcpy(&h, desc + SC_BITMAP_OFF_HEIGHT, 2);
    memcpy(&data, desc + SC_BITMAP_OFF_DATA, 4);
    if (dataOut) *dataOut = data;
    if (wOut) *wOut = w;
    if (hOut) *hOut = h;
    return data != 0;
}

// ---------------------------------------------------------------------------
// Apply
// ---------------------------------------------------------------------------

static bool VerifyAll(int maxStage, int* checked) {
    bool ok = true;
    int n = 0;
    for (size_t i = 0; i < SC_WS_PATCH_COUNT; ++i) {
        const ScScreenPatch* p = &SC_WS_PATCHES[i];
        if (p->stage > maxStage) continue;
        ++n;
        const BYTE* at = (const BYTE*)ScRuntimeAddr(p->va);
        if (!ScReadableAt(at, p->len)) {
            ScLog("WIDESCREEN REFUSED %s @0x%08X: not readable", p->name, (unsigned)p->va);
            ok = false;
            continue;
        }
        if (memcmp(at, p->expect, p->len) != 0) {
            char got[SC_WS_MAX_PATCH_LEN * 2 + 1], want[SC_WS_MAX_PATCH_LEN * 2 + 1];
            ScHexDump(at, p->len, got, sizeof(got));
            ScHexDump(p->expect, p->len, want, sizeof(want));
            ScLog("WIDESCREEN REFUSED %s @0x%08X: bytes are %s, table expects %s "
                  "(wrong build, or already patched)", p->name, (unsigned)p->va, got, want);
            ok = false;
        }
    }
    if (checked) *checked = n;
    return ok;
}

static bool WriteOne(const ScScreenPatch* p) {
    BYTE bytes[SC_WS_MAX_PATCH_LEN];
    memcpy(bytes, p->patch, p->len);
    void* at = ScRuntimeAddr(p->va);

    // Relocation fixups: the record carries a zeroed dword only the running
    // process can fill, because the relocated grid's address comes from
    // VirtualAlloc. The addend is the offset INTO the new grid the instruction
    // should name -- computed by the generator for the new stride, not copied.
    if (p->fixupOff != SC_WS_NO_FIXUP) {
        if (!g_grid) return false;
        DWORD target = (DWORD)(DWORD_PTR)(g_grid + p->fixupAddend);
        memcpy(bytes + p->fixupOff, &target, 4);
    }

    // A code cave: emit the re-encoded window + jmp back, then point the
    // window's own jmp at it. The record's `patch` already holds E9 + NOPs.
    BYTE* cave = NULL;
    if (p->caveLen) {
        cave = EmitCave(p->cave, p->caveLen, (BYTE*)at + p->len);
        if (!cave) {
            ScLog("WIDESCREEN %s @0x%08X: cave pool exhausted or unallocated (used %Iu of %d)",
                  p->name, (unsigned)p->va, g_caveUsed, SC_WS_CAVE_POOL);
            return false;
        }
        PointWindowAt(bytes, (BYTE*)at, cave);
    }

    DWORD oldProtect = 0;
    if (!VirtualProtect(at, p->len, PAGE_EXECUTE_READWRITE, &oldProtect)) {
        ScLog("WIDESCREEN %s @0x%08X: VirtualProtect failed gle=%u",
              p->name, (unsigned)p->va, (unsigned)GetLastError());
        return false;
    }

    if (g_savedCount < (int)SC_WS_MAX_SAVED) {
        g_saved[g_savedCount].addr = at;
        g_saved[g_savedCount].len = p->len;
        memcpy(g_saved[g_savedCount].bytes, at, p->len);
        ++g_savedCount;
    }

    memcpy(at, bytes, p->len);
    FlushInstructionCache(GetCurrentProcess(), at, p->len);
    DWORD ignore = 0;
    VirtualProtect(at, p->len, oldProtect, &ignore);

    char before[SC_WS_MAX_PATCH_LEN * 2 + 1], after[SC_WS_MAX_PATCH_LEN * 2 + 1];
    ScHexDump(p->expect, p->len, before, sizeof(before));
    ScHexDump(bytes, p->len, after, sizeof(after));
    if (cave) {
        char code[SC_WS_MAX_CAVE_LEN * 2 + 1];
        ScHexDump(p->cave, p->caveLen, code, sizeof(code));
        ScLog("WIDESCREEN patch stage=%d %-28s @0x%08X %s -> %s  cave@%p [%s + jmp back]  (%s)",
              p->stage, p->name, (unsigned)p->va, before, after, cave, code, p->note);
    } else {
        ScLog("WIDESCREEN patch stage=%d %-28s @0x%08X %s -> %s  (%s)",
              p->stage, p->name, (unsigned)p->va, before, after, p->note);
    }
    return true;
}

void ScScreenInstall(BYTE* base, ScMode mode) {
    ScEngineSetModuleBase(base);

    const bool wanted = ScScreenWidescreenWanted();
    if (!wanted) {
        ScLog("WIDESCREEN off (%%SCPLUGIN_WIDESCREEN%% unset or 0) -- the screen stays "
              "stock %dx%d; nothing in this module runs", SC_WS_STOCK_W, SC_WS_STOCK_H);
        return;
    }

    // Observe is the whole plugin's off switch: it stays a read-only observer
    // whatever else the environment asks for.
    if (mode == SC_MODE_OBSERVE) {
        ScLog("WIDESCREEN: %%SCPLUGIN_WIDESCREEN%% is set but the mode is observe -- "
              "IGNORED. Observe writes nothing to game memory.");
        return;
    }

    g_stage = ScScreenStageWanted();
    LoadOnlyFilter();

    DWORD data = 0;
    unsigned w = 0, h = 0;
    if (VideoAlreadyUp(&data, &w, &h)) {
        ScLog("WIDESCREEN REFUSED: the video init has already run (screen bitmap "
              "%ux%u data=0x%08X). Every pitch in this table describes a buffer that "
              "is allocated at startup, so patching now would overrun it. Inject early "
              "(scinject --early / run-with-plugin.ps1 -Widescreen 1, which passes it).",
              w, h, (unsigned)data);
        g_installRefused = true;
        return;
    }

    ScLog("WIDESCREEN install: target %dx%d, playfield %dx%d, stage<=%d "
          "(%%SCPLUGIN_WS_STAGE%%), grid %dx%d blocks = %d bytes",
          SC_WS_SCREEN_W, SC_WS_SCREEN_H, SC_WS_PLAYFIELD_W, SC_WS_PLAYFIELD_H,
          g_stage, SC_WS_GRID_COLS, SC_WS_GRID_ROWS, SC_WS_GRID_BYTES);

    // --- verify the whole table BEFORE writing a single byte ----------------
    int checked = 0;
    if (!VerifyAll(g_stage, &checked)) {
        ScLog("WIDESCREEN REFUSED: %d site(s) checked and at least one did not match. "
              "NOTHING was written -- a half-applied geometry corrupts silently instead "
              "of failing.", checked);
        g_installRefused = true;
        return;
    }
    ScLog("WIDESCREEN: %d site(s) verified against the live image", checked);

    // --- relocate the dirty grid -------------------------------------------
    // The stock grid at 0x006CEFF8 is a fixed u8[30][40] with a live global 0x4B0
    // bytes later, so it cannot grow in place: it moves to plugin-owned memory and
    // every instruction naming it absolutely is re-pointed. A wider stride is
    // encodable in place at all only because the stock row multiply -- a three-byte
    // `lea r,[c+c*4]` feeding a SIB scale of 8, x5 then x8 == the stock stride of 40
    // -- has an equally three-byte replacement: `imul r32,r/m32,imm8` with the scale
    // dropped to 2; see the generator. Stage 0 touches the display mode alone.
    if (g_stage >= SC_WS_STAGE_GRID) {
        // GUARD + grid + GUARD, all committed, grid pointer into the middle.
        // VirtualAlloc zeroes it, which is the state the BSS array it replaces
        // starts in: a grid coming up full of 1s would mark the whole screen
        // dirty on frame one, which looks like a working feature and hides a
        // real bug. Zeroed guards make an out-of-range TEST read "not dirty".
        const SIZE_T total = (SIZE_T)SC_WS_GRID_GUARD + SC_WS_GRID_BYTES + SC_WS_GRID_GUARD;
        g_gridRegion = (BYTE*)VirtualAlloc(NULL, total, MEM_COMMIT | MEM_RESERVE,
                                           PAGE_READWRITE);
        if (!g_gridRegion) {
            ScLog("WIDESCREEN REFUSED: VirtualAlloc(%Iu) for the guarded dirty grid "
                  "failed gle=%u", total, (unsigned)GetLastError());
            g_installRefused = true;
            return;
        }
        g_grid = g_gridRegion + SC_WS_GRID_GUARD;
        int refs = 0;
        for (size_t i = 0; i < SC_WS_PATCH_COUNT; ++i) {
            if (SC_WS_PATCHES[i].fixupOff != SC_WS_NO_FIXUP &&
                SC_WS_PATCHES[i].stage <= g_stage) ++refs;
        }
        ScLog("WIDESCREEN: dirty grid relocated 0x%08X -> %p (%d bytes, %dx%d), "
              "%d absolute reference(s) re-pointed",
              (unsigned)SC_WS_STOCK_GRID_VA, g_grid, SC_WS_GRID_BYTES,
              SC_WS_GRID_COLS, SC_WS_GRID_ROWS, refs);

        // Oracle: prove the guard covers the OUT-OF-RANGE index that faults.
        // grid-1 is where 0x0041DE84 reads; grid+BYTES+GUARD-1 is the far side.
        // Both must read as committed, or the box is not there -- a bare
        // allocation makes this line say MISSING.
        const bool lo = ScReadableAt(g_grid - 1, 1);
        const bool hi = ScReadableAt(g_grid + SC_WS_GRID_BYTES + SC_WS_GRID_GUARD - 1, 1);
        ScLog("WIDESCREEN: grid guard %s -- region %p..%p, %d bytes each side; "
              "grid-1 %s, grid+size+guard-1 %s (issue #113 crash: 0x0041DE84 read "
              "grid_base-1 on the pre-guard allocation)",
              (lo && hi) ? "OK" : "MISSING", g_gridRegion, g_gridRegion + total,
              SC_WS_GRID_GUARD, lo ? "committed" : "UNMAPPED",
              hi ? "committed" : "UNMAPPED");
        if (!(lo && hi)) {
            ScLog("WIDESCREEN REFUSED: the grid guard did not commit -- refusing "
                  "rather than shipping the crash back.");
            g_installRefused = true;
            return;
        }
    }

    // --- write ---------------------------------------------------------------
    int skipped = 0;
    for (size_t i = 0; i < SC_WS_PATCH_COUNT; ++i) {
        const ScScreenPatch* p = &SC_WS_PATCHES[i];
        if (p->stage > g_stage) continue;
        if (p->stage == g_stage && !NameSelected(p->name)) { ++skipped; continue; }
        if (WriteOne(p)) ++g_applied;
        else ++g_writeFailures;
    }

    g_active = (g_applied > 0 && g_writeFailures == 0);
    ScLog("WIDESCREEN %s: %d patch(es) applied, %d refused, stage<=%d",
          g_active ? "ACTIVE" : "INCOMPLETE", g_applied, g_writeFailures, g_stage);
    // Announced even when nothing is filtered, so a run that FORGOT to clear the
    // variable cannot be read as a full-stage result.
    ScLog("WIDESCREEN filter: %%SCPLUGIN_WS_ONLY%%=%s -- %d stage-%d site(s) skipped",
          g_onlySet ? g_only : "(unset, whole stage applied)", skipped, g_stage);
}

void ScScreenRemove(void) {
    if (!g_savedCount) return;
    int n = 0;
    for (int i = g_savedCount - 1; i >= 0; --i) {
        DWORD oldProtect = 0;
        if (!VirtualProtect(g_saved[i].addr, g_saved[i].len, PAGE_EXECUTE_READWRITE,
                            &oldProtect)) continue;
        memcpy(g_saved[i].addr, g_saved[i].bytes, g_saved[i].len);
        FlushInstructionCache(GetCurrentProcess(), g_saved[i].addr, g_saved[i].len);
        DWORD ignore = 0;
        VirtualProtect(g_saved[i].addr, g_saved[i].len, oldProtect, &ignore);
        ++n;
    }
    g_savedCount = 0;
    g_active = false;
    ScLog("WIDESCREEN removed: %d site(s) restored (the relocated grid region %p is "
          "left allocated on purpose -- a live loop may still hold a pointer into it)",
          n, g_gridRegion);
}

void ScScreenLogStats(void) {
    if (!ScScreenWidescreenWanted()) return;
    ScLog("WIDESCREEN STATS active=%d stage=%d applied=%d refused=%d grid=%p "
          "target=%dx%d", g_active ? 1 : 0, g_stage, g_applied,
          g_installRefused ? 1 : g_writeFailures,
          g_grid, SC_WS_SCREEN_W, SC_WS_SCREEN_H);
}
