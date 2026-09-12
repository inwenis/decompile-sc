// sc_queueind.cpp -- see sc_queueind.h.
//
// WHAT THE ENGINE SEES. While the indicator is up, the only game state this module has
// written is one BinDlg record it owns outright (a static buffer in this DLL) linked into
// the statdata dialog's child list, that record's own fields, and the redraw-invalidate
// 0x0041C400 the engine calls for every control it shows, plus the queue icons' wrapped
// handler pointers. No unit, no resource global, no sprite: there is no path from here to
// CSprite::selectionIndex or flag 0x08.
//
// WHY A CONTROL AND NOT A BLIT. The engine already draws a string into this pane, picking
// the font, the colour and the clip box (research/status-pane-text.md). An
// SC_CTRL_TYPE_LSTATIC control whose pszText points at our buffer reaches that through the
// engine's own dispatch, so the text looks native because it IS native and no art is added
// (AGENTS.md § "Hard rules"). The one thing plotted by hand is the "+N" badge's box under
// that text: a black rectangle framed in a colour read off the icon beside it (IndUpdate).

#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "sc_addresses.h"
#include "sc_engine.h"
#include "sc_env.h"
#include "sc_hook.h"
#include "sc_hudrow.h"
#include "sc_log.h"
#include "sc_prodqueue.h"
#include "sc_session.h"
#include "sc_upgrades.h"
#include "sc_queueind.h"
#include "sc_unit.h"

// The indicator's own control id. NEGATIVE on purpose: the CREATE-time handler binder
// 0x00418100 only rewrites +0x2A for controls with index > 0, so a negative id is
// binder-proof (the same trick sc_hudrow's indicator uses, with a different value so the
// two are distinguishable in a child walk).
#define SC_QIND_CTRL_ID ((short)0xFFE1)

static bool  g_enabled = false;

static ScHook g_hkDriver;
static ScHook g_hkLayout;   // queueLayout 0x004268D0 -- the phantom bracket

// Test seam -- NULL means "call the real engine".
static ScQueueIndCtlFn    g_show          = NULL;
static ScQueueIndCtlFn    g_hide          = NULL;
static ScQueueIndCtlFn    g_update        = NULL;
static ScQueueIndCtlFn    g_enable        = NULL;
static ScQueueIndDriverFn g_testOrigDriver = NULL;
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

// The indicator's own fxnUpdate (see IndUpdate) and the engine handlers it hands the text to.
static void __attribute__((fastcall)) SC_GAME_ENTRY IndUpdate(DWORD ctrl, DWORD edx,
                                                             DWORD a, DWORD b);
static DWORD g_textUpdate  = 0;   // the engine's type-9 (left) handler
static DWORD g_textCentred = 0;   // its type-10 (centre) handler, or type 9's if it has none
static DWORD g_iconDrawFn  = 0;   // the engine's own fxnUpdate for the last icon (see QIndIconDrawShim)
static DWORD g_iconDrawCtl = 0;   // the control whose +0x2E points at the shim
static bool  g_dialogLogged = false;
static bool  g_bandLogged   = false;  // "the band is too small" said once per dialog

static unsigned g_stat[SC_QIND_STAT__COUNT];

// WHAT THE STRIP HELD when the GAME THREAD last left it, snapshotted at the end of the
// frame path. The observer thread cannot answer this honestly: the strip's fields are
// written INSIDE the driver call, mid-walk, by the engine's own layout with the phantom in
// the ring. Nothing is drawn in between -- the dialog is rendered later, by graphic layer 2
// -- so the player never sees the intermediate state, but an asynchronous reader lands in
// it often enough to make a suite flaky (measured: the same assertion passed one run and
// failed the next). A snapshot taken by the writing thread is coherent by construction.
struct QIconSnap { short icon; WORD mode; DWORD flags; DWORD grp; DWORD text; };
static QIconSnap g_icons[SC_STATQ_SLOTS];
static int       g_iconsN = 0;

// WHICH QUEUE ICONS THE PLUGIN IS HOLDING AN ITEM BEHIND, recorded by the GAME THREAD as it
// fills them and read by the interact shim on that same thread, so it needs no locking. It
// is a list of CONTROL POINTERS rather than of display indices because the shim is handed a
// control and has to answer "is this one mine" without walking anything, on an event that
// arrives hundreds of times a second.
static DWORD g_ownedIcon[SC_STATQ_SLOTS];
static int   g_ownedIconN = 0;

static bool IsPluginOwnedIcon(DWORD ctrl) {
    for (int i = 0; i < g_ownedIconN; ++i) if (g_ownedIcon[i] == ctrl) return true;
    return false;
}

// THE BOX AS IT LOOKS WITH NOTHING OF OURS IN IT, and why a copy of it is kept at all.
//
// `ink` -- non-background bytes in a rect -- cannot answer "did our text draw" in THIS
// dialog: the pane's own art is IN this surface, so every rect in it is saturated and
// `ink > 0` holds before anyone draws anything (measured: refInk=1330 of 1330 bytes over a
// 38x35 queue icon, ink=448 of 448 inside the indicator's own box).
//
// What CAN fail is a comparison against the same pixels without our text on them: the game
// thread copies the box out of the surface on the frames the indicator is HIDDEN (by which
// time the engine has repainted whatever was under it), and the diff against that copy is
// how many bytes our line is currently responsible for. Zero means nothing of ours is on
// the screen, whatever the control's fields say.
#define SC_QIND_BASELINE_MAX 4096
static BYTE  g_baseline[SC_QIND_BASELINE_MAX];
static short g_baseRect[4] = { 0, 0, 0, 0 };
static bool  g_baseValid = false;

// ---------------------------------------------------------------------------
// THE EPOCH TEST (sc_session.h). Everything above belongs to ONE dialog in ONE game, and
// the only thing that invalidates it is `root != g_dialog` in ScQueueIndOnFrame -- a
// comparison of two HEAP ADDRESSES. The engine builds the same dialogs in the same order
// every game, so a new game's status pane can land on the byte for byte same address as the
// old one's, and that test then says "same dialog" about a dialog never seen before.
//
// EnsureSpliced covers the SPLICE: it re-checks `InChain(root)` and drops g_spliced when
// our control is not in the new chain. Nothing covers THE BASELINE, and `ScQueueIndBoxDiff`
// diffing live pixels against a baseline carried across a game start fails by producing a
// PLAUSIBLE NUMBER rather than a zero. Nothing the player sees is wrong -- this is an
// ORACLE that can lie (AGENTS.md § "Oracles: pixel counts and instruments").
static unsigned g_session = 0;

static void ForgetUpgradeIcons(void);

static void QIndSessionSync(void) {
    const unsigned now = ScSessionEpoch();
    if (g_session == now) return;
    if (g_dialog || g_baseValid || g_spliced) {
        ScLog("QIND session %u -> %u: forgetting dialog 0x%08X, the splice (%d) and the "
              "box baseline (%d) -- they belong to a game that has ended, and the status "
              "pane of the next one can be allocated at the same address",
              g_session, now, (unsigned)g_dialog, g_spliced ? 1 : 0, g_baseValid ? 1 : 0);
    }
    g_dialog       = 0;
    g_spliced      = false;
    g_shown        = false;
    g_anchor       = 0;
    g_mode         = SC_QIND_NONE;
    g_text[0]      = '\0';
    g_dialogLogged = false;
    g_bandLogged   = false;
    g_iconsN       = 0;
    g_iconDrawCtl  = 0;
    g_baseValid    = false;
    g_baseRect[0] = g_baseRect[1] = g_baseRect[2] = g_baseRect[3] = 0;
    ForgetUpgradeIcons();
    g_session = now;
}

// ---------------------------------------------------------------------------
// Engine primitives, through the seam (same conventions sc_hudrow verified)
// ---------------------------------------------------------------------------

typedef void (*OrigDriverFn)(void);

static void CallOrigDriver(void) {
    if (g_testOrigDriver) { g_testOrigDriver(); return; }
    if (g_hkDriver.installed) ((OrigDriverFn)g_hkDriver.trampoline)();
}

static int   SelectionCount(void) { return (int)*(BYTE*)ScRuntimeAddr(SC_VA_CLIENT_SELECTION_COUNT); }

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

// Forward: the box sizing needs the surface width, and the surface reader lives with the
// ink probe further down.
static DWORD SurfaceOf(DWORD root);

// The height of the font the SC_CTRL_FONT_SMALLEST bit selects, out of the font's own
// header -- the byte SC_VA_SET_FONT copies into the global the string draw's clip rule is
// measured against (sc_addresses.h). 0 when the handle is not up yet, which callers treat
// as "no answer" rather than as zero. Exported rather than kept private because sc_hudrow
// needs it too: its own box has to be taller than the font or the engine refuses to draw it.
int ScQueueIndSmallFontHeight(void) {
    if (!ScEngineModuleBase()) return 0;
    DWORD f = *(DWORD*)ScRuntimeAddr(SC_VA_FONT_SMALLEST);
    if (!ScReadable(f, SC_FONT_OFF_HEIGHT + 1)) return 0;
    return (int)*(BYTE*)(f + SC_FONT_OFF_HEIGHT);
}

static int SmallFontHeight(void) { return ScQueueIndSmallFontHeight(); }

bool ScQueueIndPlaceBand(int left, int top, int want, int surfW, int surfH,
                         short* box, int* fontH) {
    int right  = left + want;
    if (right > surfW - 1) right = surfW - 1;
    int bottom = top + SC_QIND_BOX_H;
    if (bottom > surfH) bottom = surfH;
    box[0] = (short)left;  box[1] = (short)top;
    box[2] = (short)right; box[3] = (short)bottom;
    *fontH = SmallFontHeight();
    return bottom - top >= (*fontH > 0 ? *fontH : SC_QIND_BAND_MIN_H) && right - left >= want;
}

static int OverflowOf(DWORD unit) {
    int n = ScProdQueueOverflowCount(unit);   // -1 when the building is not tracked
    return n > 0 ? n : 0;
}

// ---------------------------------------------------------------------------
// THE PHANTOM BRACKET -- make queueLayout see the slots the plugin holds items behind as
// OCCUPIED, for exactly the length of its own call.
//
// The last-slot click dies whenever the plugin and the engine FIGHT over the DISABLED bit:
// queueLayout greys every slot whose ring entry is 0xE4, re-lighting it by hand makes the
// engine's next disableControl a live call instead of a no-op, and that call's dwUser=6
// event clears the player's PRESSED bit mid-click (every fill provokes exactly one disable
// -- 1153974 = 1153974, measured). Neither bit-level fix works: restoring PRESSED was
// measured rescuing 110,381 presses in one click and still cancelling nothing, and leaving
// DISABLED set draws the slot through ticon.pcx remap row 4, the disabled colours, 14 of 16
// entries away from the lit row (the icon blit 0x00456C30 tests flag 0x2 at 0x00456C42).
//
// So the fight is not fought at all. The pre-hook writes the held item's type into the
// empty ring slot; queueLayout then takes its OCCUPIED branch -- grp/icon/mode/type from
// its own globals, the slot label, enableControl -- and the post-hook puts 0xE4 back the
// instant it returns. No disable is provoked (enableControl early-outs once the slot is
// lit), no dwUser=6 exists to clear a press, and the slot the player clicks is byte-for-byte
// a vanilla occupied slot at input time: the hit test reads VISIBLE, the press/activate
// cycle reads PRESSED, and FUN_004573A0 emits {0x20, k} through the engine's own code.
// sc_prodqueue's cancel-icon branch serves the command, because at command-processing time
// the ring slot is empty again.
//
// WHY THE WINDOW CANNOT BE OBSERVED, rather than merely is not:
//   * It opens and closes inside ONE call frame on the thread that runs queueLayout, so
//     no same-thread reader -- the Train-button gate, the tick, the cancel handlers, the
//     AI, every drawer -- can interleave with it. That every engine reader of the ring IS
//     on that thread is classified reader-by-reader in research/production-queue.md 8.8,
//     and holds structurally: the engine's own ring mutations (productionTick's and
//     cancelBuildQueueSlot's multi-store compactions) are unsynchronised, so a reader on
//     another thread would have observed torn rings in VANILLA. THREADCHECK measures that
//     live: every hooked game-side site logs its thread id on the first call and on any
//     CHANGE -- a changed id is this argument breaking, so it must be loud, never
//     deduplicated away -- and the suite asserts they are one id.
//   * The two readers that genuinely are on other threads -- this plugin's observer
//     (PRODQ/PRODQSEL, STATQ) and the test harness -- read g_ringGen around the ring
//     (seqlock: odd = open, changed = straddled) and retry, so a phantom cannot reach a
//     log line either.
//
// The writes are the two bare stores the plugin already makes elsewhere (capture/promote,
// sc_prodqueue 6.3): no resource global, no AI mirror, no event. The saved value is
// restored VERBATIM rather than assumed 0xE4, and a slot that turns out non-empty is
// REFUSED and counted (PHANTOM_DIRTY) rather than overwritten.
static WORD          g_phantomSaved[SC_BUILD_QUEUE_SLOTS];
static BYTE          g_phantomSlot[SC_BUILD_QUEUE_SLOTS];
static int           g_phantomN    = 0;
static DWORD         g_phantomUnit = 0;
static volatile LONG g_ringGen     = 0;

