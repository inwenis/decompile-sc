// sc_stormpresent.cpp -- task 074. See sc_stormpresent.h for the why.
//
// THE PRESENT PIPELINE (StarCraft.exe 0x0041D420, one frame):
//   ord350 (lock)  -> ord432 (copy framebuffer 0x6CEFF4 -> locked surface via the
//                     region 0x6D5E18) -> ord356 (unlock / flip)
// (exe IAT: 0x4FE5A0=ord350, 0x4FE5A4=ord432, 0x4FE59C=ord356; work/scratch/074/iat.py.)
//
// storm keeps its OWN virtual-screen geometry in .data:
//   [storm+0x5A7C0]=8 (bpp)  [storm+0x5A7C4]=640 (WIDTH)  [storm+0x5A7C8]=480 (height)
// proven width/height by ord342 (imul height,[+0x5A7C4] for the DIB size + BitBlt),
// written by ord341 (the DDraw display-mode init, from its width argument) and by
// ord344's literal reset.
//
// The 640 wall, and why it is CONDITIONAL:
//   ord350 locking the primary (index 0) with a NULL rect either
//     (a) locks it DIRECTLY -- returns the primary pointer, never reads the geometry
//         (0x34DAB); or
//     (b) FALLS BACK -- builds a clip rect (0,0,[width],[height]) into the clip table
//         [storm+0x5EA74..0x5EA80], stores the fallback lock pointer at
//         [storm+0x5EA70], and re-locks a SYSTEM-MEMORY surface (index 3, 0x34E22).
//   ord356 unlocking the primary, if the fallback pointer [0x5EA70] is set, Blts that
//   (0,0,640,480) clip from the sysmem surface to the visible primary (0x34827) --
//   THAT Blt is the 640 cap. If the primary was locked directly, ord356 skips the Blt
//   and the present is already full-width.
//
// So which branch cnc-ddraw takes decides the entire fix, and it is a RUNTIME fact.
// This module's PROBE mode reads it out of the live process; it writes nothing.

#include "sc_stormpresent.h"

#include <stdio.h>
#include <string.h>

#include "sc_console.h"
#include "sc_hook.h"
#include "sc_log.h"
#include "sc_screen.h"
#include "sc_session.h"

#define SC_GAME_ENTRY __attribute__((force_align_arg_pointer))

// storm RVAs (preferred base 0x15000000; resolved from the LOADED module below).
#define STORM_RVA_BPP        0x0005A7C0u   // = 8
#define STORM_RVA_WIDTH      0x0005A7C4u   // = 640
#define STORM_RVA_HEIGHT     0x0005A7C8u   // = 480
#define STORM_RVA_FBLOCKPTR  0x0005EA70u   // fallback sysmem lock pointer (0 = direct)
#define STORM_RVA_CLIP       0x0005EA74u   // {l,t,r,b} flip clip, 4 dwords
#define STORM_RVA_SURFTABLE  0x0005EA84u   // IDirectDrawSurface*[4]; [0]=primary [3]=sysmem
#define STORM_RVA_PRIMARY    0x0005EA90u   // the DirectDraw object / primary handle ord356 Blts to
// Ordinal_440 (SRgnCreate) region-grid outputs: [+0]cells [+4]cells [+8]log2w
// [+0xC]log2h [+0x10]WIDTH [+0x14]HEIGHT. The exe patches Ordinal_440's width arg
// to 0x320 (sc_screen_patches.h storm.region.width @0x0041D531); did it take?
#define STORM_RVA_RGNGRID    0x0005AC10u
// IDirectDrawSurface vtable byte offsets (verified against storm: Lock=+0x64,
// Unlock=+0x80, Blt=+0x14 all matched the exe's present calls). GetSurfaceDesc = 22.
#define DDS_VTBL_GETSURFACEDESC 0x58u

