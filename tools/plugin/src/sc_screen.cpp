// sc_screen.cpp -- see sc_screen.h.
//
// WHY THIS SHAPE
//
// research/renderer-viewport.md's central finding is that the playfield's size
// is not stored anywhere: it is an immediate in every function that clips to it.
// So there is no variable to set and no hook to install -- widening the screen
// is a few dozen instruction-operand rewrites, and the only interesting
// engineering question is how to make a few dozen hand-derived byte writes into
// game code something a reviewer can trust.
//
// Three things do that, and they are the design:
//
//   1. THE TABLE IS GENERATED, NOT WRITTEN. tools/renderer_patch_sites.py reads
//      the same StarCraft.exe, disassembles each declared site, LOCATES the old
//      value inside the instruction rather than trusting a hand-counted offset,
//      and refuses to emit a site whose bytes are not what the map says. The
//      header it produces carries the original and patched disassembly as
//      comments beside every record.
//
//   2. EVERY SITE IS RE-VERIFIED IN THE LIVE PROCESS, and the whole table is
//      refused on the first mismatch. This is the detour engine's rule
//      (sc_hook.cpp: "is the code at `target` the code we disassembled?")
//      applied to data-sized patches. A half-applied geometry is far worse than
//      none: it does not fail, it corrupts.
//
//   3. IT REFUSES TO RUN LATE. Every patch here is only correct if it lands
//      BEFORE the video init allocates the framebuffer -- patching the pitch of
//      a buffer that has already been allocated at the old size is a heap
//      overrun in someone else's process. The install checks the framebuffer
//      pointer (0x006CEFF4, zero until the init runs) and refuses if the game
//      is already up. That is why the launcher passes scinject --early for a
//      widescreen run.
//
// THE ONE RELOCATION. The dirty-block grid at 0x006CEFF8 is a fixed u8[30][40]
// with a live global 0x4B0 bytes later (the render-target pointer, named by 126
// instructions), so it cannot grow in place. It moves to plugin-owned memory and
// all 21 instructions that name it absolutely are re-pointed (12 rebase records
// plus 9 code rewrites whose fixup dword names the grid; the 21st -- 0x0048CBC7,
// found by 034's scan and lost between scan and table -- was restored by task
// 064, which is what closes the named-ref accounting). The row addressing
// that turns a row index into a byte offset is a `lea r,[c+c*4]` feeding a SIB
// scale of 8 -- x5 then x8 == the stock stride of 40 -- and the stride is
// reachable only because x25 fits `imul r32,r/m32,imm8` in the same three bytes
// and the scale can drop to 2. That coincidence is what makes stage 1 possible
// at all; see the generator for the full argument.

#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "sc_screen.h"
#include "sc_addresses.h"
#include "sc_engine.h"
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
// Two different refusals, which used to share one `g_refused`. The install veto is
// set by the pre-flight checks, each of which RETURNS -- so it and the per-patch
// failure count are never both non-zero, which is how one variable got away with it.
static bool   g_installRefused = false;   // a pre-flight check said no; nothing written
static int    g_writeFailures = 0;        // patches that failed their own write

// Guard padding around the relocated grid. The stock grid at 0x006CEFF8 sits in
// .data with live globals on both sides (research/renderer-viewport.md 5, "boxed
// in by the linker's data layout"), so the engine's UNCLAMPED grid consumers --
// 0x0041DE20 tests a dialog rect's cells with a SIGNED column (x1>>4) and never
// clamps x1<0 the way the WRITE path 0x0041E0D0 does -- read a neighbouring
// mapped byte when a control sits a few pixels off an edge, and the stock game
// never faults. Relocating the grid to a bare VirtualAlloc page removed that
// padding: a dialog at x=-1..-16 makes 0x0041DE84 `mov dl,[ebx]` read grid-1,
// which is the unmapped guard page -> the "0x0041DE84 referenced 0x...DFFFF"
// crash (issue #113 follow-up; the faulting address was exactly the grid base
// minus one). Re-create the box: commit GUARD bytes on each side so a small
// out-of-range index reads harmless zeroed scratch, exactly as stock read a
// harmless neighbour. ponytail: fixed 64KB each side covers any near-screen
// dialog coordinate (col +/-, row*stride); a wildly out-of-range coord would
// have faulted stock too. If a real consumer ever needs more, clamp it instead.
#define SC_WS_GRID_GUARD 0x10000

