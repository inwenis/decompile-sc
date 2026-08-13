// sc_console.cpp -- task 073. See sc_console.h for what the two halves are.
//
// Mechanism notes, each read out of StarCraft.exe 1.16.1 by this task
// (work/scratch/073/decomp + listings; the findings go to renderer-viewport.md):
//
//  * The dialog-layer composite: layer 2's draw (0x0041CB50) builds the dirty
//    rect list (storm region 0x006D5E2C -> count 0x006CF4B4, rects 0x006CF4C0),
//    draws each visible dialog's controls into the DIALOG'S OWN surface
//    (0x0041C080: render target = root+0x36, positions root-relative), then per
//    (dialog, rect) blits that surface to the screen (0x0041C810 -> 0x004EF440
//    -> 0x004172F0) with dest = the rect and src = rect MINUS THE DIALOG'S LIVE
//    BOUNDS (+0x04). Surface pixel (0,0) therefore lands at (bounds.left,
//    bounds.top) EVERY frame a rect covering it is dirty: the composite follows
//    the live bounds, and a moved-but-never-dirtied dialog keeps its stale
//    pixels, which is what 071's NO-GO picture showed.
//
//  * The console art: game\<race>console.pcx is loaded once into the
//    descriptor at 0x00597240 (0x004C3950), and each console dialog's surface
//    is INITIALISED with the art slice under its bounds AT SURFACE-CREATION
//    TIME (0x004C35F0: rect = live bounds, src = the art descriptor, dest = the
//    fresh surface at (0,0)). So a dialog moved AFTER its surface exists takes
//    its art slice with it -- and a dialog moved BEFORE creation would slice
//    the 640-wide art out of range. That ordering is why the move below waits
//    for the surface.
//
//  * updateControl (0x0041C400, EAX = control) marks the control's CURRENT
//    live-bounds rect into the dirty region. Calling it before AND after the
//    bounds write is what repaints both the vacated and the new rect.

#include "sc_console.h"

#include <stdio.h>
#include <string.h>

#include "sc_addresses.h"
#include "sc_hook.h"
#include "sc_log.h"
#include "sc_screen.h"
#include "sc_session.h"

#define SC_GAME_ENTRY __attribute__((force_align_arg_pointer))

// The one widescreen geometry this repo builds is 800x480 (sc_screen stages), so
// the right edge is +160 from the stock 640. If a second width ever exists this
// becomes a read of the patched layer rect, not a second constant.
#define SC_CONSOLE_SHIFT_X 160

#define SC_CONSOLE_MAX_ROOTS   16
#define SC_CONSOLE_TRACE_MAX   2000
#define SC_CONSOLE_NAME_LEN    20

static BYTE* g_base    = NULL;
static bool  g_edge    = false;
static bool  g_trace   = false;
static ScHook g_hkCompose;

static unsigned g_session = 0;

// The interact wrap table: one row per wrapped ROOT dialog.
struct WrapSlot {
    DWORD dlg;
    DWORD orig;
    char  name[SC_CONSOLE_NAME_LEN];
};
static WrapSlot g_wrap[SC_CONSOLE_MAX_ROOTS];
static int      g_wrapN = 0;

// The move table: one row per translated root, holding what to restore.
struct MoveSlot {
    DWORD dlg;
    short l, t, r, b;   // ORIGINAL bounds
};
static MoveSlot g_moved[4];
static int      g_movedN = 0;

static unsigned g_traceLines   = 0;
static unsigned g_traceDropped = 0;
static unsigned g_frames       = 0;
static unsigned g_moves        = 0;
static unsigned g_selects      = 0;
static volatile LONG g_selectReq = 0;   // set by the observer's marker poll

// The dialog dirty-mark clip (sc_addresses.h SC_VA_DLG_DIRTY_CLIP_*): stock
// {0,0,640,480}, no writer in the binary, so one widen is stable. Original max-x
// kept for restore.
static bool  g_clipPatched = false;
static DWORD g_clipOrigX1  = 0;