// exe: the per-frame present region and the base region it is built from, plus the
// exe's own Ordinal_529 thunk (region -> rect list) -- the exact call layer2Draw makes.
#define EXE_VA_REGION_FRAME  0x006D5E18u
#define EXE_VA_REGION_BASE   0x006D5E14u
#define EXE_VA_ORD529_THUNK  0x00411E60u
#define SC_EXE_PREFERRED_BASE 0x00400000u
// storm ord432 (RVA 0x1A520), THE buffer->primary copy the exe present calls every
// frame: stdcall(dst, src, dstPitch, srcPitch, region), RET 0x14, returns 1. It
// copies only the dirty REGION (x<640, because the presentable region is 640 wide),
// so on a static frame the primary's x>=640 columns are never written and stay black
// even though the 800-wide buffer holds map there. The WIDEN hooks this and, after
// the engine's own copy, copies the x=640..799 strip straight from the buffer to the
// primary EVERY frame -- so the far quarter tracks the buffer without depending on a
// dirty mark. Prologue: push ebp; mov ebp,esp; mov eax,[ebp+0x18] (55 8B EC 8B 45 18),
// 6 bytes / 3 whole instructions / no PC-relative. Resolved from the LOADED storm.dll.
#define STORM_RVA_ORD432     0x0001A520u
// The widescreen geometry this repo builds (sc_screen_patches.h SC_WS_SCREEN_*).
#define SC_WS_WIDTH  800
#define SC_WS_HEIGHT 480
#define SC_STOCK_WIDTH 640

static ScStormMode g_mode = SC_STORM_OFF;
static BYTE*  g_exeBase   = NULL;
static BYTE*  g_stormBase = NULL;
static bool   g_writeAllowed = false;
static unsigned g_logs = 0;

// --- WIDEN state ---
static ScHook   g_hkCopy;                   // hook on storm ord432 (the present copy)
static unsigned g_stripFrames = 0;          // frames the x>=640 strip was copied (stats)
static unsigned g_stripSkipped = 0;         // present calls that did NOT meet the widescreen guard

static void* ExeRt(DWORD staticVa) {
    return (void*)(g_exeBase + (staticVa - SC_EXE_PREFERRED_BASE));
}
static void* StormRt(DWORD rva) {
    return (void*)(g_stormBase + rva);
}

static bool Readable(const void* addr, DWORD len) {
    if (!addr || len == 0) return false;
    MEMORY_BASIC_INFORMATION mbi;
    if (VirtualQuery(addr, &mbi, sizeof(mbi)) != sizeof(mbi)) return false;
    if (mbi.State != MEM_COMMIT) return false;
    if (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD)) return false;
    const DWORD ok = PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY |
                     PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY;
    if ((mbi.Protect & ok) == 0) return false;
    const BYTE* start = (const BYTE*)addr;
    const BYTE* regEnd = (const BYTE*)mbi.BaseAddress + mbi.RegionSize;
    return start >= (const BYTE*)mbi.BaseAddress && start + len <= regEnd;
}

static DWORD RdU32(const void* addr, bool* ok) {
    if (!Readable(addr, 4)) { if (ok) *ok = false; return 0; }
    if (ok) *ok = true;
    return *(const DWORD*)addr;
}

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------

// -1 = unset, else the explicit SC_STORM_* the env asked for.
static int StormEnvExplicit(void) {
    char buf[16];
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_STORM_PRESENT", buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return -1;
    if (buf[0] == '0' || buf[0] == 'n' || buf[0] == 'N') return SC_STORM_OFF;
    if (buf[0] == 'p' || buf[0] == 'P') return SC_STORM_PROBE;
    return SC_STORM_WIDEN;   // 1/y/widen
}

// The present-widen is PART of the widescreen feature: without it the engine
// computes 800 columns and the window shows 640 (renderer-viewport.md 19.8/20). So
// when widescreen is active at a stage whose buffer actually holds 800-wide playfield
// (stage >= 2), the ship default is WIDEN. %SCPLUGIN_STORM_PRESENT% overrides:
// 0 = off, probe = read-only, widen = force on.
ScStormMode ScStormPresentModeWanted(void) {
    const int ex = StormEnvExplicit();
    if (ex == SC_STORM_OFF) return SC_STORM_OFF;
    if (ex == SC_STORM_PROBE) return SC_STORM_PROBE;
    const bool wsPlayfield = ScScreenWidescreenWanted() && ScScreenStageWanted() >= 2;
    if (ex == SC_STORM_WIDEN) return SC_STORM_WIDEN;      // forced (gated again in Install)
    return wsPlayfield ? SC_STORM_WIDEN : SC_STORM_OFF;   // unset: widen iff widescreen playfield
}

