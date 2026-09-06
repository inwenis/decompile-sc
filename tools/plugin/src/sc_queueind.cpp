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
static ScHook g_hkLayout;   // queueLayout 0x004268D0 -- the phantom bracket (task 066)

// Test seam -- NULL means "call the real engine".
static ScQueueIndCtlFn    g_show          = NULL;
static ScQueueIndCtlFn    g_hide          = NULL;
static ScQueueIndCtlFn    g_update        = NULL;
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
static bool  g_dialogLogged = false;
static bool  g_bandLogged   = false;  // "the band is too small" said once per dialog

static unsigned g_stat[SC_QIND_STAT__COUNT];

// WHAT THE STRIP HELD when the GAME THREAD last left it, snapshotted at the end of the
// frame path. It exists because the observer thread cannot answer this question honestly:
// the strip's fields change INSIDE the driver call (under task 039 the layout re-greyed
// the filled slots and the plugin's hand-fill put them back microseconds later; under
// task 066 the engine's own layout writes them, mid-walk, with the phantom in the ring).
// Nothing is drawn in between -- the dialog is rendered later, by graphic layer 2 -- so
// the player never sees the intermediate state, but an asynchronous reader lands in it
// often enough to make a suite flaky (measured: the same assertion passed one run and
// failed the next). A snapshot taken by the thread that does the writing is coherent by
// construction.
struct QIconSnap { short icon; WORD mode; DWORD flags; DWORD grp; DWORD text; };
static QIconSnap g_icons[SC_STATQ_SLOTS];
static int       g_iconsN = 0;

// WHICH QUEUE ICONS THE PLUGIN IS HOLDING AN ITEM BEHIND, recorded by the GAME THREAD as it
// fills them and read by the interact shim (task 061 -- see the block above the shim) on
// that same thread, so it needs no locking. It is a list of CONTROL POINTERS rather than of
// display indices because the shim is handed a control and has to answer "is this one mine"
// without walking anything, on an event that arrives hundreds of times a second.
static DWORD g_ownedIcon[SC_STATQ_SLOTS];
static int   g_ownedIconN = 0;

static bool IsPluginOwnedIcon(DWORD ctrl) {
    for (int i = 0; i < g_ownedIconN; ++i) if (g_ownedIcon[i] == ctrl) return true;
    return false;
}

// THE BOX AS IT LOOKS WITH NOTHING OF OURS IN IT, and why a copy of it is kept at all.
//
// `ink` -- non-background bytes in a rect -- cannot answer "did our text draw" in THIS
// dialog, and the first live run of task 039 is what proved it: the probe reported
// refInk=1330 over a 38x35 queue icon, i.e. 1330 of 1330 bytes non-zero, and ink=448 of
// 448 inside the indicator's own box. The pane's own art is IN this surface, so every rect
// in it is saturated and `ink > 0` is true before anyone draws anything. Task 033's
// indicator assertion rested on that number for weeks.
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
// THE EPOCH TEST (sc_session.h) -- THE SEVENTH SURVIVOR, found by task 054's sweep and
// not in issue #67's inventory of six.
//
// Everything above belongs to ONE dialog in ONE game, and the ONLY thing that
// invalidates it is `root != g_dialog` in ScQueueIndOnFrame -- a comparison of two HEAP
// ADDRESSES. The engine builds the same dialogs in the same order every game, so the
// new game's status pane can land on the byte for byte same address as the old one's,
// and that test then says "same dialog" about a dialog this module has never seen.
//
// For the SPLICE that is already handled, and honestly: EnsureSpliced re-checks
// `InChain(root)` and drops g_spliced when our control is not actually in the new
// chain. For THE BASELINE it is not. `g_baseline` is a copy of the screen bytes under
// the indicator's box taken while the indicator was hidden, and `ScQueueIndBoxDiff` --
// the oracle that answers "did OUR pixels land", the one task 039 built precisely
// because an ink count cannot -- diffs live pixels against it. Carried across a game it
// diffs this game's surface against another game's, and it fails by producing a
// PLAUSIBLE NUMBER rather than by reading zero, which is the failure mode AGENTS.md
// says costs three tasks to notice.
//
// Nothing the player sees is wrong here; this is an ORACLE that can lie. That is a
// weaker consequence than the other six and it is adopted anyway, for the reason the
// same rulebook gives: when an instrument turns out to be blind, every place it is
// load-bearing gets audited in the same sitting.
static unsigned g_session = 0;

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
    g_baseValid    = false;
    g_baseRect[0] = g_baseRect[1] = g_baseRect[2] = g_baseRect[3] = 0;
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
// as "no answer" rather than as zero.
//
// sc_hudrow asks for this too -- its own box has to be taller than the font or the engine
// refuses to draw it -- which is why the answer is exported rather than kept private.
int ScQueueIndSmallFontHeight(void) {
    if (!ScEngineModuleBase()) return 0;
    DWORD f = *(DWORD*)ScRuntimeAddr(SC_VA_FONT_SMALLEST);
    if (!ScReadable(f, SC_FONT_OFF_HEIGHT + 1)) return 0;
    return (int)*(BYTE*)(f + SC_FONT_OFF_HEIGHT);
}

static int SmallFontHeight(void) { return ScQueueIndSmallFontHeight(); }

static int OverflowOf(DWORD unit) {
    int n = ScProdQueueOverflowCount(unit);   // -1 when the building is not tracked
    return n > 0 ? n : 0;
}