unsigned ScQueueIndRingGen(void) { return (unsigned)g_ringGen; }

// The writer takes no lock, so waiting here cannot hold it up. Without the wait, 32
// back-to-back tries all landed in one open window (ringStable=0 on 7 of 24 PRODQ records
// of one run). 4096 pauses, at most ~140 cycles each on current x86, bound a wait that
// never ends to about 0.2 ms.
unsigned ScQueueIndRingGenSettled(void) {
    unsigned g = ScQueueIndRingGen();
    for (int spin = 0; (g & 1) && spin < 4096; ++spin) { YieldProcessor(); g = ScQueueIndRingGen(); }
    return g;
}

// The guarded section is EXACTLY the six reads: at the layout's real call rate (~40k/s,
// measured phantom=21M over 9.5 min) a wider section straddles a window on every retry.
int ScQueueIndReadRing(DWORD unit, BYTE* head, WORD* ring) {
    for (int attempt = 0; attempt < 32; ++attempt) {
        unsigned g1 = ScQueueIndRingGenSettled();
        if (g1 & 1) continue;
        if (head) *head = *(BYTE*)(unit + SC_CUNIT_OFF_BUILD_QUEUE_SLOT);
        for (int i = 0; i < SC_BUILD_QUEUE_SLOTS; ++i) ring[i] = ScUnitQueueSlot(unit, i);
        if (ScQueueIndRingGen() == g1) return 1;
    }
    if (head) *head = *(BYTE*)(unit + SC_CUNIT_OFF_BUILD_QUEUE_SLOT);
    for (int i = 0; i < SC_BUILD_QUEUE_SLOTS; ++i) ring[i] = ScUnitQueueSlot(unit, i);
    return 0;
}

int ScQueueIndPhantomApply(void) {
    g_phantomN    = 0;
    g_phantomUnit = 0;
    if (!g_enabled) return 0;
    DWORD unit = ScPortraitUnit();   // the global queueLayout itself reads, per slot
    if (!ScUnitPtrValid(unit)) return 0;
    if (ScProdQueueOverflowCount(unit) <= 0) return 0;

    const BYTE head      = *(BYTE*)(unit + SC_CUNIT_OFF_BUILD_QUEUE_SLOT);
    const int  engineLen = ScUnitQueueLength(unit);
    int wrote = 0;
    for (int k = engineLen; k < SC_BUILD_QUEUE_SLOTS; ++k) {
        int type = ScProdQueueOverflowAt(unit, k - engineLen);
        if (type < 0) break;
        const int slot = ((int)head + k) % SC_BUILD_QUEUE_SLOTS;   // the engine's arithmetic
        WORD* p = (WORD*)(unit + SC_CUNIT_OFF_BUILD_QUEUE + (DWORD)slot * 2);
        if (*p != SC_BUILD_QUEUE_EMPTY) { ++g_stat[SC_QIND_STAT_PHANTOM_DIRTY]; break; }
        // The window opens BEFORE the first store and closes AFTER the last restore --
        // InterlockedIncrement is a full fence on x86, so a seqlock reader that saw an
        // even, unchanged generation saw no phantom byte.
        if (wrote == 0) InterlockedIncrement(&g_ringGen);
        g_phantomSaved[wrote] = *p;
        g_phantomSlot[wrote]  = (BYTE)slot;
        *p = (WORD)type;
        ++wrote;
        ++g_stat[SC_QIND_STAT_PHANTOM];
    }
    if (wrote) { g_phantomUnit = unit; g_phantomN = wrote; }
    return wrote;
}

void ScQueueIndPhantomRestore(void) {
    if (g_phantomN == 0) return;
    for (int i = g_phantomN - 1; i >= 0; --i) {
        WORD* p = (WORD*)(g_phantomUnit + SC_CUNIT_OFF_BUILD_QUEUE +
                          (DWORD)g_phantomSlot[i] * 2);
        *p = g_phantomSaved[i];
    }
    g_phantomN    = 0;
    g_phantomUnit = 0;
    InterlockedIncrement(&g_ringGen);
}

// ---------------------------------------------------------------------------
// QUEUED RESEARCH AS ICONS
// ---------------------------------------------------------------------------
//
// A researching building's pane is laid out by the two research layouts (0x00426500
// upgrade, 0x004266F0 tech), which the per-unit-type act 0x00427890 dispatches to when the
// building is not training (0x00401E70 == 0) and CUnit+0xC8/0xC9 is off its sentinel. Each
// fills ITS OWN icon control (id 15, sitting where queue slot 0 sits) the way queueLayout
// fills a queue slot -- grp = cmdicons, frame = the id's icon out of the dat table, mode 5
// (upgrade) / 4 (tech), type = the id, enableControl -- and leaves the four small queue
// icons (ids 3..6) HIDDEN: neither layout touches them, and the only thing that does is
// the hide-all sweep 0x00457310 run when the pane's layout KIND (SC_VA_STAT_ALL_HIDDEN)
// changes, not per call. So the frame path fills ids 3..6 with the held items using those
// same fields, shows them with the engine's own showControl, and leaves the engine's own
// icon handler (0x00457480) to draw and hit-test them. Nothing is written every frame:
// fields are rewritten only when the item behind a slot changes, and show/enable early-out
// on their own bit (AGENTS.md § "Engine-owned flags").
//
// A click on one of them emits {0x20, k} through the engine's own activate (0x004573A0,
// cases 2..6) exactly as a queued unit's icon does. cancelBuildQueueSlot (0x00466A70) is a
// no-op for a ring slot holding 0xE4, so an unrouted click costs nothing; sc_prodqueue's
// cancel-train detour routes it to ScUpgQueueCancelAt.
//
// Only in a research layout. Any other layout owns icons 3..6 itself (queueLayout re-lays
// them out on every call), so held items are drawn only while SC_VA_STAT_ALL_HIDDEN reads 7
// or 8, and the composer's "+N" covers them the rest of the time.
struct UpgIconSnap { DWORD unit; int kind; int id; bool shown; };
static UpgIconSnap g_upgIcon[SC_QIND_UPGRADE_ICONS];
static char        g_upgLabel[SC_QIND_UPGRADE_ICONS][4];   // "2 ".."5 ", queueLayout's format

static void ForgetUpgradeIcons(void) {
    for (int i = 0; i < SC_QIND_UPGRADE_ICONS; ++i) {
        g_upgIcon[i].unit = 0; g_upgIcon[i].kind = -1; g_upgIcon[i].id = -1;
        g_upgIcon[i].shown = false;
    }
}

int ScQueueIndUpgradeIcons(int held) {
    if (held <= 0) return 0;
    if (held <= SC_QIND_UPGRADE_ICONS) return held;
    return SC_QIND_UPGRADE_ICONS - 1;
}

// The cmdicons.grp frame for a held item, out of the same table the research layout reads
// for the running one. -1 for an id the table does not cover.
static int UpgIconFrame(int kind, int id) {
    if (kind == SC_UPGQ_KIND_TECH) {
        if (id < 0 || id >= SC_TECH_COUNT) return -1;
        return (int)*(WORD*)((DWORD)ScRuntimeAddr(SC_VA_TECH_ICON) + (DWORD)id * 2);
    }
    if (kind != SC_UPGQ_KIND_UPGRADE || id < 0 || id >= SC_UPGRADE_COUNT) return -1;
    return (int)*(WORD*)((DWORD)ScRuntimeAddr(SC_VA_UPGRADE_ICON) + (DWORD)id * 2);
}