// ---------------------------------------------------------------------------
// The region rect count, through the exe's own Ordinal_529 thunk (stdcall:
// region, &count[in=cap out=written], rects). The same call sc_console used.
// ---------------------------------------------------------------------------
static void LogRegionRects(const char* what, DWORD regionVaOfPtr) {
    bool ok = false;
    DWORD region = RdU32(ExeRt(regionVaOfPtr), &ok);
    if (!ok || !region) { ScLog("STORM region %s: handle %s", what, ok ? "NULL" : "unreadable"); return; }
    DWORD cnt = 8;
    int rects[8][4];
    memset(rects, 0, sizeof(rects));
    typedef void (__attribute__((stdcall)) *RgnRectsFn)(DWORD, DWORD*, void*);
    ((RgnRectsFn)ExeRt(EXE_VA_ORD529_THUNK))(region, &cnt, rects);
    char line[320]; size_t used = 0; line[0] = '\0';
    for (DWORD i = 0; i < cnt && i < 8 && used + 48 < sizeof(line); ++i)
        used += (size_t)_snprintf(line + used, sizeof(line) - used, "%s(%d,%d,%d,%d)",
                                  i ? " " : "", rects[i][0], rects[i][1], rects[i][2], rects[i][3]);
    ScLog("STORM region %s: handle=0x%08X rects(n=%u, first 8): %s",
          what, (unsigned)region, (unsigned)cnt, line);
}

// The SRgn struct ord432 actually copies from (allocator 0x1A7E0, size 0x30;
// builder ord436 0x1B1F0): +0x08 span-buffer base, +0x14 span rows, +0x18 left,
// +0x1C row count, +0x20..0x2C bounding rect {l,t,r,b}. The bounding rect is the
// Ordinal_529-independent readout of the copy extent -- (0,0,640,480) here IS the
// 640 cap; (0,0,800,480) means the cap is elsewhere.
static void LogRegionStruct(const char* t, const char* what, DWORD regionVaOfPtr) {
    bool ok = false;
    DWORD r = RdU32(ExeRt(regionVaOfPtr), &ok);
    if (!ok || !r || !Readable((void*)(DWORD_PTR)r, 0x30)) {
        ScLog("STORM [%s] region-struct %s: handle %s", t, what,
              (!ok || !r) ? "NULL/unreadable ptr" : "handle unreadable");
        return;
    }
    const DWORD* f = (const DWORD*)(DWORD_PTR)r;
    ScLog("STORM [%s] region-struct %s: handle=0x%08X +08=0x%08X +14=0x%08X +18=%d "
          "+1C(rows)=%d  BOUNDS[+20]=(%d,%d,%d,%d)",
          t, what, (unsigned)r, (unsigned)f[2], (unsigned)f[5], (int)f[6],
          (int)f[7], (int)f[8], (int)f[9], (int)f[10], (int)f[11]);
}

// ---------------------------------------------------------------------------
// The read-only diagnostic
// ---------------------------------------------------------------------------