// The PRESENT sliver (task 073, finding two). The buffer->screen present is a
// storm region clipped against a BASE region (0x006D5E14) that 0x0041D470
// rebuilds from the screen-image list (0x0051A338/0x0051A33C) -- and imgCreate
// (0x0041D640) has exactly ONE caller in the whole binary: the console.pcx
// loader, whose node is (0,0,640,480). So in game NOTHING past x=639 has ever
// been presented through the buffer path (070's own window captures show the
// right band black on glass while its 800-wide dumps held map). One extra node
// covering (640,0)-(800,480), created through the engine's own imgCreate --
// which itself triggers the 0x0041D470 rebuild -- widens the base region for
// the whole game. Engine-owned node; the engine's console teardown frees it
// with the list, so there is nothing to remove.
#pragma pack(push, 1)
struct ScImgDesc { WORD w; WORD h; DWORD bits; };
#pragma pack(pop)
static ScImgDesc g_sliverDesc;
static unsigned  g_sliverSession = 0;
static unsigned  g_slivers       = 0;

static void* Rt(DWORD staticVa) {
    return (void*)(g_base + (staticVa - SC_PREFERRED_IMAGE_BASE));
}

static bool Readable(DWORD addr, DWORD len) {
    if (!addr || len == 0) return false;
    MEMORY_BASIC_INFORMATION mbi;
    if (VirtualQuery((LPCVOID)(DWORD_PTR)addr, &mbi, sizeof(mbi)) != sizeof(mbi)) return false;
    if (mbi.State != MEM_COMMIT) return false;
    if (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD)) return false;
    const DWORD ok = PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY |
                     PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY;
    if ((mbi.Protect & ok) == 0) return false;
    DWORD regionEnd = (DWORD)(DWORD_PTR)mbi.BaseAddress + (DWORD)mbi.RegionSize;
    return addr + len <= regionEnd;
}

// Engine updateControl: EAX = control (sc_addresses.h SC_VA_UPDATE_CONTROL; the
// same asm seam sc_queueind uses, conventions verified by sc_hudrow).
static void CallUpdate(DWORD ctrl) {
    void* fn = Rt(SC_VA_UPDATE_CONTROL);
    DWORD inout = ctrl;
    __asm__ __volatile__("calll *%[fn]"
        : "+a"(inout) : [fn] "r"(fn) : "ecx", "edx", "cc", "memory");
}

// A dialog's name is its pszText. Game data: copied byte-guarded and sanitised.
static void ReadName(DWORD dlg, char* out, size_t outLen) {
    out[0] = '\0';
    if (!Readable(dlg + SC_BINDLG_OFF_TEXT, 4)) return;
    DWORD p = *(DWORD*)(dlg + SC_BINDLG_OFF_TEXT);
    if (!p) return;
    size_t i = 0;
    for (; i + 1 < outLen; ++i) {
        if (!Readable(p + (DWORD)i, 1)) break;
        BYTE c = *(BYTE*)(p + i);
        if (c == 0) break;
        out[i] = (c < 32 || c > 126 || c == '|' || c == '\'') ? '.' : (char)c;
    }
    out[i] = '\0';
}

// ---------------------------------------------------------------------------
// The interact trace
// ---------------------------------------------------------------------------

typedef int (__attribute__((fastcall)) *ScInteractFn)(DWORD, DWORD);

static WrapSlot* FindWrap(DWORD dlg) {
    for (int i = 0; i < g_wrapN; ++i)
        if (g_wrap[i].dlg == dlg) return &g_wrap[i];
    return NULL;
}

