// The present pipeline (StarCraft.exe 0x0041D420, one frame): ord350 (lock) -> ord432
// (copy framebuffer 0x6CEFF4 -> locked surface via the region 0x6D5E18) -> ord356
// (unlock / flip). exe IAT: 0x4FE5A0=ord350, 0x4FE5A4=ord432, 0x4FE59C=ord356.
//
// storm keeps its OWN virtual-screen geometry in .data: [storm+0x5A7C0]=8 (bpp),
// [storm+0x5A7C4]=640 (width), [storm+0x5A7C8]=480 (height). Width/height proven by
// ord342 (imul height,[+0x5A7C4] for the DIB size + BitBlt); written by ord341 (the
// DDraw display-mode init, from its width argument) and by ord344's literal reset.
// The 640 wall is CONDITIONAL: ord350 locking the primary (index 0) with a NULL rect
// either locks it DIRECTLY (returns the primary pointer, never reads the geometry,
// 0x34DAB) or FALLS BACK -- clip rect (0,0,[width],[height]) into [storm+0x5EA74..0x5EA80],
// fallback lock pointer at [storm+0x5EA70], re-lock of the sysmem surface (index 3,
// 0x34E22) -- and ord356 then Blts that (0,0,640,480) clip to the visible primary
// (0x34827), which IS the cap. Which branch cnc-ddraw takes is a runtime fact, read out
// of the live process by PROBE mode, which writes nothing.

#include "sc_stormpresent.h"

#include <stdio.h>
#include <string.h>

#include "sc_addresses.h"
#include "sc_console.h"
#include "sc_engine.h"
#include "sc_env.h"
#include "sc_hook.h"
#include "sc_log.h"
#include "sc_screen.h"
#include "sc_session.h"

// storm RVAs (preferred base 0x15000000; resolved from the LOADED module below).
#define STORM_RVA_BPP        0x0005A7C0u   // = 8
#define STORM_RVA_WIDTH      0x0005A7C4u   // = 640
#define STORM_RVA_HEIGHT     0x0005A7C8u   // = 480
#define STORM_RVA_FALLBACK_LOCK_PTR 0x0005EA70u   // fallback sysmem lock pointer (0 = direct)
#define STORM_RVA_CLIP       0x0005EA74u   // {l,t,r,b} flip clip, 4 dwords
#define STORM_RVA_SURFTABLE  0x0005EA84u   // IDirectDrawSurface*[4]; [0]=primary [3]=sysmem
#define STORM_RVA_PRIMARY    0x0005EA90u   // the DirectDraw object / primary handle ord356 Blts to
// Ordinal_440 (SRgnCreate) region-grid outputs: [+0]cells [+4]cells [+8]log2w
// [+0xC]log2h [+0x10]WIDTH [+0x14]HEIGHT.
#define STORM_RVA_RGNGRID    0x0005AC10u
// IDirectDrawSurface vtable byte offsets (verified against storm: Lock=+0x64,
// Unlock=+0x80, Blt=+0x14 all matched the exe's present calls). GetSurfaceDesc = 22.
#define DDS_VTBL_GETSURFACEDESC 0x58u

// exe: the per-frame present region and the base region it is built from, plus the
// exe's own Ordinal_529 thunk (region -> rect list) -- the exact call layer2Draw makes.
#define EXE_VA_REGION_FRAME  0x006D5E18u
#define EXE_VA_REGION_BASE   0x006D5E14u
#define EXE_VA_ORD529_THUNK  0x00411E60u
// storm ord432 (RVA 0x1A520), THE buffer->primary copy the exe present calls every frame:
// stdcall(dst, src, dstPitch, srcPitch, region), RET 0x14, returns 1. It copies only the
// dirty REGION (x<640, the presentable region's width), so on a static frame the primary's
// x>=640 columns stay black even though the wide buffer holds map there.
#define STORM_RVA_ORD432     0x0001A520u
static ScStormMode g_mode = SC_STORM_OFF;
static BYTE*  g_stormBase = NULL;
static bool   g_writeAllowed = false;
static unsigned g_logs = 0;

// --- WIDEN state ---
static ScHook   g_hkCopy;                   // hook on storm ord432 (the present copy)
static unsigned g_stripFrames = 0;          // presents that copied the x>=640 strip
static unsigned g_cursorForced = 0;         // times layer 0's always-draw bit was found clear and set
static unsigned g_tipForced    = 0;         // the same for layer 1, the tooltip
static bool     g_tipFix       = true;      // %SCPLUGIN_TIPFIX%: 0 leaves layer 1 dirty-driven
static unsigned g_stripSkipped = 0;         // present calls that did NOT meet the widescreen guard
static int      g_primaryRows  = -1;        // the primary's dwHeight (GetSurfaceDesc), read once; -1 = unread
static unsigned g_mirrorFrames = 0;         // presents that mirrored the WHOLE frame (console buffer-resident)

