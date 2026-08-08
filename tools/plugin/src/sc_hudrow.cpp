// sc_hudrow.cpp -- see sc_hudrow.h.
//
// PAGE MODEL. The shadow list arrives from sc_fanout ordered overflow-first,
// visible-last. The DISPLAY list reorders it live-visible-first, then live
// overflow -- so page 1 is always the engine's own <=12 units (the conductor's
// rule: the engine's truth is one flip away, and a selection change snaps back to
// it). Dead units are dropped at refresh, so a page never shows a corpse for more
// than one cond tick.
//
// WHAT THE ENGINE SEES. While a page is displayed, the only game state this module
// has written is: the 12 buttons' statUser records (the exact bytes the engine's
// own layout function writes), the buttons' interact POINTERS (control+0x2A, data
// in the dialog heap -- restored on the way back to stock), the dirty/all-hidden
// bytes the engine's own click handlers also write, and one spliced text control
// whose handlers are the engine's own per-type defaults. Sprites are never touched
// -- there is no path from here to CSprite::selectionIndex or flag 0x08.

#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "sc_addresses.h"
#include "sc_fanout.h"
#include "sc_hook.h"
#include "sc_hudrow.h"
#include "sc_log.h"

#define HUD_MAX 256

static BYTE* g_base    = NULL;
static bool  g_enabled = false;

static ScHook g_hkDispatch;

// Test seam -- NULL means "call the real engine".
static ScHudCtlFn       g_show             = NULL;
static ScHudCtlFn       g_hide             = NULL;
static ScHudCtlFn       g_update           = NULL;
static ScHudInteractFn  g_engineInteract   = NULL;
static ScHudDispatchFn  g_testOrigDispatch = NULL;

// Shadow snapshot + liveness baseline (valid for one shadow version).
static ScShadowInfo g_list[HUD_MAX];
static BYTE         g_alive[HUD_MAX];
static int          g_n   = 0;
static int          g_vis = 0;
static unsigned     g_ver = 0;
static bool         g_verValid = false;

// The display list: live visible units first, then live overflow.
static DWORD g_disp[HUD_MAX];
static int   g_dispN     = 0;
static int   g_page      = 0;
static int   g_pageCount = 1;
static bool  g_flipPending = false;

// What the 12 buttons currently show, for the cond drift check.
struct HudSlotCache { DWORD unit; BYTE uniq; DWORD hp; WORD id; };
static HudSlotCache g_cache[SC_HUD_BUTTON_COUNT];
static int          g_cacheN = 0;
static bool         g_cacheValid = false;

// Dialog bookkeeping. All pointers below belong to ONE dialog instance; a new
// dialog (new game -> console re-created) invalidates the lot.
static DWORD g_dialog = 0;
static DWORD g_wrapBtn[SC_HUD_BUTTON_COUNT];
static int   g_wrapCount = 0;
static bool  g_indSpliced = false;
static BYTE  g_indCtrl[SC_BINDLG_SIZE];
static char  g_indText[64];
static bool  g_rectsLogged = false;

static unsigned g_statActs    = 0;   // act runs that displayed a page
static unsigned g_statStock   = 0;   // act runs deferred to the engine
static unsigned g_statFlips   = 0;
static unsigned g_statStale   = 0;   // dead units dropped from the display list
static unsigned g_statWraps   = 0;
static unsigned g_statSplices = 0;

static void* Rt(DWORD staticVa) {
    return (void*)(g_base + (staticVa - SC_PREFERRED_IMAGE_BASE));
}

// ---------------------------------------------------------------------------
// Engine primitives, through the seam
// ---------------------------------------------------------------------------

// 0x004186A0 / 0x00418700 take the control in ESI (GPTP unit_stat_selection.cpp
// helpers; our decompile of 0x00425960 shows the same register use). VC6
// callee-saved rules preserve EBX/ESI/EDI across the call.
static void CallShow(DWORD ctrl) {
    if (g_show) { g_show(ctrl); return; }
    void* fn = Rt(SC_VA_SHOW_CONTROL);
    __asm__ __volatile__("calll *%[fn]"
        : : "S"(ctrl), [fn] "r"(fn) : "eax", "ecx", "edx", "cc", "memory");
}