static int __attribute__((fastcall)) SC_GAME_ENTRY ConsoleInteractShim(DWORD ctrl, DWORD evt) {
    WrapSlot* w = FindWrap(ctrl);
    if (!w || !w->orig) {
        // A shim call with no table row means the table was reset under a live
        // pointer (session change mid-dispatch). Claim nothing.
        return 0;
    }
    int ret = ((ScInteractFn)w->orig)(ctrl, evt);
    if (evt) {
        const WORD type = *(WORD*)(evt + SC_EVT_OFF_TYPE);
        // The floods that ate the first run's 600-line cap before the game even
        // loaded (TitleDlg every ~100ms): type 13 (a timer tick carrying a raw
        // pointer in dwUser) and the type-14 dwUser=8 sweep. Both dropped;
        // mouse buttons (4..8) and the rest of the USER codes stay.
        const bool flood = (type == 13) ||
                           (type == SC_EVT_TYPE_USER && *(DWORD*)evt == 8);
        if (type != SC_EVT_MOUSEMOVE && !flood) {
            if (g_traceLines < SC_CONSOLE_TRACE_MAX) {
                ++g_traceLines;
                ScLog("CTRACE dlg='%s' 0x%08X type=%u user=%u x=%d y=%d -> ret=%d",
                      w->name, (unsigned)ctrl, (unsigned)type, (unsigned)*(DWORD*)evt,
                      (int)*(short*)(evt + SC_EVT_OFF_X),
                      (int)*(short*)(evt + SC_EVT_OFF_Y), ret);
            } else {
                ++g_traceDropped;
            }
        }
    }
    return ret;
}

static void WrapRoot(DWORD dlg, const char* name) {
    if (FindWrap(dlg)) return;
    if (g_wrapN >= SC_CONSOLE_MAX_ROOTS) return;
    if (!Readable(dlg + SC_BINDLG_OFF_INTERACT, 4)) return;
    DWORD* fn = (DWORD*)(dlg + SC_BINDLG_OFF_INTERACT);
    if (*fn == (DWORD)&ConsoleInteractShim) return;   // stale table row survived; leave it
    WrapSlot* w = &g_wrap[g_wrapN];
    w->dlg  = dlg;
    w->orig = *fn;
    strncpy(w->name, name[0] ? name : "?", sizeof(w->name) - 1);
    w->name[sizeof(w->name) - 1] = '\0';
    ++g_wrapN;
    *fn = (DWORD)&ConsoleInteractShim;
    ScLog("CTRACE wrapped root '%s' 0x%08X orig=0x%08X (dispatch order = dialog-list "
          "order; the first non-zero return claims the event)",
          w->name, (unsigned)dlg, (unsigned)w->orig);
}

static void UnwrapAll(void) {
    for (int i = 0; i < g_wrapN; ++i) {
        DWORD dlg = g_wrap[i].dlg;
        if (!Readable(dlg + SC_BINDLG_OFF_INTERACT, 4)) continue;
        DWORD* fn = (DWORD*)(dlg + SC_BINDLG_OFF_INTERACT);
        if (*fn == (DWORD)&ConsoleInteractShim) *fn = g_wrap[i].orig;
    }
    g_wrapN = 0;
    memset(g_wrap, 0, sizeof(g_wrap));
}

// ---------------------------------------------------------------------------
// The move
// ---------------------------------------------------------------------------

static bool AlreadyMoved(DWORD dlg) {
    for (int i = 0; i < g_movedN; ++i)
        if (g_moved[i].dlg == dlg) return true;
    return false;
}

// Both surface descriptors, logged as evidence: the draw walk installs +0x36
// and the status allocator fills +0x0C (sc_addresses.h explains the pair).
static void LogSurfaces(DWORD dlg, const char* name) {
    for (int k = 0; k < 2; ++k) {
        DWORD d = dlg + (k == 0 ? SC_BINDLG_OFF_SURFACE : SC_BINDLG_OFF_SURFACE_ALT);
        if (!Readable(d, 8)) continue;
        ScLog("CONSOLE surf '%s' +0x%02X: w=%d h=%d bits=0x%08X", name,
              (unsigned)(k == 0 ? SC_BINDLG_OFF_SURFACE : SC_BINDLG_OFF_SURFACE_ALT),
              (int)*(short*)(d + SC_SURFACE_OFF_W),
              (int)*(short*)(d + SC_SURFACE_OFF_H),
              (unsigned)*(DWORD*)(d + SC_SURFACE_OFF_BITS));
    }
}

