// sc_queueind.cpp -- see sc_queueind.h.
//
// WHAT THE ENGINE SEES. While the indicator is up, the only game state this module has
// written is: one BinDlg record it owns outright (a static buffer in this DLL) linked into
// the statdata dialog's child list, that record's own fields, and the redraw-invalidate
// 0x0041C400 the engine's own layout function calls for every control it shows. It writes
// no unit, no resource global, no engine-owned control, and it never touches a sprite --
// there is no path from here to CSprite::selectionIndex or flag 0x08.
//
// WHY A CONTROL AND NOT A BLIT. The engine already has a routine that draws a string into
// this pane, picks the font, sets the colour and clips to a box
// (research/status-pane-text.md). A control of type SC_CTRL_TYPE_LSTATIC with pszText
// pointing at our buffer reaches it through the engine's own dispatch, which means the
// text looks native because it IS native, and no art is added (hard rule 1).

#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "sc_addresses.h"
#include "sc_hook.h"
#include "sc_hudrow.h"
#include "sc_log.h"
#include "sc_prodqueue.h"
#include "sc_upgrades.h"
#include "sc_queueind.h"

#define SC_GAME_ENTRY __attribute__((force_align_arg_pointer))

// The indicator's own control id. NEGATIVE on purpose: the CREATE-time handler binder
// 0x00418100 only rewrites +0x2A for controls with index > 0, so a negative id is
// binder-proof (the same trick sc_hudrow's indicator uses, with a different value so the
// two are distinguishable in a child walk).
#define SC_QIND_CTRL_ID ((short)0xFFE1)

static BYTE* g_base    = NULL;
static bool  g_enabled = false;

static ScHook g_hkDriver;

// Test seam -- NULL means "call the real engine".
static ScQIndCtlFn    g_show          = NULL;
static ScQIndCtlFn    g_hide          = NULL;
static ScQIndCtlFn    g_update        = NULL;
static ScQIndDriverFn g_testOrigDriver = NULL;
static bool           g_testing       = false;

// Dialog bookkeeping. Every pointer below belongs to ONE dialog instance; a new dialog
// (new game -> console re-created) invalidates the lot.
static DWORD g_dialog   = 0;
static bool  g_spliced  = false;
static BYTE  g_ctrl[SC_BINDLG_SIZE];
static char  g_text[48];
static bool  g_shown    = false;
static int   g_mode     = SC_QIND_NONE;
static DWORD g_anchor   = 0;          // the control the box is positioned against
static bool  g_dialogLogged = false;

static unsigned g_stat[SC_QIND_STAT__COUNT];

// WHAT THE STRIP HELD when the GAME THREAD last left it, snapshotted at the end of the
// frame path. It exists because the observer thread cannot answer this question honestly:
// the engine's own layout re-greys the slots the plugin fills, and it runs INSIDE the same
// driver call, a few microseconds before FillOverflowIcons puts them back. Nothing is drawn
// in between -- the dialog is rendered later, by graphic layer 2 -- so the player never sees
// the intermediate state, but an asynchronous reader lands in it often enough to make a
// suite flaky (measured: the same assertion passed one run and failed the next). A snapshot
// taken by the thread that does the writing is coherent by construction.
struct QIconSnap { short icon; WORD mode; DWORD flags; };
static QIconSnap g_icons[SC_STATQ_SLOTS];
static int       g_iconsN = 0;

static void* Rt(DWORD staticVa) {
    return (void*)(g_base + (staticVa - SC_PREFERRED_IMAGE_BASE));
}

// ---------------------------------------------------------------------------
// Engine primitives, through the seam (same conventions sc_hudrow verified)
// ---------------------------------------------------------------------------

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

static void CallUpdate(DWORD ctrl) {
    if (g_update) { g_update(ctrl); return; }
    void* fn = Rt(SC_VA_UPDATE_CONTROL);
    DWORD inout = ctrl;
    __asm__ __volatile__("calll *%[fn]"
        : "+a"(inout) : [fn] "r"(fn) : "ecx", "edx", "cc", "memory");
}

typedef void (*OrigDriverFn)(void);

static void CallOrigDriver(void) {
    if (g_testOrigDriver) { g_testOrigDriver(); return; }
    if (g_hkDriver.installed) ((OrigDriverFn)g_hkDriver.trampoline)();
}

static DWORD StatDialog(void)   { return *(DWORD*)Rt(SC_VA_STATDATA_DIALOG); }
static DWORD PortraitUnit(void) { return *(DWORD*)Rt(SC_VA_ACTIVE_PORTRAIT_UNIT); }
static int   SelectionCount(void) { return (int)*(BYTE*)Rt(SC_VA_CLIENT_SELECTION_COUNT); }

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