// Saved originals, so a FreeLibrary detach can put the process back.
#define SC_WS_MAX_SAVED 128
static struct {
    void* addr;
    BYTE  len;
    BYTE  bytes[SC_WS_MAX_PATCH_LEN];
} g_saved[SC_WS_MAX_SAVED];
static int g_savedCount = 0;

static void HexDump(const BYTE* p, int n, char* out, int outLen) {
    int used = 0;
    out[0] = '\0';
    for (int i = 0; i < n && used + 3 < outLen; ++i) {
        used += _snprintf(out + used, outLen - used, "%02X", p[i]);
    }
}

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------

bool ScScreenWidescreenWanted(void) {
    char buf[16];
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_WIDESCREEN", buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return false;
    return buf[0] == '1' || buf[0] == 'y' || buf[0] == 'Y';
}

int ScScreenStageWanted(void) {
    char buf[16];
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_WS_STAGE", buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return 1;
    int v = buf[0] - '0';
    if (v < 0) v = 0;
    if (v > SC_WS_STAGE_MAX) v = SC_WS_STAGE_MAX;
    return v;
}

// %SCPLUGIN_WS_ONLY% -- comma-separated NAME PREFIXES. When set, a patch at the
// TOP stage is written only if its name starts with one of them; every lower
// stage is written in full, because a stage is the base the selection sits on.
// Stage 2 is 121 sites in one lump and its damage cannot be attributed from
// outside the process, so this exists to bisect it.
//
// COUPLING WARNING, and it is not a footnote. These groups are NOT independent.
// research/renderer-viewport.md 12.5: the terrain blitter walks the dirty grid
// LINEARLY, one byte per column, never re-basing per row -- so the grid's stride
// and the blitter's column count must move TOGETHER or they desynchronise by
// (stride - columns) bytes every row. Selecting `terrain` without `grid`
// produces a DIFFERENTLY broken picture, not a partial fix, and reading it as
// "terrain is the culprit" would be a wrong finding manufactured by the tool.
// Only coherent subsets mean anything: {grid, terrain, dirty} move as one.
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

int ScScreenViewportTilesX(void) {
    // scroll.clamp.x.tiles is a stage-3 site; below that, or with the table
    // refused, the engine still clamps the camera at the stock 20 tiles.
    return (g_active && g_stage >= SC_WS_STAGE_SCROLL_CLAMP)
        ? (SC_WS_SCREEN_W / 32) : SC_VIEWPORT_TILES_X;
}

// ---------------------------------------------------------------------------
// Safe reads -- a wrong static address must produce a refusal, never a fault
// inside the game.
// ---------------------------------------------------------------------------

static bool RangeReadable(const void* addr, size_t n) {
    MEMORY_BASIC_INFORMATION mbi;
    if (VirtualQuery(addr, &mbi, sizeof(mbi)) != sizeof(mbi)) return false;
    if (mbi.State != MEM_COMMIT) return false;
    if (mbi.Protect & PAGE_GUARD) return false;
    const DWORD readable = PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY |
                           PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE |
                           PAGE_EXECUTE_WRITECOPY;
    if ((mbi.Protect & readable) == 0) return false;
    const BYTE* start = (const BYTE*)addr;
    const BYTE* regEnd = (const BYTE*)mbi.BaseAddress + mbi.RegionSize;
    return start >= (const BYTE*)mbi.BaseAddress && start + n <= regEnd;
}

// ---------------------------------------------------------------------------
// The gate: has the video init already run?
//
// 0x006CEFF4 is the framebuffer pointer. It lives in BSS and is zero until
// FUN_004DB060 (or one of its two twins) calls SMemAlloc. A non-zero value means
// the buffer exists at the OLD size, and every pitch this table rewrites would
// then be a promise the allocation cannot keep.
// ---------------------------------------------------------------------------