static void TryMove(DWORD dlg, const char* name) {
    if (AlreadyMoved(dlg) || g_movedN >= (int)(sizeof(g_moved) / sizeof(g_moved[0]))) return;
    if (!Readable(dlg + SC_BINDLG_OFF_BOUNDS, 8)) return;

    // Wait for the surface: moving BEFORE 0x004C35F0 has copied the art slice
    // would make that copy read the 640-wide console.pcx out of range.
    DWORD bits36 = Readable(dlg + SC_BINDLG_OFF_SURFACE + SC_SURFACE_OFF_BITS, 4)
                       ? *(DWORD*)(dlg + SC_BINDLG_OFF_SURFACE + SC_SURFACE_OFF_BITS) : 0;
    DWORD bits0C = Readable(dlg + SC_BINDLG_OFF_SURFACE_ALT + SC_SURFACE_OFF_BITS, 4)
                       ? *(DWORD*)(dlg + SC_BINDLG_OFF_SURFACE_ALT + SC_SURFACE_OFF_BITS) : 0;
    if (!bits36 && !bits0C) return;   // not yet drawn once; try again next frame

    short* bl = (short*)(dlg + SC_BINDLG_OFF_BOUNDS);       // l,t,r,b
    MoveSlot* m = &g_moved[g_movedN];
    m->dlg = dlg; m->l = bl[0]; m->t = bl[1]; m->r = bl[2]; m->b = bl[3];

    LogSurfaces(dlg, name);
    CallUpdate(dlg);                    // the rect being VACATED goes dirty
    bl[0] = (short)(m->l + SC_CONSOLE_SHIFT_X);
    bl[2] = (short)(m->r + SC_CONSOLE_SHIFT_X);
    CallUpdate(dlg);                    // the rect being CLAIMED goes dirty
    ++g_movedN;
    ++g_moves;
    ScLog("CONSOLE moved '%s' 0x%08X (%d,%d)-(%d,%d) -> (%d,%d)-(%d,%d) "
          "flags=0x%08X surf36bits=0x%08X surf0Cbits=0x%08X",
          name, (unsigned)dlg, m->l, m->t, m->r, m->b,
          (int)bl[0], (int)bl[1], (int)bl[2], (int)bl[3],
          (unsigned)*(DWORD*)(dlg + SC_BINDLG_OFF_FLAGS),
          (unsigned)bits36, (unsigned)bits0C);
}

static void UnmoveAll(void) {
    for (int i = 0; i < g_movedN; ++i) {
        DWORD dlg = g_moved[i].dlg;
        if (!Readable(dlg + SC_BINDLG_OFF_BOUNDS, 8)) continue;
        short* bl = (short*)(dlg + SC_BINDLG_OFF_BOUNDS);
        // Restore only if the bounds still read as OUR move; anything else means
        // the record was freed and reused, and writing it would corrupt a stranger.
        if (bl[0] == (short)(g_moved[i].l + SC_CONSOLE_SHIFT_X) &&
            bl[2] == (short)(g_moved[i].r + SC_CONSOLE_SHIFT_X)) {
            CallUpdate(dlg);
            bl[0] = g_moved[i].l;
            bl[2] = g_moved[i].r;
            CallUpdate(dlg);
        }
    }
    g_movedN = 0;
    memset(g_moved, 0, sizeof(g_moved));
}

// ---------------------------------------------------------------------------
// The present sliver (see the struct above for the mechanism)
// ---------------------------------------------------------------------------

// Dump a storm region's rect list through the exe's own Ordinal_529 thunk
// (0x00411E60: stdcall(region, &count, rects); count in = capacity, out =
// rects written -- the exact call layer2Draw makes at 0x0041CC20).
static void LogRegionRects(const char* what, DWORD regionVaOfPtr) {
    DWORD region = Readable((DWORD)(DWORD_PTR)Rt(regionVaOfPtr), 4)
                       ? *(DWORD*)Rt(regionVaOfPtr) : 0;
    if (!region) { ScLog("CONSOLE region %s: handle NULL", what); return; }
    DWORD cnt = 8;
    int rects[8][4];
    memset(rects, 0, sizeof(rects));
    typedef void (__attribute__((stdcall)) *RgnRectsFn)(DWORD, DWORD*, void*);
    ((RgnRectsFn)Rt(0x00411E60u))(region, &cnt, rects);
    char line[320];
    size_t used = 0;
    line[0] = '\0';
    for (DWORD i = 0; i < cnt && i < 8 && used + 48 < sizeof(line); ++i) {
        used += (size_t)_snprintf(line + used, sizeof(line) - used, "%s(%d,%d,%d,%d)",
                                  i ? " " : "", rects[i][0], rects[i][1],
                                  rects[i][2], rects[i][3]);
    }
    ScLog("CONSOLE region %s: handle=0x%08X rects(n=%u, first 8): %s",
          what, (unsigned)region, (unsigned)cnt, line);
}