static DWORD ChildOf(DWORD dlg)  { return *(DWORD*)(dlg + SC_BINDLG_OFF_FIRST_CHILD); }
static DWORD NextOf(DWORD ctrl)  { return *(DWORD*)(ctrl + SC_BINDLG_OFF_NEXT); }
static short IndexOf(DWORD ctrl) { return *(short*)(ctrl + SC_BINDLG_OFF_INDEX); }

static DWORD RootOf(DWORD dialog) {
    if (*(WORD*)(dialog + SC_BINDLG_OFF_TYPE) != 0) {
        return *(DWORD*)(dialog + SC_BINDLG_OFF_PARENT);
    }
    return dialog;
}

// Every child walk in this file is BOUNDED. ScQueueIndLogState runs on the OBSERVER
// thread against a list the game thread owns, so a torn `next` has to end the walk rather
// than spin it -- the same rule sc_card.cpp's walk follows.
static DWORD FindChildById(DWORD root, short id) {
    DWORD c = ChildOf(root);
    for (int guard = 0; c && guard < SC_MAX_CTRLS_WALK; ++guard, c = NextOf(c)) {
        if (IndexOf(c) == id) return c;
    }
    return 0;
}

// Is this a CUnit pointer, by the unit array's own bounds and stride? Same test the other
// modules make; a pointer that fails it is never dereferenced.
static bool UnitValid(DWORD unit) {
    if (!unit) return false;
    DWORD base = (DWORD)Rt(SC_VA_UNIT_ARRAY_BASE);
    if (unit < base) return false;
    DWORD off = unit - base;
    if (off % SC_CUNIT_SIZE != 0) return false;
    return (off / SC_CUNIT_SIZE) < SC_MAX_UNIT_INDEX;
}

// How many of the engine's five ring slots this building is holding. The plugin's
// overflow is NOT counted here -- that is the whole point of the two numbers.
static int EngineQueueLength(DWORD unit) {
    int n = 0;
    for (int i = 0; i < SC_BUILD_QUEUE_SLOTS; ++i) {
        WORD t = *(WORD*)(unit + SC_CUNIT_OFF_BUILD_QUEUE + (DWORD)i * 2);
        if (t != SC_BUILD_QUEUE_EMPTY) ++n;
    }
    return n;
}

static int OverflowOf(DWORD unit) {
    int n = ScProdQueueOverflowCount(unit);   // -1 when the building is not tracked
    return n > 0 ? n : 0;
}

// ---------------------------------------------------------------------------
// The composer -- pure, so hooktest drives exactly this
// ---------------------------------------------------------------------------

// How many of the strip's five icons this building's LOGICAL queue can fill: the engine's
// own ring items first, then the plugin's overflow, capped at the five the strip has.
int ScQueueIndDrawableSlots(const ScQueueIndView* v) {
    if (!v) return 0;
    int n = v->engineLen + v->overflow;
    return n > SC_STATQ_SLOTS ? SC_STATQ_SLOTS : n;
}

int ScQueueIndCompose(char* out, int outLen, const ScQueueIndView* v) {
    if (!out || outLen <= 0) return SC_QIND_NONE;
    out[0] = '\0';
    if (!v) return SC_QIND_NONE;

    // sc_hudrow's own indicator owns this corner of the pane while the row is paging
    // (it is drawn from the paged act, over the same buttons this module would anchor
    // to). One indicator at a time, and the row's is the one that matches what the row
    // is doing.
    if (v->hudPages > 1) return SC_QIND_NONE;

    if (v->selection <= 1) {
        // Queued UPGRADES have no icons at all -- they are not in the building's ring --
        // so for them the whole logical queue is invisible, not just its tail. One line,
        // and it takes precedence because a building researching is not also training.
        if (v->upgrades > 0) {
            _snprintf(out, (size_t)outLen - 1, "+%d upg", v->upgrades);
            out[outLen - 1] = '\0';
            return SC_QIND_UPGRADE;
        }
        // The strip has five icons. The plugin fills the ones past the engine's ring from
        // its own overflow (FillOverflowIcons), so what is left UNDRAWN is whatever the
        // logical queue holds past those five.
        const int hidden = v->engineLen + v->overflow - SC_STATQ_SLOTS;
        if (hidden <= 0) return SC_QIND_NONE;
        _snprintf(out, (size_t)outLen - 1, "+%d", hidden);
        out[outLen - 1] = '\0';
        return SC_QIND_STRIP;
    }

    // Several buildings: the strip is not drawn at all (the engine takes its multi-select
    // branch and shows the wireframe row), so a "+N" would have nothing to sit beside.
    // What the player needs to see here is that one click reached more than one building.
    if (v->buildings < 2 || v->queued <= 0) return SC_QIND_NONE;
    _snprintf(out, (size_t)outLen - 1, "%d bldgs  %d queued", v->buildings, v->queued);
    out[outLen - 1] = '\0';
    return SC_QIND_GROUP;
}