static bool VideoAlreadyUp(DWORD* dataOut, unsigned* wOut, unsigned* hOut) {
    const BYTE* desc = (const BYTE*)ScRuntimeAddr(SC_VA_SCREEN_BITMAP);
    DWORD data = 0;
    WORD w = 0, h = 0;
    if (!RangeReadable(desc, 8)) return false;   // unreadable -> not up yet
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
        if (!RangeReadable(at, p->len)) {
            ScLog("WIDESCREEN REFUSED %s @0x%08X: not readable", p->name, (unsigned)p->va);
            ok = false;
            continue;
        }
        if (memcmp(at, p->expect, p->len) != 0) {
            char got[SC_WS_MAX_PATCH_LEN * 2 + 1], want[SC_WS_MAX_PATCH_LEN * 2 + 1];
            HexDump(at, p->len, got, sizeof(got));
            HexDump(p->expect, p->len, want, sizeof(want));
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

    // Relocation fixups: the record carries a zeroed dword that only the running
    // process can fill, because the relocated grid's address comes from
    // VirtualAlloc. The addend is the offset INTO the new grid the instruction
    // should name -- recomputed by the generator for the new stride, not copied.
    if (p->fixupOff != SC_WS_NO_FIXUP) {
        if (!g_grid) return false;
        DWORD target = (DWORD)(DWORD_PTR)(g_grid + p->fixupAddend);
        memcpy(bytes + p->fixupOff, &target, 4);
    }

    void* at = ScRuntimeAddr(p->va);
    DWORD oldProtect = 0;
    if (!VirtualProtect(at, p->len, PAGE_EXECUTE_READWRITE, &oldProtect)) {
        ScLog("WIDESCREEN %s @0x%08X: VirtualProtect failed gle=%u",
              p->name, (unsigned)p->va, (unsigned)GetLastError());
        return false;
    }

    if (g_savedCount < SC_WS_MAX_SAVED) {
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
    HexDump(p->expect, p->len, before, sizeof(before));
    HexDump(bytes, p->len, after, sizeof(after));
    ScLog("WIDESCREEN patch stage=%d %-28s @0x%08X %s -> %s  (%s)",
          p->stage, p->name, (unsigned)p->va, before, after, p->note);
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

    // Observe is the whole plugin's off switch and must stay byte-for-byte the
    // task-008 read-only observer, whatever else the environment asks for --
    // the same gate task 025 and 029 are under.
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
    // Only stage 1 and above needs it; stage 0 touches the display mode alone.
    if (g_stage >= SC_WS_STAGE_GRID) {
        // GUARD + grid + GUARD, all committed, grid pointer into the middle
        // (see SC_WS_GRID_GUARD above). VirtualAlloc zeroes it, which is the
        // state the BSS array it replaces starts in -- stated rather than
        // assumed: a grid that came up full of 1s would mark the whole screen
        // dirty on frame one, which looks like a working feature and hides a
        // real bug. The guard pages are zeroed too, so an out-of-range TEST
        // reads "not dirty" and is harmless.
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

        // Oracle: prove the guard actually protects the OUT-OF-RANGE index that
        // crashed. grid-1 is where 0x0041DE84 faulted; grid+BYTES+GUARD-1 is the
        // far side. Both must read as committed, or the box is not there. This
        // line would say MISSING on the pre-fix bare allocation.
        const bool lo = RangeReadable(g_grid - 1, 1);
        const bool hi = RangeReadable(g_grid + SC_WS_GRID_BYTES + SC_WS_GRID_GUARD - 1, 1);
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
    // variable cannot be read as a full-stage result. An unannounced subset is
    // the same class of mistake as an assertion that cannot fail.
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
    // The relocated grid is deliberately LEAKED, exactly like a trampoline: the
    // game thread may be inside a loop holding a pointer into it right now.
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