// imgCreate 0x0041D640: EDI = &{u16 w, u16 h, u8* bits}, stack (x, y), stdcall
// RET 8, returns the node. Convention read off its one caller (0x004C3A03:
// push 0 / push 0 / mov edi,0x597240 / call).
static void AddPresentSliver(void) {
    if (g_sliverSession == g_session) return;
    // The console node must exist first (its loader is what put the list head
    // up), and the buffer must be allocated -- both true once the console
    // dialogs are being drawn, which is when this is called.
    DWORD bits = Readable((DWORD)(DWORD_PTR)Rt(0x006CEFF4u), 4)
                     ? *(DWORD*)Rt(0x006CEFF4u) : 0;
    if (!bits) return;
    LogRegionRects("base 0x6D5E14 BEFORE sliver", 0x006D5E14u);
    g_sliverDesc.w = 160;
    g_sliverDesc.h = 480;
    g_sliverDesc.bits = bits;   // region SHAPE is what matters; content is the buffer
    void* fn = Rt(0x0041D640u);
    ScImgDesc* d = &g_sliverDesc;
    DWORD node = 0;
    __asm__ __volatile__("pushl $0\n\t"
                         "pushl $640\n\t"
                         "calll *%[fn]"
                         : "=a"(node)
                         : "D"(d), [fn] "r"(fn)
                         : "ecx", "edx", "cc", "memory");
    g_sliverSession = g_session;
    ++g_slivers;
    if (node && Readable(node, 0x20)) {
        // The node the engine built from our descriptor, read back field by
        // field (imgCreate stores: +8 storm handle, +0xC x, +0x10 y, +0x14
        // x+w, +0x18 y+h). A NULL handle means Ordinal_445 rejected the
        // descriptor and the region combine has nothing to add.
        ScLog("CONSOLE present sliver: node=0x%08X handle=0x%08X rect=(%d,%d)-(%d,%d)",
              (unsigned)node, (unsigned)*(DWORD*)(node + 8),
              *(int*)(node + 0xC), *(int*)(node + 0x10),
              *(int*)(node + 0x14), *(int*)(node + 0x18));
    } else {
        ScLog("CONSOLE present sliver: imgCreate returned 0x%08X (unreadable)",
              (unsigned)node);
    }
    LogRegionRects("base 0x6D5E14 AFTER sliver", 0x006D5E14u);
}

// ---------------------------------------------------------------------------
// The marker-driven select aid (see the header for why it exists)
// ---------------------------------------------------------------------------

// The engine's client-side selection pair, in the click handler's own order.
// Conventions from sc_addresses.h; the CreateNewUnitSelections asm seam is
// sc_fanout's, verbatim.
static void CallCreateSelections(DWORD* list, int count) {
    void* fn = Rt(SC_VA_CREATE_NEW_UNIT_SELECTIONS);
    __asm__ __volatile__("pushl %[n]\n\t"
                         "calll *%[fn]"
                         : "+a"(list)
                         : [n] "m"(count), [fn] "r"(fn)
                         : "ecx", "edx", "cc", "memory");
}

typedef void (__attribute__((stdcall)) *ScCmdactSelectFn)(DWORD count, DWORD* units);

void ScConsoleOnMarker(const char* label) {
    if (!label || (!g_edge && !g_trace)) return;
    if (strncmp(label, "conedge-select", 14) == 0) InterlockedExchange(&g_selectReq, 1);
}