// ---------------------------------------------------------------------------
// The view, read out of game memory
// ---------------------------------------------------------------------------

static void ReadView(ScQueueIndView* v) {
    memset(v, 0, sizeof(*v));
    v->selection = SelectionCount();
    v->hudPages  = ScHudRowPageCount();

    if (v->selection <= 1) {
        DWORD unit = PortraitUnit();
        if (!UnitValid(unit)) return;
        v->engineLen = EngineQueueLength(unit);
        v->overflow  = OverflowOf(unit);
        int upg = ScUpgQueueCount(unit);          // -1 when the building is not tracked
        v->upgrades = upg > 0 ? upg : 0;
        return;
    }

    // The engine's own client selection is the truth about what the player has selected
    // (0x00597208, walked to the sentinel). Buildings past the engine's twelve cannot be
    // shown by the row either, so counting the engine's list is counting what the pane is
    // about.
    DWORD* slot = (DWORD*)Rt(SC_VA_CLIENT_SELECTION_GROUP);
    for (int i = 0; i < SC_HUD_BUTTON_COUNT; ++i) {
        DWORD unit = slot[i];
        if (!UnitValid(unit)) continue;
        int len = EngineQueueLength(unit) + OverflowOf(unit);
        if (len > 0) { ++v->buildings; v->queued += len; }
    }
}

// ---------------------------------------------------------------------------
// The spliced control
// ---------------------------------------------------------------------------

static bool InChain(DWORD root) {
    DWORD ind = (DWORD)&g_ctrl[0];
    DWORD c = ChildOf(root);
    for (int guard = 0; c && guard < SC_MAX_CTRLS_WALK; ++guard, c = NextOf(c)) {
        if (c == ind) return true;
    }
    return false;
}

// Spliced at the HEAD of the child list: the CREATE-time binder skips it (index <= 0), the
// engine's hide-all sweeps hide it like any child, and being drawn from our own frame tail
// keeps its text on top of whatever it overlays.
static bool EnsureSpliced(DWORD root) {
    DWORD ind = (DWORD)&g_ctrl[0];
    if (g_spliced && !InChain(root)) g_spliced = false;   // same-address dialog realloc
    if (g_spliced) return true;

    // Runtime evidence guard, same shape as sc_hudrow's: the engine must have a real
    // interact AND update handler for this control type in its own default tables. If
    // either is null, this build does not dispatch the type the way the table dump says,
    // so refuse to splice rather than hand the dialog a control it cannot draw.
    DWORD tInteract = *(DWORD*)((DWORD)Rt(SC_VA_DEFAULT_INTERACT_TABLE) +
                                SC_CTRL_TYPE_LSTATIC * 4);
    DWORD tUpdate   = *(DWORD*)((DWORD)Rt(SC_VA_DEFAULT_UPDATE_TABLE) +
                                SC_CTRL_TYPE_LSTATIC * 4);
    if (!tInteract || !tUpdate) {
        ScLog("QIND: no engine handler for control type %d (interact=0x%08X update=0x%08X)"
              " -- indicator suppressed", SC_CTRL_TYPE_LSTATIC,
              (unsigned)tInteract, (unsigned)tUpdate);
        ++g_stat[SC_QIND_STAT_REFUSED];
        return false;
    }

    memset(g_ctrl, 0, sizeof(g_ctrl));
    *(DWORD*)(ind + SC_BINDLG_OFF_FLAGS)    = SC_CTRL_FONT_SMALLEST;
    *(short*)(ind + SC_BINDLG_OFF_INDEX)    = SC_QIND_CTRL_ID;
    *(WORD*) (ind + SC_BINDLG_OFF_TYPE)     = (WORD)SC_CTRL_TYPE_LSTATIC;
    *(DWORD*)(ind + SC_BINDLG_OFF_TEXT)     = (DWORD)g_text;
    *(DWORD*)(ind + SC_BINDLG_OFF_PARENT)   = root;
    *(DWORD*)(ind + SC_BINDLG_OFF_INTERACT) = tInteract;
    *(DWORD*)(ind + SC_BINDLG_OFF_UPDATE)   = tUpdate;
    *(DWORD*)(ind + SC_BINDLG_OFF_NEXT)     = ChildOf(root);
    *(DWORD*)(root + SC_BINDLG_OFF_FIRST_CHILD) = ind;
    g_spliced = true;
    ++g_stat[SC_QIND_STAT_SPLICES];
    return true;
}