// Light icons 3..(3+want-1) with `unit`'s first `want` held items and take down any this
// module lit past that. `want` 0 (no research layout, nothing held, no unit) takes them
// all down. Every write is compared first, so a settled pane costs four reads.
static void FillUpgradeIcons(DWORD root, DWORD unit, int want) {
    DWORD c = ScDlgFindChild(root, (short)(SC_STATQ_FIRST_CONTROL + 1));   // id 3
    for (int i = 0; i < SC_QIND_UPGRADE_ICONS && c; ++i, c = ScDlgNext(c)) {
        UpgIconSnap* s = &g_upgIcon[i];
        DWORD* flags = (DWORD*)(c + SC_BINDLG_OFF_FLAGS);
        const bool visible = (*flags & SC_CTRL_FLAG_VISIBLE) != 0;
        const int  kind  = i < want ? ScUpgQueueKindAt(unit, i) : -1;
        const int  id    = i < want ? ScUpgQueueIdAt(unit, i) : -1;
        const int  frame = kind < 0 ? -1 : UpgIconFrame(kind, id);
        DWORD su = *(DWORD*)(c + SC_BINDLG_OFF_USER);
        if (frame < 0 || !su) {
            if (s->shown) {
                if (visible) { ScCtrlHideVia(g_hide, c); ScCtrlUpdateVia(g_update, c); }
                ++g_stat[SC_QIND_STAT_UPG_ICON_HIDES];
            }
            s->unit = 0; s->kind = -1; s->id = -1; s->shown = false;
            continue;
        }
        const bool changed = !(s->shown && s->unit == unit && s->kind == kind && s->id == id);
        if (changed) {
            // The five fields queueLayout's occupied branch writes (sc_addresses.h at
            // SC_VA_GRP_CMDICONS), with the research layout's own mode. The border graphic
            // is queueLayout's too: 4 for the three middle slots, 2 for the last.
            *(DWORD*)(su + SC_STATUSER_OFF_GRP)  = *(DWORD*)ScRuntimeAddr(SC_VA_GRP_CMDICONS);
            *(short*)(su + SC_STATUSER_OFF_ICON) = (short)frame;
            *(WORD*) (su + SC_STATUSER_OFF_MODE) = (WORD)(kind == SC_UPGQ_KIND_TECH
                                                          ? SC_STATUSER_MODE_TECH
                                                          : SC_STATUSER_MODE_UPGRADE);
            *(short*)(su + SC_STATUSER_OFF_TYPE) = (short)id;
            *(DWORD*)(c + SC_BINDLG_OFF_TEXT)    = (DWORD)g_upgLabel[i];
            *(WORD*) (c + SC_BINDLG_OFF_GRAPHIC) = (WORD)(i + 1 < SC_QIND_UPGRADE_ICONS ? 4 : 2);
            s->unit = unit; s->kind = kind; s->id = id;
        }
        if (*flags & SC_CTRL_FLAG_DISABLED) ScCtrlEnableVia(g_enable, c);
        if (!visible || changed) {
            ScCtrlShowVia(g_show, c);
            *flags |= SC_CTRL_FLAG_DRAWN;
            ScCtrlUpdateVia(g_update, c);
            if (!s->shown) ++g_stat[SC_QIND_STAT_UPG_ICON_SHOWS];
            s->shown = true;
        }
    }
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

    // sc_hudrow's own indicator owns this corner of the pane while the row is paging (it is
    // drawn from the paged act, over the same buttons this module would anchor to). One
    // indicator at a time, and the row's is the one that matches what the row is doing.
    if (v->hudPages > 1) return SC_QIND_NONE;

    if (v->selection <= 1) {
        // Queued UPGRADES are drawn by the frame path into the four small queue icons the
        // research layout leaves hidden (ids 3..6; the engine's own research icon, id 15,
        // sits where slot 0 would be), so what is left UNDRAWN is the queue past those four.
        // It takes precedence because a building researching is not also training.
        if (v->upgrades > 0) {
            const int drawn  = v->research ? ScQueueIndUpgradeIcons(v->upgrades) : 0;
            const int hidden = v->upgrades - drawn;
            if (hidden <= 0) return SC_QIND_NONE;
            _snprintf(out, (size_t)outLen - 1, "+%d", hidden);
            out[outLen - 1] = '\0';
            return SC_QIND_UPGRADE;
        }
        // The strip has five icons. The ones past the engine's ring are drawn from the
        // plugin's overflow, by the engine itself via the phantom bracket, so what is left
        // UNDRAWN is whatever the logical queue holds past those five.
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

// A ring length the OBSERVER can trust (ScQueueIndReadRing); on the game thread the
// generation is even and unmoving, so this costs one extra load there.
static int CoherentEngineLen(DWORD unit, int* stable) {
    WORD ring[SC_BUILD_QUEUE_SLOTS];
    int ok = ScQueueIndReadRing(unit, NULL, ring);
    if (stable) *stable = ok;
    return ScRingLength(ring);
}

// Returns 1 when every ring read settled against the phantom window's seqlock, 0 when
// one never did (the caller prints that rather than trusting the numbers).
static int ReadView(ScQueueIndView* v) {
    int stable = 1;
    memset(v, 0, sizeof(*v));
    v->selection = SelectionCount();
    v->hudPages  = ScHudRowPageCount();

    if (v->selection <= 1) {
        DWORD unit = ScPortraitUnit();
        if (!ScUnitPtrValid(unit)) return stable;
        v->engineLen = CoherentEngineLen(unit, &stable);
        v->overflow  = OverflowOf(unit);
        int upg = ScUpgQueueCount(unit);          // -1 when the building is not tracked
        v->upgrades = upg > 0 ? upg : 0;
        const int layout = (int)*(BYTE*)ScRuntimeAddr(SC_VA_STAT_ALL_HIDDEN);
        v->research = (layout == SC_STAT_LAYOUT_UPGRADE || layout == SC_STAT_LAYOUT_TECH) ? 1 : 0;
        return stable;
    }

    // The engine's own client selection is the truth about what the player has selected
    // (0x00597208, walked to the sentinel). Buildings past the engine's twelve cannot be
    // shown by the row either, so counting the engine's list is counting what the pane is
    // about.
    DWORD* slot = (DWORD*)ScRuntimeAddr(SC_VA_CLIENT_SELECTION_GROUP);
    for (int i = 0; i < SC_HUD_BUTTON_COUNT; ++i) {
        DWORD unit = slot[i];
        if (!ScUnitPtrValid(unit)) continue;
        int s = 1;
        int len = CoherentEngineLen(unit, &s) + OverflowOf(unit);
        if (!s) stable = 0;
        if (len > 0) { ++v->buildings; v->queued += len; }
    }
    return stable;
}

// ---------------------------------------------------------------------------
// The spliced control
// ---------------------------------------------------------------------------

static bool InChain(DWORD root) {
    DWORD ind = (DWORD)&g_ctrl[0];
    DWORD c = ScDlgChild(root);
    for (int guard = 0; c && guard < SC_MAX_CTRLS_WALK; ++guard, c = ScDlgNext(c)) {
        if (c == ind) return true;
    }
    return false;
}

// Spliced at the TAIL of the child list, and the tail is what decides whether the text is
// on top of what it overlays. The CREATE-time binder skips it either way (index <= 0) and
// the engine's hide-all sweeps hide it like any child wherever it sits, so the position
// costs nothing else.
//
// What CallUpdate reaches (updateControl 0x0041C400) does not paint: it intersects the
// control's rect with the dialog's and merges the result into the screen's dirty region
// (its tail 0x0041C200 snaps the rect to a 16px grid and clamps it into the globals at
// 0x0051A16C..). The paint is the dialog's own redraw walk at 0x0041C683, which takes the
// children from `[dlg+0x42]` and steps `[esi]` head to tail, clearing each control's DRAWN
// bit as it queues it (0x0041C754) -- so a control drawn EARLIER is a control drawn UNDER.
// At the HEAD of the list this text is painted first and every engine control overlapping
// it paints over it, in the same frame, every frame.
static bool EnsureSpliced(DWORD root) {
    DWORD ind = (DWORD)&g_ctrl[0];
    if (g_spliced && !InChain(root)) g_spliced = false;   // same-address dialog realloc
    if (g_spliced) return true;

    // AND THE OTHER DIRECTION, which the line above does not cover: the flag says NOT
    // spliced while our control is already in this chain -- reachable because the
    // game-session epoch clears the flag without touching the chain. Appending again is not
    // a duplicate, it is a CYCLE: the memset below zeroes g_ctrl's `next`, the tail walk
    // then ends ON g_ctrl, and the append writes g_ctrl->next = g_ctrl. The engine's redraw
    // walk (0x0041C683) follows `next` to the end of the list, so a self-link is an infinite
    // loop inside the game's own paint, not a cosmetic bug. Adopting the existing link is
    // also right on its own terms: the control IS in the chain, so the invariant the flag
    // records is already true.
    if (InChain(root)) {
        ScLog("QIND: our indicator control is already in this dialog's chain while the "
              "module thought it was not -- adopting the existing link rather than "
              "appending a second one (dialog 0x%08X)", (unsigned)root);
        g_spliced = true;
        return true;
    }

    // Runtime evidence guard, same shape as sc_hudrow's: the engine must have a real
    // interact AND update handler for this control type in its own default tables. If
    // either is null, this build does not dispatch the type the way the table dump says,
    // so refuse to splice rather than hand the dialog a control it cannot draw.
    DWORD tInteract = 0, tUpdate = 0;
    ScDlgDefaultHandlers(SC_CTRL_TYPE_LSTATIC, &tInteract, &tUpdate);
    if (!tInteract || !tUpdate) {
        ScLog("QIND: no engine handler for control type %d (interact=0x%08X update=0x%08X)"
              " -- indicator suppressed", SC_CTRL_TYPE_LSTATIC,
              (unsigned)tInteract, (unsigned)tUpdate);
        ++g_stat[SC_QIND_STAT_REFUSED];
        return false;
    }

    DWORD cInteract = 0, cUpdate = 0;
    ScDlgDefaultHandlers(SC_CTRL_TYPE_CSTATIC, &cInteract, &cUpdate);
    g_textUpdate  = tUpdate;
    g_textCentred = cUpdate ? cUpdate : tUpdate;

    memset(g_ctrl, 0, sizeof(g_ctrl));
    ScDlgMakeStaticText(ind, root, SC_QIND_CTRL_ID, g_text, tInteract, (DWORD)&IndUpdate);
    if (!ScDlgAppendChild(root, ind)) {
        ScLog("QIND: child list longer than %d -- splice refused", SC_MAX_CTRLS_WALK);
        ++g_stat[SC_QIND_STAT_REFUSED];
        return false;
    }
    g_spliced = true;
    ++g_stat[SC_QIND_STAT_SPLICES];
    return true;
}

// Put the box on the anchor control, in the anchor's own coordinate space (control bounds
// are parent-relative -- updateControl 0x0041C400 adds the parent's origin itself). The
// bounds come from the LIVE control every time the anchor changes, never from a constant.
//
// THE BOX HAS TO FIT THE STRING, in both directions, and neither failure is loud:
//   * too SHORT and the engine draws nothing at all (research/status-pane-text.md 5);
//   * too NARROW and it draws a TRUNCATION, which is worse than nothing because it reads
//     as a working feature (measured in a live group run: a box 22px wide clamped to one
//     wireframe button, holding "4 bldgs  4 queued").
// So the width is computed from the string rather than from the anchor. SC_QIND_CHAR_W is
// a deliberate over-estimate of the small font's advance -- over-reserving costs a little
// slack, under-reserving costs the tail of the string.
//
// Writes into the CALLER'S four shorts rather than straight into the control, because the
// answer is recomputed every frame: the group band is a function of which buttons are
// VISIBLE, and that changes with the size of the selection without the line's text
// necessarily changing. The caller compares, and only then moves the control and redraws.
static bool PlaceOn(short* b, DWORD anchor, DWORD root, int mode, int textLen) {
    short* a = ScDlgBounds(anchor);
    int   want = textLen * SC_QIND_CHAR_W;
    if (want < SC_QIND_BOX_W) want = SC_QIND_BOX_W;

    if (mode == SC_QIND_GROUP) {
        // BELOW THE ROW, NOT ON IT. Starting at the first wireframe button's own top-left
        // puts ~120 pixels of text straight across the top row of unit icons; painting on
        // top of them (the tail splice, above) makes it visible but not READABLE, because
        // the pixels underneath are unit wireframes. The pane has a band the multi-select
        // branch leaves empty -- everything else in it belongs to the single-select layout
        // and is hidden here -- and that band is where a line of text belongs.
        //
        // Measured off the LIVE row every time: the twelve buttons are two rows of six and
        // only their own rects say where the lower one ends. A constant read off one
        // install is not a layout (AGENTS.md § "Claims about the binary").
        int rowLeft = a[0], rowBottom = a[3];
        DWORD c = ScDlgFindChild(root, SC_HUD_FIRST_SMALL_BUTTON);
        for (int i = 0; i < SC_HUD_BUTTON_COUNT && c; ++i, c = ScDlgNext(c)) {
            if ((*(DWORD*)(c + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE) == 0) continue;
            short* rb = ScDlgBounds(c);
            if (rb[0] < rowLeft)   rowLeft = rb[0];
            if (rb[3] > rowBottom) rowBottom = rb[3];
        }

        int surfW = 0, surfH = 0;
        DWORD d = SurfaceOf(root);
        if (d) {
            surfW = (int)*(WORD*)(d + SC_SURFACE_OFF_W);
            surfH = (int)*(WORD*)(d + SC_SURFACE_OFF_H);
        }
        if (surfW <= 0 || surfH <= 0) return false;

        int fontH = 0;
        if (!ScQueueIndPlaceBand(rowLeft, rowBottom + SC_QIND_BAND_GAP, want, surfW, surfH,
                                 b, &fontH)) {
            if (!g_bandLogged) {
                ScLog("QIND: the band below the row is (%d,%d,%d,%d) on a %dx%d surface -- "
                      "too small for \"%d chars\" at fontH=%d; the group line is suppressed",
                      b[0], b[1], b[2], b[3], surfW, surfH, textLen, fontH);
                g_bandLogged = true;
            }
            return false;
        }
    } else {
        // THE BADGE, on the icon's top-right corner and as wide as the count: a "+N" in the
        // middle of the icon sits on unit art and is hard to read (IndUpdate paints the box
        // under it). It stays inside the icon it annotates, because staying within a control
        // the engine repaints is what guarantees our pixels are painted over when the
        // indicator goes away. UPGRADE's "+N" is the same shape: the frame path leaves icon 6
        // empty whenever there is a count to draw (ScQueueIndUpgradeIcons).
        int w = textLen * SC_QIND_CHAR_W + SC_QIND_BADGE_PAD;
        if (w > a[2] - a[0]) w = a[2] - a[0];
        b[0] = (short)(a[2] - w); b[1] = a[1]; b[2] = a[2];
        b[3] = (short)(a[1] + SC_QIND_BOX_H > a[3] ? a[3] : a[1] + SC_QIND_BOX_H);
    }
    return true;
}

// The indicator's fxnUpdate: __fastcall(ECX = control), two stack dwords, RET 8 -- how
// 0x0041C1E5 calls it and how the engine's own static-text handlers return. GROUP draws the
// line with the engine's left-justified handler, as a loaded control of that type would.
// STRIP and UPGRADE first paint the badge into the render target the draw walk has just
// pointed at this dialog's surface, then centre the count in it with the engine's
// centre-justified handler.
// The badge's pixels: the control's box, one row short of the small font's height (its
// glyphs sit in the top rows; the box is taller only to satisfy the draw's clip rule), filled
// with the pane's own black and framed in the icon's own border blue (in UPGRADE the icon is
// hidden, so the frame takes whatever the pane shows there), both read off the
// surface: the icon's second row is its bright border, and SC_QIND_BADGE_BLACK_DX right of the
// icon is pane background. Not palette index 0, which is not the pane's black: the pane holds it
// in 12 of its 24840 bytes (`surfInk=24828`).
void ScQueueIndFillBadge(DWORD ctrl, DWORD surface) {
    if (!surface || !g_anchor) return;
    const int w = (int)*(WORD*)(surface + SC_SURFACE_OFF_W);
    const int h = (int)*(WORD*)(surface + SC_SURFACE_OFF_H);
    BYTE* bits = (BYTE*)*(DWORD*)(surface + SC_SURFACE_OFF_BITS);
    const short* b = ScDlgBounds(ctrl);
    const short* a = ScDlgBounds(g_anchor);
    int rows = ScQueueIndSmallFontHeight() - 1;
    if (rows < 5) rows = SC_QIND_BAND_MIN_H;
    const int x0 = b[0], x1 = b[2], y0 = b[1], y1 = b[1] + rows;
    const int bx = a[2] + SC_QIND_BADGE_BLACK_DX, by = a[1] + rows;
    if (!bits || x0 < 0 || y0 < 0 || x1 > w || y1 > h || y1 > b[3] || x1 - x0 < 3 ||
        a[0] < 0 || a[1] + 1 >= h || a[0] + 10 >= w || bx >= w || by >= h) return;
    const BYTE frame = bits[(a[1] + 1) * w + a[0] + 10];
    const BYTE black = bits[by * w + bx];
    for (int y = y0; y < y1; ++y) {
        BYTE* row = bits + y * w;
        for (int x = x0; x < x1; ++x) {
            row[x] = (y == y0 || y == y1 - 1 || x == x0 || x == x1 - 1) ? frame : black;
        }
    }
}

// THE BADGE RIDES ON THE LAST ICON'S OWN DRAW (STRIP; in UPGRADE the icon is hidden and the
// control's own IndUpdate is what paints it). Drawn only by its own control, the badge was
// painted every frame and gone from the surface by the next, never reaching the screen (both
// measured; what erased it is not established). So that icon's fxnUpdate is wrapped the way
// the interacts are -- a data write, no code patched -- and the badge is painted right after
// the engine draws the icon, in the same pass, whatever dirtied it.
static void __attribute__((fastcall)) SC_GAME_ENTRY QIndIconDrawShim(DWORD ctrl, DWORD edx,
                                                                    DWORD a, DWORD b) {
    ((ScCtrlDrawFn)g_iconDrawFn)(ctrl, edx, a, b);
    if (ctrl == g_anchor && g_shown && g_spliced) IndUpdate((DWORD)&g_ctrl[0], edx, a, b);
}

// The icon's fxnUpdate is bound once, when the dialog is built (its CREATE case, 0x00457CB7 ->
// 0x00457480); this runs every frame only to catch a new dialog.
static void WrapLastIconDraw(DWORD root) {
    const DWORD shim = (DWORD)&QIndIconDrawShim;
    DWORD c = ScDlgFindChild(root, SC_STATQ_LAST_CONTROL);
    if (!c) return;
    DWORD* fn = (DWORD*)(c + SC_BINDLG_OFF_UPDATE);
    g_iconDrawCtl = c;
    if (*fn == shim || *fn == 0) return;
    g_iconDrawFn = *fn;
    *fn = shim;
}

static void UnwrapLastIconDraw(void) {
    if (g_iconDrawCtl && ScReadable(g_iconDrawCtl + SC_BINDLG_OFF_UPDATE, 4) &&
        *(DWORD*)(g_iconDrawCtl + SC_BINDLG_OFF_UPDATE) == (DWORD)&QIndIconDrawShim) {
        *(DWORD*)(g_iconDrawCtl + SC_BINDLG_OFF_UPDATE) = g_iconDrawFn;
    }
    g_iconDrawCtl = 0;
}

static void __attribute__((fastcall)) SC_GAME_ENTRY IndUpdate(DWORD ctrl, DWORD edx,
                                                             DWORD a, DWORD b) {
    DWORD fn = g_textUpdate;
    if (g_mode == SC_QIND_STRIP || g_mode == SC_QIND_UPGRADE) {
        ScQueueIndFillBadge(ctrl, *(DWORD*)ScRuntimeAddr(SC_VA_RENDER_TARGET));
        fn = g_textCentred;
    }
    ((ScCtrlDrawFn)fn)(ctrl, edx, a, b);
}

DWORD ScQueueIndOwnUpdate(void)    { return (DWORD)&IndUpdate; }
DWORD ScQueueIndEngineUpdate(void) { return g_textUpdate; }

// Which control the indicator hangs off, per mode. A mode ScQueueIndCompose can return but
// this function has no case for is invisible in every real game, on every building:
// ScQueueIndOnFrame reads the null anchor as "nothing to show" and resets the mode to
// SC_QIND_NONE before ever attempting a splice.
//   STRIP   -- the LAST queue icon (id 6). While the plugin holds overflow it keeps the
//              engine's ring at four, so that icon is precisely the one drawn empty.
//   UPGRADE -- the SAME icon (id 6). The frame path draws held research into icons 3..5
//              and leaves 6 free whenever there is a count to put on it.
//   GROUP   -- the first wireframe button (id 0x21). The line does not sit ON that button
//              (see PlaceOn) -- the button is where the ROW's geometry is read from, and it
//              is what RepaintUnder asks the engine to redraw.
static DWORD AnchorFor(DWORD root, int mode) {
    if (mode == SC_QIND_STRIP || mode == SC_QIND_UPGRADE) {
        return ScDlgFindChild(root, SC_STATQ_LAST_CONTROL);
    }
    if (mode == SC_QIND_GROUP) return ScDlgFindChild(root, SC_HUD_FIRST_SMALL_BUTTON);
    return 0;
}

// ---------------------------------------------------------------------------
// The fifth icon (and the fourth, and any other the plugin is holding)
// ---------------------------------------------------------------------------

// The fifth queue slot draws empty whenever the plugin is holding overflow: the engine's
// ring is held at SC_PRODQ_ENGINE_HOLD = 4 so the client keeps sending Train commands
// (research/production-queue.md 5.2), so queueLayout (0x004268D0) has only four items to
// draw and greys the fifth. The ring must stay at four; the DISPLAY is what needs fixing,
// and the PHANTOM BRACKET above does it by making the engine lay the slot out itself.
//
// So this function PUBLISHES, it does not paint: which icons are the plugin's (for the
// interact shim's counters and the suite's `owned=`), and the game-thread snapshot of what
// the strip holds (for the observer, which must never read the engine's mid-layout state).
// Hand-writing the slot's own fields here is a prohibition, not an option -- the bracket
// block above carries the measurements that closed it off.
static void PublishOwnedIcons(DWORD root, const ScQueueIndView* v, DWORD unit) {
    const int drawable = ScQueueIndDrawableSlots(v);

    // WHICH SLOTS ARE OURS, rebuilt every fill by the thread that does the filling. The
    // shim reads it to decide whose press to protect, and it has to be re-derived rather
    // than accumulated: an item promoted into the ring hands its icon back to the engine,
    // and protecting a press on a slot the engine now owns changes vanilla behaviour for
    // no reason.
    //
    // BUILT INTO A LOCAL AND PUBLISHED IN ONE WRITE, count LAST. Clearing the count and
    // refilling in place opens a window -- hundreds of times a second -- where the list
    // reads EMPTY to the observer (measured: `owned=` read 0 in 48 of 68 QIND lines of one
    // run), and a torn value cannot say whether the thing it measures was true. Count last
    // so that a reader which sees the count sees entries written before it.
    DWORD owned[SC_STATQ_SLOTS];
    int   ownedN = 0;
    {
        DWORD oc = ScDlgFindChild(root, SC_STATQ_FIRST_CONTROL);
        for (int k = 0; k < SC_STATQ_SLOTS && oc; ++k, oc = ScDlgNext(oc)) {
            if (k >= v->engineLen && k < drawable &&
                ScProdQueueOverflowAt(unit, k - v->engineLen) >= 0 &&
                ownedN < SC_STATQ_SLOTS) {
                owned[ownedN++] = oc;
            }
        }
    }
    for (int i = 0; i < ownedN; ++i) g_ownedIcon[i] = owned[i];
    g_ownedIconN = ownedN;
}

// The snapshot, taken after every fill, by the thread that did it, the count set last: the
// observer thread logs it between frames, and a count reset to 0 while the walk refilled it
// read back as a two-icon strip (measured, `icons=[..,..] engineLen=4` on a five-lit pane).
static void SnapshotIcons(DWORD root) {
    int n = 0;
    DWORD sc = ScDlgFindChild(root, SC_STATQ_FIRST_CONTROL);
    for (int k = 0; k < SC_STATQ_SLOTS && sc; ++k, sc = ScDlgNext(sc)) {
        DWORD su = *(DWORD*)(sc + SC_BINDLG_OFF_USER);
        QIconSnap* q = &g_icons[n++];
        q->flags = *(DWORD*)(sc + SC_BINDLG_OFF_FLAGS);
        q->icon  = su ? *(short*)(su + SC_STATUSER_OFF_ICON) : -1;
        q->mode  = su ? *(WORD*) (su + SC_STATUSER_OFF_MODE) : 0;
        q->grp   = su ? *(DWORD*)(su + SC_STATUSER_OFF_GRP)  : 0;
        q->text  = *(DWORD*)(sc + SC_BINDLG_OFF_TEXT);
    }
    g_iconsN = n;
}

// ---------------------------------------------------------------------------
// THE QUEUE-ICON INTERACT SHIM -- a measurement, and nothing else.
//
// Each icon's interact POINTER (control+0x2A, plain dialog-heap data, no code patched --
// the same mechanism sc_hudrow's page gesture uses on the twelve wireframe buttons) is
// wrapped with a shim that counts the event and tail-calls the engine's own handler. It
// changes no behaviour: every event goes on to exactly the function it would have reached.
//
// WHAT IT ESTABLISHED, and why `disableOnOwned` is the phantom bracket's tripwire. A click
// on a slot the plugin lights by hand emits NO Cancel Train command at all (0 x
// `CMD id=0x20` at queueCommand) while the card's Cancel and a middle icon emit normally,
// and a click inside the icon but outside the "+N" box does not emit either -- so the text
// control never owned those pixels, and could not: the hit test 0x00418340 takes the FIRST
// child that accepts dwUser=4, LSTATIC refuses that code outright, and the icons precede it
// in the chain anyway. What kills the click is dwUser=6, which `disableControl`
// (0x00418640) sends after it sets the DISABLED bit and whose type 2 handler is
// `AND [ctrl+0x18],0xBFFFFFFF` -- CLEAR PRESSED. The mouse-down arms PRESSED, a dwUser=6
// milliseconds later clears it, and the mouse-up finds nothing armed, so no ACTIVATE and no
// command (measured on the failing slot: idx=6 dwUser=6 x1474 in 13 seconds, against a
// working idx=3 whose PRESSED stays armed through LBUTTONUP into ACTIVATE --
// research/production-queue.md 8.6). With the bracket holding, the engine never disables an
// owned slot, so `disableOnOwned` must not move at all while `phantom` climbs; a suite reads
// both either side of a click, which is what separates "the fix is active" from "the race
// was won".
//
// WHAT THE TRACE DROPS, AND WHY EACH ONE. MOUSEMOVE (type 3) arrives thousands of times a
// second, `dwUser=8` is a periodic sweep the engine sends all five icons about ten times a
// second whether anything happened or not, and an INVISIBLE control cannot be under
// anybody's cursor. None of the three can carry the answer and together they are the entire
// flood -- unfiltered, the trace hits its line cap in the MENUS before a single click. Each
// drop is COUNTED, because a filtered trace that does not say what it filtered is a count
// over an unknown denominator.
#define SC_QIND_CLICKTRACE_MAX 2000
#define SC_QIND_SWEEP_USER     8
static bool  g_clickTrace  = false;
static DWORD g_iconOrigFn  = 0;                     // the engine's own status-control interact
static DWORD g_iconWrapped[SC_STATQ_SLOTS];
static int   g_iconWrapN   = 0;
static unsigned g_clickTraceLines   = 0;
static unsigned g_clickTraceSeen    = 0;   // events the shim was handed, all kinds
static unsigned g_clickTraceMoves   = 0;   // ... dropped: MOUSEMOVE
static unsigned g_clickTraceSweeps  = 0;   // ... dropped: the dwUser=8 sweep
static unsigned g_clickTraceHidden  = 0;   // ... dropped: control not visible
static unsigned g_clickTraceCapped  = 0;   // ... dropped: over the line cap

typedef int (__attribute__((fastcall)) *ScIconInteractFn)(DWORD, DWORD);

static int __attribute__((fastcall)) SC_GAME_ENTRY QIndIconInteractShim(DWORD ctrl, DWORD evt) {
    {
        static DWORD tid = 0;
        ScThreadCheck("qind-interact", &tid);
    }
    // MEASURES ONLY -- and restoring the PRESSED bit here is a PROHIBITION, not an option.
    // Measured across one click: disableWithPress +110381 and pressKept +110381, with zero
    // 0x20 commands reaching queueCommand and the minerals not moving, so the restore
    // worked on every one of them and cancelled nothing. Worse, `pressKept` kept climbing
    // for six seconds after a SIXTY MILLISECOND click (807134 of 1153974 disable events
    // arrived with a press in flight), so the press never comes back down: the mouse-up
    // never reaches 0x004E19F0, the handler that both clears the press and emits the
    // ACTIVATE, and putting the bit back just holds the button down forever.
    //
    // WHERE A NEXT ATTEMPT WOULD START is one function: `0x00418830`, called on button-down
    // with the hit control, sends it a `dwUser=5` "can you take focus" query and records
    // `[dlg+0x3e] = ctrl` ONLY if the control returns non-zero, and the dialog's focused
    // control is what the button-up is routed to. The trace shows that query reaching our
    // icon (`idx=6 type=14 dwUser=5 flags=0x00000418`), so what it ANSWERS is the open
    // question, not whether it is asked.
    //
    // AND NO SINGLE-RUN CONCLUSION ABOUT ANY OF IT IS VALID: the click is a RACE, and the
    // instrument flips the outcome in BOTH directions (with the bracket out, tracing
    // cancels and not tracing does not; with it in, the reverse), which is incoherent as a
    // cause, so the variable is timing. A claim that this is fixed has to click N times and
    // assert the RATE (AGENTS.md § "Oracles: threads, races, confounds").
    //
    // The counters below cost one compare on an event the engine sends anyway.
    if (g_iconOrigFn && evt &&
        *(WORD*)(evt + SC_EVT_OFF_TYPE) == SC_EVT_TYPE_USER &&
        *(DWORD*)evt == SC_USER_DISABLED &&
        IsPluginOwnedIcon(ctrl)) {
        // Counted here as well, or QINDCLICKSTATS's `seen` would be a denominator with the
        // busiest event on the busiest control missing from it.
        ++g_clickTraceSeen;
        ++g_stat[SC_QIND_STAT_DISABLE_OWNED];
        const DWORD flags = *(DWORD*)(ctrl + SC_BINDLG_OFF_FLAGS);
        if (flags & SC_CTRL_FLAG_PRESSED) ++g_stat[SC_QIND_STAT_DISABLE_PRESSED];
        return ((ScIconInteractFn)g_iconOrigFn)(ctrl, evt);
    }
    if (g_iconOrigFn && evt) {
        ++g_clickTraceSeen;
        const WORD  type   = *(WORD*)(evt + SC_EVT_OFF_TYPE);
        const DWORD dwUser = *(DWORD*)evt;
        const DWORD flags  = *(DWORD*)(ctrl + SC_BINDLG_OFF_FLAGS);
        if (type == SC_EVT_MOUSEMOVE)                                ++g_clickTraceMoves;
        else if (type == SC_EVT_TYPE_USER && dwUser == SC_QIND_SWEEP_USER)
                                                                     ++g_clickTraceSweeps;
        else if ((flags & SC_CTRL_FLAG_VISIBLE) == 0)                ++g_clickTraceHidden;
        else if (g_clickTraceLines >= SC_QIND_CLICKTRACE_MAX)         ++g_clickTraceCapped;
        else {
            ++g_clickTraceLines;
            ScLog("QINDCLICK ctrl=0x%08X idx=%d type=%u dwUser=%u flags=0x%08X "
                  "disabled=%d visible=%d x=%d y=%d",
                  (unsigned)ctrl, (int)*(short*)(ctrl + SC_BINDLG_OFF_INDEX),
                  (unsigned)type, (unsigned)dwUser, (unsigned)flags,
                  (flags & SC_CTRL_FLAG_DISABLED) ? 1 : 0,
                  (flags & SC_CTRL_FLAG_VISIBLE) ? 1 : 0,
                  (int)*(short*)(evt + SC_EVT_OFF_X),
                  (int)*(short*)(evt + SC_EVT_OFF_Y));
        }
    }
    if (!g_iconOrigFn) return 0;
    return ((ScIconInteractFn)g_iconOrigFn)(ctrl, evt);
}

// Wrap/unwrap the five queue icons. Idempotent, and it takes the ENGINE'S OWN pointer from
// the first icon rather than from a constant -- if this build dispatches these controls
// through something else, the trace records that and wraps nothing.
static void WrapIconInteracts(DWORD root) {
    const DWORD shim = (DWORD)&QIndIconInteractShim;
    g_iconWrapN = 0;
    DWORD c = ScDlgFindChild(root, SC_STATQ_FIRST_CONTROL);
    for (int k = 0; k < SC_STATQ_SLOTS && c; ++k, c = ScDlgNext(c)) {
        DWORD* fn = (DWORD*)(c + SC_BINDLG_OFF_INTERACT);
        if (*fn != shim) {
            if (!g_iconOrigFn) {
                g_iconOrigFn = *fn;
                ScLog("QINDCLICK: tracing the five queue icons; the engine's own interact for "
                      "them is 0x%08X", (unsigned)g_iconOrigFn);
            }
            if (*fn != g_iconOrigFn) {
                ScLog("QINDCLICK: icon idx=%d dispatches through 0x%08X, not 0x%08X -- not "
                      "wrapped", (int)*(short*)(c + SC_BINDLG_OFF_INDEX),
                      (unsigned)*fn, (unsigned)g_iconOrigFn);
                continue;
            }
            *fn = shim;
        }
        if (g_iconWrapN < SC_STATQ_SLOTS) g_iconWrapped[g_iconWrapN++] = c;
    }
}

static void UnwrapIconInteracts(void) {
    const DWORD shim = (DWORD)&QIndIconInteractShim;
    for (int i = 0; i < g_iconWrapN; ++i) {
        DWORD c = g_iconWrapped[i];
        if (!ScReadable(c + SC_BINDLG_OFF_INTERACT, 4)) continue;
        DWORD* fn = (DWORD*)(c + SC_BINDLG_OFF_INTERACT);
        if (*fn == shim && g_iconOrigFn) *fn = g_iconOrigFn;
    }
    g_iconWrapN = 0;
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
        if (!ScReadable(d, 8)) continue;
        int w = (int)*(WORD*)(d + SC_SURFACE_OFF_W);
        int h = (int)*(WORD*)(d + SC_SURFACE_OFF_H);
        DWORD bits = *(DWORD*)(d + SC_SURFACE_OFF_BITS);
        if (w <= 0 || h <= 0 || w > 640 || h > 480 || !bits) continue;
        if (!ScReadable(bits, (DWORD)(w * h))) continue;
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

// Two queue-slot rects, compared byte for byte on the dialog's own 8-bit surface. See the
// block above the call site for why this is the honest oracle for the fifth icon and a
// plain ink count is not. The last SC_QIND_SLOT_LABEL_ROWS rows are skipped because the
// engine draws each slot's NUMBER there and the numbers legitimately differ ("1 " against
// "5 "); the badge sits in the top rows, which are compared.
// Returns the count of differing bytes, or -1 when the surface is unreadable, either
// control is missing or hidden, or the two rects are not the same size (which is the
// engine's layout saying these two slots are not comparable, not a defect here).
int ScQueueIndSlotDiff(DWORD root, int slotA, int slotB) {
    if (!root || slotA < 0 || slotB < 0 ||
        slotA >= SC_STATQ_SLOTS || slotB >= SC_STATQ_SLOTS) return -1;
    DWORD d = SurfaceOf(root);
    if (!d) return -1;
    const int   w    = (int)*(WORD*)(d + SC_SURFACE_OFF_W);
    const int   h    = (int)*(WORD*)(d + SC_SURFACE_OFF_H);
    const DWORD bits = *(DWORD*)(d + SC_SURFACE_OFF_BITS);

    short* r[2];
    for (int i = 0; i < 2; ++i) {
        DWORD c = ScDlgFindChild(root, (short)(SC_STATQ_FIRST_CONTROL + (i ? slotB : slotA)));
        if (!c) return -1;
        if ((*(DWORD*)(c + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE) == 0) return -1;
        r[i] = ScDlgBounds(c);
    }
    const int bw = r[0][2] - r[0][0], bh = r[0][3] - r[0][1];
    if (bw <= 0 || bh <= SC_QIND_SLOT_LABEL_ROWS) return -1;
    if (r[1][2] - r[1][0] != bw || r[1][3] - r[1][1] != bh) return -1;
    for (int i = 0; i < 2; ++i) {
        if (r[i][0] < 0 || r[i][1] < 0 || r[i][0] + bw > w || r[i][1] + bh > h) return -1;
    }

    int diff = 0;
    for (int y = 0; y < bh - SC_QIND_SLOT_LABEL_ROWS; ++y) {
        const BYTE* ra = (const BYTE*)(bits + (DWORD)((r[0][1] + y) * w + r[0][0]));
        const BYTE* rb = (const BYTE*)(bits + (DWORD)((r[1][1] + y) * w + r[1][0]));
        for (int x = 0; x < bw; ++x) if (ra[x] != rb[x]) ++diff;
    }
    return diff;
}

// Walk a rect of the dialog surface. The two callers want different things out of the same
// bounds check, so each inlines its own body rather than passing a callback. `maxBytes <= 0`
// means "no size limit", and every caller states its own: a fixed cap here would silently
// make this module's own buffer the size limit for all of them, sc_hudrow's wider band
// included.
static bool BoxOnSurface(DWORD root, const short* r, DWORD* bits, int* w, int* stride,
                         int maxBytes) {
    DWORD d = root ? SurfaceOf(root) : 0;
    if (!d) return false;
    const int sw = (int)*(WORD*)(d + SC_SURFACE_OFF_W);
    const int sh = (int)*(WORD*)(d + SC_SURFACE_OFF_H);
    if (r[0] < 0 || r[1] < 0 || r[2] > sw || r[3] > sh) return false;
    if (r[2] <= r[0] || r[3] <= r[1]) return false;
    if (maxBytes > 0 && (r[2] - r[0]) * (r[3] - r[1]) > maxBytes) return false;
    *bits   = *(DWORD*)(d + SC_SURFACE_OFF_BITS);
    *w      = sw;
    *stride = sw;
    return *bits != 0;
}

// THE ONE READER. Copy a rect of the dialog's own 8-bit surface into a caller-owned buffer.
// Both modules' "the pane without our text on it" copies go through here, so there is one
// place that knows where this dialog's pixels live and one bounds check guarding them.
int ScQueueIndCopyRect(DWORD root, const short* rect, BYTE* out, int outMax) {
    if (!rect || !out || outMax <= 0) return 0;
    DWORD bits; int w, stride;
    if (!BoxOnSurface(root, rect, &bits, &w, &stride, outMax)) return 0;
    const int bw = rect[2] - rect[0], bh = rect[3] - rect[1];
    for (int y = 0; y < bh; ++y) {
        memcpy(out + (size_t)y * bw,
               (const void*)(bits + (DWORD)((rect[1] + y) * stride + rect[0])), (size_t)bw);
    }
    return bw * bh;
}

// The surface's own dimensions, for callers sizing a box against it. 0 when neither
// candidate offset reads as a plausible surface -- an honest "no answer", and the callers
// treat it as a refusal to place rather than as a zero-sized pane.
int ScQueueIndSurfaceSize(DWORD root, int* w, int* h) {
    DWORD d = root ? SurfaceOf(root) : 0;
    if (!d) return 0;
    if (w) *w = (int)*(WORD*)(d + SC_SURFACE_OFF_W);
    if (h) *h = (int)*(WORD*)(d + SC_SURFACE_OFF_H);
    return 1;
}

// Copy the box out of the surface. Called on the GAME thread, on frames the indicator is
// not showing -- so what it captures is the pane with our line already repainted away.
static void CaptureBaseline(DWORD root, const short* r) {
    g_baseValid = false;
    if (ScQueueIndCopyRect(root, r, g_baseline, SC_QIND_BASELINE_MAX) <= 0) return;
    g_baseRect[0] = r[0]; g_baseRect[1] = r[1]; g_baseRect[2] = r[2]; g_baseRect[3] = r[3];
    g_baseValid = true;
}

// How many bytes of the box differ from that copy. -1 when there is no copy for THIS rect
// (the box moved, or the indicator has not been hidden yet in this dialog), which is an
// honest "no answer" rather than a zero.
int ScQueueIndBoxDiff(DWORD root) {
    // The epoch first, so a baseline carried across a game start reports -1 ("no
    // answer") rather than a plausible byte count diffed against another game's pixels.
    QIndSessionSync();
    if (!g_baseValid) return -1;
    const short* r = (const short*)&g_ctrl[SC_BINDLG_OFF_BOUNDS];
    for (int i = 0; i < 4; ++i) if (r[i] != g_baseRect[i]) return -1;
    DWORD bits; int w, stride;
    if (!BoxOnSurface(root, r, &bits, &w, &stride, SC_QIND_BASELINE_MAX)) return -1;
    const int bw = r[2] - r[0], bh = r[3] - r[1];
    int diff = 0;
    for (int y = 0; y < bh; ++y) {
        const BYTE* row = (const BYTE*)(bits + (DWORD)((r[1] + y) * stride + r[0]));
        const BYTE* base = g_baseline + (size_t)y * bw;
        for (int x = 0; x < bw; ++x) if (row[x] != base[x]) ++diff;
    }
    return diff;
}

// ---------------------------------------------------------------------------
// Read-back oracles
// ---------------------------------------------------------------------------

// Everything here is re-read from the live dialog. In particular `text` comes through the
// CONTROL's own pszText pointer, not from g_text: a wrong splice or a stale pointer shows
// up on the line instead of being masked by our own intent.
//
// THREADS. Called from the observer thread's marker channel, so it must only READ. Every
// read here is a single field of dialog or record memory, and the two plugin counts it
// quotes are lock-free scans of small fixed arrays, so a torn one mis-reports one log line
// and cannot corrupt anything. The half that WRITES is the frame path, game thread only,
// inside the detour.
void ScQueueIndLogState(const char* tag) {
    const char* t = tag ? tag : "-";
    DWORD dlg  = ScEngineModuleBase() ? ScStatDialog() : 0;
    DWORD root = dlg ? ScDlgRoot(dlg) : 0;
    if (!root) { ScLog("QIND [%s] dialog=0 (no status pane in this process state)", t); return; }

    DWORD ind = (DWORD)&g_ctrl[0];
    bool  linked = InChain(root);
    DWORD flags  = linked ? *(DWORD*)(ind + SC_BINDLG_OFF_FLAGS) : 0;
    short* b     = ScDlgBounds(ind);
    const char* live = "";
    if (linked) {
        DWORD p = *(DWORD*)(ind + SC_BINDLG_OFF_TEXT);
        if (ScReadable(p, 1)) live = (const char*)p;
    }

    // THIS RUNS ON THE OBSERVER THREAD, and ReadView reads the ring -- which the phantom
    // bracket makes non-empty for the length of each queueLayout call on the game thread.
    // `ringStable=0` on the printed line means every retry straddled a window, so the
    // ring-derived numbers are suspect: the reader is told rather than left to discover it.
    ScQueueIndView v;
    int ringStable = ReadView(&v);

    int ink = linked ? ScQueueIndSurfaceInk(root, b[0], b[1], b[2], b[3]) : -1;

    // THE POSITIVE CONTROL for that number. `ink=0` has two readings -- "we drew nothing"
    // and "the probe cannot see this surface" -- and only one of them is a bug, so the same
    // probe runs over a rect the ENGINE fills: the first queue icon (id 2), which draws a
    // unit portrait whenever anything is queued. refInk=0 says the probe is blind and its
    // verdict on the indicator means nothing: prove the pattern positive where it should
    // match before trusting it where it should not
    // (AGENTS.md § "Oracles: pixel counts and instruments").
    //
    // IT HAS TO BE A CONTROL THAT IS ACTUALLY UP. Queue icon 2 is hidden in a multi-building
    // selection (the engine draws the wireframe row instead), so the reference is the first
    // VISIBLE of (queue icon 2, wireframe button 0x21) and the line says which it used. It
    // does NOT fall back to a hidden one -- ink over a control nobody can see answers
    // neither question -- so a pane with no candidate up reports -1, and `surfInk` below is
    // what answers "is the probe blind" in EVERY state, that one included.
    int refInk = -1, refId = 0;
    {
        const short cand[2] = { SC_STATQ_FIRST_CONTROL, SC_HUD_FIRST_SMALL_BUTTON };
        for (int i = 0; i < 2; ++i) {
            DWORD ref = ScDlgFindChild(root, cand[i]);
            if (!ref) continue;
            if ((*(DWORD*)(ref + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE) == 0) continue;
            short* rb2 = ScDlgBounds(ref);
            refInk = ScQueueIndSurfaceInk(root, rb2[0], rb2[1], rb2[2], rb2[3]);
            refId  = cand[i];
            break;
        }
    }

    // CAN THE PROBE READ THIS SURFACE AT ALL -- the only liveness question with an answer in
    // every state, the drained pane included. Whole surface deliberately: the pane's own art
    // covers it, which is the same fact that makes `ink` useless as an oracle and this number
    // a good blindness check. A live surface is never 0 here, so 0 or -1 voids the line.
    const int surfInk = ScQueueIndSurfaceInk(root, 0, 0, 0x7FFF, 0x7FFF);

    // THE SCREEN-LEVEL CHECK ON THE FIFTH ICON, and why it is a DIFFERENCE rather than a
    // count: ink inside the "+N" box sits inside an icon the engine fills, so it can never
    // be 0, and an assertion on it passes happily while this module draws the wrong art.
    // Slots 0 and 4 are the same size (38x35) and the engine gives BOTH the same border
    // graphic 2 (queueLayout 0x00426A0D: graphic 4 only for k in 1..3), so with five of one
    // type queued the two rects are the same picture and every byte that differs below the
    // label row is something this plugin put there. Three states, three readings:
    //   a wrong GRP  -> hundreds of bytes differ (different art entirely);
    //   text drawn UNDER the icon -> 0 (the icon painted over it);
    //   text drawn ON TOP -> the glyph, tens of bytes.
    int slotDiff = ScQueueIndSlotDiff(root, 0, SC_STATQ_SLOTS - 1);

    // The two GRPs the engine picks between, so every `art` letter below is decidable
    // against the engine's own globals rather than against a number this file remembers.
    const DWORD grpIcons = *(DWORD*)ScRuntimeAddr(SC_VA_GRP_CMDICONS);
    const DWORD grpBtns  = *(DWORD*)ScRuntimeAddr(SC_VA_GRP_CMDBTNS);

    // The strip as the game thread last left it (see g_icons), per slot:
    // `icon:mode:state:art:label`. `art` is I when the slot draws from the ICON grp (what an
    // occupied slot must draw from), B when it points at the button-BORDER grp the engine
    // leaves on an EMPTY slot, ? for neither; `label` is 1 when the slot carries the number
    // the engine draws on every occupied icon. A frame index alone cannot say which PICTURE
    // is on the screen; the frame index and the GRP together can.
    char icons[224];
    int used = 0;
    icons[0] = '\0';
    for (int i = 0; i < g_iconsN && used + 26 < (int)sizeof(icons); ++i) {
        DWORD g = g_icons[i].grp;
        used += _snprintf(icons + used, sizeof(icons) - (size_t)used, "%s0x%03X:%u:%s:%c:%d",
                          i ? "," : "", (unsigned)(WORD)g_icons[i].icon,
                          (unsigned)g_icons[i].mode,
                          (g_icons[i].flags & SC_CTRL_FLAG_DISABLED) ? "grey" :
                          ((g_icons[i].flags & SC_CTRL_FLAG_VISIBLE) ? "lit" : "hidden"),
                          (g && g == grpIcons) ? 'I' : ((g && g == grpBtns) ? 'B' : '?'),
                          g_icons[i].text ? 1 : 0);
    }

    ScLog("QIND [%s] mode=%d linked=%d visible=%d text=\"%s\" bounds=(%d,%d,%d,%d) ink=%d "
          "refInk=%d refId=%d surfInk=%d slotDiff=%d boxDiff=%d fontH=%d icons=[%s] "
          "sel=%d engineLen=%d overflow=%d upg=%d bldgs=%d queued=%d hudPages=%d "
          "anchor=0x%08X owned=%d disableOnOwned=%u disableWithPress=%u pressKept=%u "
          "phantom=%u phantomDirty=%u ringGen=%u ringStable=%d layout=%d research=%d "
          "upgIconShows=%u upgIconHides=%u",
          t, g_mode, linked ? 1 : 0,
          (flags & SC_CTRL_FLAG_VISIBLE) ? 1 : 0, live,
          linked ? b[0] : 0, linked ? b[1] : 0, linked ? b[2] : 0, linked ? b[3] : 0, ink,
          refInk, refId, surfInk, slotDiff, ScQueueIndBoxDiff(root), SmallFontHeight(), icons,
          v.selection, v.engineLen, v.overflow, v.upgrades, v.buildings, v.queued,
          v.hudPages, (unsigned)g_anchor,
          // `owned` is how many queue icons the plugin is holding an item behind right now;
          // `disableOnOwned` is the phantom bracket's tripwire (see the shim above).
          g_ownedIconN,
          g_stat[SC_QIND_STAT_DISABLE_OWNED], g_stat[SC_QIND_STAT_DISABLE_PRESSED],
          g_stat[SC_QIND_STAT_PRESSKEPT],
          g_stat[SC_QIND_STAT_PHANTOM], g_stat[SC_QIND_STAT_PHANTOM_DIRTY],
          ScQueueIndRingGen(), ringStable,
          (int)*(BYTE*)ScRuntimeAddr(SC_VA_STAT_ALL_HIDDEN), v.research,
          g_stat[SC_QIND_STAT_UPG_ICON_SHOWS], g_stat[SC_QIND_STAT_UPG_ICON_HIDES]);
}

// One line per child of the statdata dialog: which controls in this pane are engine-drawn
// text and where the free pixels are, read off the LIVE dialog on THIS install rather than
// off a dump (research/hud-selection-row.md 10).
void ScQueueIndLogDialog(const char* tag) {
    const char* t = tag ? tag : "-";
    DWORD dlg  = ScEngineModuleBase() ? ScStatDialog() : 0;
    DWORD root = dlg ? ScDlgRoot(dlg) : 0;
    if (!root) { ScLog("QINDDLG [%s] dialog=0", t); return; }

    short* rb = ScDlgBounds(root);
    DWORD  d  = SurfaceOf(root);
    ScLog("QINDDLG [%s] root=0x%08X rect=(%d,%d,%d,%d) surfaceAt=+0x%02X %dx%d bits=0x%08X",
          t, (unsigned)root, rb[0], rb[1], rb[2], rb[3],
          d ? (unsigned)(d - root) : 0u,
          d ? (int)*(WORD*)(d + SC_SURFACE_OFF_W) : 0,
          d ? (int)*(WORD*)(d + SC_SURFACE_OFF_H) : 0,
          d ? (unsigned)*(DWORD*)(d + SC_SURFACE_OFF_BITS) : 0u);

    int n = 0;
    for (DWORD c = ScDlgChild(root); c && n < SC_MAX_CTRLS_WALK; c = ScDlgNext(c), ++n) {
        short* b = ScDlgBounds(c);
        DWORD  f = *(DWORD*)(c + SC_BINDLG_OFF_FLAGS);
        DWORD  p = *(DWORD*)(c + SC_BINDLG_OFF_TEXT);
        const char* s = (p && ScReadable(p, 1)) ? (const char*)p : "";
        // INTERACT as well as UPDATE. Two controls that look identical in flags and bounds
        // can still be dispatched by different code, and when one takes a click and the
        // other does not, that pointer is the first thing worth ruling out -- one line
        // instead of an argument about dispatch.
        ScLog("QINDDLG [%s] id=%d type=%u flags=0x%08X vis=%d rect=(%d,%d,%d,%d) "
              "interact=0x%08X update=0x%08X text=\"%.24s\"",
              t, (int)ScDlgIndex(c), (unsigned)*(WORD*)(c + SC_BINDLG_OFF_TYPE),
              (unsigned)f, (f & SC_CTRL_FLAG_VISIBLE) ? 1 : 0,
              b[0], b[1], b[2], b[3],
              (unsigned)*(DWORD*)(c + SC_BINDLG_OFF_INTERACT),
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
static void RepaintUnder(DWORD root) {
    // OUR OWN BOX FIRST, because the group line does not sit on the buttons. updateControl
    // takes the rect from the control it is given, so calling it on the (now hidden)
    // indicator is what puts the band it was using back into the dirty region -- and a
    // hidden control draws nothing, so what lands there is whatever the dialog paints under
    // it. Repainting only the anchor strands the line on the surface the moment it is not
    // sitting on an engine control any more.
    if (g_spliced) ScCtrlUpdateVia(g_update, (DWORD)&g_ctrl[0]);
    if (!g_anchor) return;
    if (*(DWORD*)(g_anchor + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE) ScCtrlUpdateVia(g_update, g_anchor);
    // ... and the whole row after it: the band is one gap below those buttons, so their
    // redraw is what is next to the line's pixels, and the group case is the one where the
    // engine has the most to put back.
    if (g_mode == SC_QIND_GROUP && root) {
        DWORD c = ScDlgFindChild(root, SC_HUD_FIRST_SMALL_BUTTON);
        for (int i = 0; i < SC_HUD_BUTTON_COUNT && c; ++i, c = ScDlgNext(c)) {
            if (*(DWORD*)(c + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE) ScCtrlUpdateVia(g_update, c);
        }
    }
}

void ScQueueIndOnFrame(void) {
    if (!g_enabled) return;
    QIndSessionSync();
    ++g_stat[SC_QIND_STAT_FRAMES];

    DWORD dlg  = ScStatDialog();
    DWORD root = dlg ? ScDlgRoot(dlg) : 0;
    if (root != g_dialog) {
        // A new dialog instance: every cached pointer belongs to the old one. Forget them
        // rather than dereference them. The wrapped interact pointers are among them --
        // dropping the list without restoring is correct here (the records are gone), and
        // WrapIconInteracts rebuilds it against the new dialog on this same frame.
        g_iconWrapN    = 0;
        g_iconDrawCtl  = 0;
        g_ownedIconN   = 0;
        ForgetUpgradeIcons();
        g_dialog       = root;
        g_spliced      = false;
        g_shown        = false;
        g_anchor       = 0;
        g_mode         = SC_QIND_NONE;
        g_text[0]      = '\0';
        g_dialogLogged = false;
        g_bandLogged   = false;
        // THE BASELINE BELONGS TO THE OLD DIALOG'S SURFACE. Its rect can match the new one
        // exactly -- the pane is laid out the same way every time -- so without this the
        // first read in a new dialog diffs live pixels against a copy of a buffer that is
        // gone. -1 ("no answer") is the only honest state here.
        g_baseValid    = false;
    }
    if (!root) return;

    // The trace wraps ALL FIVE icons, not only the one the plugin fills: the working case
    // (an icon whose ring slot is occupied) is the control against which the failing one
    // means anything.
    WrapIconInteracts(root);
    WrapLastIconDraw(root);

    ScQueueIndView v;
    ReadView(&v);

    // The fifth icon is the ENGINE's to draw (the phantom bracket around queueLayout ran
    // inside CallOrigDriver, before this line). What the frame path owns is the owned-icon
    // list and the game-thread snapshot, published from the settled post-layout state.
    if (v.selection <= 1 && v.overflow > 0 && v.hudPages <= 1) {
        DWORD unit = ScPortraitUnit();
        if (ScUnitPtrValid(unit)) PublishOwnedIcons(root, &v, unit);
        else g_ownedIconN = 0;
    } else {
        // No overflow behind the strip this frame -- so the plugin owns no slot either.
        // Same reason as the clear inside PublishOwnedIcons: the owned list must expire
        // with the state that created it, not outlive it.
        g_ownedIconN = 0;
    }
    {
        // Held research into icons 3..6 -- or all of them back down, which is what any
        // other state of the pane asks for (the sweep may already have hidden them; the
        // fill compares before it writes).
        DWORD unit = ScPortraitUnit();
        int want = 0;
        if (v.selection <= 1 && v.research && v.hudPages <= 1 && ScUnitPtrValid(unit)) {
            want = ScQueueIndUpgradeIcons(v.upgrades);
        }
        FillUpgradeIcons(root, unit, want);
    }
    SnapshotIcons(root);

    char want[sizeof(g_text)];
    int mode = ScQueueIndCompose(want, (int)sizeof(want), &v);

    // The portrait unit is the engine's own precondition for the pane holding anything at
    // all; without it the dispatcher hides every child and there is nothing to sit beside.
    if (mode != SC_QIND_NONE && !ScPortraitUnit()) mode = SC_QIND_NONE;

    DWORD anchor = mode != SC_QIND_NONE ? AnchorFor(root, mode) : 0;
    if (mode != SC_QIND_NONE && !anchor) mode = SC_QIND_NONE;

    if (mode == SC_QIND_NONE) {
        bool hidNow = false;
        if (g_shown) {
            ScCtrlHideVia(g_hide, (DWORD)&g_ctrl[0]);
            g_shown = false;
            RepaintUnder(root);
            ++g_stat[SC_QIND_STAT_HIDES];
            hidNow = true;
            ScLog("QIND hide (nothing to show: sel=%d overflow=%d bldgs=%d hudPages=%d)",
                  v.selection, v.overflow, v.buildings, v.hudPages);
        }
        g_mode = SC_QIND_NONE;
        // THE BASELINE: the pixels our line is measured against, taken on the game thread
        // for the same reason the icon snapshot is, and NOT ON THE FRAME WE HID ON.
        // RepaintUnder only marks the region dirty -- the paint is the dialog's own redraw
        // walk, which has not run when this returns -- so a copy taken now still holds OUR
        // OWN LINE and the next boxDiff reads 0 with the text plainly on the screen: a check
        // that fails at random (AGENTS.md § "Oracles: what counts as a read-back"). Every
        // later NONE frame is after the redraw, and the copy is retaken on each of them.
        if (g_spliced && !hidNow) {
            CaptureBaseline(root, (const short*)&g_ctrl[SC_BINDLG_OFF_BOUNDS]);
        }
        return;
    }

    if (!EnsureSpliced(root)) return;
    if (!g_dialogLogged) { ScQueueIndLogDialog("attach"); g_dialogLogged = true; }

    // The box, worked out fresh every frame: it is a function of the anchor, the string AND
    // the layout around it, and only the first two are cheap to notice changing.
    //
    // A REFUSED box is a real answer. The space this line needs may not be there, and the
    // indicator draws correctly or it does not draw at all, because a line the player cannot
    // read is worse than none.
    DWORD ind = (DWORD)&g_ctrl[0];
    short* b = ScDlgBounds(ind);
    short box[4];
    if (!PlaceOn(box, anchor, root, mode, (int)strlen(want))) {
        if (g_shown) {
            ScCtrlHideVia(g_hide, ind);
            g_shown = false;
            RepaintUnder(root);
            ++g_stat[SC_QIND_STAT_HIDES];
        }
        g_mode = SC_QIND_NONE;
        g_text[0] = '\0';
        return;
    }
    const bool boxMoved = (b[0] != box[0] || b[1] != box[1] ||
                           b[2] != box[2] || b[3] != box[3]);
    if (boxMoved) {
        // A badge that narrows ("+10" -> "+9") leaves its old left columns on the icon; the
        // icon's own repaint takes them away, and the badge is drawn back over it.
        if (g_shown && mode != SC_QIND_GROUP) ScCtrlUpdateVia(g_update, anchor);
        b[0] = box[0]; b[1] = box[1]; b[2] = box[2]; b[3] = box[3];
    }
    g_anchor = anchor;

    const bool moved   = boxMoved || (mode != g_mode);
    const bool changed = (strcmp(want, g_text) != 0);
    if (changed) {
        memcpy(g_text, want, sizeof(g_text) < sizeof(want) ? sizeof(g_text) : sizeof(want));
        g_text[sizeof(g_text) - 1] = '\0';
    }
    g_mode = mode;

    // Redraw when the text or the position changed, and re-show whenever the engine's own
    // hide-all sweep has taken the visible bit off us (which it does on every re-layout).
    const bool visible = (*(DWORD*)(ind + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE) != 0;
    // THE OTHER PLACE THE BASELINE IS TAKEN, without which the FIRST show of every dialog
    // reads -1: the copy in the hidden branch above needs a splice to have happened, and the
    // splice happens on the frame we first show, so a pane going straight from "nothing
    // queued" to "+4" never gets one. Here we are about to draw into a box we were NOT in
    // last frame, so the surface holds the pane WITHOUT our line. `!g_shown` is the whole
    // condition: shown last frame means the surface already holds our text, and a copy of
    // that would make the next boxDiff read 0.
    if (!g_shown) CaptureBaseline(root, b);
    if (changed || moved || !visible || !g_shown) {
        ScCtrlShowVia(g_show, ind);
        *(DWORD*)(ind + SC_BINDLG_OFF_FLAGS) |= SC_CTRL_FLAG_DRAWN;
        ScCtrlUpdateVia(g_update, ind);
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
    static DWORD tid = 0;
    ScThreadCheck("qind-driver", &tid);
    CallOrigDriver();
    ScQueueIndOnFrame();
}

// queueLayout's detour: the phantom bracket and NOTHING else. __stdcall(BinDlg* ctrl),
// RET 4, argument on the stack (read off the listing at 0x004268D8, sc_addresses.h) --
// so a plain stdcall C function preserves what the engine's callers expect, and pushing
// the argument again for the trampoline costs one dword.
typedef void (__attribute__((stdcall)) *ScQueueLayoutFn)(DWORD ctrl);

// Reentrancy guard for the bracket's save buffer. The save is a STATIC (g_phantomSaved), so
// a nested queueLayout entry while a bracket is open would clobber the outer save and the
// restore would write the wrong bytes back. No such nesting is known -- the layout is
// straight-line (its callees mark dirty regions, they do not re-dispatch layouts) and the
// bracket runs on one thread -- but "no known path" is an assumption, so the static is made
// safe under it being wrong: only the OUTERMOST entry applies and restores, an inner entry
// runs the original bare, and the event is logged loudly because it means this model of the
// function is wrong and someone should look.
static int g_layoutDepth = 0;

static void __attribute__((stdcall)) SC_GAME_ENTRY HkQueueLayout(DWORD ctrl) {
    static DWORD tid = 0;
    ScThreadCheck("qind-layout", &tid);
    ++g_layoutDepth;
    if (g_layoutDepth > 1) {
        static bool said = false;
        if (!said) {
            ScLog("QIND: queueLayout re-entered with a phantom bracket open (depth=%d) -- "
                  "the inner call runs UNBRACKETED and this model of the function is "
                  "wrong; investigate", g_layoutDepth);
            said = true;
        }
        if (g_hkLayout.installed) ((ScQueueLayoutFn)g_hkLayout.trampoline)(ctrl);
        --g_layoutDepth;
        return;
    }
    ScQueueIndPhantomApply();
    if (g_hkLayout.installed) ((ScQueueLayoutFn)g_hkLayout.trampoline)(ctrl);
    ScQueueIndPhantomRestore();
    --g_layoutDepth;
}

// Verified prologue -- ScHookInstall refuses to patch if memory disagrees. Bytes and window
// from a HookProbe dump of statDisplayDriver (FUN_004d93f0) against this binary:
//   0x004D93F0  A0 3C 72 59 00   MOV AL,[0x0059723C]   = 5 bytes / 1 instruction, absolute
//   (not PC-relative), so it relocates into the trampoline unchanged.
static const BYTE kPrologueDriver[] = { 0xA0, 0x3C, 0x72, 0x59, 0x00 };

// queueLayout 0x004268D0: PUSH EBP / MOV EBP,ESP / SUB ESP,0x20 = 6 bytes, 3 whole
// instructions, none PC-relative (dumped in sc_addresses.h beside SC_VA_QUEUE_LAYOUT).
static const BYTE kPrologueLayout[] = { 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x20 };

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

bool ScQueueIndEnabled(void) {
    return ScEnvFlag("SCPLUGIN_QUEUEIND", false);
}

void ScQueueIndInit(BYTE* moduleBase, bool enabled) {
    ScEngineSetModuleBase(moduleBase);
    g_enabled = enabled;
    g_show = g_hide = g_update = g_enable = NULL;
    g_testOrigDriver = NULL;
    g_testing  = false;
    g_dialog   = 0;
    g_spliced  = false;
    g_shown    = false;
    g_mode     = SC_QIND_NONE;
    g_anchor   = 0;
    g_text[0]  = '\0';
    g_dialogLogged = false;
    g_bandLogged   = false;
    g_iconsN = 0;
    g_iconWrapN = 0;
    g_ownedIconN = 0;
    ForgetUpgradeIcons();
    for (int i = 0; i < SC_QIND_UPGRADE_ICONS; ++i) {
        _snprintf(g_upgLabel[i], sizeof(g_upgLabel[i]), "%d ", i + 2);
        g_upgLabel[i][sizeof(g_upgLabel[i]) - 1] = '\0';
    }
    g_iconOrigFn = 0;
    g_phantomN = 0;
    g_phantomUnit = 0;
    g_ringGen = 0;
    g_clickTraceLines = 0;
    g_clickTrace = ScEnvFlag("SCPLUGIN_QIND_CLICKTRACE", false);
    if (g_clickTrace) {
        ScLog("QINDCLICK: click trace ON (%%SCPLUGIN_QIND_CLICKTRACE%%) -- every non-MOUSEMOVE "
              "event the engine hands a queue icon is logged, up to %d lines, and passed "
              "straight on to the engine's own handler", SC_QIND_CLICKTRACE_MAX);
    }
    memset(g_ctrl, 0, sizeof(g_ctrl));
    ScLog("QIND: %s (%%SCPLUGIN_QUEUEIND%%). Draws a \"+N\" over the last queue icon when "
          "the logical queue is longer than the strip can show, a \"N bldgs M queued\" "
          "line for a group, and held research into queue icons 3..6; engine-drawn text "
          "and icons, no new art.",
          enabled ? "ON" : "off");
}

int ScQueueIndInstall(void) {
    if (!g_enabled) return 0;
    // BOTH or NEITHER. The driver hook without the layout bracket leaves nothing lighting
    // the slot and nothing owning the click; the bracket without the driver hook is a lit
    // slot with no "+N" and no snapshot. A partial install rolls itself back and disables
    // the feature.
    if (!ScHookInstall(&g_hkDriver, "statDisplayDriver", ScRuntimeAddr(SC_VA_STAT_DISPLAY_DRIVER),
                       (void*)&HkStatDisplayDriver, 5,
                       kPrologueDriver, (int)sizeof(kPrologueDriver))) {
        ScLog("QIND: driver hook failed to install -- feature disabled");
        g_enabled = false;
        return 0;
    }
    if (!ScHookInstall(&g_hkLayout, "queueLayout", ScRuntimeAddr(SC_VA_QUEUE_LAYOUT),
                       (void*)&HkQueueLayout, (int)sizeof(kPrologueLayout),
                       kPrologueLayout, (int)sizeof(kPrologueLayout))) {
        ScLog("QIND: queueLayout hook failed to install -- rolling the driver hook back, "
              "feature disabled");
        ScHookRemove(&g_hkDriver);
        g_enabled = false;
        return 0;
    }
    return 1;
}

void ScQueueIndRemove(void) {
    ScHookRemove(&g_hkDriver);
    ScHookRemove(&g_hkLayout);
    // A phantom left in the ring survives its window only if the game thread died inside
    // queueLayout -- but restore is idempotent and cheap, so make unload leave the ring
    // clean unconditionally rather than reason about that.
    ScQueueIndPhantomRestore();
    UnwrapIconInteracts();
    UnwrapLastIconDraw();

    // Take the control back out of the dialog. Single dword writes, guarded reads because
    // the dialog may already be gone. Mid-game unload stays unsupported (the game thread
    // may be inside the detour), same policy as sc_circles and sc_hudrow.
    if (g_spliced && g_dialog && ScReadable(g_dialog + SC_BINDLG_OFF_FIRST_CHILD, 4)) {
        ScDlgRemoveChild(g_dialog, (DWORD)&g_ctrl[0]);
    }
    g_spliced = false;
    g_shown   = false;
}

void ScQueueIndLogStats(void) {
    if (!g_enabled) return;
    ScLog("QINDSTATS frames=%u shows=%u hides=%u splices=%u refused=%u "
          "phantom=%u phantomDirty=%u "
          "disableOnOwned=%u disableWithPress=%u pressKept=%u "
          "upgIconShows=%u upgIconHides=%u",
          g_stat[SC_QIND_STAT_FRAMES], g_stat[SC_QIND_STAT_SHOWS],
          g_stat[SC_QIND_STAT_HIDES], g_stat[SC_QIND_STAT_SPLICES],
          g_stat[SC_QIND_STAT_REFUSED],
          g_stat[SC_QIND_STAT_PHANTOM], g_stat[SC_QIND_STAT_PHANTOM_DIRTY],
          g_stat[SC_QIND_STAT_DISABLE_OWNED], g_stat[SC_QIND_STAT_DISABLE_PRESSED],
          g_stat[SC_QIND_STAT_PRESSKEPT],
          g_stat[SC_QIND_STAT_UPG_ICON_SHOWS], g_stat[SC_QIND_STAT_UPG_ICON_HIDES]);
    // The trace's own denominator: what it saw and what it dropped, so "no click event was
    // ever logged" and "the filter ate it" are different readings rather than one silence.
    if (g_clickTrace) {
        ScLog("QINDCLICKSTATS seen=%u logged=%u droppedMoves=%u droppedSweeps=%u "
              "droppedHidden=%u droppedOverCap=%u wrapped=%d engineFn=0x%08X",
              g_clickTraceSeen, g_clickTraceLines, g_clickTraceMoves, g_clickTraceSweeps,
              g_clickTraceHidden, g_clickTraceCapped, g_iconWrapN, (unsigned)g_iconOrigFn);
    }
}

// ---------------------------------------------------------------------------
// Test seam
// ---------------------------------------------------------------------------

void ScQueueIndTestBegin(BYTE* fakeModuleBase,
                         ScQueueIndCtlFn show, ScQueueIndCtlFn hide, ScQueueIndCtlFn update,
                         ScQueueIndCtlFn enable, ScQueueIndDriverFn origDriver) {
    ScQueueIndInit(fakeModuleBase, fakeModuleBase != NULL);
    g_show           = show;
    g_hide           = hide;
    g_update         = update;
    g_enable         = enable;
    g_testOrigDriver = origDriver;
    g_testing        = true;
    g_dialogLogged   = true;         // the fake tree's dump is not the evidence
    for (int i = 0; i < SC_QIND_STAT__COUNT; ++i) g_stat[i] = 0;
}

int         ScQueueIndCurrentMode(void) { QIndSessionSync(); return g_mode; }
const char* ScQueueIndCurrentText(void) { QIndSessionSync(); return g_text; }
bool        ScQueueIndIsSpliced(void)   { QIndSessionSync(); return g_spliced; }
bool        ScQueueIndIsShown(void)     { QIndSessionSync(); return g_shown; }
int         ScQueueIndStat(int which) {
    if (which < 0 || which >= SC_QIND_STAT__COUNT) return 0;
    return (int)g_stat[which];
}