static void DoRequestedSelect(void) {
    if (!InterlockedCompareExchange(&g_selectReq, 0, 1)) return;
    DWORD player = Readable((DWORD)(DWORD_PTR)Rt(SC_VA_ACTIVE_PLAYER_ID), 4)
                       ? *(DWORD*)Rt(SC_VA_ACTIVE_PLAYER_ID) : 0xFFFFFFFF;
    if (player >= SC_MAX_PLAYERS) {
        ScLog("CONSOLE select: active player %u out of range -- nothing selected", player);
        return;
    }
    DWORD unit = *(DWORD*)((BYTE*)Rt(SC_VA_PLAYER_UNIT_LIST) + player * 4);
    int walked = 0;
    while (unit && walked < SC_MAX_UNITS_WALK) {
        if (!Readable(unit, 0x150)) { unit = 0; break; }
        if (*(DWORD*)(unit + SC_CUNIT_OFF_FLAGS) & SC_UNIT_FLAG_COMPLETED) break;
        unit = *(DWORD*)(unit + SC_CUNIT_OFF_LIST_NEXT);
        ++walked;
    }
    if (!unit) {
        ScLog("CONSOLE select: no completed unit in player %u's list -- nothing selected",
              player);
        return;
    }
    DWORD list[2] = { unit, 0 };
    CallCreateSelections(list, 1);
    ((ScCmdactSelectFn)Rt(SC_VA_CMDACT_SELECT))(1, list);
    // The client half: the funnel pair fills activePlayerSelection and the wire,
    // and the status driver's own updateSelectedUnitData (0x004C38B0) copies it
    // into clientSelectionGroup + portrait -- but only when this flag asks it to
    // (0x004D93F0's first instruction reads it). Measured without it: active=1
    // sim=1, client=0, card empty.
    *(BYTE*)Rt(SC_VA_CLIENT_SEL_CHANGED) = 1;
    ++g_selects;
    ScLog("CONSOLE selected unit=0x%08X type=%d player=%u (engine funnel: 0x0049AE40 "
          "then CMDACT_Select; client_selection_changed set)",
          (unsigned)unit, (int)*(WORD*)(unit + SC_CUNIT_OFF_UNIT_ID), player);
}

// ---------------------------------------------------------------------------
// The per-frame walk (game thread, from the composer detour)
// ---------------------------------------------------------------------------

static void SessionSync(void) {
    const unsigned now = ScSessionEpoch();
    if (g_session == now) return;
    // The dialogs of the previous game are freed heap; forget, never touch.
    g_wrapN  = 0;
    memset(g_wrap, 0, sizeof(g_wrap));
    g_movedN = 0;
    memset(g_moved, 0, sizeof(g_moved));
    g_session = now;
}

static void OnFrame(void) {
    ++g_frames;
    SessionSync();
    DoRequestedSelect();
    if (!Readable((DWORD)(DWORD_PTR)Rt(SC_VA_DIALOG_LIST), 4)) return;
    DWORD dlg = *(DWORD*)Rt(SC_VA_DIALOG_LIST);
    int n = 0;
    while (dlg && n < SC_MAX_DIALOGS_WALK) {
        if (!Readable(dlg, SC_BINDLG_SIZE)) break;
        char name[SC_CONSOLE_NAME_LEN];
        ReadName(dlg, name, sizeof(name));
        if (g_trace) WrapRoot(dlg, name);
        if (g_edge && ScScreenActive() &&
            (strcmp(name, "StatRes") == 0 || strcmp(name, "StatBtn") == 0)) {
            AddPresentSliver();
            TryMove(dlg, name);
        }
        dlg = *(DWORD*)(dlg + SC_BINDLG_OFF_NEXT);
        ++n;
    }
}

// ---------------------------------------------------------------------------
// The composer detour
// ---------------------------------------------------------------------------

typedef void (*ComposeFn)(void);

static void SC_GAME_ENTRY HkFrameCompose(void) {
    // Work first, then the original: bounds writes and dirty marks made here are
    // consumed by the compose that follows in the same call.
    OnFrame();
    if (g_hkCompose.installed) ((ComposeFn)g_hkCompose.trampoline)();
}

// HookProbe against this binary (work/scratch/073/hookprobe.tsv): 0x0041E280
// opens PUSH EBP / MOV EBP,ESP / SUB ESP,0x14 = 6 bytes, 3 whole instructions,
// none PC-relative.
static const BYTE kPrologueCompose[] = { 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x14 };

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