static void Unsplice(DWORD root) {
    if (!g_spliced) return;
    DWORD ind = (DWORD)&g_ctrl[0];
    if (root) {
        CallHide(ind);
        DWORD* link = (DWORD*)(root + SC_BINDLG_OFF_FIRST_CHILD);
        for (int guard = 0; *link && *link != ind && guard < SC_MAX_CTRLS_WALK; ++guard) {
            link = (DWORD*)(*link + SC_BINDLG_OFF_NEXT);
        }
        if (*link == ind) *link = NextOf(ind);
    }
    g_spliced = false;
    g_shown   = false;
}

// Put the box on the anchor control, in the anchor's own coordinate space (control bounds
// are parent-relative -- updateControl 0x0041C400 adds the parent's origin itself). The
// bounds come from the LIVE control every time the anchor changes, never from a constant.
static void PlaceOn(DWORD anchor) {
    DWORD ind = (DWORD)&g_ctrl[0];
    short* a = (short*)(anchor + SC_BINDLG_OFF_BOUNDS);
    short* b = (short*)(ind + SC_BINDLG_OFF_BOUNDS);
    short left = (short)(a[0] + SC_QIND_INSET_X);
    short top  = (short)(a[1] + SC_QIND_INSET_Y);
    b[0] = left;
    b[1] = top;
    // Never grow past the anchor's own right/bottom edge: the anchor is a control the
    // engine repaints, and staying inside it is what guarantees our pixels are painted
    // over when the indicator goes away.
    b[2] = (short)(left + SC_QIND_BOX_W > a[2] ? a[2] : left + SC_QIND_BOX_W);
    b[3] = (short)(top + SC_QIND_BOX_H > a[3] ? a[3] : top + SC_QIND_BOX_H);
    g_anchor = anchor;
}

// Which control the indicator hangs off, per mode:
//   STRIP -- the LAST queue icon (id 6). While the plugin holds overflow it keeps the
//            engine's ring at four, so that icon is precisely the one drawn empty.
//   GROUP -- the first wireframe button (id 0x21), the left end of the row that IS the
//            multi-select display.
static DWORD AnchorFor(DWORD root, int mode) {
    if (mode == SC_QIND_STRIP) return FindChildById(root, SC_STATQ_LAST_CONTROL);
    if (mode == SC_QIND_GROUP) return FindChildById(root, SC_HUD_FIRST_SMALL_BUTTON);
    return 0;
}

// ---------------------------------------------------------------------------
// The fifth icon (and the fourth, and any other the plugin is holding)
// ---------------------------------------------------------------------------

// The user, playing the deployed build: "when i queue more then 5 units the 5'th slot is
// emtpy". It is: task 025 keeps the engine's ring at SC_PRODQ_ENGINE_HOLD = 4 so the client
// keeps sending Train commands (research/production-queue.md 5.2), so the engine's own
// layout queueLayout (0x004268D0) has only four items to draw and greys the fifth. The
// FEATURE is right and the ring must stay at four; the DISPLAY is what is wrong.
//
// So: after the engine has laid the strip out, fill the icons it left empty from the
// plugin's own overflow, writing the same three statUser fields queueLayout writes for an
// occupied slot (research/production-queue.md 8.1):
//     statUser->icon = type;  statUser->mode = 3;  statUser->type = type;
// and clearing the DISABLED bit so the icon draws lit like any other queued item.
//
// Clearing DISABLED also makes it CLICKABLE, and that is deliberate and paid for on the
// other side: a click on icon k emits {0x20, k}, and sc_prodqueue's cancel handler now
// consumes any display index at or above the ring's own length and cancels its OWN item
// instead of letting cancelBuildQueueSlot refund an empty ring slot.
//
// Only writes when something actually differs, so a settled strip costs five compares.
static void FillOverflowIcons(DWORD root, const ScQueueIndView* v, DWORD unit) {
    const int drawable = ScQueueIndDrawableSlots(v);
    DWORD c = FindChildById(root, SC_STATQ_FIRST_CONTROL);
    for (int k = 0; k < SC_STATQ_SLOTS && c; ++k, c = NextOf(c)) {
        if (k < v->engineLen) continue;              // the engine's own item: leave it
        if (k >= drawable) continue;                 // nothing to put here
        int type = ScProdQueueOverflowAt(unit, k - v->engineLen);
        if (type < 0) continue;
        DWORD su = *(DWORD*)(c + SC_BINDLG_OFF_USER);
        if (!su) continue;
        DWORD* flags = (DWORD*)(c + SC_BINDLG_OFF_FLAGS);
        const bool sameIcon = *(short*)(su + SC_STATUSER_OFF_ICON) == (short)type &&
                              *(WORD*) (su + SC_STATUSER_OFF_MODE) == 3 &&
                              *(short*)(su + SC_STATUSER_OFF_TYPE) == (short)type;
        const bool lit = (*flags & SC_CTRL_FLAG_DISABLED) == 0;
        if (sameIcon && lit && (*flags & SC_CTRL_FLAG_VISIBLE)) continue;
        *(short*)(su + SC_STATUSER_OFF_ICON) = (short)type;
        *(WORD*) (su + SC_STATUSER_OFF_MODE) = 3;
        *(short*)(su + SC_STATUSER_OFF_TYPE) = (short)type;
        *flags &= ~(DWORD)SC_CTRL_FLAG_DISABLED;
        CallShow(c);
        *flags |= SC_CTRL_FLAG_DRAWN;
        CallUpdate(c);
        ++g_stat[SC_QIND_STAT_ICONS];
    }

    // The snapshot, taken after the fill, by the thread that did it.
    g_iconsN = 0;
    DWORD sc = FindChildById(root, SC_STATQ_FIRST_CONTROL);
    for (int k = 0; k < SC_STATQ_SLOTS && sc; ++k, sc = NextOf(sc)) {
        DWORD su = *(DWORD*)(sc + SC_BINDLG_OFF_USER);
        QIconSnap* q = &g_icons[g_iconsN++];
        q->flags = *(DWORD*)(sc + SC_BINDLG_OFF_FLAGS);
        q->icon  = su ? *(short*)(su + SC_STATUSER_OFF_ICON) : -1;
        q->mode  = su ? *(WORD*) (su + SC_STATUSER_OFF_MODE) : 0;
    }
}