void ScStormPresentLog(const char* tag) {
    if (g_mode == SC_STORM_OFF || !g_stormBase) return;
    const char* t = tag ? tag : "-";
    ++g_logs;

    bool okW, okH, okB;
    DWORD w = RdU32(StormRt(STORM_RVA_WIDTH), &okW);
    DWORD h = RdU32(StormRt(STORM_RVA_HEIGHT), &okH);
    DWORD bpp = RdU32(StormRt(STORM_RVA_BPP), &okB);
    ScLog("STORM [%s] geometry: bpp=%s%u width=%s%u height=%s%u (storm base 0x%08X)",
          t, okB ? "" : "?", (unsigned)bpp, okW ? "" : "?", (unsigned)w,
          okH ? "" : "?", (unsigned)h, (unsigned)(DWORD_PTR)g_stormBase);

    bool okF;
    DWORD fb = RdU32(StormRt(STORM_RVA_FBLOCKPTR), &okF);
    bool okC[4]; DWORD clip[4];
    for (int i = 0; i < 4; ++i) clip[i] = RdU32((BYTE*)StormRt(STORM_RVA_CLIP) + i * 4, &okC[i]);
    ScLog("STORM [%s] present path: fallbackLockPtr[0x5EA70]=%s0x%08X (%s) "
          "clip[0x5EA74]=(%d,%d,%d,%d)",
          t, okF ? "" : "?", (unsigned)fb,
          (okF && fb) ? "SYSMEM FALLBACK is live -- ord356 Blts the clip; the 640 cap is here"
                      : "0 -> primary locked DIRECTLY this sample; no ord356 Blt, cap is NOT the clip",
          (int)clip[0], (int)clip[1], (int)clip[2], (int)clip[3]);

    bool okS[4]; DWORD surf[4];
    for (int i = 0; i < 4; ++i) surf[i] = RdU32((BYTE*)StormRt(STORM_RVA_SURFTABLE) + i * 4, &okS[i]);
    bool okP; DWORD prim = RdU32(StormRt(STORM_RVA_PRIMARY), &okP);
    ScLog("STORM [%s] surfaces[0x5EA84]: [0]=0x%08X [1]=0x%08X [2]=0x%08X [3]=0x%08X "
          "primary[0x5EA90]=0x%08X",
          t, (unsigned)surf[0], (unsigned)surf[1], (unsigned)surf[2], (unsigned)surf[3],
          okP ? (unsigned)prim : 0);

    // storm's region-grid dimensions (Ordinal_440 outputs). If the exe's
    // Ordinal_440 width patch to 0x320 took, [+0x10] reads 800; if it still reads
    // 640, storm builds every region on a 640-wide grid and THAT clips the copy.
    bool okG[6]; DWORD g[6];
    for (int i = 0; i < 6; ++i) g[i] = RdU32((BYTE*)StormRt(STORM_RVA_RGNGRID) + i * 4, &okG[i]);
    ScLog("STORM [%s] region-grid[0x5AC10]: cells=%u/%u log2=(%u,%u) WIDTH=%s%u HEIGHT=%u",
          t, (unsigned)g[0], (unsigned)g[1], (unsigned)g[2], (unsigned)g[3],
          okG[4] ? "" : "?", (unsigned)g[4], (unsigned)g[5]);

    // The primary surface's REAL geometry, via IDirectDrawSurface::GetSurfaceDesc.
    // A black RIGHT band with no letterbox means the primary is 800 and only 0..639
    // were written (cap is the copy); a 640 primary would mean the surface itself is
    // narrow. Read-only COM call, pointer-guarded.
    bool okS0; DWORD prim0 = RdU32(StormRt(STORM_RVA_SURFTABLE), &okS0);
    if (okS0 && prim0 && Readable((void*)(DWORD_PTR)prim0, 4)) {
        DWORD vtbl = *(DWORD*)(DWORD_PTR)prim0;
        if (Readable((void*)(DWORD_PTR)(vtbl + DDS_VTBL_GETSURFACEDESC), 4)) {
            DWORD fn = *(DWORD*)(DWORD_PTR)(vtbl + DDS_VTBL_GETSURFACEDESC);
            BYTE ddsd[0x6C];
            memset(ddsd, 0, sizeof(ddsd));
            *(DWORD*)ddsd = 0x6C;   // dwSize
            typedef long (__attribute__((stdcall)) *GetDescFn)(DWORD, void*);
            long hr = ((GetDescFn)(DWORD_PTR)fn)(prim0, ddsd);
            ScLog("STORM [%s] primary 0x%08X GetSurfaceDesc hr=0x%08X: dwWidth=%u dwHeight=%u "
                  "lPitch=%d dwFlags=0x%08X",
                  t, (unsigned)prim0, (unsigned)hr,
                  (unsigned)*(DWORD*)(ddsd + 0x0C), (unsigned)*(DWORD*)(ddsd + 0x08),
                  (int)*(long*)(ddsd + 0x10), (unsigned)*(DWORD*)(ddsd + 0x04));
        } else {
            ScLog("STORM [%s] primary 0x%08X: vtable+0x58 unreadable -- no GetSurfaceDesc", t, (unsigned)prim0);
        }
    } else {
        ScLog("STORM [%s] primary surface pointer not readable (0x%08X)", t, (unsigned)prim0);
    }

    LogRegionRects("frame 0x6D5E18", EXE_VA_REGION_FRAME);
    LogRegionRects("base  0x6D5E14", EXE_VA_REGION_BASE);
    LogRegionStruct(t, "frame 0x6D5E18", EXE_VA_REGION_FRAME);
    LogRegionStruct(t, "base  0x6D5E14", EXE_VA_REGION_BASE);
}