static bool EnvIsOne(const char* var) {
    char buf[16];
    DWORD n = GetEnvironmentVariableA(var, buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return false;
    return buf[0] == '1' || buf[0] == 'y' || buf[0] == 'Y';
}

bool ScConsoleEdgeWanted(void)  { return EnvIsOne("SCPLUGIN_CONSOLE_EDGE"); }
bool ScConsoleTraceWanted(void) { return EnvIsOne("SCPLUGIN_CONSOLE_TRACE"); }

void ScConsoleInstall(BYTE* moduleBase, bool edge, bool trace) {
    g_base  = moduleBase;
    g_edge  = edge;
    g_trace = trace;
    memset(&g_hkCompose, 0, sizeof(g_hkCompose));
    g_wrapN = 0;  memset(g_wrap, 0, sizeof(g_wrap));
    g_movedN = 0; memset(g_moved, 0, sizeof(g_moved));
    g_traceLines = g_traceDropped = g_frames = g_moves = 0;
    g_session = 0;
    if (!edge && !trace) {
        ScLog("CONSOLE: off (%%SCPLUGIN_CONSOLE_EDGE%%/%%SCPLUGIN_CONSOLE_TRACE%%)");
        return;
    }
    if (edge && !ScScreenWidescreenWanted()) {
        ScLog("CONSOLE: %%SCPLUGIN_CONSOLE_EDGE%% is set without %%SCPLUGIN_WIDESCREEN%% -- "
              "there is no right edge to move to at 640; the move is DISARMED "
              "(the trace, if wanted, still runs)");
        g_edge = false;
        if (!trace) return;
    }
    if (!ScHookInstall(&g_hkCompose, "frameCompose", Rt(SC_VA_FRAME_COMPOSE),
                       (void*)&HkFrameCompose, (int)sizeof(kPrologueCompose),
                       kPrologueCompose, (int)sizeof(kPrologueCompose))) {
        ScLog("CONSOLE: frame-compose hook failed to install -- feature disabled");
        g_edge = g_trace = false;
        return;
    }
    if (g_edge) {
        // The dialog dirty-mark clip's max-x (sc_addresses.h): stock 640, no
        // writer in the binary, so this one dword is the whole of why a dialog
        // moved past x=639 never repaints. Refuse the move if it does not read
        // stock -- a different value means a different build or another patch.
        DWORD* x1 = (DWORD*)Rt(SC_VA_DLG_DIRTY_CLIP_X1);
        if (*x1 == 640) {
            g_clipOrigX1 = *x1;
            *x1 = 640 + SC_CONSOLE_SHIFT_X;
            g_clipPatched = true;
            ScLog("CONSOLE: dialog dirty-mark clip max-x 640 -> %u (0x0051A174; the "
                  ".data constant updateControlInner clamps every dialog dirty rect "
                  "against -- stock, it makes a repaint past x=639 unmarkable)",
                  (unsigned)*x1);
        } else {
            ScLog("CONSOLE: dirty-clip max-x at 0x0051A174 reads %u, not the stock 640 "
                  "-- the move is DISARMED (wrong build or a competing patch)",
                  (unsigned)*x1);
            g_edge = false;
        }
    }
    ScLog("CONSOLE: ON edge=%d trace=%d (frame hook at 0x0041E280; StatRes/StatBtn "
          "+%d once their surfaces exist, old+new rects marked dirty)",
          g_edge ? 1 : 0, g_trace ? 1 : 0, SC_CONSOLE_SHIFT_X);
}

void ScConsoleRemove(void) {
    UnmoveAll();
    UnwrapAll();
    if (g_clipPatched) {
        *(DWORD*)Rt(SC_VA_DLG_DIRTY_CLIP_X1) = g_clipOrigX1;
        g_clipPatched = false;
    }
    ScHookRemove(&g_hkCompose);
}

void ScConsoleLogStats(void) {
    if (!g_edge && !g_trace && g_frames == 0) return;
    ScLog("CONSOLESTATS frames=%u moves=%u wrapped=%d traceLines=%u traceDropped=%u "
          "selects=%u slivers=%u",
          g_frames, g_moves, g_wrapN, g_traceLines, g_traceDropped, g_selects,
          g_slivers);
}