// ---------------------------------------------------------------------------
// THE PHANTOM BRACKET (task 066) -- make queueLayout see the slots the plugin holds
// items behind as OCCUPIED, for exactly the length of its own call.
//
// Task 061 proved the last-slot click dies because the plugin and the engine FIGHT over
// the DISABLED bit: queueLayout greys every slot whose ring entry is 0xE4, the plugin's
// re-lighting made the engine's next disableControl a live call instead of a no-op, and
// that call's dwUser=6 event clears a player's PRESSED bit mid-click (every fill provoked
// exactly one disable -- 1153974 = 1153974, measured). Task 066 then killed the two
// bit-level fixes: restoring PRESSED was measured rescuing 110,381 presses in one click
// and still cancelling nothing (PR #95), and never clearing DISABLED draws the slot
// through ticon.pcx remap row 4 -- the disabled colours, 14 of 16 entries away from the
// lit row (the icon blit 0x00456C30 tests exactly flag 0x2 at 0x00456C42).
//
// So the fight is not fought at all. The pre-hook writes the held item's type into the
// empty ring slot; queueLayout then takes its OCCUPIED branch -- grp/icon/mode/type from
// its own globals, the slot label, enableControl -- and the post-hook puts 0xE4 back the
// instant it returns. No disable is ever provoked (enableControl early-outs once the slot
// is lit), no dwUser=6 exists to clear a press, and the slot the player clicks is
// byte-for-byte a vanilla occupied slot at input time: the hit test reads VISIBLE, the
// press/activate cycle reads PRESSED, and FUN_004573A0 emits {0x20, k} through the
// engine's own code. sc_prodqueue's cancel-icon branch (task 039, never reachable until
// now) serves the command, because at command-processing time the ring slot is empty.
//
// WHY THE WINDOW CANNOT BE OBSERVED, rather than merely was not (the conductor's binding
// constraint on this design):
//   * It opens and closes inside ONE call frame on the thread that runs queueLayout, so
//     no same-thread reader -- the Train-button gate, the tick, the cancel handlers, the
//     AI, every drawer -- can interleave with it. That every engine reader of the ring IS
//     on that thread is classified reader-by-reader in research/production-queue.md 8.8,
//     and holds structurally: the engine's own ring mutations (productionTick's and
//     cancelBuildQueueSlot's multi-store compactions) are unsynchronised, so a reader on
//     another thread would have observed torn rings in VANILLA.
//   * The two readers that genuinely are on other threads -- this plugin's observer
//     (PRODQ/PRODQSEL, STATQ) and the test harness -- read g_ringGen around the ring
//     (seqlock: odd = open, changed = straddled) and retry, so a phantom can never reach
//     a log line either. THREADCHECK lines measure the whole claim live: every hooked
//     game-side site logs its thread id once, and the suite asserts they are one id.
//
// The writes themselves are the two bare stores the plugin already makes elsewhere
// (capture/promote, sc_prodqueue 6.3): no resource global, no AI mirror, no event. The
// saved value is restored VERBATIM rather than assumed 0xE4, and a slot that turns out
// non-empty is REFUSED and counted (PHANTOM_DIRTY) rather than overwritten.
static WORD          g_phantomSaved[SC_BUILD_QUEUE_SLOTS];
static BYTE          g_phantomSlot[SC_BUILD_QUEUE_SLOTS];
static int           g_phantomN    = 0;
static DWORD         g_phantomUnit = 0;
static volatile LONG g_ringGen     = 0;

unsigned ScQueueIndRingGen(void) { return (unsigned)g_ringGen; }

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

// One line per SITE, on the first call and on any CHANGE -- a changed id is the
// single-thread claim breaking and must be loud, not deduplicated away.
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
        // The strip has five icons. The ones past the engine's ring are drawn from the
        // plugin's overflow (by the engine itself, via the phantom bracket -- task 066),
        // so what is left UNDRAWN is whatever the logical queue holds past those five.
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