// ---------------------------------------------------------------------------
// WIDEN: present the far quarter (x=640..799) the dirty-rect copy leaves black
//
// MEASURED, and why the obvious levers do NOT work on their own:
//  * Run 5: the presentable region is 640 wide because its primary image node is the
//    640-wide console, and the SRgn combine (ord443) does NOT raise a region's +0x18
//    -- a genuinely solid (640,0)-(800,480) node left base +0x18 = 640. So ADDING
//    image nodes cannot widen the present (073's node was dead at the mechanism level).
//  * Run 6/7: widening the base region to 800 (frame region then inherits 800) makes
//    the present carry x>640 ONLY on frames that re-mark those cells dirty. The present
//    is dirty-rect; on a STATIC load frame the primary's x>=640 stays black even with
//    an 800 base, because nothing re-copies it (run 7: base +0x18=800, glass map = 0).
//
// So the robust fix intercepts THE COPY. ord432 copies the dirty region (x<640) as
// normal; then this copies the x=640..799 strip straight from the 800-wide buffer to
// the primary, every frame. It touches ONLY x>=640, where there is no console/HUD
// (the console is 640 wide), so it overwrites nothing the engine draws there -- it is
// NOT a full-frame copy. src/dst/pitches are ord432's own arguments, so the strip is
// always consistent with the engine's own copy of the same frame.
// ---------------------------------------------------------------------------

typedef int (__attribute__((stdcall)) *ScOrd432Fn)(DWORD dst, DWORD src, DWORD dstPitch,
                                                    DWORD srcPitch, DWORD region);

static int __attribute__((stdcall)) SC_GAME_ENTRY
HkOrd432(DWORD dst, DWORD src, DWORD dstPitch, DWORD srcPitch, DWORD region) {
    // The engine's own copy first (the dirty region, x<640, unchanged).
    int ret = ((ScOrd432Fn)g_hkCopy.trampoline)(dst, src, dstPitch, srcPitch, region);
    // Then the far quarter, straight from the buffer. Guarded on the widescreen
    // geometry so a stray 640-pitch call can never write past a 640-wide surface.
    if (g_mode == SC_STORM_WIDEN && dst && src &&
        dstPitch >= (DWORD)SC_WS_WIDTH && srcPitch >= (DWORD)SC_WS_WIDTH) {
        const int stripW = SC_WS_WIDTH - SC_STOCK_WIDTH;   // 160
        BYTE* d = (BYTE*)(DWORD_PTR)dst + SC_STOCK_WIDTH;
        BYTE* s = (BYTE*)(DWORD_PTR)src + SC_STOCK_WIDTH;
        for (int y = 0; y < SC_WS_HEIGHT; ++y) {
            memcpy(d, s, (size_t)stripW);
            d += dstPitch;
            s += srcPitch;
        }
        ++g_stripFrames;
    } else if (g_mode == SC_STORM_WIDEN) {
        ++g_stripSkipped;
    }
    return ret;
}

// storm ord432 prologue: push ebp; mov ebp,esp; mov eax,[ebp+0x18] (55 8B EC 8B 45 18)
// -- 6 bytes, 3 whole instructions, no PC-relative operand.
static const BYTE kPrologueOrd432[] = { 0x55, 0x8B, 0xEC, 0x8B, 0x45, 0x18 };

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