// --- present timing ---------------------------------------------------------
// "Did the game stall, or did the machine?" needs two numbers the same clock produced:
// the interval the ENGINE left between consecutive presents, and this hook's own cost
// inside one (the mirror memcpy). Everything is integer microseconds from
// QueryPerformanceCounter, so the game thread's x87 state is never touched, and ONE
// ScLog per window is the whole log budget -- a per-frame line would itself be the stall.
//
// Only intervals whose BOTH ends were in game are sampled, because the interval that
// spans a menu, a map load or an alt-tab is not the game hitching; when the console walk
// cannot say (it is gated on the console move being armed) every interval is sampled and
// the line reports ingame=-1 so a zero is never mistaken for "no time was spent in game".
#define SC_STORMTIME_WINDOW_S  60
#define SC_STORMTIME_STALL_US  100000   // an interval this long is a hitch a player sees
#define SC_STORMTIME_STALL_LINES 64     // STORMSTALL lines per session: a stall storm must not become one

static LONGLONG g_qpf        = 0;   // counter frequency; 0 = no usable clock, timing off
static LONGLONG g_tPrev      = 0;   // previous present's stamp; 0 = no predecessor yet
static LONGLONG g_tWinStart  = 0;
static int      g_prevInGame = -1;
static unsigned g_winPresents = 0, g_winIngame = 0, g_winSamples = 0, g_winStalls = 0;
static bool     g_winIngameKnown = false;
static LONGLONG g_winSumUs = 0, g_winMaxUs = 0, g_winHookSumUs = 0, g_winHookMaxUs = 0;
static unsigned g_totPresents = 0, g_totSamples = 0, g_totStalls = 0, g_totWindows = 0;
static LONGLONG g_totSumUs = 0, g_totMaxUs = 0, g_totHookMaxUs = 0;
static unsigned g_totLogMaxUs = 0, g_totLogLines = 0, g_totLogSumUs = 0;
static unsigned g_logLinesAtPrev = 0, g_logUsAtPrev = 0;   // ScLogWriteCostSoFar at the previous present
static LONGLONG g_hookUsPrev = 0;
static unsigned g_stallLines = 0;
// Process CPU (kernel + user, GetProcessTimes, 100 ns units) at the window's start, and
// the closed windows' totals, so a play log prices the per-frame full redraw as a
// percent of one core over the same wall clock the present intervals use.
static ULONGLONG g_cpuWinStart = 0, g_totCpu100ns = 0;
static LONGLONG  g_totWallUs = 0;

static ULONGLONG CpuNow100ns(void) {
    FILETIME c, e, k, u;
    if (!GetProcessTimes(GetCurrentProcess(), &c, &e, &k, &u)) return 0;
    ULARGE_INTEGER kk, uu;
    kk.LowPart = k.dwLowDateTime; kk.HighPart = k.dwHighDateTime;
    uu.LowPart = u.dwLowDateTime; uu.HighPart = u.dwHighDateTime;
    return kk.QuadPart + uu.QuadPart;
}

static unsigned CpuPct(ULONGLONG cpu100ns, LONGLONG wallUs) {
    return wallUs > 0 ? (unsigned)((cpu100ns / 10) * 100 / (ULONGLONG)wallUs) : 0;
}

static void* StormRt(DWORD rva) {
    return (void*)(g_stormBase + rva);
}