static void CallHide(DWORD ctrl) {
    if (g_hide) { g_hide(ctrl); return; }
    void* fn = Rt(SC_VA_HIDE_CONTROL);
    __asm__ __volatile__("calll *%[fn]"
        : : "S"(ctrl), [fn] "r"(fn) : "eax", "ecx", "edx", "cc", "memory");
}

// 0x0041C400 takes the control in EAX.
static void CallUpdate(DWORD ctrl) {
    if (g_update) { g_update(ctrl); return; }
    void* fn = Rt(SC_VA_UPDATE_CONTROL);
    DWORD inout = ctrl;
    __asm__ __volatile__("calll *%[fn]"
        : "+a"(inout) : [fn] "r"(fn) : "ecx", "edx", "cc", "memory");
}

typedef int (__attribute__((fastcall)) *EngineInteractFn)(DWORD, DWORD);
static int CallEngineInteract(DWORD ctrl, DWORD evt) {
    EngineInteractFn fn = g_engineInteract
        ? (EngineInteractFn)g_engineInteract
        : (EngineInteractFn)Rt(SC_VA_WIREFRAME_BTN_INTERACT);
    return fn(ctrl, evt);
}

// The original dispatcher, through the trampoline. No arguments, returns void.
typedef void (*OrigDispatchFn)(void);

static void CallOrigDispatch(void) {
    if (g_testOrigDispatch) { g_testOrigDispatch(); return; }
    if (g_hkDispatch.installed) ((OrigDispatchFn)g_hkDispatch.trampoline)();
}

static DWORD StatDialog(void)   { return *(DWORD*)Rt(SC_VA_STATDATA_DIALOG); }
static DWORD PortraitUnit(void) { return *(DWORD*)Rt(SC_VA_ACTIVE_PORTRAIT_UNIT); }

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

static bool Readable(DWORD addr, DWORD len) {
    if (!addr || len == 0) return false;
    MEMORY_BASIC_INFORMATION mbi;
    if (VirtualQuery((LPCVOID)addr, &mbi, sizeof(mbi)) != sizeof(mbi)) return false;
    if (mbi.State != MEM_COMMIT) return false;
    if (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD)) return false;
    const DWORD ok = PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY |
                     PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY;
    if ((mbi.Protect & ok) == 0) return false;
    DWORD regionEnd = (DWORD)mbi.BaseAddress + (DWORD)mbi.RegionSize;
    return addr + len <= regionEnd;
}

// The unit array is a fixed global; a captured pointer was bounds/stride-checked
// by sc_fanout, so reading its uniqueness byte is safe (same as StillAlive there).
static bool UnitAlive(const ScShadowInfo* u) {
    if (!u->unit) return false;
    return *(BYTE*)(u->unit + SC_CUNIT_OFF_UNIQUENESS) == u->uniqueness;
}

static WORD UnitTag(DWORD unit) {
    if (!unit) return 0;
    DWORD base = (DWORD)Rt(SC_VA_UNIT_ARRAY_BASE);
    if (unit < base) return 0;
    DWORD off = unit - base;
    if (off % SC_CUNIT_SIZE != 0) return 0;
    DWORD index = off / SC_CUNIT_SIZE + 1;
    if (index > SC_MAX_UNIT_INDEX) return 0;
    return (WORD)(((WORD)*(BYTE*)(unit + SC_CUNIT_OFF_UNIQUENESS) << 11) | (WORD)index);
}

static DWORD ChildOf(DWORD dlg)  { return *(DWORD*)(dlg + SC_BINDLG_OFF_FIRST_CHILD); }
static DWORD NextOf(DWORD ctrl)  { return *(DWORD*)(ctrl + SC_BINDLG_OFF_NEXT); }
static short IndexOf(DWORD ctrl) { return *(short*)(ctrl + SC_BINDLG_OFF_INDEX); }

// Normalize the dispatcher's argument to the root dialog, the way the engine's
// own layout function does (control -> parent).
static DWORD RootOf(DWORD dialog) {
    if (*(WORD*)(dialog + SC_BINDLG_OFF_TYPE) != 0) {
        return *(DWORD*)(dialog + SC_BINDLG_OFF_PARENT);
    }
    return dialog;
}