// ---------------------------------------------------------------------------
// The ink probe (see the header: corroboration, never the content oracle)
// ---------------------------------------------------------------------------

// Resolve the dialog's surface descriptor: the offset the DRAW WALK installs first, the
// allocator's arithmetic second (sc_addresses.h explains why there are two candidates).
// Returns the descriptor address, or 0 when neither reads as a plausible surface.
static DWORD SurfaceOf(DWORD root) {
    const DWORD cand[2] = { root + SC_BINDLG_OFF_SURFACE, root + SC_BINDLG_OFF_SURFACE_ALT };
    for (int i = 0; i < 2; ++i) {
        DWORD d = cand[i];
        if (!Readable(d, 8)) continue;
        int w = (int)*(WORD*)(d + SC_SURFACE_OFF_W);
        int h = (int)*(WORD*)(d + SC_SURFACE_OFF_H);
        DWORD bits = *(DWORD*)(d + SC_SURFACE_OFF_BITS);
        if (w <= 0 || h <= 0 || w > 640 || h > 480 || !bits) continue;
        if (!Readable(bits, (DWORD)(w * h))) continue;
        return d;
    }
    return 0;
}

int ScQueueIndSurfaceInk(DWORD root, int left, int top, int right, int bottom) {
    DWORD d = root ? SurfaceOf(root) : 0;
    if (!d) return -1;
    int w = (int)*(WORD*)(d + SC_SURFACE_OFF_W);
    int h = (int)*(WORD*)(d + SC_SURFACE_OFF_H);
    DWORD bits = *(DWORD*)(d + SC_SURFACE_OFF_BITS);
    if (left < 0) left = 0;
    if (top < 0) top = 0;
    if (right > w) right = w;
    if (bottom > h) bottom = h;
    if (right <= left || bottom <= top) return 0;
    int ink = 0;
    for (int y = top; y < bottom; ++y) {
        const BYTE* row = (const BYTE*)(bits + (DWORD)(y * w));
        for (int x = left; x < right; ++x) if (row[x]) ++ink;
    }
    return ink;
}

// ---------------------------------------------------------------------------
// Read-back oracles
// ---------------------------------------------------------------------------