// A ring length the OBSERVER can trust. The guarded section is EXACTLY the five word
// reads and nothing else -- the first version guarded a whole ReadView (selection walk,
// overflow scan, upgrade scan included), and at the layout's real call rate (~40k/s,
// measured phantom=21M over 9.5min) eight retries of a section that long straddled a
// window EVERY time: run 2's [14] arm consumed an engineLen of 5 from a line whose own
// ringStable said 0. Narrow section + 32 tries makes a settle failure a real anomaly.
// On the game thread the generation is even and unmoving, so this is one extra load.
static int CoherentEngineLen(DWORD unit, int* stable) {
    for (int attempt = 0; attempt < 32; ++attempt) {
        unsigned g1 = ScQueueIndRingGen();
        if (g1 & 1) continue;
        int n = ScUnitQueueLength(unit);
        if (ScQueueIndRingGen() == g1) { if (stable) *stable = 1; return n; }
    }
    if (stable) *stable = 0;
    return ScUnitQueueLength(unit);
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

// Spliced at the TAIL of the child list. The CREATE-time binder skips it either way (index
// <= 0) and the engine's hide-all sweeps hide it like any child wherever it sits, so the
// end of the list costs nothing -- and it is the end that decides whether the text is on
// top of what it overlays.
//
// THIS USED TO BE THE HEAD, with a comment claiming "being drawn from our own frame tail
// keeps its text on top". That is the wrong model of when pixels land, and it is task
// 039's second defect -- the user's "some text ... but it was behind the buildings icons".
// What CallUpdate reaches (updateControl 0x0041C400) does not paint: it intersects the
// control's rect with the dialog's and merges the result into the screen's dirty region
// (its tail is 0x0041C200, which snaps the rect to a 16px grid and clamps it into the
// globals at 0x0051A16C..). The paint is the dialog's own redraw walk at 0x0041C683,
// which takes the children from `[dlg+0x42]` and steps `[esi]` -- head to tail, clearing
// each control's DRAWN bit as it queues it (0x0041C754) -- so a control drawn EARLIER is
// a control drawn UNDER. At the head of the list, our text was painted first and every
// engine control that overlapped it painted over it, in the same frame, every frame.
static bool EnsureSpliced(DWORD root) {
    DWORD ind = (DWORD)&g_ctrl[0];
    if (g_spliced && !InChain(root)) g_spliced = false;   // same-address dialog realloc
    if (g_spliced) return true;

    // AND THE OTHER DIRECTION, which the line above does not cover: we think we are NOT
    // spliced but our control is already in this chain. Appending it again is not a
    // duplicate, it is a CYCLE -- the memset below zeroes g_ctrl's `next`, the tail walk
    // then ends ON g_ctrl, and the append writes g_ctrl->next = g_ctrl. The engine's
    // redraw walk (0x0041C683) follows `next` to the end of the list, so a self-link is
    // an infinite loop inside the game's own paint, not a cosmetic bug.
    //
    // It was unreachable while the ONLY thing that cleared g_spliced was a dialog whose
    // address had changed -- a different chain by definition. Task 054 added a second
    // clearer (the game-session epoch), so "cleared but still linked" stopped being
    // impossible by construction, and this makes it impossible by test instead. Adopting
    // an existing link is also the correct answer on its own terms: the control IS in the
    // chain, so the invariant the flag records is already true.
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

    memset(g_ctrl, 0, sizeof(g_ctrl));
    ScDlgMakeStaticText(ind, root, SC_QIND_CTRL_ID, g_text, tInteract, tUpdate);
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
//   * too SHORT and the engine draws nothing at all (research/status-pane-text.md 5 --
//     the defect that made sc_hudrow's page indicator invisible for weeks);
//   * too NARROW and it draws a TRUNCATION, which is worse than nothing because it reads
//     as a working feature. Measured in a live group run before this was fixed: a box
//     22px wide clamped to one wireframe button, holding "4 bldgs  4 queued".
// So the width is computed from the string rather than from the anchor. SC_QIND_CHAR_W is
// a deliberate over-estimate of the small font's advance -- over-reserving costs nothing
// (the box is a clip rect, not a fill), under-reserving costs the tail of the string.
//
// Writes into the CALLER'S four shorts rather than straight into the control, because the
// answer is recomputed every frame: the group band is a function of which buttons are
// VISIBLE, and that changes with the size of the selection without the line's text
// necessarily changing (a seventh building that is not producing adds a row of buttons and
// not a word). The caller compares, and only then moves the control and redraws.
static bool PlaceOn(short* b, DWORD anchor, DWORD root, int mode, int textLen) {
    short* a = ScDlgBounds(anchor);
    short left = (short)(a[0] + SC_QIND_INSET_X);
    short top  = (short)(a[1] + SC_QIND_INSET_Y);
    int   want = textLen * SC_QIND_CHAR_W;
    if (want < SC_QIND_BOX_W) want = SC_QIND_BOX_W;

    if (mode == SC_QIND_GROUP) {
        // BELOW THE ROW, NOT ON IT. This line used to start at the first wireframe
        // button's own top-left, which put ~120 pixels of text straight across the top row
        // of unit icons -- the user, on the deployed build: "there was some text printed in
        // the spot where the 12 icons are saying sth about a queue but it was behind the
        // buildings icons so couldn't rly tell". Painting it on top instead of under it
        // (the tail splice, above) makes it visible; it does not make it READABLE, because
        // the pixels underneath are unit wireframes. The pane has a band the multi-select
        // branch leaves empty -- everything else in it belongs to the single-select layout
        // and is hidden here -- and that band is where a line of text belongs.
        //
        // Measured off the LIVE row every time, never from the numbers a dump once showed:
        // the twelve buttons are two rows of six and only their own rects say where the
        // lower one ends. (AGENTS.md, task 034: an enumeration that scanned for a NAME is
        // not exhaustive -- here, a constant that was read off one install is not a layout.)
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

        top  = (short)(rowBottom + SC_QIND_BAND_GAP);
        left = (short)rowLeft;
        int right  = left + want;
        if (right > surfW - 1) right = surfW - 1;
        int bottom = top + SC_QIND_BOX_H;
        if (bottom > surfH) bottom = surfH;

        // The rule the engine's own draw applies (SC_VA_DRAW_STRING: it refuses outright
        // when `top + fontHeight > clip.bottom`, and the clip box is these bounds), checked
        // against the FONT'S OWN height rather than against a constant. A band too short is
        // the failure that draws nothing while every other read-back says the indicator is
        // fine -- so it is refused here, loudly, instead of being discovered by a player.
        const int fontH = SmallFontHeight();
        if (bottom - top < (fontH > 0 ? fontH : SC_QIND_BAND_MIN_H) ||
            right - left < want) {
            if (!g_bandLogged) {
                ScLog("QIND: the band below the row is (%d,%d,%d,%d) on a %dx%d surface -- "
                      "too small for \"%d chars\" at fontH=%d; the group line is suppressed",
                      left, top, right, bottom, surfW, surfH, textLen, fontH);
                g_bandLogged = true;
            }
            return false;
        }
        b[0] = left; b[1] = top;
        b[2] = (short)right;
        b[3] = (short)bottom;
    } else if (mode == SC_QIND_UPGRADE) {
        // "+N upg" runs longer than STRIP's "+N" (up to "+16 upg", 7 chars), and the icon
        // it starts on (id 6) is only ~38px wide -- clamping to it the way STRIP does would
        // TRUNCATE the string, which the warning above this function already paid for once
        // in the GROUP case. A researching building's five queue icons are all idle
        // placeholders (nothing is in its production ring), so running the box past icon
        // 6's own bounds does not clip anything the engine actually drew there; RepaintUnder
        // repaints the whole strip for this mode for the same reason it repaints the whole
        // row for GROUP.
        int right = left + want;
        int surfW = 0;
        DWORD d = SurfaceOf(root);
        if (d) surfW = (int)*(WORD*)(d + SC_SURFACE_OFF_W);
        // SLIDE IT LEFT rather than clamp the right edge. Icon 6 starts at x=231 on the
        // live 270-wide pane, so "+2 upg" (42px at SC_QIND_CHAR_W) already runs 4px past
        // the surface and a clamp would have TRUNCATED it -- the failure this file warns
        // about twice above, because a cut string reads as a working feature. Found by
        // this task's fixture once the fake pane grew the real surface (task 037 shipped
        // with the clamp; nothing else about that mode changes here).
        if (surfW > 0 && right > surfW - 1) {
            int shift = right - (surfW - 1);
            if (left - shift < 0) shift = left;
            left  -= (short)shift;
            right -= shift;
        }
        if (right - left < want) return false;
        b[0] = left; b[1] = top;
        b[2] = (short)right;
        b[3] = (short)(top + SC_QIND_BOX_H);
    } else {
        // A "+N" is short and belongs inside the icon it annotates: staying within a
        // control the engine repaints is what guarantees our pixels are painted over when
        // the indicator goes away.
        b[0] = left; b[1] = top;
        b[2] = (short)(left + want > a[2] ? a[2] : left + want);
        b[3] = (short)(top + SC_QIND_BOX_H > a[3] ? a[3] : top + SC_QIND_BOX_H);
    }
    return true;
}

// Which control the indicator hangs off, per mode:
//   STRIP   -- the LAST queue icon (id 6). While the plugin holds overflow it keeps the
//              engine's ring at four, so that icon is precisely the one drawn empty.
//   UPGRADE -- the SAME icon (id 6). A researching building's ring is not producing units
//              at all, so every one of the five queue icons sits idle and greyed -- the
//              last one is free for exactly the reason it is free in the STRIP case, and
//              reusing it needs no second anchor point.
//   GROUP   -- the first wireframe button (id 0x21). The line no longer sits ON that button
//              (see PlaceOn) -- the button is where the ROW's geometry is read from, and it
//              is what RepaintUnder asks the engine to redraw.
//
// task 037: SC_QIND_UPGRADE had no case here. ScQueueIndCompose could return it all day --
// and hooktest's own composer test did exactly that -- but with no anchor, ScQueueIndOnFrame
// read the null return as "nothing to show" and reset the mode to SC_QIND_NONE before ever
// attempting a splice, on every building, in every real game. Nothing in this function or
// its caller looks at the unit's type, so the fix could not be Engineering-Bay-specific.
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

// The user, playing the deployed build: "when i queue more then 5 units the 5'th slot is
// emtpy". It is: task 025 keeps the engine's ring at SC_PRODQ_ENGINE_HOLD = 4 so the client
// keeps sending Train commands (research/production-queue.md 5.2), so the engine's own
// layout queueLayout (0x004268D0) has only four items to draw and greys the fifth. The
// FEATURE is right and the ring must stay at four; the DISPLAY is what is wrong.
//
// HOW THE SLOT GETS FILLED MOVED, twice, and both former mechanisms are dead:
//   * task 033/039 wrote the five fields queueLayout writes for an occupied slot BY HAND
//     here (grp/icon/mode/type/label) and cleared DISABLED to light the slot. The missing
//     grp was 039's user-visible bug, and the bit-clearing was 061's: every fill made the
//     engine's next disableControl a live call whose dwUser=6 event destroyed the player's
//     own click (research/production-queue.md 8.6).
//   * task 066 deleted all of it. The PHANTOM BRACKET around queueLayout itself (see
//     ScQueueIndPhantomApply above) makes the engine see the slot as occupied and write
//     every field with its own code -- so there is nothing left here to hand-write, no
//     flag to clear, and no fight for the engine to win.
//
// What remains on the frame path is PUBLICATION, not painting: which icons are the
// plugin's (for the interact shim's counters and the suite's `owned=`), and the
// game-thread snapshot of what the strip holds (for the observer, which must never read
// the engine's mid-layout state).
static void PublishOwnedIcons(DWORD root, const ScQueueIndView* v, DWORD unit) {
    const int drawable = ScQueueIndDrawableSlots(v);

    // WHICH SLOTS ARE OURS, rebuilt every fill by the thread that does the filling. The
    // shim reads it to decide whose press to protect, and it has to be re-derived rather
    // than accumulated: an item promoted into the ring hands its icon back to the engine,
    // and protecting a press on a slot the engine now owns would be changing vanilla
    // behaviour for no reason.
    //
    // BUILT INTO A LOCAL AND PUBLISHED IN ONE WRITE, count LAST. The first version cleared
    // `g_ownedIconN` and refilled it in place, which put a window -- hundreds of times a
    // second -- where the list read EMPTY while this function was running. The observer
    // duly sampled it: `owned=` read 0 in 48 of 68 QIND lines of one run. Nothing was
    // provably wrong on the game thread, and that is exactly the complaint: a torn value
    // cannot tell you whether the thing it measures was true, which is the disease task 039
    // wrote three paragraphs about and this is the same file doing it again. Count last
    // because a reader that sees the count sees entries that were written before it.
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

    // The snapshot, taken after the fill, by the thread that did it.
    g_iconsN = 0;
    DWORD sc = ScDlgFindChild(root, SC_STATQ_FIRST_CONTROL);
    for (int k = 0; k < SC_STATQ_SLOTS && sc; ++k, sc = ScDlgNext(sc)) {
        DWORD su = *(DWORD*)(sc + SC_BINDLG_OFF_USER);
        QIconSnap* q = &g_icons[g_iconsN++];
        q->flags = *(DWORD*)(sc + SC_BINDLG_OFF_FLAGS);
        q->icon  = su ? *(short*)(su + SC_STATUSER_OFF_ICON) : -1;
        q->mode  = su ? *(WORD*) (su + SC_STATUSER_OFF_MODE) : 0;
        q->grp   = su ? *(DWORD*)(su + SC_STATUSER_OFF_GRP)  : 0;
        q->text  = *(DWORD*)(sc + SC_BINDLG_OFF_TEXT);
    }
}

// ---------------------------------------------------------------------------
// WHY A CLICK ON THE FILLED SLOT DID NOTHING, AND THE ONE THING THIS SHIM PUTS BACK
// (task 061 -- the user, on the deployed build: "i can cancel a queue unit by clicking it,
// but it doesn't work if i click the last slock when it has our extra +x text")
//
// It was never the "+N". Measured, in a real game, before any of this was written:
//
//   * NO Cancel Train command reaches queueCommand at all -- 0 x `CMD id=0x20` for a click
//     on that slot, while the card's Cancel and a middle icon both emit normally;
//   * a click INSIDE the icon but OUTSIDE our text box does not emit either, so the text
//     control does not own those pixels (and could not: the hit test 0x00418340 takes the
//     FIRST child that accepts dwUser=4, our LSTATIC type refuses that code outright, and
//     the icons come before it in the chain anyway).
//
// What the icons are actually handed says the rest. Same run, same dialog, one working
// control and one failing control, from the trace below:
//
//   idx=3  type=14 dwUser=4  flags=0x00000419   <- hit test accepts
//   idx=3  type=4            flags=0x00000419   <- LBUTTONDOWN
//   idx=3  type=14 dwUser=4  flags=0x40000419   <- PRESSED armed, and it STAYS armed
//   idx=3  type=5            flags=0x40000419   <- LBUTTONUP, still armed
//   idx=3  type=14 dwUser=2  flags=0x00000499   <- ACTIVATE -> {0x20,1} on the wire
//
//   idx=6  type=14 dwUser=6  flags=0x0000041B disabled=1     x1474 in 13 seconds,
//   idx=6  type=14 dwUser=6  flags=0x0000041B disabled=1     ~180k more over the cap
//
// dwUser=6 is what `disableControl` (0x00418640) sends after it sets the DISABLED bit, and
// type 2's handler for it is `AND [ctrl+0x18],0xBFFFFFFF` -- CLEAR PRESSED. So:
//
//   1. queueLayout greys every slot whose ring entry is 0xE4. Display 4's ring entry is
//      empty BY DESIGN -- task 025 holds the engine's ring at four so the client keeps
//      sending Train -- so it is greyed on every layout pass.
//   2. The task-039 hand-fill (deleted by task 066) cleared that bit directly to light
//      the slot.
//   3. Which means the engine's NEXT disableControl is no longer the no-op it is in
//      vanilla: it disables again AND SENDS dwUser=6.
//   4. Round and round, hundreds of times a second (the fill counter measured our side
//      of the same fight: 371834 in one run).
//   5. A player's mouse-down arms PRESSED. Two milliseconds later a dwUser=6 clears it.
//      The mouse-up 60ms later finds nothing armed, so no ACTIVATE, no statusCtrlActivate,
//      no command. The other four icons hold occupied ring slots, are never disabled, and
//      cancel normally -- which is exactly the shape the user reported.
//
// THE FIX IS NOT HERE. Task 066's phantom bracket around queueLayout (ScQueueIndPhantomApply,
// far above) removes the disable AT ITS SOURCE: the engine lays the owned slot out as
// occupied and calls enableControl, so no dwUser=6 is ever sent and there is no press to
// rescue. Two bit-level fixes died before it and are recorded so nobody rebuilds them:
// restoring PRESSED across the disable event was measured rescuing 110,381 presses in one
// click and still cancelling nothing, with the press latched forever (PR #95 4); leaving
// DISABLED set draws the slot through ticon.pcx remap row 4, the disabled colours (task
// 066's static read of 0x00456C30 -- the row differs from the lit one in 14 of 16 entries).
//
// What stays below is the MEASUREMENT: `disableOnOwned` is now the fix's tripwire. Pre-fix
// it moved EXACTLY once per click, deterministically (PR #95's paired rows); with the
// bracket holding it must not move at all. A suite asserts the pair -- the phantom counter
// moving, this one still -- which is what separates "the fix is active" from "the race was
// won" on a green arm.
//
// ---------------------------------------------------------------------------
// CLICK TRACE (task 061) -- what the ENGINE hands each queue icon, at the instant it
// hands it over.
//
// The user cannot cancel the last queue slot while our "+N" is on it, and one in-game run
// established which half of the problem it is: NO Cancel Train command reaches
// queueCommand at all (0 x `CMD id=0x20`), and a second run showed the same for a click
// INSIDE the icon but OUTSIDE our text box -- so the "+N" control does not own those
// pixels and the icon itself is refusing.
//
// "Refusing" is still two things -- the hit test never returns this control, or it does
// and the press/activate sequence stops somewhere after -- and the only honest way to tell
// them apart is to watch what the control is actually sent. So each icon's interact
// POINTER (control+0x2A, plain dialog-heap data, no code patched -- the same mechanism
// sc_hudrow's page gesture uses on the twelve wireframe buttons) is wrapped with a shim
// that logs the event and tail-calls the engine's own handler. It changes no behaviour:
// every event goes on to exactly the function it would have reached.
//
// WHAT IT DROPS, AND WHY EACH ONE. The first version of this trace logged every
// non-MOUSEMOVE event and hit its 400-line cap 35 seconds into the run, in the MENUS,
// before a single click -- so the run cost a game and answered nothing:
//
//   QINDCLICK ctrl=0x090C8D78 idx=2 type=14 dwUser=8 flags=0x00000410 visible=0 ...   x5
//   ... the same five lines again 100ms later, and again, 400 lines deep
//
// MOUSEMOVE (type 3) arrives thousands of times a second. `dwUser=8` is a periodic sweep
// the engine sends all five icons about ten times a second whether anything happened or
// not. And an INVISIBLE control cannot be under anybody's cursor. None of the three can
// carry the answer, and together they are the entire flood -- so all three are dropped and
// each drop is COUNTED, because a filtered trace that does not say what it filtered is a
// count over an unknown denominator.
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
    // MEASURES ONLY. There WAS a fix here -- restore the PRESSED bit the engine's disable
    // event clears on a slot the plugin owns -- and it is reverted, because the run that
    // could finally attribute it showed it does not work AND does active harm:
    //
    //     across the click: disableOnOwned +136382, disableWithPress +110381,
    //                       pressKept +110381
    //     FAIL exactly one 0x20 reached queueCommand (0)
    //     FAIL minerals go up by exactly one Probe's 50 (2600 -> 2600)
    //
    // The collision is real and the restore worked on every one of 110,381 of them, and no
    // command was emitted. Restoring the press is NOT sufficient. Worse, `pressKept` kept
    // climbing for the six seconds between the two readings of a SIXTY MILLISECOND click
    // (end of run: 807134 of 1153974 disable events arrived with a press in flight) --
    // i.e. the press never came back down. The mouse-up never clears it, which is the same
    // fact as "the up never reaches 0x004E19F0", the handler that both clears the press and
    // emits the ACTIVATE. Putting the bit back just holds the button down forever.
    //
    // WHERE THE NEXT ATTEMPT STARTS, and it is one function: `0x00418830`, called on
    // button-down with the hit control, sends it a `dwUser=5` "can you take focus" query
    // and records `[dlg+0x3e] = ctrl` ONLY if the control returns non-zero. The dialog's
    // focused control is what the button-up is routed to. The trace shows that query
    // reaching our icon (`idx=6 type=14 dwUser=5 flags=0x00000418` at 12:39:05.008), so
    // what it ANSWERS is the open question, not whether it is asked.
    //
    // AND THE THING THAT INVALIDATES SINGLE-RUN CONCLUSIONS ABOUT ANY OF THIS: the click is
    // a RACE, and both builds have only ever been sampled one run at a time --
    //
    //     pre-fix,  trace off : no cancel (3 clicks)      pre-fix,  trace ON : CANCELLED
    //     post-fix, trace off : CANCELLED                 post-fix, trace ON : no cancel
    //
    // The instrument flips the outcome in BOTH directions, which is incoherent as a cause,
    // so the variable is timing. Anything that claims this is fixed has to click N times
    // and assert the RATE; a single click is the check-that-fails-at-random AGENTS.md rates
    // no better than one that cannot fail.
    //
    // The counters below stay because they are what established all of the above, and they
    // cost one compare on an event the engine sends anyway.
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
// plain ink count is not. Rows 0..SC_QIND_SLOT_LABEL_ROWS are skipped because the engine
// draws each slot's NUMBER there and the numbers legitimately differ ("1 " against "5 ").
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
    for (int y = SC_QIND_SLOT_LABEL_ROWS; y < bh; ++y) {
        const BYTE* ra = (const BYTE*)(bits + (DWORD)((r[0][1] + y) * w + r[0][0]));
        const BYTE* rb = (const BYTE*)(bits + (DWORD)((r[1][1] + y) * w + r[1][0]));
        for (int x = 0; x < bw; ++x) if (ra[x] != rb[x]) ++diff;
    }
    return diff;
}

// Walk a rect of the dialog surface. `fn` is inlined by hand twice below rather than
// abstracted: the two callers want different things out of the same bounds check.
//
// `maxBytes <= 0` means "no size limit". The cap used to be SC_QIND_BASELINE_MAX
// unconditionally, which silently made this module's own buffer the size limit for every
// caller -- including sc_hudrow, whose band is wider. Each caller now states its own.
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
    // bracket (task 066) makes non-empty for the length of each queueLayout call on the
    // game thread. ReadView retries its ring reads against the seqlock (CoherentEngineLen,
    // tight section) and reports whether they settled; `ringStable=0` on the printed line
    // means every retry straddled a window -- the ring-derived numbers on the line are
    // then suspect, which the reader is told rather than left to discover.
    ScQueueIndView v;
    int ringStable = ReadView(&v);

    int ink = linked ? ScQueueIndSurfaceInk(root, b[0], b[1], b[2], b[3]) : -1;

    // THE POSITIVE CONTROL for that number. `ink=0` has two readings -- "we drew nothing"
    // and "the probe cannot see this surface" -- and only one of them is a bug, so the same
    // probe is run over a rect the ENGINE fills: the first queue icon (id 2), which draws a
    // unit portrait whenever anything is queued. A run where refInk is 0 as well says the
    // probe is blind and its verdict on the indicator means nothing (AGENTS.md: prove the
    // pattern positive somewhere it should match, before trusting it where it should not).
    //
    // AND IT HAS TO BE A CONTROL THAT IS ACTUALLY UP. The first queue icon is hidden in a
    // multi-building selection -- the engine draws the wireframe row instead -- so using it
    // there would report refInk=0 and read as "the probe is blind" on every group frame.
    // The reference is therefore the first VISIBLE of (queue icon 2, wireframe button
    // 0x21), and the line says which one it used.
    //
    // AND IT DOES NOT FALL BACK TO A HIDDEN ONE. Ink over a control nobody can see answers
    // neither question this number is for, so a pane where no candidate is up reports -1 and
    // that stays a failure wherever a visible reference is required. `surfInk` below is the
    // number that answers "is the probe blind" in EVERY state, including that one.
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

    // CAN THE PROBE READ THIS SURFACE AT ALL -- the only liveness question that has an answer
    // in every state, the drained pane included. Whole surface, deliberately: the pane's own
    // art covers it, which is the same fact that makes `ink` useless as an oracle and makes
    // this number a good blindness check. A live surface is never 0 here, so 0 or -1 says the
    // read failed and every other number on this line is worthless.
    const int surfInk = ScQueueIndSurfaceInk(root, 0, 0, 0x7FFF, 0x7FFF);

    // THE SCREEN-LEVEL CHECK ON THE FIFTH ICON, and the reason it is a DIFFERENCE rather
    // than a count. Ink inside the "+N" box cannot say whether the indicator drew: the box
    // sits inside an icon the engine fills, so the icon's own pixels are inside it and the
    // number can never be 0 (task 033 asserted exactly that, and it passed while this
    // module was drawing the wrong art). Slots 0 and 4 are the same size (38x35) and the
    // engine gives BOTH the same border graphic 2 (queueLayout 0x00426A0D: graphic 4 only
    // for k in 1..3), so when the queue holds five of one type the two rects are the same
    // picture -- and every byte that differs below the label row is something this plugin
    // put there. Three states, three readings, one number:
    //   a wrong GRP  -> hundreds of bytes differ (different art entirely);
    //   text drawn UNDER the icon -> 0 (the icon painted over it);
    //   text drawn ON TOP -> the glyph, tens of bytes.
    int slotDiff = ScQueueIndSlotDiff(root, 0, SC_STATQ_SLOTS - 1);

    // The two GRPs the engine picks between, so every `art` letter below is decidable
    // against the engine's own globals rather than against a number this file remembers.
    const DWORD grpIcons = *(DWORD*)ScRuntimeAddr(SC_VA_GRP_CMDICONS);
    const DWORD grpBtns  = *(DWORD*)ScRuntimeAddr(SC_VA_GRP_CMDBTNS);

    // The strip as the game thread last left it (see g_icons), per slot:
    // `icon:mode:state:art:label`. `art` is I when the slot draws from the ICON grp (what
    // an occupied slot must draw from), B when it still points at the button-BORDER grp
    // the engine leaves behind on an EMPTY slot -- task 039's bug, and the field the old
    // line could not show -- and ? for neither. `label` is 1 when the slot carries the
    // number the engine draws on every occupied icon. A frame index alone cannot say
    // which PICTURE is on the screen; the frame index and the GRP together can.
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
          "phantom=%u phantomDirty=%u ringGen=%u ringStable=%d",
          t, g_mode, linked ? 1 : 0,
          (flags & SC_CTRL_FLAG_VISIBLE) ? 1 : 0, live,
          linked ? b[0] : 0, linked ? b[1] : 0, linked ? b[2] : 0, linked ? b[3] : 0, ink,
          refInk, refId, surfInk, slotDiff, ScQueueIndBoxDiff(root), SmallFontHeight(), icons,
          v.selection, v.engineLen, v.overflow, v.upgrades, v.buildings, v.queued,
          v.hudPages, (unsigned)g_anchor,
          // `owned` is how many queue icons the plugin is holding an item behind right now.
          // `disableOnOwned` is the fix's TRIPWIRE (task 066): pre-fix the engine's disable
          // landed on an owned slot exactly once per click; with the phantom bracket it must
          // not move at all while `phantom` climbs. A suite reads both either side of a
          // click -- which is what stops the regression arm passing for some reason other
          // than the fix.
          g_ownedIconN,
          g_stat[SC_QIND_STAT_DISABLE_OWNED], g_stat[SC_QIND_STAT_DISABLE_PRESSED],
          g_stat[SC_QIND_STAT_PRESSKEPT],
          g_stat[SC_QIND_STAT_PHANTOM], g_stat[SC_QIND_STAT_PHANTOM_DIRTY],
          ScQueueIndRingGen(), ringStable);
}