void ScStormPresentInstall(BYTE* exeBase, bool writeAllowed) {
    g_exeBase = exeBase;
    g_writeAllowed = writeAllowed;
    g_mode = ScStormPresentModeWanted();
    g_logs = 0;
    if (g_mode == SC_STORM_OFF) {
        // Name the half that decided it. Issue #113: "unset/0" could not distinguish
        // "the launcher exported 0" from "nothing to present", and the deployed wide
        // game ran with the copy OFF behind exactly that line.
        if (StormEnvExplicit() == SC_STORM_OFF)
            ScLog("STORM present: off -- %%SCPLUGIN_STORM_PRESENT%%=0 (explicit)");
        else
            ScLog("STORM present: off -- %%SCPLUGIN_STORM_PRESENT%% unset and no widescreen "
                  "playfield to present (widescreen=%d stage=%d; auto-arms at stage>=2)",
                  ScScreenWidescreenWanted() ? 1 : 0, ScScreenStageWanted());
        return;
    }
    g_stormBase = (BYTE*)GetModuleHandleA("storm.dll");
    if (!g_stormBase) {
        ScLog("STORM present: storm.dll not loaded in this process -- module DISABLED");
        g_mode = SC_STORM_OFF;
        return;
    }
    if (g_mode == SC_STORM_WIDEN && !writeAllowed) {
        ScLog("STORM present: widen requested but mode is observe -- IGNORED (observe "
              "writes nothing to game memory). Read-only probe still runs.");
        g_mode = SC_STORM_PROBE;
    }
    if (g_mode == SC_STORM_WIDEN && !(ScScreenWidescreenWanted() && ScScreenStageWanted() >= 2)) {
        // The strip copies the buffer's x>=640 columns, which only hold 800-wide
        // playfield when widescreen is active at stage >= 2; otherwise it would carry
        // black/garbage. Disarm to read-only rather than corrupt the screen.
        ScLog("STORM present: widen needs widescreen stage>=2 (an 800-wide playfield "
              "buffer) -- widescreen=%d stage=%d. DISARMED to read-only PROBE.",
              ScScreenWidescreenWanted() ? 1 : 0, ScScreenStageWanted());
        g_mode = SC_STORM_PROBE;
    }
    if (g_mode == SC_STORM_WIDEN && ScConsoleEdgeWanted()) {
        // Task 073's console move (merged, behind %SCPLUGIN_CONSOLE_EDGE%) direct-blits
        // the moved resource bar and command card at x>640 (renderer-viewport.md 19.1).
        // The strip copy would overwrite them with terrain every frame, so the two are
        // MUTUALLY EXCLUSIVE for now: the console-edge experiment wins, the storm widen
        // disarms. Stated so nobody turning on both discovers it as a defect.
        ScLog("STORM present: %%SCPLUGIN_CONSOLE_EDGE%% (073's console move) is ON -- its "
              "moved card/bar are direct-blitted at x>640 and the strip copy would overwrite "
              "them. The storm present widen is DISARMED to PROBE (the two are mutually "
              "exclusive for now).");
        g_mode = SC_STORM_PROBE;
    }
    if (g_mode == SC_STORM_WIDEN) {
        g_stripFrames = 0;
        g_stripSkipped = 0;
        memset(&g_hkCopy, 0, sizeof(g_hkCopy));
        void* ord432 = StormRt(STORM_RVA_ORD432);   // resolved from the LOADED storm.dll
        if (!ScHookInstall(&g_hkCopy, "stormWidenCopy", ord432,
                           (void*)&HkOrd432, (int)sizeof(kPrologueOrd432),
                           kPrologueOrd432, (int)sizeof(kPrologueOrd432))) {
            ScLog("STORM WIDEN: copy hook at storm ord432 (0x%08X) failed to install -- "
                  "falling back to read-only PROBE", (unsigned)(DWORD_PTR)ord432);
            g_mode = SC_STORM_PROBE;
        } else {
            ScLog("STORM present: WIDEN armed. storm base 0x%08X; game-thread hook at storm "
                  "ord432 (0x%08X) copies the x=640..799 strip from the 800-wide buffer to the "
                  "primary each present, so the buffer->glass present carries all 800 columns. "
                  "The read-only geometry log also runs on the marker channel.",
                  (unsigned)(DWORD_PTR)g_stormBase, (unsigned)(DWORD_PTR)ord432);
        }
    }
    if (g_mode == SC_STORM_PROBE) {
        ScLog("STORM present: PROBE (read-only). storm base 0x%08X; logging geometry + "
              "present path + region on the marker channel. Writes nothing to game memory.",
              (unsigned)(DWORD_PTR)g_stormBase);
    }
}

void ScStormPresentRemove(void) {
    // PROBE writes nothing. WIDEN: un-splice the copy hook. Nothing in game memory is
    // left changed -- the strip copy only wrote presented pixels, which the next stock
    // present overwrites.
    if (g_hkCopy.installed) ScHookRemove(&g_hkCopy);
}

void ScStormPresentLogStats(void) {
    if (g_mode == SC_STORM_OFF) return;
    ScLog("STORMSTATS mode=%d logs=%u stripFrames=%u stripSkipped=%u stormBase=0x%08X",
          (int)g_mode, g_logs, g_stripFrames, g_stripSkipped,
          (unsigned)(DWORD_PTR)g_stormBase);
}