// Everything here is re-read from the live dialog. In particular `text` is read through
// the CONTROL's own pszText pointer, not printed from g_text: if the splice were wrong,
// or the pointer stale, this line would say so instead of echoing our intent.
// NOTE ON THREADS. This is called from the observer thread's marker channel, so it must
// only READ, and every read here is a single field of dialog or record memory: a torn one
// mis-reports one log line and cannot corrupt anything. The two plugin counts it quotes
// (ScProdQueueOverflowCount / ScUpgQueueCount) are lock-free scans of small fixed arrays
// for the same reason. The frame path -- the half that WRITES -- runs on the game thread
// only, inside the detour.
void ScQueueIndLogState(const char* tag) {
    const char* t = tag ? tag : "-";
    DWORD dlg  = g_base ? StatDialog() : 0;
    DWORD root = dlg ? RootOf(dlg) : 0;
    if (!root) { ScLog("QIND [%s] dialog=0 (no status pane in this process state)", t); return; }

    DWORD ind = (DWORD)&g_ctrl[0];
    bool  linked = InChain(root);
    DWORD flags  = linked ? *(DWORD*)(ind + SC_BINDLG_OFF_FLAGS) : 0;
    short* b     = (short*)(ind + SC_BINDLG_OFF_BOUNDS);
    const char* live = "";
    if (linked) {
        DWORD p = *(DWORD*)(ind + SC_BINDLG_OFF_TEXT);
        if (Readable(p, 1)) live = (const char*)p;
    }

    ScQueueIndView v;
    ReadView(&v);

    int ink = linked ? ScQueueIndSurfaceInk(root, b[0], b[1], b[2], b[3]) : -1;

    // THE POSITIVE CONTROL for that number. `ink=0` has two readings -- "we drew nothing"
    // and "the probe cannot see this surface" -- and only one of them is a bug, so the same
    // probe is run over a rect the ENGINE fills: the first queue icon (id 2), which draws a
    // unit portrait whenever anything is queued. A run where refInk is 0 as well says the
    // probe is blind and its verdict on the indicator means nothing (AGENTS.md: prove the
    // pattern positive somewhere it should match, before trusting it where it should not).
    int refInk = -1;
    {
        DWORD ref = FindChildById(root, SC_STATQ_FIRST_CONTROL);
        if (ref) {
            short* rb2 = (short*)(ref + SC_BINDLG_OFF_BOUNDS);
            refInk = ScQueueIndSurfaceInk(root, rb2[0], rb2[1], rb2[2], rb2[3]);
        }
    }

    // The strip as the game thread last left it (see g_icons): `icon:mode:state` per slot.
    char icons[96];
    int used = 0;
    icons[0] = ' ';
    for (int i = 0; i < g_iconsN && used + 16 < (int)sizeof(icons); ++i) {
        used += _snprintf(icons + used, sizeof(icons) - (size_t)used, "%s0x%03X:%u:%s",
                          i ? "," : "", (unsigned)(WORD)g_icons[i].icon,
                          (unsigned)g_icons[i].mode,
                          (g_icons[i].flags & SC_CTRL_FLAG_DISABLED) ? "grey" :
                          ((g_icons[i].flags & SC_CTRL_FLAG_VISIBLE) ? "lit" : "hidden"));
    }

    ScLog("QIND [%s] mode=%d linked=%d visible=%d text=\"%s\" bounds=(%d,%d,%d,%d) ink=%d "
          "refInk=%d icons=[%s] "
          "sel=%d engineLen=%d overflow=%d upg=%d bldgs=%d queued=%d hudPages=%d "
          "anchor=0x%08X",
          t, g_mode, linked ? 1 : 0,
          (flags & SC_CTRL_FLAG_VISIBLE) ? 1 : 0, live,
          linked ? b[0] : 0, linked ? b[1] : 0, linked ? b[2] : 0, linked ? b[3] : 0, ink,
          refInk, icons,
          v.selection, v.engineLen, v.overflow, v.upgrades, v.buildings, v.queued,
          v.hudPages, (unsigned)g_anchor);
}

// One line per child of the statdata dialog. This is the answer to "which controls in this
// pane are engine-drawn text, and where are the free pixels" read off the LIVE dialog on
// THIS install, which is what hud-selection-row.md 10 listed as an open question.
void ScQueueIndLogDialog(const char* tag) {
    const char* t = tag ? tag : "-";
    DWORD dlg  = g_base ? StatDialog() : 0;
    DWORD root = dlg ? RootOf(dlg) : 0;
    if (!root) { ScLog("QINDDLG [%s] dialog=0", t); return; }

    short* rb = (short*)(root + SC_BINDLG_OFF_BOUNDS);
    DWORD  d  = SurfaceOf(root);
    ScLog("QINDDLG [%s] root=0x%08X rect=(%d,%d,%d,%d) surfaceAt=+0x%02X %dx%d bits=0x%08X",
          t, (unsigned)root, rb[0], rb[1], rb[2], rb[3],
          d ? (unsigned)(d - root) : 0u,
          d ? (int)*(WORD*)(d + SC_SURFACE_OFF_W) : 0,
          d ? (int)*(WORD*)(d + SC_SURFACE_OFF_H) : 0,
          d ? (unsigned)*(DWORD*)(d + SC_SURFACE_OFF_BITS) : 0u);

    int n = 0;
    for (DWORD c = ChildOf(root); c && n < SC_MAX_CTRLS_WALK; c = NextOf(c), ++n) {
        short* b = (short*)(c + SC_BINDLG_OFF_BOUNDS);
        DWORD  f = *(DWORD*)(c + SC_BINDLG_OFF_FLAGS);
        DWORD  p = *(DWORD*)(c + SC_BINDLG_OFF_TEXT);
        const char* s = (p && Readable(p, 1)) ? (const char*)p : "";
        ScLog("QINDDLG [%s] id=%d type=%u flags=0x%08X vis=%d rect=(%d,%d,%d,%d) "
              "update=0x%08X text=\"%.24s\"",
              t, (int)IndexOf(c), (unsigned)*(WORD*)(c + SC_BINDLG_OFF_TYPE),
              (unsigned)f, (f & SC_CTRL_FLAG_VISIBLE) ? 1 : 0,
              b[0], b[1], b[2], b[3],
              (unsigned)*(DWORD*)(c + SC_BINDLG_OFF_UPDATE), s);
    }
    ScLog("QINDDLG [%s] children=%d", t, n);
}