static DWORD StormReadU32(const void* addr, bool* ok) {
    if (!ScReadableAt(addr, 4)) { if (ok) *ok = false; return 0; }
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

// Without the widen the engine computes every column of the wide screen and the window
// shows 640 (renderer-viewport.md 19.8/20), so the default is WIDEN whenever the buffer
// actually holds a wide playfield (widescreen at stage >= 2). %SCPLUGIN_STORM_PRESENT%
// overrides: 0 = off, probe = read-only, widen = force on.
ScStormMode ScStormPresentModeWanted(void) {
    const int ex = StormEnvExplicit();
    if (ex == SC_STORM_OFF) return SC_STORM_OFF;
    if (ex == SC_STORM_PROBE) return SC_STORM_PROBE;
    const bool wsPlayfield = ScScreenWidescreenWanted() && ScScreenStageWanted() >= 2;
    if (ex == SC_STORM_WIDEN) return SC_STORM_WIDEN;      // forced (gated again in Install)
    return wsPlayfield ? SC_STORM_WIDEN : SC_STORM_OFF;
}

// ---------------------------------------------------------------------------
// The region rect count, through the exe's own Ordinal_529 thunk (stdcall:
// region, &count[in=cap out=written], rects).
// ---------------------------------------------------------------------------
static void LogRegionRects(const char* what, DWORD regionVaOfPtr) {
    bool ok = false;
    DWORD region = StormReadU32(ScRuntimeAddr(regionVaOfPtr), &ok);
    if (!ok || !region) { ScLog("STORM region %s: handle %s", what, ok ? "NULL" : "unreadable"); return; }
    DWORD cnt = 8;
    int rects[8][4];
    memset(rects, 0, sizeof(rects));
    typedef void (__attribute__((stdcall)) *RgnRectsFn)(DWORD, DWORD*, void*);
    ((RgnRectsFn)ScRuntimeAddr(EXE_VA_ORD529_THUNK))(region, &cnt, rects);
    char line[320]; size_t used = 0; line[0] = '\0';
    for (DWORD i = 0; i < cnt && i < 8 && used + 48 < sizeof(line); ++i)
        used += (size_t)_snprintf(line + used, sizeof(line) - used, "%s(%d,%d,%d,%d)",
                                  i ? " " : "", rects[i][0], rects[i][1], rects[i][2], rects[i][3]);
    ScLog("STORM region %s: handle=0x%08X rects(n=%u, first 8): %s",
          what, (unsigned)region, (unsigned)cnt, line);
}

// The SRgn struct ord432 copies from (allocator 0x1A7E0, size 0x30; builder ord436
// 0x1B1F0): +0x08 span base, +0x14 span rows, +0x18 left, +0x1C row count, +0x20..0x2C
// bounding rect {l,t,r,b}. That rect is the Ordinal_529-independent copy extent:
// (0,0,640,480) IS the 640 cap; a wider rect puts the cap elsewhere.
static void LogRegionStruct(const char* t, const char* what, DWORD regionVaOfPtr) {
    bool ok = false;
    DWORD r = StormReadU32(ScRuntimeAddr(regionVaOfPtr), &ok);
    if (!ok || !r || !ScReadableAt((void*)(DWORD_PTR)r, 0x30)) {
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
    DWORD w = StormReadU32(StormRt(STORM_RVA_WIDTH), &okW);
    DWORD h = StormReadU32(StormRt(STORM_RVA_HEIGHT), &okH);
    DWORD bpp = StormReadU32(StormRt(STORM_RVA_BPP), &okB);
    ScLog("STORM [%s] geometry: bpp=%s%u width=%s%u height=%s%u (storm base 0x%08X)",
          t, okB ? "" : "?", (unsigned)bpp, okW ? "" : "?", (unsigned)w,
          okH ? "" : "?", (unsigned)h, (unsigned)(DWORD_PTR)g_stormBase);

    bool okF;
    DWORD fb = StormReadU32(StormRt(STORM_RVA_FALLBACK_LOCK_PTR), &okF);
    bool okC[4]; DWORD clip[4];
    for (int i = 0; i < 4; ++i) clip[i] = StormReadU32((BYTE*)StormRt(STORM_RVA_CLIP) + i * 4, &okC[i]);
    ScLog("STORM [%s] present path: fallbackLockPtr[0x5EA70]=%s0x%08X (%s) "
          "clip[0x5EA74]=(%d,%d,%d,%d)",
          t, okF ? "" : "?", (unsigned)fb,
          (okF && fb) ? "SYSMEM FALLBACK is live -- ord356 Blts the clip; the 640 cap is here"
                      : "0 -> primary locked DIRECTLY this sample; no ord356 Blt, cap is NOT the clip",
          (int)clip[0], (int)clip[1], (int)clip[2], (int)clip[3]);

    bool okS[4]; DWORD surf[4];
    for (int i = 0; i < 4; ++i) surf[i] = StormReadU32((BYTE*)StormRt(STORM_RVA_SURFTABLE) + i * 4, &okS[i]);
    bool okP; DWORD prim = StormReadU32(StormRt(STORM_RVA_PRIMARY), &okP);
    ScLog("STORM [%s] surfaces[0x5EA84]: [0]=0x%08X [1]=0x%08X [2]=0x%08X [3]=0x%08X "
          "primary[0x5EA90]=0x%08X",
          t, (unsigned)surf[0], (unsigned)surf[1], (unsigned)surf[2], (unsigned)surf[3],
          okP ? (unsigned)prim : 0);

    // The exe patches Ordinal_440's width argument to the screen width (storm.region.width
    // @0x0041D531): if it took, [+0x10] reads that width; if it still reads 640, storm
    // builds every region on a 640-wide grid and THAT clips the copy.
    bool okG[6]; DWORD g[6];
    for (int i = 0; i < 6; ++i) g[i] = StormReadU32((BYTE*)StormRt(STORM_RVA_RGNGRID) + i * 4, &okG[i]);
    ScLog("STORM [%s] region-grid[0x5AC10]: cells=%u/%u log2=(%u,%u) WIDTH=%s%u HEIGHT=%u",
          t, (unsigned)g[0], (unsigned)g[1], (unsigned)g[2], (unsigned)g[3],
          okG[4] ? "" : "?", (unsigned)g[4], (unsigned)g[5]);

    // The primary surface's REAL geometry, via IDirectDrawSurface::GetSurfaceDesc: a
    // black RIGHT band with no letterbox and a wide primary means only 0..639 were
    // written (the cap is the copy); a 640 primary means the surface itself is narrow.
    // Read-only COM call, pointer-guarded.
    bool okS0; DWORD prim0 = StormReadU32(StormRt(STORM_RVA_SURFTABLE), &okS0);
    if (okS0 && prim0 && ScReadableAt((void*)(DWORD_PTR)prim0, 4)) {
        DWORD vtbl = *(DWORD*)(DWORD_PTR)prim0;
        if (ScReadableAt((void*)(DWORD_PTR)(vtbl + DDS_VTBL_GETSURFACEDESC), 4)) {
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
// WIDEN: present the columns past x=639 that the dirty-rect copy leaves black
//
// Two levers do NOT widen the present, measured:
//  * Adding image nodes: the presentable region is 640 wide because its primary image
//    node is the 640-wide console, and the SRgn combine (ord443) does NOT raise a
//    region's +0x18 -- a genuinely solid (640,0)-(800,480) node left base +0x18 = 640.
//  * Widening the base region to 800 (the frame region then inherits 800): the present
//    is dirty-rect, so it carries x>640 only on frames that re-mark those cells dirty;
//    on a STATIC frame the primary's x>=640 stays black with an 800 base (measured:
//    base +0x18=800, glass map = 0).
//
// So the robust fix intercepts THE COPY: after ord432's own dirty-region copy, this copies
// the x>=640 strip straight from the wide buffer to the primary, every frame. It
// touches ONLY x>=640, where there is no console/HUD (the console is 640 wide), so it
// overwrites nothing the engine draws and is NOT a full-frame copy; src/dst/pitches are
// ord432's own arguments, so the strip always matches the engine's copy of that frame.
// ---------------------------------------------------------------------------

typedef int (__attribute__((stdcall)) *ScOrd432Fn)(DWORD dst, DWORD src, DWORD dstPitch,
                                                    DWORD srcPitch, DWORD region);

// The primary's real row count, via IDirectDrawSurface::GetSurfaceDesc on storm's surface
// table entry 0. Read once; an unreadable table or a failed call returns 0 and the mirror
// falls back to the table's H. This keeps a whole-frame mirror inside the surface if a
// display-mode change ever leaves the primary shorter than the table says.
static int ReadPrimaryRows(void) {
    if (!g_stormBase) return 0;
    bool ok; DWORD prim0 = StormReadU32(StormRt(STORM_RVA_SURFTABLE), &ok);
    if (!ok || !prim0 || !ScReadableAt((void*)(DWORD_PTR)prim0, 4)) return 0;
    DWORD vtbl = *(DWORD*)(DWORD_PTR)prim0;
    if (!ScReadableAt((void*)(DWORD_PTR)(vtbl + DDS_VTBL_GETSURFACEDESC), 4)) return 0;
    DWORD fn = *(DWORD*)(DWORD_PTR)(vtbl + DDS_VTBL_GETSURFACEDESC);
    BYTE ddsd[0x6C];
    memset(ddsd, 0, sizeof(ddsd));
    *(DWORD*)ddsd = 0x6C;
    typedef long (__attribute__((stdcall)) *GetDescFn)(DWORD, void*);
    long hr = ((GetDescFn)(DWORD_PTR)fn)(prim0, ddsd);
    if (hr != 0) return 0;
    return (int)*(DWORD*)(ddsd + 0x08);   // dwHeight
}

int ScStormReadPrimaryRows(void) { return ReadPrimaryRows(); }

#define DDS_VTBL_GETPALETTE 0x50u
#define DDP_VTBL_RELEASE    0x08u
#define DDP_VTBL_GETENTRIES 0x10u
bool ScStormReadPalette(BYTE* out1024) {
    // storm.dll by name when the present module is off: its base doubles as its
    // installed flag, so it is read here, never set.
    BYTE* base = g_stormBase ? g_stormBase : (BYTE*)GetModuleHandleA("storm.dll");
    if (!base) return false;
    bool ok; DWORD prim0 = StormReadU32(base + STORM_RVA_SURFTABLE, &ok);
    if (!ok || !prim0 || !ScReadableAt((void*)(DWORD_PTR)prim0, 4)) return false;
    DWORD vtbl = *(DWORD*)(DWORD_PTR)prim0;
    if (!ScReadableAt((void*)(DWORD_PTR)(vtbl + DDS_VTBL_GETPALETTE), 4)) return false;
    typedef long (__attribute__((stdcall)) *GetPalFn)(DWORD, DWORD*);
    typedef long (__attribute__((stdcall)) *GetEntriesFn)(DWORD, DWORD, DWORD, DWORD, void*);
    typedef unsigned long (__attribute__((stdcall)) *ReleaseFn)(DWORD);
    DWORD pal = 0;
    if (((GetPalFn)(DWORD_PTR)*(DWORD*)(DWORD_PTR)(vtbl + DDS_VTBL_GETPALETTE))(prim0, &pal) != 0 || !pal)
        return false;
    DWORD pvt = *(DWORD*)(DWORD_PTR)pal;
    const long hr = ScReadableAt((void*)(DWORD_PTR)(pvt + DDP_VTBL_GETENTRIES), 4)
        ? ((GetEntriesFn)(DWORD_PTR)*(DWORD*)(DWORD_PTR)(pvt + DDP_VTBL_GETENTRIES))(pal, 0, 0, 256, out1024)
        : -1;
    ((ReleaseFn)(DWORD_PTR)*(DWORD*)(DWORD_PTR)(pvt + DDP_VTBL_RELEASE))(pal);   // GetPalette AddRef'd it
    return hr == 0;
}

static LONGLONG QpcNow(void) {
    if (!g_qpf) return 0;
    LARGE_INTEGER v;
    QueryPerformanceCounter(&v);
    return v.QuadPart;
}

// Ticks -> microseconds. Only ever handed a DELTA: multiplying a raw counter by a
// million overflows 64 bits, a delta of a whole day does not.
static LONGLONG TicksToUs(LONGLONG d) { return (d > 0 && g_qpf) ? (d * 1000000) / g_qpf : 0; }

// `x.yz ms` out of microseconds without touching the FPU. Truncates, so a stall reads
// slightly short rather than slightly long.
#define SC_MS_WHOLE(us)  ((unsigned)((us) / 1000))
#define SC_MS_FRAC(us)   ((unsigned)(((us) % 1000) / 10))

static void TimeEmitWindow(LONGLONG wallUs) {
    const LONGLONG avgUs  = g_winSamples  ? g_winSumUs     / g_winSamples  : 0;
    const LONGLONG hAvgUs = g_winPresents ? g_winHookSumUs / g_winPresents : 0;
    unsigned logLines = 0, logSumUs = 0, logMaxUs = 0;
    ScLogWriteCostTake(&logLines, &logSumUs, &logMaxUs);
    const ULONGLONG cpuNow = CpuNow100ns();
    const ULONGLONG cpu = cpuNow - g_cpuWinStart;
    g_cpuWinStart = cpuNow;
    ScLog("STORMTIME window=%ds presents=%u avg_ms=%u.%02u max_ms=%u.%02u stalls100=%u "
          "hook_avg_us=%u hook_max_us=%u log_lines=%u log_avg_us=%u log_max_us=%u "
          "samples=%u ingame=%d cpu_pct=%u",
          SC_STORMTIME_WINDOW_S, g_winPresents,
          SC_MS_WHOLE(avgUs), SC_MS_FRAC(avgUs),
          SC_MS_WHOLE(g_winMaxUs), SC_MS_FRAC(g_winMaxUs),
          g_winStalls, (unsigned)hAvgUs, (unsigned)g_winHookMaxUs,
          logLines, logLines ? logSumUs / logLines : 0, logMaxUs,
          g_winSamples, g_winIngameKnown ? (int)g_winIngame : -1, CpuPct(cpu, wallUs));
    g_totCpu100ns += cpu;
    g_totWallUs   += wallUs;
    if (logMaxUs > g_totLogMaxUs) g_totLogMaxUs = logMaxUs;
    g_totLogLines += logLines;
    g_totLogSumUs += logSumUs;
    ++g_totWindows;
    g_totPresents += g_winPresents;
    g_totSamples  += g_winSamples;
    g_totStalls   += g_winStalls;
    g_totSumUs    += g_winSumUs;
    if (g_winMaxUs > g_totMaxUs) g_totMaxUs = g_winMaxUs;
    if (g_winHookMaxUs > g_totHookMaxUs) g_totHookMaxUs = g_winHookMaxUs;
    g_winPresents = g_winIngame = g_winSamples = g_winStalls = 0;
    g_winIngameKnown = false;
    g_winSumUs = g_winMaxUs = g_winHookSumUs = g_winHookMaxUs = 0;
}

// tEnter: the hook's entry stamp, which is the present's own arrival time.
// tWork:  taken after the engine's copy returned, so the hook cost is OURS alone.
static void TimeSample(LONGLONG tEnter, LONGLONG tWork) {
    if (!g_qpf || !tEnter) return;
    const LONGLONG now = QpcNow();
    const int inGame = ScConsoleInGame();

    ++g_winPresents;
    if (inGame >= 0) { g_winIngameKnown = true; if (inGame) ++g_winIngame; }
    const LONGLONG hookUs = TicksToUs(now - tWork);
    g_winHookSumUs += hookUs;
    if (hookUs > g_winHookMaxUs) g_winHookMaxUs = hookUs;
    unsigned logLines = 0, logUs = 0;
    ScLogWriteCostSoFar(&logLines, &logUs);

    if (g_tPrev && (inGame < 0 || (inGame == 1 && g_prevInGame == 1))) {
        const LONGLONG dtUs = TicksToUs(tEnter - g_tPrev);
        ++g_winSamples;
        g_winSumUs += dtUs;
        if (dtUs > g_winMaxUs) g_winMaxUs = dtUs;
        if (dtUs > SC_STORMTIME_STALL_US) {
            ++g_winStalls;
            // One line per hitch, charging the interval to the log lines written inside
            // it and to the previous present's mirror; what is left is the engine or
            // the machine.
            if (g_stallLines < SC_STORMTIME_STALL_LINES) {
                ++g_stallLines;
                ScLog("STORMSTALL dt_ms=%u.%02u log_lines=%u log_us=%u hook_us=%u",
                      SC_MS_WHOLE(dtUs), SC_MS_FRAC(dtUs),
                      logLines - g_logLinesAtPrev, logUs - g_logUsAtPrev, (unsigned)g_hookUsPrev);
            }
        }
    }
    g_tPrev = tEnter;
    g_prevInGame = inGame;
    g_logLinesAtPrev = logLines;
    g_logUsAtPrev = logUs;
    g_hookUsPrev = hookUs;

    if (!g_tWinStart) { g_tWinStart = now; g_cpuWinStart = CpuNow100ns(); }
    else if (now - g_tWinStart >= g_qpf * SC_STORMTIME_WINDOW_S) {
        TimeEmitWindow(TicksToUs(now - g_tWinStart));
        g_tWinStart = now;
    }
}

// Bit 0x20 of a layer's flags is the composer's sticky "draw every frame"
// (SC_LAYER_FLAG_ALWAYS_DRAW: survives the 0xF8 mask, wiped only by the table init).
// Set per present, not once: this is where its absence would show, and a count of 1
// means sticky as read, more means something re-initialised the table.
static void ForceAlwaysDraw(int layer, unsigned* forced) {
    BYTE* flags = (BYTE*)ScRuntimeAddr(SC_VA_GRAPHIC_LAYERS + (DWORD)layer * SC_LAYER_STRIDE +
                                       SC_LAYER_OFF_FLAGS);
    if (*flags & SC_LAYER_FLAG_ALWAYS_DRAW) return;
    *flags |= SC_LAYER_FLAG_ALWAYS_DRAW;
    ++*forced;
}

static int __attribute__((stdcall)) SC_GAME_ENTRY
HkOrd432(DWORD dst, DWORD src, DWORD dstPitch, DWORD srcPitch, DWORD region) {
    const LONGLONG tEnter = QpcNow();
    int ret = ((ScOrd432Fn)g_hkCopy.trampoline)(dst, src, dstPitch, srcPitch, region);
    const LONGLONG tWork = QpcNow();
    // Guarded on the widescreen geometry so a stray 640-pitch call can never write past
    // a 640-wide surface.
    const int W = ScScreenTargetWidth(), H = ScScreenTargetHeight();
    if (g_mode == SC_STORM_WIDEN && dst && src &&
        dstPitch >= (DWORD)W && srcPitch >= (DWORD)W) {
        const int stripW = W - SC_SCREEN_W;   // 160 at 800, 640 at 1280
        // The primary's real row count, read once. The mirror never copies past it, so a
        // display-mode change that leaves the primary shorter than the table says cannot
        // overrun it.
        if (g_primaryRows < 0) {
            g_primaryRows = ReadPrimaryRows();
            ScLog("STORM present: primary dwHeight=%d (table H=%d) -- the mirror covers "
                  "min(H, dwHeight) rows%s", g_primaryRows, H,
                  g_primaryRows == 0 ? " (unreadable: assuming H)" : "");
        }
        const int rows = (g_primaryRows > 0 && g_primaryRows < H) ? g_primaryRows : H;
        // THE CURSOR IN THE STRIP (renderer-viewport.md 21.9). The engine's copy is
        // dirty-driven, so at x<640 the primary ACCUMULATES the cursor's last pixels; this
        // strip copy MIRRORS the buffer instead, and the composer (0x0041E280) draws layer 0
        // only when its flags carry 0x01/0x02 or its rect covers a dirty cell -- otherwise
        // save-under has run and the buffer holds cursor-FREE pixels at present time. A
        // parked plain arrow (one-frame GRP, the animation tick bails at 0x004BE209) is
        // redrawn only when something else dirties a cell under it, so the mirror blanks it
        // on every other present: a strobe confined to x>=640. With always-draw set the
        // cursor is composed every frame (save-under before, restore-under after, so the
        // buffer is left cursor-free) and the mirror always carries it; cost at x<640 is
        // nil, since pixels drawn into cells that are not dirty are not presented.
        ForceAlwaysDraw(SC_LAYER_CURSOR, &g_cursorForced);
        if (ScConsoleBufferResident()) {
            // THE TOOLTIP OVER A BUFFER-RESIDENT DIALOG. Layer 1 (the context-help tooltip)
            // is drawn only on its show frame (0x004813D0 sets needs-redraw once) or when a
            // dirty cell lies under it. In stock the dialog composite's DIRECT branch
            // (0x0041C939..) re-paints the tooltip onto the dialog surface itself; the BUFFER
            // branch (0x0041C859.., every converted root) does not, and the frame driver
            // 0x0041CA00 re-composites the tooltip-free dialog surface over the box every
            // frame. The engine's present never showed it (dirty cells only); the whole-frame
            // mirror does, as a tooltip that strobes or vanishes after one present. The
            // draw is a no-op while hidden (0x004810F3 tests SC_VA_TOOLTIP_VISIBLE), so
            // always-draw costs one <=160x92 blit per frame while a tooltip is up.
            if (g_tipFix) ForceAlwaysDraw(SC_LAYER_TOOLTIP, &g_tipForced);
            // The 2x-HEIGHT build (renderer-viewport.md 22): every in-game root composites
            // into the buffer (sc_console.cpp), so the buffer IS the whole picture --
            // console, cursor, mask -- and the engine's own region-clipped copy is a subset
            // of this one, from the same buffer in the same frame. Mirroring after it, this
            // wins. A direct-blitted console (the width-only shape) would be erased by a full
            // mirror, which is why that shape only mirrors the far strip below.
            BYTE* d = (BYTE*)(DWORD_PTR)dst;
            BYTE* s = (BYTE*)(DWORD_PTR)src;
            for (int y = 0; y < rows; ++y) {
                memcpy(d, s, (size_t)W);
                d += dstPitch;
                s += srcPitch;
            }
            ++g_mirrorFrames;
        } else {
            // Width-only: the console direct-blits at x<640, so only the far band mirrors and
            // the console is never painted over.
            BYTE* d = (BYTE*)(DWORD_PTR)dst + SC_SCREEN_W;
            BYTE* s = (BYTE*)(DWORD_PTR)src + SC_SCREEN_W;
            for (int y = 0; y < rows; ++y) {
                memcpy(d, s, (size_t)stripW);
                d += dstPitch;
                s += srcPitch;
            }
        }
        ++g_stripFrames;
    } else if (g_mode == SC_STORM_WIDEN) {
        ++g_stripSkipped;
    }
    TimeSample(tEnter, tWork);
    return ret;
}

// storm ord432 prologue: push ebp; mov ebp,esp; mov eax,[ebp+0x18] (55 8B EC 8B 45 18)
// -- 6 bytes, 3 whole instructions, no PC-relative operand.
static const BYTE kPrologueOrd432[] = { 0x55, 0x8B, 0xEC, 0x8B, 0x45, 0x18 };

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

void ScStormPresentInstall(BYTE* exeBase, bool writeAllowed) {
    ScEngineSetModuleBase(exeBase);
    g_writeAllowed = writeAllowed;
    g_mode = ScStormPresentModeWanted();
    g_logs = 0;
    if (g_mode == SC_STORM_OFF) {
        // Name the half that decided it: a bare "unset/0" cannot distinguish "the
        // launcher exported 0" from "nothing to present", and a wide game running with
        // the copy OFF is diagnosed from this line.
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
        // The strip copies the buffer's x>=640 columns, which only hold
        // playfield when widescreen is active at stage >= 2; otherwise it would carry
        // black/garbage. Disarm to read-only rather than corrupt the screen.
        ScLog("STORM present: widen needs widescreen stage>=2 (an 800-wide playfield "
              "buffer) -- widescreen=%d stage=%d. DISARMED to read-only PROBE.",
              ScScreenWidescreenWanted() ? 1 : 0, ScScreenStageWanted());
        g_mode = SC_STORM_PROBE;
    }
    if (g_mode == SC_STORM_WIDEN) {
        g_stripFrames = 0;
        g_cursorForced = 0;
        g_tipForced = 0;
        g_tipFix = ScEnvFlag("SCPLUGIN_TIPFIX", true);
        g_stripSkipped = 0;
        g_mirrorFrames = 0;
        g_primaryRows = -1;
        LARGE_INTEGER f;
        g_qpf = QueryPerformanceFrequency(&f) ? f.QuadPart : 0;
        g_tPrev = g_tWinStart = 0;
        g_prevInGame = -1;
        g_winPresents = g_winIngame = g_winSamples = g_winStalls = 0;
        g_winIngameKnown = false;
        g_winSumUs = g_winMaxUs = g_winHookSumUs = g_winHookMaxUs = 0;
        g_totPresents = g_totSamples = g_totStalls = g_totWindows = 0;
        g_totSumUs = g_totMaxUs = g_totHookMaxUs = 0;
        g_cpuWinStart = g_totCpu100ns = 0;
        g_totWallUs = 0;
        memset(&g_hkCopy, 0, sizeof(g_hkCopy));
        void* ord432 = StormRt(STORM_RVA_ORD432);
        if (!ScHookInstall(&g_hkCopy, "stormWidenCopy", ord432,
                           (void*)&HkOrd432, (int)sizeof(kPrologueOrd432),
                           kPrologueOrd432, (int)sizeof(kPrologueOrd432))) {
            ScLog("STORM WIDEN: copy hook at storm ord432 (0x%08X) failed to install -- "
                  "falling back to read-only PROBE", (unsigned)(DWORD_PTR)ord432);
            g_mode = SC_STORM_PROBE;
        } else {
            ScLog("STORM present: WIDEN armed. storm base 0x%08X; game-thread hook at storm "
                  "ord432 (0x%08X) copies the x=%d..%d strip from the %d-wide buffer to the "
                  "primary each present, so the buffer->glass present carries all %d columns. "
                  "The read-only geometry log also runs on the marker channel.",
                  (unsigned)(DWORD_PTR)g_stormBase, (unsigned)(DWORD_PTR)ord432,
                  SC_SCREEN_W, ScScreenTargetWidth() - 1, ScScreenTargetWidth(), ScScreenTargetWidth());
            ScLog("STORM present: tooltip layer always-draw %s (%%SCPLUGIN_TIPFIX%%; applies "
                  "while the console is buffer-resident)", g_tipFix ? "ON" : "off");
            // Said out loud at arm time so "no STORMTIME line in the log" is readable as
            // "the game never presented" and never as "the clock was unusable".
            ScLog("STORMTIME: %s -- one line per %d s of presents (qpf=%u Hz). ingame=-1 on a "
                  "line means the console walk could not tell menu from game, so every "
                  "interval was sampled.",
                  g_qpf ? "armed" : "DISABLED: QueryPerformanceFrequency failed",
                  SC_STORMTIME_WINDOW_S, (unsigned)g_qpf);
        }
    }
    if (g_mode == SC_STORM_PROBE) {
        ScLog("STORM present: PROBE (read-only). storm base 0x%08X; logging geometry + "
              "present path + region on the marker channel. Writes nothing to game memory.",
              (unsigned)(DWORD_PTR)g_stormBase);
    }
}

void ScStormPresentRemove(void) {
    // PROBE writes nothing; WIDEN only needs the copy hook un-spliced, because the strip
    // copy wrote presented pixels only, which the next stock present overwrites.
    if (g_hkCopy.installed) ScHookRemove(&g_hkCopy);
}

void ScStormPresentLogStats(void) {
    if (g_mode == SC_STORM_OFF) return;
    // The cumulative half of STORMTIME: the window totals plus whatever the window in
    // flight has collected, so a session shorter than one window still reports numbers.
    const unsigned presents = g_totPresents + g_winPresents;
    const unsigned samples  = g_totSamples + g_winSamples;
    const LONGLONG sumUs    = g_totSumUs + g_winSumUs;
    const LONGLONG avgUs    = samples ? sumUs / samples : 0;
    const LONGLONG maxUs    = g_winMaxUs > g_totMaxUs ? g_winMaxUs : g_totMaxUs;
    const LONGLONG hMaxUs   = g_winHookMaxUs > g_totHookMaxUs ? g_winHookMaxUs : g_totHookMaxUs;
    unsigned logLines = 0, logSumUs = 0, logMaxUs = 0;
    ScLogWriteCostTake(&logLines, &logSumUs, &logMaxUs);
    if (logMaxUs > g_totLogMaxUs) g_totLogMaxUs = logMaxUs;
    g_totLogLines += logLines;
    g_totLogSumUs += logSumUs;
    // The window in flight joins the closed ones; a QPC start of 0 means no present yet.
    const ULONGLONG cpu = g_totCpu100ns + (g_tWinStart ? CpuNow100ns() - g_cpuWinStart : 0);
    const LONGLONG  wallUs = g_totWallUs + (g_tWinStart ? TicksToUs(QpcNow() - g_tWinStart) : 0);
    ScLog("STORMSTATS mode=%d logs=%u stripFrames=%u mirrorFrames=%u stripSkipped=%u cursorForced=%u tipForced=%u primaryRows=%d stormBase=0x%08X "
          "windows=%u presents=%u samples=%u avgMs=%u.%02u maxMs=%u.%02u stalls100=%u hookMaxUs=%u "
          "logLines=%u logAvgUs=%u logMaxUs=%u cpuPct=%u",
          (int)g_mode, g_logs, g_stripFrames, g_mirrorFrames, g_stripSkipped, g_cursorForced, g_tipForced,
          g_primaryRows, (unsigned)(DWORD_PTR)g_stormBase,
          g_totWindows, presents, samples,
          SC_MS_WHOLE(avgUs), SC_MS_FRAC(avgUs), SC_MS_WHOLE(maxUs), SC_MS_FRAC(maxUs),
          g_totStalls + g_winStalls, (unsigned)hMaxUs,
          g_totLogLines, g_totLogLines ? g_totLogSumUs / g_totLogLines : 0, g_totLogMaxUs,
          CpuPct(cpu, wallUs));
}