// One line per child of the statdata dialog. This is the answer to "which controls in this
// pane are engine-drawn text, and where are the free pixels" read off the LIVE dialog on
// THIS install, which is what hud-selection-row.md 10 listed as an open question.
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
        // can still be dispatched by different code, and when one of them takes a click and
        // the other does not, that pointer is the first thing worth ruling out -- one line
        // instead of an argument about dispatch (task 061).
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
    // OUR OWN BOX FIRST, and it is the half that matters now the group line has left the
    // buttons. updateControl takes the rect from the control it is given, so calling it on
    // the (now hidden) indicator is what puts the band it was using back into the dirty
    // region -- and a hidden control draws nothing, so what lands there is whatever the
    // dialog paints under it. Repainting only the anchor would strand the line on the
    // surface the moment it was not sitting on an engine control any more.
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
    // "+N upg" can run past icon 6 into the space above icons 2..5 too (see PlaceOn), so
    // the same reasoning applies: repaint the whole strip, not just the icon it started on.
    } else if (g_mode == SC_QIND_UPGRADE && root) {
        DWORD c = ScDlgFindChild(root, SC_STATQ_FIRST_CONTROL);
        for (int i = 0; i < SC_STATQ_SLOTS && c; ++i, c = ScDlgNext(c)) {
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
        g_ownedIconN   = 0;
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
        // first read in a new dialog would diff live pixels against a copy taken from a
        // buffer that no longer exists. -1 ("no answer") is the only honest state here.
        g_baseValid    = false;
    }
    if (!root) return;

    // The trace wraps ALL FIVE icons, not only the one the plugin fills: the working case
    // (an icon whose ring slot is occupied) is the control against which the failing one
    // means anything. Off unless %SCPLUGIN_QIND_CLICKTRACE% is set.
    WrapIconInteracts(root);

    ScQueueIndView v;
    ReadView(&v);

    // The fifth icon is the ENGINE's to draw now (the phantom bracket around queueLayout
    // ran inside CallOrigDriver, before this line). What the frame path still owns is the
    // owned-icon list and the game-thread snapshot, published from the settled post-layout
    // state.
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
        // THE BASELINE: the pixels our line will be measured against, taken here on the game
        // thread for the same reason the icon snapshot is.
        //
        // NOT ON THE FRAME WE HID ON. RepaintUnder only marks the region dirty -- the paint
        // is the dialog's own redraw walk, which has not run yet when this returns -- so a
        // copy taken now would still hold OUR OWN LINE, and the next boxDiff would read 0
        // with the text plainly on the screen. That is a check failing at random, which
        // AGENTS.md rates no better than one that cannot fail. Every later NONE frame is
        // after the redraw, and the copy is retaken on each of them.
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
    // A REFUSED box is a real answer. The space this line needs may not be there -- and the
    // task that fixed this module said so in as many words: the indicator draws correctly or
    // it does not draw at all, because a line the player cannot read is worse than none.
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
    if (boxMoved) { b[0] = box[0]; b[1] = box[1]; b[2] = box[2]; b[3] = box[3]; }
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
    // THE OTHER PLACE THE BASELINE IS TAKEN, and without it the FIRST show of every dialog
    // reads -1. The copy in the hidden branch above needs a splice to have happened, and the
    // splice happens on the frame we first show -- so a pane that goes straight from "nothing
    // queued" to "+4" would never have had one taken. Here we are about to draw into a box we
    // were NOT in last frame, so what is on the surface right now is the pane WITHOUT our
    // line, which is exactly the copy we want. `!g_shown` is the whole condition: if we were
    // shown last frame the surface already holds our text, and a copy of that would make the
    // next boxDiff read 0.
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

// Reentrancy guard for the bracket's save buffer. The save is a STATIC (g_phantomSaved),
// so a nested queueLayout entry while a bracket is open would clobber the outer save and
// the restore would write the wrong bytes back. No such nesting is known -- the layout is
// straight-line (its callees mark dirty regions, they do not re-dispatch layouts) and the
// bracket runs on one thread -- but "no known path" is an assumption, and this makes the
// static safe under it being wrong: only the OUTERMOST entry applies and restores, an
// inner entry runs the original bare, and the event is logged loudly because it means the
// model of this function is wrong and someone should look.
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
// from HookProbe against this binary
// (work/scratch/033/hookprobe/statDisplayDriver.FUN_004d93f0.asm):
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
    g_bandLogged   = false;
    g_iconsN = 0;
    g_iconWrapN = 0;
    g_ownedIconN = 0;
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
          "the logical queue is longer than the strip can show, and a \"N bldgs M queued\" "
          "line for a group; engine-drawn text, no new art.",
          enabled ? "ON" : "off");
}