// ---------------------------------------------------------------------------
// The per-frame body
// ---------------------------------------------------------------------------

// Repaint whatever the indicator was covering. The anchor is an engine-owned control, so
// asking the engine to update it is exactly how its own pixels come back -- which is why
// the box is kept inside the anchor's bounds in the first place.
static void RepaintAnchor(void) {
    if (!g_anchor) return;
    if (*(DWORD*)(g_anchor + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE) CallUpdate(g_anchor);
}

void ScQueueIndOnFrame(void) {
    if (!g_enabled) return;
    ++g_stat[SC_QIND_STAT_FRAMES];

    DWORD dlg  = StatDialog();
    DWORD root = dlg ? RootOf(dlg) : 0;
    if (root != g_dialog) {
        // A new dialog instance: every cached pointer belongs to the old one. Forget them
        // rather than dereference them.
        g_dialog       = root;
        g_spliced      = false;
        g_shown        = false;
        g_anchor       = 0;
        g_mode         = SC_QIND_NONE;
        g_text[0]      = '\0';
        g_dialogLogged = false;
    }
    if (!root) return;

    ScQueueIndView v;
    ReadView(&v);

    // The fifth icon comes first and is independent of the text: a queue of exactly five
    // has nothing to say in words and still has an icon the engine did not draw.
    if (v.selection <= 1 && v.overflow > 0 && v.hudPages <= 1) {
        DWORD unit = PortraitUnit();
        if (UnitValid(unit)) FillOverflowIcons(root, &v, unit);
    }

    char want[sizeof(g_text)];
    int mode = ScQueueIndCompose(want, (int)sizeof(want), &v);

    // The portrait unit is the engine's own precondition for the pane holding anything at
    // all; without it the dispatcher hides every child and there is nothing to sit beside.
    if (mode != SC_QIND_NONE && !PortraitUnit()) mode = SC_QIND_NONE;

    DWORD anchor = mode != SC_QIND_NONE ? AnchorFor(root, mode) : 0;
    if (mode != SC_QIND_NONE && !anchor) mode = SC_QIND_NONE;

    if (mode == SC_QIND_NONE) {
        if (g_shown) {
            CallHide((DWORD)&g_ctrl[0]);
            g_shown = false;
            RepaintAnchor();
            ++g_stat[SC_QIND_STAT_HIDES];
            ScLog("QIND hide (nothing to show: sel=%d overflow=%d bldgs=%d hudPages=%d)",
                  v.selection, v.overflow, v.buildings, v.hudPages);
        }
        g_mode = SC_QIND_NONE;
        return;
    }

    if (!EnsureSpliced(root)) return;
    if (!g_dialogLogged) { ScQueueIndLogDialog("attach"); g_dialogLogged = true; }

    const bool moved   = (anchor != g_anchor);
    const bool changed = (strcmp(want, g_text) != 0);
    if (moved) PlaceOn(anchor);
    if (changed) {
        memcpy(g_text, want, sizeof(g_text) < sizeof(want) ? sizeof(g_text) : sizeof(want));
        g_text[sizeof(g_text) - 1] = '\0';
    }
    g_mode = mode;

    // Redraw when the text or the position changed, and re-show whenever the engine's own
    // hide-all sweep has taken the visible bit off us (which it does on every re-layout).
    DWORD ind = (DWORD)&g_ctrl[0];
    const bool visible = (*(DWORD*)(ind + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE) != 0;
    if (changed || moved || !visible || !g_shown) {
        CallShow(ind);
        *(DWORD*)(ind + SC_BINDLG_OFF_FLAGS) |= SC_CTRL_FLAG_DRAWN;
        CallUpdate(ind);
        g_shown = true;
        ++g_stat[SC_QIND_STAT_SHOWS];
        if (changed || moved) ScQueueIndLogState("show");
    }
}

// ---------------------------------------------------------------------------
// Detour entry point
// ---------------------------------------------------------------------------

// The driver takes no arguments and its result is ignored. Running the original FIRST is
// the whole design: the status pane has to be laid out (and its hide-all sweep done)
// before the indicator decides what to say and re-shows itself.
static void SC_GAME_ENTRY HkStatDisplayDriver(void) {
    CallOrigDriver();
    ScQueueIndOnFrame();
}

// Verified prologue -- ScHookInstall refuses to patch if memory disagrees. Bytes and window
// from HookProbe against this binary
// (work/scratch/033/hookprobe/statDisplayDriver.FUN_004d93f0.asm):
//   0x004D93F0  A0 3C 72 59 00   MOV AL,[0x0059723C]   = 5 bytes / 1 instruction, absolute
//   (not PC-relative), so it relocates into the trampoline unchanged.
static const BYTE kPrologueDriver[] = { 0xA0, 0x3C, 0x72, 0x59, 0x00 };

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

bool ScQueueIndEnabled(void) {
    char buf[16];
    DWORD n = GetEnvironmentVariableA("SCPLUGIN_QUEUEIND", buf, sizeof(buf));
    if (n == 0 || n >= sizeof(buf)) return false;
    return buf[0] != '0';
}

void ScQueueIndInit(BYTE* moduleBase, bool enabled) {
    g_base    = moduleBase;
    g_enabled = enabled;
    g_show = g_hide = g_update = NULL;
    g_testOrigDriver = NULL;
    g_testing  = false;
    g_dialog   = 0;
    g_spliced  = false;
    g_shown    = false;
    g_mode     = SC_QIND_NONE;
    g_anchor   = 0;
    g_text[0]  = '\0';
    g_dialogLogged = false;
    g_iconsN = 0;
    memset(g_ctrl, 0, sizeof(g_ctrl));
    ScLog("QIND: %s (%%SCPLUGIN_QUEUEIND%%). Draws a \"+N\" over the last queue icon when "
          "the logical queue is longer than the strip can show, and a \"N bldgs M queued\" "
          "line for a group; engine-drawn text, no new art.",
          enabled ? "ON" : "off");
}

int ScQueueIndInstallHooks(void) {
    if (!g_enabled) return 0;
    if (ScHookInstall(&g_hkDriver, "statDisplayDriver", Rt(SC_VA_STAT_DISPLAY_DRIVER),
                      (void*)&HkStatDisplayDriver, 5,
                      kPrologueDriver, (int)sizeof(kPrologueDriver))) {
        return 1;
    }
    ScLog("QIND: driver hook failed to install -- feature disabled");
    g_enabled = false;
    return 0;
}

void ScQueueIndRemoveHooks(void) {
    ScHookRemove(&g_hkDriver);

    // Take the control back out of the dialog. Single dword writes, guarded reads because
    // the dialog may already be gone. Mid-game unload stays unsupported (the game thread
    // may be inside the detour), same policy as sc_circles and sc_hudrow.
    if (g_spliced && g_dialog && Readable(g_dialog + SC_BINDLG_OFF_FIRST_CHILD, 4)) {
        DWORD ind = (DWORD)&g_ctrl[0];
        DWORD* link = (DWORD*)(g_dialog + SC_BINDLG_OFF_FIRST_CHILD);
        while (*link && *link != ind) {
            if (!Readable(*link + SC_BINDLG_OFF_NEXT, 4)) { link = NULL; break; }
            link = (DWORD*)(*link + SC_BINDLG_OFF_NEXT);
        }
        if (link && *link == ind) *link = NextOf(ind);
    }
    g_spliced = false;
    g_shown   = false;
}

void ScQueueIndLogStats(void) {
    if (!g_enabled) return;
    ScLog("QINDSTATS frames=%u shows=%u hides=%u splices=%u refused=%u iconsFilled=%u",
          g_stat[SC_QIND_STAT_FRAMES], g_stat[SC_QIND_STAT_SHOWS],
          g_stat[SC_QIND_STAT_HIDES], g_stat[SC_QIND_STAT_SPLICES],
          g_stat[SC_QIND_STAT_REFUSED], g_stat[SC_QIND_STAT_ICONS]);
}

// ---------------------------------------------------------------------------
// Test seam
// ---------------------------------------------------------------------------

void ScQueueIndTestBegin(BYTE* fakeModuleBase,
                         ScQIndCtlFn show, ScQIndCtlFn hide, ScQIndCtlFn update,
                         ScQIndDriverFn origDriver) {
    ScQueueIndInit(fakeModuleBase, fakeModuleBase != NULL);
    g_show           = show;
    g_hide           = hide;
    g_update         = update;
    g_testOrigDriver = origDriver;
    g_testing        = true;
    g_dialogLogged   = true;         // the fake tree's dump is not the evidence
    for (int i = 0; i < SC_QIND_STAT__COUNT; ++i) g_stat[i] = 0;
}

int         ScQueueIndCurrentMode(void) { return g_mode; }
const char* ScQueueIndCurrentText(void) { return g_text; }
bool        ScQueueIndIsSpliced(void)   { return g_spliced; }
bool        ScQueueIndIsShown(void)     { return g_shown; }
int         ScQueueIndStat(int which) {
    if (which < 0 || which >= SC_QIND_STAT__COUNT) return 0;
    return (int)g_stat[which];
}