static DWORD FindChildById(DWORD root, short id) {
    for (DWORD c = ChildOf(root); c; c = NextOf(c)) {
        if (IndexOf(c) == id) return c;
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Shadow refresh + display list
// ---------------------------------------------------------------------------

// Returns true when the display list holds more than 12 live units. Sets
// *selChanged when the shadow version moved, *death when a unit displayed under
// the SAME version died since the last refresh -- both snap back to page 1.
static bool RefreshShadow(bool* selChanged, bool* death) {
    unsigned ver = 0;
    int vis = 0;
    int n = ScFanoutCopyShadow(g_list, HUD_MAX, &vis, &ver);

    bool changed = (!g_verValid || ver != g_ver);
    bool died    = false;

    BYTE aliveNow[HUD_MAX];
    for (int i = 0; i < n; ++i) {
        aliveNow[i] = UnitAlive(&g_list[i]) ? 1 : 0;
        // Same version => same list contents in the same order, so a per-index
        // liveness comparison is exact.
        if (!changed && g_alive[i] && !aliveNow[i]) died = true;
    }
    memcpy(g_alive, aliveNow, (size_t)n);
    g_n   = n;
    g_vis = vis <= n ? vis : n;
    g_ver = ver;
    g_verValid = true;

    if (changed || died) {
        g_page = 0;
        g_cacheValid = false;
    }

    // Display list: live visible units (the tail of the shadow list) first, so
    // page 1 is the engine's own selection; then live overflow (the head).
    const int overflowN = g_n - g_vis;
    g_dispN = 0;
    for (int i = overflowN; i < g_n; ++i) {
        if (g_alive[i]) g_disp[g_dispN++] = g_list[i].unit; else ++g_statStale;
    }
    for (int i = 0; i < overflowN; ++i) {
        if (g_alive[i]) g_disp[g_dispN++] = g_list[i].unit; else ++g_statStale;
    }
    g_pageCount = g_dispN > 0 ? (g_dispN + SC_HUD_BUTTON_COUNT - 1) / SC_HUD_BUTTON_COUNT : 1;
    if (g_page >= g_pageCount) g_page = 0;

    if (selChanged) *selChanged = changed;
    if (death)      *death      = died;
    return g_dispN > SC_HUD_BUTTON_COUNT;
}

// ---------------------------------------------------------------------------
// The button shim
// ---------------------------------------------------------------------------

#define SC_GAME_ENTRY __attribute__((force_align_arg_pointer))

int ScHudRowOnButtonEvent(DWORD ctrl, DWORD evt) {
    // The dialog framework delivers the RAW mouse event to the control under the
    // cursor with its type intact -- 0x00418EB0 groups cases 4/6/7/9 and tail-calls
    // control+0x2A (hud-selection-row.md 5.1). So a right-click arrives here as
    // event->type == 7, and the stock button interact ignores it, which is what
    // makes the gesture free to claim.
    if (g_enabled && evt && g_pageCount > 1) {
        WORD type = *(WORD*)(evt + SC_EVT_OFF_TYPE);
        if (type == SC_EVT_RBUTTONDOWN) {
            g_page = (g_page + 1) % g_pageCount;
            g_flipPending = true;
            *(BYTE*)Rt(SC_VA_STAT_DIRTY) = 1;
            ++g_statFlips;
            ScLog("HUDROW flip -> page %d/%d", g_page + 1, g_pageCount);
            return 1;
        }
    }
    return CallEngineInteract(ctrl, evt);
}

static int __attribute__((fastcall)) SC_GAME_ENTRY
HudBtnInteractShim(DWORD ctrl, DWORD evt) {
    return ScHudRowOnButtonEvent(ctrl, evt);
}

// (Re)wrap the 12 buttons' interact pointers. Idempotent; called from every
// paged act run, which is what survives the engine re-binding them at dialog
// CREATE (the binder writes the table value back; the next act run re-wraps).
static void EnsureWrapped(DWORD firstBtn) {
    const DWORD engineFn = (DWORD)Rt(SC_VA_WIREFRAME_BTN_INTERACT);
    const DWORD shim     = (DWORD)&HudBtnInteractShim;
    g_wrapCount = 0;
    DWORD c = firstBtn;
    for (int i = 0; i < SC_HUD_BUTTON_COUNT && c; ++i, c = NextOf(c)) {
        DWORD* interact = (DWORD*)(c + SC_BINDLG_OFF_INTERACT);
        if (*interact == engineFn) { *interact = shim; ++g_statWraps; }
        // Record every button that now points at the shim, whether this run
        // wrapped it or an earlier one did -- the restore path walks this list.
        if (*interact == shim && g_wrapCount < SC_HUD_BUTTON_COUNT) {
            g_wrapBtn[g_wrapCount++] = c;
        }
    }
}

static void Unwrap(void) {
    const DWORD engineFn = (DWORD)Rt(SC_VA_WIREFRAME_BTN_INTERACT);
    const DWORD shim     = (DWORD)&HudBtnInteractShim;
    for (int i = 0; i < g_wrapCount; ++i) {
        DWORD* interact = (DWORD*)(g_wrapBtn[i] + SC_BINDLG_OFF_INTERACT);
        if (*interact == shim) *interact = engineFn;
    }
    g_wrapCount = 0;
}

// ---------------------------------------------------------------------------
// The indicator control
// ---------------------------------------------------------------------------

// Spliced at the HEAD of the child list: the CREATE-time handler binder skips it
// (index <= 0), the hide-all sweeps hide it like any child, and drawing last in
// our act keeps its text on top of the button strip it overlays. It overlays the
// TOP EDGE of the first buttons on purpose: those rects repaint whenever the
// buttons redraw, so leaving paged mode cannot strand indicator pixels on the
// dialog surface.
static void EnsureIndicator(DWORD root, DWORD firstBtn) {
    DWORD ind = (DWORD)&g_indCtrl[0];
    if (!g_indSpliced) {
        memset(g_indCtrl, 0, sizeof(g_indCtrl));
        short* b   = (short*)(firstBtn + SC_BINDLG_OFF_BOUNDS);
        short* ib  = (short*)(ind + SC_BINDLG_OFF_BOUNDS);
        ib[0] = (short)(b[0] + 2);        // left
        ib[1] = (short)(b[1] + 1);        // top
        ib[2] = (short)(b[0] + 150);      // right
        ib[3] = (short)(b[1] + 10);       // bottom
        *(DWORD*)(ind + SC_BINDLG_OFF_FLAGS)    = SC_CTRL_FLAG_VISIBLE | 0x400; // smallest font
        *(short*)(ind + SC_BINDLG_OFF_INDEX)    = (short)0xFFE0;   // negative: binder-proof
        *(WORD*) (ind + SC_BINDLG_OFF_TYPE)     = 9;               // LSTATIC
        *(DWORD*)(ind + SC_BINDLG_OFF_TEXT)     = (DWORD)g_indText;
        *(DWORD*)(ind + SC_BINDLG_OFF_PARENT)   = root;
        *(DWORD*)(ind + SC_BINDLG_OFF_INTERACT) =
            *(DWORD*)((DWORD)Rt(SC_VA_DEFAULT_INTERACT_TABLE) + 9 * 4);
        *(DWORD*)(ind + SC_BINDLG_OFF_UPDATE)   =
            *(DWORD*)((DWORD)Rt(SC_VA_DEFAULT_UPDATE_TABLE) + 9 * 4);
        *(DWORD*)(ind + SC_BINDLG_OFF_NEXT)     = ChildOf(root);
        *(DWORD*)(root + SC_BINDLG_OFF_FIRST_CHILD) = ind;
        g_indSpliced = true;
        ++g_statSplices;
    }
    const int start = g_page * SC_HUD_BUTTON_COUNT;
    _snprintf(g_indText, sizeof(g_indText) - 1, "%d units  %d-%d  (%d/%d)",
              g_dispN, start + 1, start + g_cacheN, g_page + 1, g_pageCount);
    g_indText[sizeof(g_indText) - 1] = '\0';
    CallShow(ind);
    *(DWORD*)(ind + SC_BINDLG_OFF_FLAGS) |= SC_CTRL_FLAG_DRAWN;
    CallUpdate(ind);
}

static void UnspliceIndicator(DWORD root) {
    if (!g_indSpliced) return;
    DWORD ind = (DWORD)&g_indCtrl[0];
    CallHide(ind);
    DWORD* link = (DWORD*)(root + SC_BINDLG_OFF_FIRST_CHILD);
    while (*link && *link != ind) link = (DWORD*)(*link + SC_BINDLG_OFF_NEXT);
    if (*link == ind) *link = NextOf(ind);
    g_indSpliced = false;
}

// ---------------------------------------------------------------------------
// The two detour cores
// ---------------------------------------------------------------------------

// The read-back oracle: what the LIVE DIALOG's buttons now hold, read out of the
// controls after the fill, not echoed from our own inputs.
static void LogReadback(DWORD firstBtn) {
    char buf[3 * 64];
    int used = 0;
    int shown = 0;
    DWORD c = firstBtn;
    buf[0] = '\0';
    for (int i = 0; i < SC_HUD_BUTTON_COUNT && c; ++i, c = NextOf(c)) {
        if (!(*(DWORD*)(c + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE)) continue;
        DWORD su = *(DWORD*)(c + SC_BINDLG_OFF_USER);
        if (!su) continue;
        WORD tag = UnitTag(*(DWORD*)(su + SC_STATUSER_OFF_UNIT));
        int room = (int)sizeof(buf) - used;
        if (room < 8) break;
        used += _snprintf(buf + used, (size_t)room, "%s%04X", shown ? " " : "", tag);
        ++shown;
    }
    ScLog("HUDROW show n=%d page=%d/%d slots=%d [%s] indicator=\"%s\"",
          g_dispN, g_page + 1, g_pageCount, shown, buf, g_indText);
}

// Where the buttons are, so an automated test can aim a right-click at one --
// same rationale as sc_circles' LogCirclePositions. Raw control bounds plus the
// root's own rect, logged once per dialog instance; the reader decides the
// coordinate space from both.
static void LogButtonRects(DWORD root, DWORD firstBtn) {
    if (g_rectsLogged) return;
    char buf[512];
    int used = 0;
    short* rb = (short*)(root + SC_BINDLG_OFF_BOUNDS);
    used += _snprintf(buf + used, sizeof(buf) - (size_t)used, "root=[%d,%d,%d,%d]",
                      rb[0], rb[1], rb[2], rb[3]);
    DWORD c = firstBtn;
    for (int i = 0; i < SC_HUD_BUTTON_COUNT && c; ++i, c = NextOf(c)) {
        short* b = (short*)(c + SC_BINDLG_OFF_BOUNDS);
        int room = (int)sizeof(buf) - used;
        if (room < 32) break;
        used += _snprintf(buf + used, (size_t)room, " b%d=[%d,%d,%d,%d]",
                          i + 1, b[0], b[1], b[2], b[3]);
    }
    ScLog("HUDROW rects %s", buf);
    g_rectsLogged = true;
}

static void FillPage(DWORD root, DWORD firstBtn) {
    // The engine's own hidden-sweep, replicated (0x00425960 lines 11-20 of the
    // decompile): hide everything once, then show what this run displays.
    BYTE* allHidden = (BYTE*)Rt(SC_VA_STAT_ALL_HIDDEN);
    if (*allHidden != 1) {
        for (DWORD c = ChildOf(root); c; c = NextOf(c)) CallHide(c);
        *allHidden = 1;
    }

    const int start = g_page * SC_HUD_BUTTON_COUNT;
    g_cacheN = 0;
    DWORD c = firstBtn;
    for (int i = 0; i < SC_HUD_BUTTON_COUNT && c; ++i, c = NextOf(c)) {
        const int idx = start + i;
        DWORD su = *(DWORD*)(c + SC_BINDLG_OFF_USER);
        if (idx < g_dispN && su) {
            DWORD unit = g_disp[idx];
            WORD  id   = *(WORD*)(unit + SC_CUNIT_OFF_UNIT_ID);
            *(DWORD*)(su + SC_STATUSER_OFF_UNIT) = unit;
            *(WORD*) (su + SC_STATUSER_OFF_ID)   = id;
            CallShow(c);
            *(DWORD*)(c + SC_BINDLG_OFF_FLAGS) |= SC_CTRL_FLAG_DRAWN;
            // Unconditional, unlike the engine's first-show-only update: a page
            // flip changes a button's content without changing its visibility,
            // and the wireframe repaints only when the control is updated.
            CallUpdate(c);
            HudSlotCache* s = &g_cache[g_cacheN++];
            s->unit = unit;
            s->uniq = *(BYTE*)(unit + SC_CUNIT_OFF_UNIQUENESS);
            s->hp   = *(DWORD*)(unit + SC_CUNIT_OFF_HITPOINTS);
            s->id   = id;
        } else {
            CallHide(c);
        }
    }

    EnsureIndicator(root, firstBtn);
    g_cacheValid  = true;
    g_flipPending = false;
    ++g_statActs;
    LogReadback(firstBtn);
}

// Leave paged mode: restore the stock pointers, remove the indicator, force-repaint
// the buttons so any pixels our indicator left on the dialog surface are painted
// over, then hand the frame to the engine's own dispatcher (which lays out the
// single-portrait or <=12 multi view normally).
static void RestoreStock(DWORD root) {
    Unwrap();
    if (root) UnspliceIndicator(root);
    g_cacheValid = false;
    DWORD c = root ? FindChildById(root, SC_HUD_FIRST_SMALL_BUTTON) : 0;
    for (int i = 0; i < SC_HUD_BUTTON_COUNT && c; ++i, c = NextOf(c)) {
        if (*(DWORD*)(c + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE) CallUpdate(c);
    }
    ScLog("HUDROW stock restored (n=%d)", g_dispN);
    CallOrigDispatch();
}

// True when a displayed unit's uniqueness / HP / type drifted since the last fill
// -- the same comparison the engine's own cond makes, over our page.
static bool PageDrifted(void) {
    for (int i = 0; i < g_cacheN; ++i) {
        const HudSlotCache* s = &g_cache[i];
        if (*(BYTE*)(s->unit + SC_CUNIT_OFF_UNIQUENESS) != s->uniq) return true;
        if (*(DWORD*)(s->unit + SC_CUNIT_OFF_HITPOINTS) != s->hp)   return true;
        if (*(WORD*) (s->unit + SC_CUNIT_OFF_UNIT_ID)   != s->id)   return true;
    }
    return false;
}

// The per-frame decision. Called by the dispatcher detour.
void ScHudRowOnDispatch(void) {
    if (!g_enabled) { CallOrigDispatch(); return; }

    bool selChanged = false, death = false;
    bool overflow = RefreshShadow(&selChanged, &death);

    DWORD dlg  = StatDialog();
    DWORD root = dlg ? RootOf(dlg) : 0;
    if (root && root != g_dialog) {
        // A new dialog instance: every cached control pointer belongs to the old
        // one. Forget them -- never touch them again.
        g_dialog      = root;
        g_wrapCount   = 0;
        g_indSpliced  = false;
        g_page        = 0;
        g_cacheValid  = false;
        g_rectsLogged = false;
    }

    DWORD firstBtn = root ? FindChildById(root, SC_HUD_FIRST_SMALL_BUTTON) : 0;

    // Page only when there is real overflow AND a dialog with a row AND a portrait
    // unit (the engine's own precondition for showing the status area at all).
    if (!overflow || !root || !firstBtn || !PortraitUnit()) {
        if (g_wrapCount > 0 || g_indSpliced) RestoreStock(root);   // hands back inside
        else CallOrigDispatch();
        ++g_statStock;
        return;
    }

    EnsureWrapped(firstBtn);
    LogButtonRects(root, firstBtn);

    // Throttle the re-fill exactly as the engine throttles its own layout: only
    // when something the page depends on changed. On a quiet frame the page just
    // persists -- nothing else writes the status buttons once we skip the engine's
    // dispatcher.
    if (selChanged || death || g_flipPending || !g_cacheValid || PageDrifted()) {
        FillPage(root, firstBtn);
    }
    // Consume the redraw-needed flag the way the engine's dispatcher does at its
    // tail, since we are standing in for it this frame.
    *(BYTE*)Rt(SC_VA_STAT_DIRTY) = 0;
}

// ---------------------------------------------------------------------------
// Detour entry point
// ---------------------------------------------------------------------------

// The engine calls the dispatcher with no arguments and ignores the return; a
// plain void function matches (EBX/ESI/EDI preserved by GCC, EAX/ECX/EDX scratch
// under VC6's rules).
static void SC_GAME_ENTRY HkStatDispatch(void) {
    ScHudRowOnDispatch();
}

// Verified prologue -- ScHookInstall refuses to patch if memory disagrees. Bytes
// and window from HookProbe against this binary
// (work/scratch/hud/hookprobe/statDataUpdate.FUN_00458120.asm):
//   0x00458120  A1 48 72 59 00   MOV EAX,[0x00597248]   = 5 bytes / 1 instruction,
// absolute (not PC-relative), so it relocates into the trampoline unchanged.
static const BYTE kPrologueDispatch[] = { 0xA1, 0x48, 0x72, 0x59, 0x00 };

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

void ScHudRowInit(BYTE* moduleBase, bool enabled) {
    g_base    = moduleBase;
    g_enabled = enabled;
    g_show = g_hide = g_update = NULL;
    g_engineInteract = NULL;
    g_testOrigDispatch = NULL;
    g_verValid = false;
    g_n = g_vis = g_dispN = 0;
    g_page = 0;
    g_pageCount = 1;
    g_flipPending = false;
    g_cacheValid = false;
    g_cacheN = 0;
    g_dialog = 0;
    g_wrapCount = 0;
    g_indSpliced = false;
    g_indText[0] = '\0';
    g_rectsLogged = false;
}

bool ScHudRowEnabled(void) { return g_enabled; }

int ScHudRowInstallHooks(void) {
    if (!g_enabled) return 0;

    if (ScHookInstall(&g_hkDispatch, "statDataUpdate",
                      Rt(SC_VA_STAT_DATA_UPDATE),
                      (void*)&HkStatDispatch, 5,
                      kPrologueDispatch, (int)sizeof(kPrologueDispatch))) {
        return 1;
    }
    ScLog("HUDROW: dispatcher hook failed to install -- feature disabled");
    g_enabled = false;
    return 0;
}

void ScHudRowRemoveHooks(void) {
    ScHookRemove(&g_hkDispatch);

    // Best-effort pointer restores. Single atomic dword writes; guarded reads
    // because the dialog may be gone. Mid-game unload stays unsupported (the
    // game thread may be inside the shim), same policy as sc_circles.
    if (g_wrapCount > 0) {
        const DWORD engineFn = (DWORD)Rt(SC_VA_WIREFRAME_BTN_INTERACT);
        const DWORD shim     = (DWORD)&HudBtnInteractShim;
        for (int i = 0; i < g_wrapCount; ++i) {
            DWORD p = g_wrapBtn[i] + SC_BINDLG_OFF_INTERACT;
            if (Readable(p, 4) && *(DWORD*)p == shim) *(DWORD*)p = engineFn;
        }
        g_wrapCount = 0;
    }
    if (g_indSpliced && g_dialog &&
        Readable(g_dialog + SC_BINDLG_OFF_FIRST_CHILD, 4)) {
        DWORD ind = (DWORD)&g_indCtrl[0];
        DWORD* link = (DWORD*)(g_dialog + SC_BINDLG_OFF_FIRST_CHILD);
        while (*link && *link != ind) {
            if (!Readable(*link + SC_BINDLG_OFF_NEXT, 4)) { link = NULL; break; }
            link = (DWORD*)(*link + SC_BINDLG_OFF_NEXT);
        }
        if (link && *link == ind) *link = NextOf(ind);
        g_indSpliced = false;
    }
}

void ScHudRowLogStats(void) {
    if (!g_enabled) return;
    ScLog("HUDROW stats: acts=%u stock=%u flips=%u staleDropped=%u wraps=%u splices=%u",
          g_statActs, g_statStock, g_statFlips, g_statStale, g_statWraps, g_statSplices);
}

// ---------------------------------------------------------------------------
// Test seam
// ---------------------------------------------------------------------------

void ScHudRowTestBegin(BYTE* fakeModuleBase,
                       ScHudCtlFn show, ScHudCtlFn hide, ScHudCtlFn update,
                       ScHudInteractFn engineInteract,
                       ScHudDispatchFn origDispatch) {
    ScHudRowInit(fakeModuleBase, fakeModuleBase != NULL);
    g_show             = show;
    g_hide             = hide;
    g_update           = update;
    g_engineInteract   = engineInteract;
    g_testOrigDispatch = origDispatch;
    g_statActs = g_statStock = g_statFlips = 0;
    g_statStale = g_statWraps = g_statSplices = 0;
}

int ScHudRowCurrentPage(void) { return g_page; }
int ScHudRowPageCount(void)   { return g_pageCount; }