int ScQueueIndInstall(void) {
    if (!g_enabled) return 0;
    // BOTH or NEITHER. The driver hook without the layout bracket is task 061's fight all
    // over again (nothing lights the slot any more, but nothing owns the click either);
    // the bracket without the driver hook is a lit slot with no "+N" and no snapshot. A
    // partial install rolls itself back and disables the feature.
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
    // iconsFilled= and noGrp= left this line with task 066: the hand-fill they counted is
    // deleted (the phantom bracket makes the ENGINE draw the slot), so nothing increments
    // them any more, and a printed count no code path can move is the task-030 defect.
    ScLog("QINDSTATS frames=%u shows=%u hides=%u splices=%u refused=%u "
          "phantom=%u phantomDirty=%u "
          "disableOnOwned=%u disableWithPress=%u pressKept=%u",
          g_stat[SC_QIND_STAT_FRAMES], g_stat[SC_QIND_STAT_SHOWS],
          g_stat[SC_QIND_STAT_HIDES], g_stat[SC_QIND_STAT_SPLICES],
          g_stat[SC_QIND_STAT_REFUSED],
          g_stat[SC_QIND_STAT_PHANTOM], g_stat[SC_QIND_STAT_PHANTOM_DIRTY],
          g_stat[SC_QIND_STAT_DISABLE_OWNED], g_stat[SC_QIND_STAT_DISABLE_PRESSED],
          g_stat[SC_QIND_STAT_PRESSKEPT]);
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
                         ScQueueIndDriverFn origDriver) {
    ScQueueIndInit(fakeModuleBase, fakeModuleBase != NULL);
    g_show           = show;
    g_hide           = hide;
    g_update         = update;
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
