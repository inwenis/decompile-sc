// sc_hudrow.cpp -- see sc_hudrow.h.
//
// PAGE MODEL. The shadow list arrives from sc_fanout ordered overflow-first,
// visible-last. The DISPLAY list reorders it live-visible-first, then live overflow,
// so page 1 is always the engine's own <=12 units and a selection change snaps back
// to it. Liveness is HP>0 plus a uniqueness match (UnitAlive), NOT uniqueness alone,
// which death does not change (selection-circles.md 4.5): a dead unit leaves the
// display list on the next dispatch, never shown or clickable for longer than a frame.
//
// WHAT THE ENGINE SEES while a page is displayed: the 12 buttons' statUser records
// (the bytes the engine's own layout function writes), their interact POINTERS
// (control+0x2A, restored on the way back to stock), the dirty/all-hidden bytes the
// engine's own click handlers also write, and one spliced text control using the
// engine's per-type default handlers. Sprites are never touched -- there is no path
// from here to CSprite::selectionIndex or flag 0x08.

#include <windows.h>
#include <stdio.h>
#include <string.h>

#include "sc_addresses.h"
#include "sc_engine.h"
#include "sc_fanout.h"
#include "sc_hook.h"
#include "sc_hudrow.h"
#include "sc_log.h"
#include "sc_queueind.h"
#include "sc_session.h"
#include "sc_unit.h"

#define HUD_MAX 256

static bool  g_enabled = false;

static ScHook g_hkDispatch;
static ScHook g_hkWireDraw;
static unsigned g_statBlank = 0;   // wireframe draws handed the empty sheet

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

static DWORD g_disp[HUD_MAX];
static int   g_dispN     = 0;
static int   g_page      = 0;
static int   g_pageCount = 1;
static bool  g_flipPending = false;

// Latched when our shadow list diverges from the engine's own selection with NO new
// commit behind it -- an engine-side removal (transport load, mind control, archon
// merge, trigger RemoveUnit) that sc_fanout's version counter never saw, or a click
// the gate rejected. While latched the row HANDS BACK TO STOCK and does not page, so
// the engine shows its own truth with no per-frame churn. Cleared only by the next
// selection commit (a version bump), which rebuilds a consistent shadow.
static bool  g_diverged = false;

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

// ---------------------------------------------------------------------------
// THE BAND BELOW THE ROW, and the two copies that say whether our line is on it
// ---------------------------------------------------------------------------
// Ceiling for a copy of the band: the pane is 270 wide on this install (measured, QINDDLG)
// and the box is SC_QIND_BOX_H tall, so 270*16 is the most this can ever need.
#define SC_HUD_BAND_MAX 4352

// `clean` is that rect with none of our line on it; `inked` is the same rect once the redraw
// walk that paints the text has run. The bytes where the two differ are the ones our text
// owns, and that mask is what makes both of this module's screen-level readings honest
// (BandDiff, BandStranded). Neither is an ink count, and that is the point -- see LogReadback.
static BYTE  g_bandClean[SC_HUD_BAND_MAX];
static BYTE  g_bandInked[SC_HUD_BAND_MAX];
static BYTE  g_bandCand[SC_HUD_BAND_MAX];      // "has it stopped changing yet" candidate
static BYTE  g_bandNow[SC_HUD_BAND_MAX];       // scratch for a live read; game thread only
static int   g_bandCleanN = 0;                 // bytes held, 0 = no copy for this rect
static int   g_bandInkedN = 0;
static int   g_bandCandN  = 0;
static DWORD g_bandCandAt = 0;                 // tick the candidate was last seen to CHANGE
static DWORD g_bandPollAt = 0;                 // next tick a poll is allowed (see BandStable)
static short g_bandRect[4] = { 0, 0, 0, 0 };   // the rect BOTH copies are of
static bool  g_indShowing  = false;            // our line is on (or bound for) the surface
static bool  g_wasPaged    = false;            // the previous call took the paged path
static bool  g_bandTooSmall = false;           // "it does not fit" said once per dialog
static bool  g_bandPending  = false;           // a hand-back is waiting to be measured
static unsigned g_statSuppressed = 0;          // calls the band refused to hold the line
static unsigned g_statEpisodes   = 0;          // times the row ENTERED paged mode -- COVERAGE

// THE PAINT-LATENCY DIAGNOSTIC, a pair rather than a bare count. This detour runs tens
// of thousands of times a second, so a seven-digit "dispatcher calls" total is
// indistinguishable from a global tick read by mistake, and a wrong number in a log is
// worse than no number because a reader reasons from it (AGENTS.md § "Diagnostics and
// reporting"). The one call count reported is DIVIDED BY ITS OWN ELAPSED MILLISECONDS at
// the moment the inked copy lands: `N calls / M ms` is self-checking arithmetic, and it is
// the evidence for gating the band copies on a clock rather than on call counts.
static unsigned g_showCalls  = 0;              // paged calls since the last show
static DWORD    g_showTick   = 0;
static bool     g_inkedLogged = false;         // that pair is worth one line per run

// HOW LONG THE SURFACE IS GIVEN TO SETTLE, in milliseconds, and why this is a CLOCK and not
// a count of dispatcher calls. Do not gate on "the next dispatcher call": the detour does
// NOT run once per rendered frame. Measured over one 40-second run, this module took
// 1,659,828 paged calls and 20,681,359 stock ones -- tens of thousands per second -- so the
// next call is almost always THE SAME painted frame, the copy comes out identical to the one
// before it, and the glyph mask is empty. An empty mask makes `stranded=0` meaningless.
// 100 ms is about six frames at 60 Hz.
#define SC_HUD_BAND_SETTLE_MS 100
// And the poll is throttled, because the alternative is copying two kilobytes tens of
// thousands of times a second on the GAME thread. ~16 ms is GetTickCount's own resolution.
#define SC_HUD_BAND_POLL_MS   16

// Both are overridable through the test seam ONLY, and the offline test sets them to zero:
// it has no engine and no real clock between frames, so a wall-clock window there would
// measure the harness rather than this module. The SEQUENCE the windows enforce -- copy, see
// it unchanged, only then trust it -- still holds at zero, because it takes two polls.
static int g_bandSettleMs = SC_HUD_BAND_SETTLE_MS;
static int g_bandPollMs   = SC_HUD_BAND_POLL_MS;

static unsigned g_statActs    = 0;   // act runs that displayed a page
static unsigned g_statStock   = 0;   // act runs deferred to the engine
static unsigned g_statFlips   = 0;
static unsigned g_statStale   = 0;   // dead units dropped from the display list
static unsigned g_statWraps   = 0;
static unsigned g_statSplices = 0;
static unsigned g_statDiverged = 0;  // times the row handed back on engine divergence
static unsigned g_statGated    = 0;  // clicks the gate swallowed (stale unit)

// ---------------------------------------------------------------------------
// Engine primitives, through the seam
// ---------------------------------------------------------------------------

typedef int (__attribute__((fastcall)) *EngineInteractFn)(DWORD, DWORD);
static int CallEngineInteract(DWORD ctrl, DWORD evt) {
    EngineInteractFn fn = g_engineInteract
        ? (EngineInteractFn)g_engineInteract
        : (EngineInteractFn)ScRuntimeAddr(SC_VA_WIREFRAME_BTN_INTERACT);
    return fn(ctrl, evt);
}

// The original dispatcher, through the trampoline. No arguments, returns void.
typedef void (*OrigDispatchFn)(void);

static void CallOrigDispatch(void) {
    if (g_testOrigDispatch) { g_testOrigDispatch(); return; }
    if (g_hkDispatch.installed) ((OrigDispatchFn)g_hkDispatch.trampoline)();
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

// Is this still the same, LIVING unit it was at capture?
//
// Two independent things can invalidate a captured unit and CUnit+0xA5 alone catches
// only ONE: research/selection-circles.md 4.5 (byte-level verified) proves 0xA5 is
// bumped by slot REUSE (0x004A0320, unit (re)init) and NOT by death, which runs
// 0x004A0740 without touching it. So a uniqueness mismatch means the slot was recycled,
// and hitpoints == 0 (CUnit+0x08, driven to 0 by the DAMAGE primitive 0x004797B0 --
// research/command-opcodes.md 6) catches a damage death whose slot is not reused yet.
// The OTHER removal paths (transport load, mind control, archon merge, trigger
// RemoveUnit) leave HP and 0xA5 untouched and are handled structurally instead: the
// divergence latch (ScHudRowOnDispatch) and the click gate (ClickUnitValid).
static bool UnitAlive(const ScShadowInfo* u) {
    if (!u->unit) return false;
    if (ScUnitUniqueness(u->unit) != u->uniqueness) return false;
    return ScUnitHitPoints(u->unit) != 0;
}

// Is a clicked wireframe unit safe to hand to the engine's Select? It must be one we
// are currently displaying (so we hold its captured uniqueness), NOT recycled, NOT dead
// (HP>0), and STILL IN PLAY (reachable in its player's unit list). That closes the
// DANGEROUS exposure -- a stale/freed CUnit* reaching CMDACT_Select where its tag would
// pass the receive-side uniqueness check. A unit that passes but has left OUR selection
// (loaded, mind-controlled) is still a live, identity-correct CUnit* and harmless to
// select; the divergence latch stops the row from offering it.
static bool ClickUnitValid(DWORD unit) {
    if (!unit) return false;
    BYTE captured = 0; bool known = false;
    for (int i = 0; i < g_cacheN; ++i) {
        if (g_cache[i].unit == unit) { captured = g_cache[i].uniq; known = true; break; }
    }
    if (!known) return false;                                        // not a shown unit
    if (ScUnitUniqueness(unit) != captured) return false;  // recycled
    if (ScUnitHitPoints(unit) == 0) return false;         // dead
    return ScUnitInOwnPlayerList(unit);                                           // in play
}

// ---------------------------------------------------------------------------
// Shadow refresh + display list
// ---------------------------------------------------------------------------

// Is this engine-held unit one WE already know to be dead? Death is our own liveness
// verdict (UnitAlive) applied to the entry we captured, so a unit we are not tracking
// counts as live -- it is a genuine difference and must be allowed to diverge.
static bool EngineSlotLive(DWORD unit) {
    for (int i = 0; i < g_n; ++i) {
        if (g_list[i].unit == unit) return g_alive[i] != 0;
    }
    return true;
}

// Does the engine's own client selection (clientSelectionGroup, 0x00597208, walked to
// the sentinel 0x597238) still match the visible tail of our shadow list, as a SET? The
// engine mutates that group on death and on some selection edits WITHOUT going through
// CMDACT_Select, so sc_fanout's version counter never moves; this catches those.
//
// BOTH SIDES ARE FILTERED FOR LIVENESS, and that is the point of the function rather
// than a detail. The engine zeroes hitPoints in its damage primitive 0x004797B0 and
// clears the unit out of clientSelectionGroup on a LATER path, so for at least one
// frame a dead unit is still IN the engine's list while our tail has dropped it.
// Comparing a live-filtered tail against an unfiltered engine list reads that ordinary
// skew as an engine-side removal, and the latch is permanent until the next commit, so
// one frame of it strands the row on stock -- a page of corpses -- for the rest of the
// selection. Filtering both sides with the SAME test cancels an ordinary death out and
// still detects what the latch exists for: a LIVE unit dropped without a commit.
static bool EngineSelectionMatchesVisible(void) {
    DWORD eng[SC_HUD_BUTTON_COUNT];
    int engN = 0;
    DWORD* slot = (DWORD*)ScRuntimeAddr(SC_VA_CLIENT_SELECTION_GROUP);
    for (int i = 0; i < SC_HUD_BUTTON_COUNT; ++i) {
        if (slot[i] && EngineSlotLive(slot[i]) && engN < SC_HUD_BUTTON_COUNT) {
            eng[engN++] = slot[i];
        }
    }
    const int overflowN = g_n - g_vis;
    int visN = 0;
    for (int i = overflowN; i < g_n; ++i) if (g_alive[i]) ++visN;
    if (visN != engN) return false;
    for (int e = 0; e < engN; ++e) {
        bool found = false;
        for (int i = overflowN; i < g_n && !found; ++i) {
            if (g_alive[i] && g_list[i].unit == eng[e]) found = true;
        }
        if (!found) return false;
    }
    return true;
}

// THE EPOCH TEST (sc_session.h). This module's whole page state is derived: the display
// list, the page number, the slot cache, the divergence latch and the dialog pointers all
// describe ONE selection in ONE game, and a counter that moves on a selection COMMIT
// cannot see a game change -- a load commits nothing, so the counter holds still and the
// previous game's page survives until the player's first click. sc_fanout bumps its
// version when the epoch moves, which alone is sufficient; this stays because the dialog
// pointers below belong to a console the new game RE-CREATES and must be dropped on a
// game change whatever the selection did, and making that depend on another module's
// counter would be the same mistake one level up.
static unsigned g_session = 0;
static unsigned g_statSessionDrop = 0;

static void HudRowSessionSync(void) {
    const unsigned now = ScSessionEpoch();
    if (g_session == now) return;
    if (g_n > 0 || g_dispN > 0 || g_page > 0 || g_dialog != 0) {
        ScLog("HUDROW session %u -> %u: dropping the page state (%d listed, %d shown, "
              "page %d, dialog 0x%08X) -- it describes a game that has ended",
              g_session, now, g_n, g_dispN, g_page + 1, (unsigned)g_dialog);
        ++g_statSessionDrop;
    }
    g_verValid   = false;
    g_n = g_vis = g_dispN = 0;
    g_page       = 0;
    g_pageCount  = 1;
    g_cacheValid = false;
    g_cacheN     = 0;
    g_diverged   = false;
    g_flipPending = false;
    // A new game re-creates the console, so every pointer here names a control that is
    // gone. ScHudRowOnDispatch re-splices when it next sees an unrecognised dialog.
    g_dialog     = 0;
    g_wrapCount  = 0;
    g_indSpliced = false;
    g_indText[0] = '\0';
    g_rectsLogged = false;
    g_session = now;
}

// Returns true when the display list holds more than 12 live units. Sets *selChanged when
// the shadow version moved OR the engine's own selection diverged from our visible tail,
// *death when a listed unit died since the last refresh -- all three snap back to page 1.
static bool RefreshShadow(bool* selChanged, bool* death) {
    HudRowSessionSync();
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

    // A real new commit (version bump) heals any divergence -- the shadow is fresh.
    // Otherwise a mismatch against the engine's own visible selection is an engine-side
    // removal CMDACT_Select never reported: LATCH so the dispatcher hands back to stock.
    if (changed) {
        g_diverged = false;
    } else if (n > 0 && !EngineSelectionMatchesVisible()) {
        g_diverged = true;
    }

    if (changed || died) {
        g_page = 0;
        g_cacheValid = false;
    }

    // Live visible units (the shadow tail) first, then live overflow -- see PAGE MODEL.
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

int ScHudRowOnButtonEvent(DWORD ctrl, DWORD evt) {
    // The dialog framework delivers the RAW mouse event to the control under the cursor
    // with its type intact -- 0x00418EB0 groups cases 4/6/7/9 and tail-calls control+0x2A
    // (hud-selection-row.md 5.1). A right-click arrives as event->type == 7 and the stock
    // button interact ignores it, which is what makes the gesture free to claim.
    if (g_enabled && evt) {
        // The click gate below reads g_cache to decide whether the unit under the
        // cursor is one WE are displaying, so it must not be answering out of the
        // previous game's cache.
        HudRowSessionSync();
        WORD type = *(WORD*)(evt + SC_EVT_OFF_TYPE);

        if (type == SC_EVT_RBUTTONDOWN && g_pageCount > 1) {
            g_page = (g_page + 1) % g_pageCount;
            g_flipPending = true;
            *(BYTE*)ScRuntimeAddr(SC_VA_STAT_DIRTY) = 1;
            ++g_statFlips;
            ScLog("HUDROW flip -> page %d/%d", g_page + 1, g_pageCount);
            return 1;
        }

        // THE CLICK GATE. An ACTIVATE (a completed click) is where the stock handler
        // 0x00458220 would put the button's statUser CUnit* into a Select command. While
        // we are paging, a displayed OVERFLOW unit can have been removed from play by a
        // path the divergence check cannot see (trigger RemoveUnit, archon-consumed --
        // neither touches clientSelectionGroup). Validate FIRST: if it is not a live,
        // in-play, non-recycled unit, SWALLOW the click and latch diverged, which bounds
        // the dangerous exposure to zero regardless of removal path and leaves the
        // corpse-display window cosmetic-only.
        if (type == SC_EVT_TYPE_USER && g_wrapCount > 0 &&
            *(DWORD*)(evt + SC_EVT_OFF_USER) == SC_USER_ACTIVATE) {
            DWORD su = *(DWORD*)(ctrl + SC_BINDLG_OFF_USER);
            DWORD unit = su ? *(DWORD*)(su + SC_STATUSER_OFF_UNIT) : 0;
            if (!ClickUnitValid(unit)) {
                ScLog("HUDROW click gate: unit 0x%08X is not live/in-play -- click "
                      "swallowed, handing back to stock", (unsigned)unit);
                g_diverged = true;
                *(BYTE*)ScRuntimeAddr(SC_VA_STAT_DIRTY) = 1;
                ++g_statGated;
                return 1;                         // swallow: engine never sees it
            }
        }
    }
    return CallEngineInteract(ctrl, evt);
}

static int __attribute__((fastcall)) SC_GAME_ENTRY
HudBtnInteractShim(DWORD ctrl, DWORD evt) {
    return ScHudRowOnButtonEvent(ctrl, evt);
}

// (Re)wrap the 12 buttons' interact pointers. Idempotent, and called from every paged act
// run, which is what survives the engine re-binding them at dialog CREATE.
static void EnsureWrapped(DWORD firstBtn) {
    const DWORD engineFn = ScRuntimeVa(SC_VA_WIREFRAME_BTN_INTERACT);
    const DWORD shim     = (DWORD)&HudBtnInteractShim;
    g_wrapCount = 0;
    DWORD c = firstBtn;
    for (int i = 0; i < SC_HUD_BUTTON_COUNT && c; ++i, c = ScDlgNext(c)) {
        DWORD* interact = (DWORD*)(c + SC_BINDLG_OFF_INTERACT);
        if (*interact == engineFn) { *interact = shim; ++g_statWraps; }
        // Record every button that now points at the shim, whether this run
        // wrapped it or an earlier one did -- the restore path walks this list.
        if (*interact == shim && g_wrapCount < SC_HUD_BUTTON_COUNT) {
            g_wrapBtn[g_wrapCount++] = c;
        }
    }
}

// Restore the wrapped interact pointers by walking the CURRENT dialog's own button
// chain -- never g_wrapBtn, whose cached addresses can be into freed heap after a
// same-address dialog realloc (root == g_dialog, so the new-dialog reset never fired).
// Walking the live chain validates membership by construction: only a button actually
// linked into `root` is touched. `root == 0` means the dialog is gone: drop the state.
static void Unwrap(DWORD root) {
    if (root) {
        const DWORD engineFn = ScRuntimeVa(SC_VA_WIREFRAME_BTN_INTERACT);
        const DWORD shim     = (DWORD)&HudBtnInteractShim;
        DWORD c = ScDlgFindChild(root, SC_HUD_FIRST_SMALL_BUTTON);
        for (int i = 0; i < SC_HUD_BUTTON_COUNT && c; ++i, c = ScDlgNext(c)) {
            DWORD* interact = (DWORD*)(c + SC_BINDLG_OFF_INTERACT);
            if (*interact == shim) *interact = engineFn;
        }
    }
    g_wrapCount = 0;
}

// ---------------------------------------------------------------------------
// The indicator control
// ---------------------------------------------------------------------------

// Is the indicator actually linked into this root's child chain? g_indSpliced goes stale
// when the engine frees the dialog and allocates a NEW one at the SAME address, which the
// root==g_dialog check cannot see; walk the chain rather than trust the flag.
static bool IndicatorInChain(DWORD root) {
    DWORD ind = (DWORD)&g_indCtrl[0];
    for (DWORD c = ScDlgChild(root); c; c = ScDlgNext(c)) if (c == ind) return true;
    return false;
}

// Spliced at the TAIL of the child list. The CREATE-time handler binder skips it either way
// (index <= 0) and the engine's hide-all sweep hides it wherever it sits -- but the END of the
// list is what decides whether the text lands ON TOP of what it overlaps.
//
// Do not splice at the HEAD on the theory that drawing last in our act keeps the text on
// top: CallUpdate reaches updateControl 0x0041C400, which does not paint -- it merges the
// control's rect into the screen's dirty region. The PAINT is the dialog's own redraw walk
// at 0x0041C683, which takes the children from [dlg+0x42] and steps [esi] head to tail, so
// a control drawn EARLIER is drawn UNDER. At the head this text is painted first and the
// twelve wireframes paint over it, in the same frame, every frame -- invisible, not merely
// hard to read (the measurement that proves it is in LogReadback).
static bool EnsureSpliced(DWORD root) {
    DWORD ind = (DWORD)&g_indCtrl[0];
    // Re-splice if we think we are spliced but are not actually in the chain
    // (same-address dialog realloc).
    if (g_indSpliced && !IndicatorInChain(root)) g_indSpliced = false;
    if (g_indSpliced) return true;

    // Runtime evidence guard for the type: the engine must have a real interact AND update
    // handler for SC_CTRL_TYPE_LSTATIC in the default tables. If either is null this build
    // does not dispatch that type the way BWAPI's enum says, so refuse to splice rather than
    // hand the dialog a control it cannot draw. The row still pages, without an indicator.
    DWORD tInteract = 0, tUpdate = 0;
    ScDlgDefaultHandlers(SC_CTRL_TYPE_LSTATIC, &tInteract, &tUpdate);
    if (!tInteract || !tUpdate) {
        ScLog("HUDROW: no engine handler for control type %d (interact=0x%08X "
              "update=0x%08X) -- indicator suppressed", SC_CTRL_TYPE_LSTATIC,
              (unsigned)tInteract, (unsigned)tUpdate);
        return false;
    }
    memset(g_indCtrl, 0, sizeof(g_indCtrl));
    // The box is positioned and the band copied before anything is shown (see
    // IndicatorFrame), which is why ScDlgMakeStaticText leaves it not-visible.
    ScDlgMakeStaticText(ind, root, (short)0xFFE0, g_indText, tInteract, tUpdate);
    if (!ScDlgAppendChild(root, ind)) {
        ScLog("HUDROW: child list longer than %d -- indicator splice refused",
              SC_MAX_CTRLS_WALK);
        return false;
    }
    g_indSpliced = true;
    ++g_statSplices;
    return true;
}

// Take the line off the surface: hide it, then ask the engine to repaint the rect it was
// using. A box in a band that belongs to NO control has to ask for its own repaint, and
// updateControl on our own (now hidden) control is the ask: a hidden control draws nothing,
// so what lands in that rect is whatever the dialog paints under it -- the same reason as
// sc_queueind's RepaintUnder.
static void HideIndicator(void) {
    if (!g_indSpliced) { g_indShowing = false; return; }
    DWORD ind = (DWORD)&g_indCtrl[0];
    ScCtrlHideVia(g_hide, ind);
    ScCtrlUpdateVia(g_update, ind);
    g_indShowing = false;
}

// THE LONGEST LINE THIS SELECTION CAN PRODUCE -- what the box is sized for, not the line
// currently on it. Sizing to the current string would move the right edge on a page flip
// whose digits grow ("1-12" -> "13-24"), and the band copies are copies of a RECT, so a
// moved box leaves the oracle with no baseline on exactly the flip it exists to measure.
// The LAST page carries the biggest numbers, so it decides the width.
static int IndicatorWidestLen(void) {
    char buf[sizeof(g_indText)];
    const int lastStart = (g_pageCount - 1) * SC_HUD_BUTTON_COUNT + 1;
    _snprintf(buf, sizeof(buf) - 1, "%d units  %d-%d  (%d/%d)",
              g_dispN, lastStart, g_dispN, g_pageCount, g_pageCount);
    buf[sizeof(buf) - 1] = '\0';
    return (int)strlen(buf);
}

// WHERE THE LINE GOES, and why it is not on the buttons.
//
// Do not start it at the first button's own top-left: that is INSIDE the icon row, across
// the wireframes, where the row paints over the text and it reads as absent.
//
// The pane has exactly one band no control occupies: below the row's lower buttons. It is
// measured off the LIVE row every frame rather than taken from a constant -- a constant read
// off one install is not a layout -- and off ALL TWELVE button rects
// rather than the visible ones. That last part is where this differs from sc_queueind's
// PlaceOn, deliberately: the row is a fixed 12-slot grid whose rects come from statdata.bin,
// a last page can light as few as ONE button, and a box that moved between pages would throw
// its baseline away on every flip.
static bool PlaceIndicator(short* box, DWORD root, DWORD firstBtn, int textLen) {
    int surfW = 0, surfH = 0;
    if (!ScQueueIndSurfaceSize(root, &surfW, &surfH) || surfW <= 0 || surfH <= 0) return false;

    short* fb = ScDlgBounds(firstBtn);
    int rowLeft = fb[0], rowBottom = fb[3];
    DWORD c = firstBtn;
    for (int i = 0; i < SC_HUD_BUTTON_COUNT && c; ++i, c = ScDlgNext(c)) {
        short* b = ScDlgBounds(c);
        if (b[0] < rowLeft)   rowLeft   = b[0];
        if (b[3] > rowBottom) rowBottom = b[3];
    }

    int want = textLen * SC_QIND_CHAR_W;
    if (want < SC_QIND_BOX_W) want = SC_QIND_BOX_W;
    // Refused loudly and once when the band cannot hold the string (ScQueueIndPlaceBand
    // says why): a nine-pixel box passes every non-pixel check while drawing nothing.
    int fontH = 0;
    if (!ScQueueIndPlaceBand(rowLeft, rowBottom + SC_QIND_BAND_GAP, want, surfW, surfH,
                             box, &fontH)) {
        if (!g_bandTooSmall) {
            ScLog("HUDROW: the band below the row is (%d,%d,%d,%d) on a %dx%d surface -- too "
                  "small for %d chars at fontH=%d, so the page indicator is SUPPRESSED "
                  "(never drawn back onto the buttons)",
                  box[0], box[1], box[2], box[3], surfW, surfH, textLen, fontH);
            g_bandTooSmall = true;
        }
        return false;
    }
    return true;
}

// Invalidate every copy: whatever rect they were of, they are not of THIS one.
static void BandForget(void) {
    g_bandCleanN = 0;
    g_bandInkedN = 0;
    g_bandCandN  = 0;
    g_bandPollAt = 0;
}

// HAS THE BAND STOPPED CHANGING? Polled at most every SC_HUD_BAND_POLL_MS, true only once the
// rect has read byte-identical for SC_HUD_BAND_SETTLE_MS. That is the honest way to ask "has
// the redraw walk run": updateControl only marks a region dirty, the paint happens later, and
// this detour cannot see the walk -- but it can see the walk's RESULT stop moving. On success
// the settled bytes are in g_bandCand, so the caller copies from there rather than taking a
// fresh (and possibly already-changed) read.
static bool BandStable(DWORD root) {
    const DWORD now = GetTickCount();
    if (g_bandPollAt && (int)(now - g_bandPollAt) < 0) return false;
    g_bandPollAt = now + (DWORD)g_bandPollMs;

    const int n = ScQueueIndCopyRect(root, g_bandRect, g_bandNow, SC_HUD_BAND_MAX);
    if (n <= 0) { g_bandCandN = 0; return false; }
    if (n != g_bandCandN || memcmp(g_bandNow, g_bandCand, (size_t)n) != 0) {
        memcpy(g_bandCand, g_bandNow, (size_t)n);
        g_bandCandN  = n;
        g_bandCandAt = now;
        return false;                                   // still moving
    }
    return (int)(now - g_bandCandAt) >= g_bandSettleMs;
}

// THE INDICATOR, once per paged frame -- not from FillPage, which runs only when the PAGE
// changes: the band's copies are a three-frame sequence, so on a quiet frame a copy that has
// to be taken "the frame after" would never be taken at all.
//
// THE SEQUENCE:
//   1. position the box off the live row; a refusal HIDES and draws nothing;
//   2. with no clean copy for this rect, take one -- but only on a paged frame that FOLLOWS
//      a paged frame, showing nothing until it is taken. updateControl only dirties, so on
//      the fill frame the surface still holds the PREVIOUS layout and a copy there would
//      make every later reading count that change as well as our text. Two paged frames
//      (~80 ms) of the row without its caption is invisible and is what makes it exact;
//   3. write the text and show it, remembering which frame that was;
//   4. on a LATER frame -- never the show frame, whose paint has not run yet -- take the
//      inked copy, which is the pane WITH our line on it.
// Returns true when it changed something worth logging.
static bool IndicatorFrame(DWORD root, DWORD firstBtn) {
    short box[4];
    if (!PlaceIndicator(box, root, firstBtn, IndicatorWidestLen())) {
        ++g_statSuppressed;
        if (g_indShowing) { HideIndicator(); BandForget(); return true; }
        return false;
    }
    if (!EnsureSpliced(root)) return false;

    DWORD  ind = (DWORD)&g_indCtrl[0];
    short* ib  = ScDlgBounds(ind);
    const bool moved = (ib[0] != box[0] || ib[1] != box[1] ||
                        ib[2] != box[2] || ib[3] != box[3]);
    if (moved) {
        // Hide FIRST, at the old rect, so the repaint covers the pixels actually on screen.
        if (g_indShowing) HideIndicator();
        ib[0] = box[0]; ib[1] = box[1]; ib[2] = box[2]; ib[3] = box[3];
        g_bandRect[0] = box[0]; g_bandRect[1] = box[1];
        g_bandRect[2] = box[2]; g_bandRect[3] = box[3];
        BandForget();
        return true;
    }

    if (g_bandCleanN <= 0) {
        if (g_indShowing) { HideIndicator(); return true; }
        // Wait for the pane THIS PAGE draws to have landed and stopped moving; a copy taken
        // earlier would hold the PREVIOUS layout.
        if (!BandStable(root)) return false;
        memcpy(g_bandClean, g_bandCand, (size_t)g_bandCandN);
        g_bandCleanN = g_bandCandN;
        // and fall straight through to the show: the copy is already taken, and a show only
        // dirties the region, so nothing our text does can end up inside it.
    }

    const int start = g_page * SC_HUD_BUTTON_COUNT;
    char want[sizeof(g_indText)];
    _snprintf(want, sizeof(want) - 1, "%d units  %d-%d  (%d/%d)",
              g_dispN, start + 1, start + g_cacheN, g_page + 1, g_pageCount);
    want[sizeof(want) - 1] = '\0';

    const bool changed = (strcmp(want, g_indText) != 0);
    const bool visible = (*(DWORD*)(ind + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE) != 0;
    // Re-show whenever the engine's own hide-all sweep has taken the visible bit off us --
    // that sweep runs on every re-layout and does not know this control is ours.
    if (changed || !visible || !g_indShowing) {
        memcpy(g_indText, want, sizeof(g_indText));
        ScCtrlShowVia(g_show, ind);
        *(DWORD*)(ind + SC_BINDLG_OFF_FLAGS) |= SC_CTRL_FLAG_DRAWN;
        ScCtrlUpdateVia(g_update, ind);
        g_indShowing = true;
        g_bandInkedN = 0;        // that copy belongs to the line that was there before
        g_bandPollAt = 0;        // poll again straight away, waiting for the paint
        g_showCalls  = 0;
        g_showTick   = GetTickCount();
        return true;
    }

    // THE INKED COPY: the band the first time it is seen to DIFFER from the clean copy, which
    // is the moment the redraw walk has actually put our line on the surface. Trigger on the
    // difference, not on elapsed calls -- the paint can be tens of thousands of calls away,
    // and clean is by construction the settled pane with none of our line in it, so nothing
    // else in this rect can move it. Polled at the same throttle and only until it is taken.
    if (g_bandInkedN <= 0 && g_bandCleanN > 0) {
        const DWORD now = GetTickCount();
        if (g_bandPollAt && (int)(now - g_bandPollAt) < 0) return false;
        g_bandPollAt = now + (DWORD)g_bandPollMs;
        const int n = ScQueueIndCopyRect(root, g_bandRect, g_bandNow, SC_HUD_BAND_MAX);
        if (n != g_bandCleanN) return false;
        if (memcmp(g_bandNow, g_bandClean, (size_t)n) == 0) return false;   // not painted yet
        memcpy(g_bandInked, g_bandNow, (size_t)n);
        g_bandInkedN = n;
        if (!g_inkedLogged) {
            // The one call count this module prints, with its own elapsed milliseconds beside
            // it so the rate is the reader's division rather than a figure to be trusted.
            ScLog("HUDROW band inked: the line landed %u dispatcher call(s) / %u ms after the "
                  "show asked for it", g_showCalls, (unsigned)(now - g_showTick));
            g_inkedLogged = true;
        }
        return true;
    }
    return false;
}

static void UnspliceIndicator(DWORD root) {
    if (!g_indSpliced) return;
    DWORD ind = (DWORD)&g_indCtrl[0];
    HideIndicator();                 // hide AND ask for the band's repaint, while still linked
    DWORD* link = (DWORD*)(root + SC_BINDLG_OFF_FIRST_CHILD);
    while (*link && *link != ind) link = (DWORD*)(*link + SC_BINDLG_OFF_NEXT);
    if (*link == ind) *link = ScDlgNext(ind);
    g_indSpliced = false;
}

// HOW MANY OF THE BAND'S BYTES ARE OURS RIGHT NOW: the same rect compared against the copy
// taken with none of our line on it -- the only number here that can say the engine drew the
// text; why it is a DIFFERENCE and not an ink count is in LogReadback. -1 is an honest "no
// answer" (no copy for this rect yet, or the surface moved); never a 0.
static int BandDiff(DWORD root) {
    if (g_bandCleanN <= 0) return -1;
    const int n = ScQueueIndCopyRect(root, g_bandRect, g_bandNow, SC_HUD_BAND_MAX);
    if (n != g_bandCleanN) return -1;
    int d = 0;
    for (int i = 0; i < n; ++i) if (g_bandNow[i] != g_bandClean[i]) ++d;
    return d;
}

// HOW MANY OF OUR OWN BYTES SURVIVED THE HAND-BACK. The bytes where `inked` differs from
// `clean` are the ones our text put on the surface -- the glyph mask -- and this counts the
// masked positions that STILL hold the inked value. 0 means the band was repainted and
// nothing of ours is left, which is what a band belonging to no control puts at risk.
// `*glyphOut` is the size of that mask and travels with the answer on purpose: a `stranded=0`
// over an EMPTY mask is not a clean band, it is a probe that never saw our line, and the two
// must not print the same.
static int BandStranded(DWORD root, int* glyphOut) {
    if (glyphOut) *glyphOut = -1;
    if (g_bandCleanN <= 0 || g_bandInkedN != g_bandCleanN) return -1;
    const int n = ScQueueIndCopyRect(root, g_bandRect, g_bandNow, SC_HUD_BAND_MAX);
    if (n != g_bandCleanN) return -1;
    int glyph = 0, stranded = 0;
    for (int i = 0; i < n; ++i) {
        if (g_bandInked[i] == g_bandClean[i]) continue;      // never ours
        ++glyph;
        if (g_bandNow[i] == g_bandInked[i]) ++stranded;
    }
    if (glyphOut) *glyphOut = glyph;
    return stranded;
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
    for (int i = 0; i < SC_HUD_BUTTON_COUNT && c; ++i, c = ScDlgNext(c)) {
        if (!(*(DWORD*)(c + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE)) continue;
        DWORD su = *(DWORD*)(c + SC_BINDLG_OFF_USER);
        if (!su) continue;
        WORD tag = ScUnitTag(*(DWORD*)(su + SC_STATUSER_OFF_UNIT));
        int room = (int)sizeof(buf) - used;
        if (room < 8) break;
        used += _snprintf(buf + used, (size_t)room, "%s%04X", shown ? " " : "", tag);
        ++shown;
    }
    // The indicator, read back the same way -- out of the CONTROL, not out of g_indText.
    // Printing our own buffer says what the module INTENDED, which is the self-echo
    // AGENTS.md § "Oracles: what counts as a read-back" rules out, and it is what lets a
    // nine-pixel-tall (i.e. never drawn) indicator pass.
    //
    // `indInk` STAYS ON THIS LINE BUT IS NOT THE ORACLE. Ink counts non-background bytes
    // inside a rect, so it can only detect text over a region the ENGINE leaves as
    // background; over a region the engine also paints it SATURATES -- every byte is already
    // non-zero before one pixel of ours exists, so the count is the rect's area whatever we
    // did. Measured with the box at (32,9,180,25) = 148 x 16 = 2368 bytes: `indInk=2368` for
    // "36 units  1-12  (1/3)", 2368 for "13-24  (2/3)", 2368 for the wrap back -- one number,
    // three strings, the full area, and `indInk > 0` asserted on it. That failure does not
    // look like zero, it looks healthy, so a positive control against ink=0 ("blind probe")
    // cannot catch it.
    //
    // `indBoxDiff` is the oracle instead: the same rect compared against a copy of itself
    // taken with none of our line on it (BandDiff). `indRefInk`/`indSurfInk` stay as the two
    // blindness checks -- a control the engine fills, and the whole surface.
    DWORD ind = (DWORD)&g_indCtrl[0];
    bool linked = false;
    for (DWORD c = ScDlgChild(g_dialog); c && !linked; c = ScDlgNext(c)) if (c == ind) linked = true;
    const char* live = "";
    int ink = -1;
    DWORD flags = 0;
    short* ib = ScDlgBounds(ind);
    if (linked) {
        flags = *(DWORD*)(ind + SC_BINDLG_OFF_FLAGS);
        DWORD p = *(DWORD*)(ind + SC_BINDLG_OFF_TEXT);
        if (ScReadable(p, 1)) live = (const char*)p;
        ink = ScQueueIndSurfaceInk(g_dialog, ib[0], ib[1], ib[2], ib[3]);
    }

    // THE POSITIVE CONTROL for the numbers above: ink over a rect the ENGINE fills. The first
    // wireframe button is up precisely because we are paging, so there is always a visible
    // candidate here -- and it still reports -1 rather than falling back to a hidden control,
    // because ink over something nobody can see answers neither question. `surfInk` (whole
    // surface) is the check that has an answer in EVERY state, hand-back included.
    int refInk = -1, refId = 0;
    DWORD ref = ScDlgFindChild(g_dialog, SC_HUD_FIRST_SMALL_BUTTON);
    if (ref && (*(DWORD*)(ref + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE)) {
        short* rb = ScDlgBounds(ref);
        refInk = ScQueueIndSurfaceInk(g_dialog, rb[0], rb[1], rb[2], rb[3]);
        refId  = SC_HUD_FIRST_SMALL_BUTTON;
    }

    ScLog("HUDROW show n=%d page=%d/%d slots=%d [%s] indicator=\"%s\" indLinked=%d "
          "indVisible=%d indBounds=(%d,%d,%d,%d) indInk=%d indBoxDiff=%d indRefInk=%d "
          "indRefId=%d indSurfInk=%d indFontH=%d indShowing=%d",
          g_dispN, g_page + 1, g_pageCount, shown, buf, live, linked ? 1 : 0,
          (flags & SC_CTRL_FLAG_VISIBLE) ? 1 : 0,
          linked ? ib[0] : 0, linked ? ib[1] : 0, linked ? ib[2] : 0, linked ? ib[3] : 0, ink,
          linked ? BandDiff(g_dialog) : -1, refInk, refId,
          ScQueueIndSurfaceInk(g_dialog, 0, 0, 0x7FFF, 0x7FFF),
          ScQueueIndSmallFontHeight(), g_indShowing ? 1 : 0);
}

// Where the buttons are, so an automated test can aim a right-click at one. Raw control
// bounds plus the root's own rect, logged once per dialog instance; the reader decides
// the coordinate space from both.
static void LogButtonRects(DWORD root, DWORD firstBtn) {
    if (g_rectsLogged) return;
    char buf[512];
    int used = 0;
    short* rb = ScDlgBounds(root);
    used += _snprintf(buf + used, sizeof(buf) - (size_t)used, "root=[%d,%d,%d,%d]",
                      rb[0], rb[1], rb[2], rb[3]);
    DWORD c = firstBtn;
    for (int i = 0; i < SC_HUD_BUTTON_COUNT && c; ++i, c = ScDlgNext(c)) {
        short* b = ScDlgBounds(c);
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
    BYTE* allHidden = (BYTE*)ScRuntimeAddr(SC_VA_STAT_ALL_HIDDEN);
    if (*allHidden != 1) {
        for (DWORD c = ScDlgChild(root); c; c = ScDlgNext(c)) ScCtrlHideVia(g_hide, c);
        *allHidden = 1;
    }

    const int start = g_page * SC_HUD_BUTTON_COUNT;
    g_cacheN = 0;
    DWORD c = firstBtn;
    for (int i = 0; i < SC_HUD_BUTTON_COUNT && c; ++i, c = ScDlgNext(c)) {
        const int idx = start + i;
        DWORD su = *(DWORD*)(c + SC_BINDLG_OFF_USER);
        if (idx < g_dispN && su) {
            DWORD unit = g_disp[idx];
            WORD  id   = *(WORD*)(unit + SC_CUNIT_OFF_UNIT_ID);
            *(DWORD*)(su + SC_STATUSER_OFF_UNIT) = unit;
            *(WORD*) (su + SC_STATUSER_OFF_ID)   = id;
            ScCtrlShowVia(g_show, c);
            *(DWORD*)(c + SC_BINDLG_OFF_FLAGS) |= SC_CTRL_FLAG_DRAWN;
            // Unconditional, unlike the engine's first-show-only update: a page
            // flip changes a button's content without changing its visibility,
            // and the wireframe repaints only when the control is updated.
            ScCtrlUpdateVia(g_update, c);
            HudSlotCache* s = &g_cache[g_cacheN++];
            s->unit = unit;
            s->uniq = ScUnitUniqueness(unit);
            s->hp   = ScUnitHitPoints(unit);
            s->id   = id;
        } else {
            ScCtrlHideVia(g_hide, c);
        }
    }

    g_cacheValid  = true;
    g_flipPending = false;
    ++g_statActs;
}

// A positive read-back that the dialog is genuinely back to stock: all 12 wireframe buttons
// point at the engine's own interact, the indicator is not linked into the child chain, and
// the chain itself is intact. Logged so an in-game test can ASSERT the hand-back rather than
// infer it from the absence of paging.
static void LogVerifyStock(DWORD root) {
    if (!root) { ScLog("HUDROW verify stock: no dialog"); return; }
    const DWORD engineFn = ScRuntimeVa(SC_VA_WIREFRAME_BTN_INTERACT);
    int engineOwned = 0, walked = 0;
    DWORD c = ScDlgFindChild(root, SC_HUD_FIRST_SMALL_BUTTON);
    for (int i = 0; i < SC_HUD_BUTTON_COUNT && c; ++i, c = ScDlgNext(c)) {
        ++walked;
        if (*(DWORD*)(c + SC_BINDLG_OFF_INTERACT) == engineFn) ++engineOwned;
    }
    int chainLen = 0;
    for (DWORD w = ScDlgChild(root); w && chainLen < 128; w = ScDlgNext(w)) ++chainLen;
    ScLog("HUDROW verify stock: engineInteract=%d/%d indicatorLinked=%d chainLen=%d",
          engineOwned, walked, IndicatorInChain(root) ? 1 : 0, chainLen);
}

// Leave paged mode: restore the stock pointers, remove the indicator, force-repaint the
// buttons, then hand the frame to the engine's own dispatcher (which lays out the
// single-portrait or <=12 multi view normally). `root == 0` means the dialog went away and the
// cached button pointers are into freed heap: drop the bookkeeping without dereferencing (the
// next paged frame re-wraps fresh).
//
// THE REPAINT HAS TWO HALVES: the band below the row belongs to no control, so
// UnspliceIndicator asks for OUR OWN rect first (updateControl on the hidden control), and
// the button sweep below covers the row that sits beside the band. `HUDROW band after stock`
// in the dispatcher is the measurement that this works.
static void RestoreStock(DWORD root) {
    Unwrap(root);
    if (root) UnspliceIndicator(root); else { g_indSpliced = false; g_indShowing = false; }
    g_cacheValid = false;
    if (root) {
        DWORD c = ScDlgFindChild(root, SC_HUD_FIRST_SMALL_BUTTON);
        for (int i = 0; i < SC_HUD_BUTTON_COUNT && c; ++i, c = ScDlgNext(c)) {
            if (*(DWORD*)(c + SC_BINDLG_OFF_FLAGS) & SC_CTRL_FLAG_VISIBLE) ScCtrlUpdateVia(g_update, c);
        }
        LogVerifyStock(root);
    }
    ScLog("HUDROW stock restored (n=%d)", g_dispN);
    CallOrigDispatch();
}

// True when a displayed unit's uniqueness / HP / type drifted since the last fill
// -- the same comparison the engine's own cond makes, over our page.
static bool PageDrifted(void) {
    for (int i = 0; i < g_cacheN; ++i) {
        const HudSlotCache* s = &g_cache[i];
        if (ScUnitUniqueness(s->unit) != s->uniq) return true;
        if (ScUnitHitPoints(s->unit) != s->hp)   return true;
        if (*(WORD*) (s->unit + SC_CUNIT_OFF_UNIT_ID)   != s->id)   return true;
    }
    return false;
}

// The per-frame decision. Called by the dispatcher detour.
void ScHudRowOnDispatch(void) {
    if (!g_enabled) { CallOrigDispatch(); return; }

    bool selChanged = false, death = false;
    bool overflow = RefreshShadow(&selChanged, &death);

    DWORD dlg  = ScStatDialog();
    DWORD root = dlg ? ScDlgRoot(dlg) : 0;
    if (root && root != g_dialog) {
        // A new dialog instance: every cached control pointer belongs to the old
        // one. Forget them -- never touch them again.
        g_dialog      = root;
        g_wrapCount   = 0;
        g_indSpliced  = false;
        g_page        = 0;
        g_cacheValid  = false;
        g_rectsLogged = false;
        // AND THE BAND COPIES BELONG TO THE OLD DIALOG'S SURFACE, whose rect can match the
        // new one exactly -- the pane is laid out the same way every time -- so without this
        // the first reading would diff live pixels against a buffer for a surface that is
        // gone. "No answer" is the only honest state here.
        g_indShowing  = false;
        g_bandTooSmall = false;
        g_bandPending  = false;
        BandForget();
    }

    DWORD firstBtn = root ? ScDlgFindChild(root, SC_HUD_FIRST_SMALL_BUTTON) : 0;

    // Page only when there is real overflow AND a dialog with a row AND a portrait unit
    // (the engine's own precondition), AND we have not DIVERGED from the engine's own
    // selection. On divergence we hand back to stock and stay stock until the next commit
    // rebuilds a consistent shadow.
    if (g_diverged && (g_wrapCount > 0 || g_indSpliced)) ++g_statDiverged;
    if (!overflow || g_diverged || !root || !firstBtn || !ScPortraitUnit()) {
        bool hidNow = false;
        if (g_wrapCount > 0 || g_indSpliced) { RestoreStock(root); hidNow = true; }
        else CallOrigDispatch();
        g_wasPaged = false;
        ++g_statStock;

        // Does leaving paged mode strand any of our pixels? A band that belongs to no control
        // has to ask for its own repaint (HideIndicator), and this reading, measured rather
        // than argued, is what says whether the ask worked.
        //
        // NOT ON THE FRAME WE HID ON. RestoreStock only marks the region dirty -- the paint is
        // the dialog's own redraw walk, which has not run when this returns -- so a reading
        // taken now would find our own line still on the surface and report every byte of it
        // stranded. Every later stock frame is after that redraw. Logged once per hand-back.
        if (hidNow) { g_bandPending = true; g_bandCandN = 0; g_bandPollAt = 0; }
        else if (g_bandPending && root && BandStable(root)) {
            int glyph = -1;
            const int stranded = BandStranded(root, &glyph);
            ScLog("HUDROW band after stock: rect=(%d,%d,%d,%d) glyphBytes=%d stranded=%d "
                  "surfInk=%d episodes=%u",
                  g_bandRect[0], g_bandRect[1], g_bandRect[2], g_bandRect[3],
                  glyph, stranded,
                  ScQueueIndSurfaceInk(root, 0, 0, 0x7FFF, 0x7FFF), g_statEpisodes);
            g_bandPending = false;
        }
        return;
    }

    ++g_showCalls;
    if (!g_wasPaged) {
        ++g_statEpisodes;
        // Entering paged mode: the surface still holds the STOCK layout, so no copy taken now
        // is a copy of the pane this page draws. BandStable decides when the new one lands.
        BandForget();
        g_wasPaged = true;
    }
    EnsureWrapped(firstBtn);
    LogButtonRects(root, firstBtn);

    // Throttle the re-fill exactly as the engine throttles its own layout: only when
    // something the page depends on changed. On a quiet frame the page just persists --
    // nothing else writes the status buttons once we skip the engine's dispatcher.
    bool filled = false;
    if (selChanged || death || g_flipPending || !g_cacheValid || PageDrifted()) {
        FillPage(root, firstBtn);
        filled = true;
    }
    // The indicator runs EVERY paged frame, quiet ones included (see IndicatorFrame).
    const bool indChanged = IndicatorFrame(root, firstBtn);
    if (filled || indChanged) LogReadback(firstBtn);

    // Consume the redraw-needed flag the way the engine's dispatcher does at its
    // tail, since we are standing in for it this frame.
    *(BYTE*)ScRuntimeAddr(SC_VA_STAT_DIRTY) = 0;
}

// ---------------------------------------------------------------------------
// Detour entry point
// ---------------------------------------------------------------------------

// The engine calls the dispatcher with no arguments and ignores the return; a plain void
// function matches (EBX/ESI/EDI preserved by GCC, EAX/ECX/EDX scratch under VC6's rules).
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
// The row's pictures (see ScHudRowWireHasArt in sc_hudrow.h)
// ---------------------------------------------------------------------------

// Every units.dat id, so the draw's own guard never sends one to frame 0; every frame one
// transparent pixel, so the blit puts nothing on the button.
#define SC_WIRE_EMPTY_FRAMES 228
#define SC_WIRE_EMPTY_DATA   (6 + SC_WIRE_EMPTY_FRAMES * 8)
static BYTE g_emptySheet[SC_WIRE_EMPTY_DATA + 3];

static void BuildEmptySheet(void) {
    *(WORD*)&g_emptySheet[0] = SC_WIRE_EMPTY_FRAMES;
    *(WORD*)&g_emptySheet[2] = 32;
    *(WORD*)&g_emptySheet[4] = 32;
    for (int i = 0; i < SC_WIRE_EMPTY_FRAMES; ++i) {
        BYTE* f = &g_emptySheet[6 + i * 8];
        f[0] = 0; f[1] = 0; f[2] = 1; f[3] = 1;
        *(DWORD*)(f + 4) = SC_WIRE_EMPTY_DATA;
    }
    *(WORD*)&g_emptySheet[SC_WIRE_EMPTY_DATA] = 2;   // row 0 starts after the row table
    g_emptySheet[SC_WIRE_EMPTY_DATA + 2] = 0x81;       // skip one pixel
}

const BYTE* ScHudRowEmptySheet(void) { return g_emptySheet; }

bool ScHudRowWireHasArt(unsigned id) {
    if (id < 106) return true;   // every unit; 106 is the first building
    return id == 106 || id == 111 || id == 113 || id == 114 || id == 116 || id == 122;
}

void ScHudRowOnWireDraw(DWORD button, DWORD edx, ScHudWireDrawFn orig) {
    DWORD su = *(DWORD*)(button + SC_BINDLG_OFF_USER);
    if (!su || ScHudRowWireHasArt(*(WORD*)(su + SC_STATUSER_OFF_ID))) {
        orig(button, edx);
        return;
    }
    // One call, on the game thread that owns the sheet: nothing else can read it meanwhile.
    DWORD* sheet = (DWORD*)ScRuntimeAddr(SC_VA_GRPWIRE_SHEET);
    DWORD real = *sheet;
    *sheet = (DWORD)&g_emptySheet[0];
    orig(button, edx);
    *sheet = real;
    ++g_statBlank;
}

static void __attribute__((fastcall)) SC_GAME_ENTRY HkWireDraw(DWORD button, DWORD edx) {
    ScHudRowOnWireDraw(button, edx, (ScHudWireDrawFn)g_hkWireDraw.trampoline);
}

static const BYTE kPrologueWireDraw[] = { 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x18 };

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

void ScHudRowInit(BYTE* moduleBase, bool enabled) {
    ScEngineSetModuleBase(moduleBase);
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
    g_diverged = false;
    g_indShowing = false;
    g_wasPaged = false;
    g_bandTooSmall = false;
    g_bandPending = false;
    g_bandCleanN = g_bandInkedN = g_bandCandN = 0;
    g_bandCandAt = g_bandPollAt = 0;
    g_bandRect[0] = g_bandRect[1] = g_bandRect[2] = g_bandRect[3] = 0;
    g_statEpisodes = 0;
    g_showCalls = 0;
    g_showTick = 0;
    g_inkedLogged = false;
    g_session = ScSessionEpoch();
    g_statSessionDrop = 0;
    g_statBlank = 0;
    BuildEmptySheet();
}

bool ScHudRowEnabled(void) { return g_enabled; }

int ScHudRowInstall(void) {
    if (!g_enabled) return 0;

    if (ScHookInstall(&g_hkDispatch, "statDataUpdate",
                      ScRuntimeAddr(SC_VA_STAT_DATA_UPDATE),
                      (void*)&HkStatDispatch, 5,
                      kPrologueDispatch, (int)sizeof(kPrologueDispatch))) {
        if (ScHookInstall(&g_hkWireDraw, "wireframeDraw",
                          ScRuntimeAddr(SC_VA_WIREFRAME_DRAW),
                          (void*)&HkWireDraw, (int)sizeof(kPrologueWireDraw),
                          kPrologueWireDraw, (int)sizeof(kPrologueWireDraw))) {
            return 1;
        }
        ScHookRemove(&g_hkDispatch);
    }
    ScLog("HUDROW: a hook failed to install -- feature disabled");
    g_enabled = false;
    return 0;
}

void ScHudRowRemove(void) {
    ScHookRemove(&g_hkWireDraw);
    ScHookRemove(&g_hkDispatch);

    // Best-effort pointer restores: single atomic dword writes, guarded reads because the
    // dialog may be gone. Mid-game unload stays unsupported (the game thread may be in the
    // shim), same policy as sc_circles.
    if (g_wrapCount > 0) {
        const DWORD engineFn = ScRuntimeVa(SC_VA_WIREFRAME_BTN_INTERACT);
        const DWORD shim     = (DWORD)&HudBtnInteractShim;
        for (int i = 0; i < g_wrapCount; ++i) {
            DWORD p = g_wrapBtn[i] + SC_BINDLG_OFF_INTERACT;
            if (ScReadable(p, 4) && *(DWORD*)p == shim) *(DWORD*)p = engineFn;
        }
        g_wrapCount = 0;
    }
    if (g_indSpliced && g_dialog &&
        ScReadable(g_dialog + SC_BINDLG_OFF_FIRST_CHILD, 4)) {
        ScDlgRemoveChild(g_dialog, (DWORD)&g_indCtrl[0]);
        g_indSpliced = false;
    }
}

void ScHudRowLogStats(void) {
    if (!g_enabled) return;
    // `pagedEpisodes` IS THE COVERAGE NUMBER -- times the row ENTERED paged mode. This
    // module's whole seam is the >12 state, so a run that never reached it proves nothing
    // about the indicator in either direction while looking exactly like a clean pass
    // (AGENTS.md § "Oracles: absence and defect-era checks"); 0 here means no verdict.
    //
    // An EPISODE count and not a call count on purpose: this detour runs tens of thousands of
    // times a second, so a seven-digit total is indistinguishable from a tick global read by
    // mistake. `acts` beside it (pages actually displayed) is the same size and kind of fact,
    // and both cross-check against the run's own `HUDROW show` lines.
    ScLog("HUDROW stats: acts=%u stock=%u flips=%u staleDropped=%u wraps=%u splices=%u "
          "diverged=%u gated=%u pagedEpisodes=%u bandSuppressed=%u session=%u "
          "sessionDrops=%u blankDraws=%u",
          g_statActs, g_statStock, g_statFlips, g_statStale, g_statWraps, g_statSplices,
          g_statDiverged, g_statGated, g_statEpisodes, g_statSuppressed,
          g_session, g_statSessionDrop, g_statBlank);
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
    g_statDiverged = g_statGated = 0;
}

// The read-backs sync too: "which page is the row on" has no answer that spans a game
// change, and a test reading the previous game's page here could not see a stale page.
int ScHudRowCurrentPage(void)  { HudRowSessionSync(); return g_page; }
int ScHudRowPageCount(void)    { HudRowSessionSync(); return g_pageCount; }
int ScHudRowGatedCount(void)   { return (int)g_statGated; }
bool ScHudRowIsDiverged(void)  { HudRowSessionSync(); return g_diverged; }
int ScHudRowPagedFrames(void)  { return (int)g_statEpisodes; }
void ScHudRowTestSetBandTiming(int settleMs, int pollMs) {
    g_bandSettleMs = settleMs < 0 ? 0 : settleMs;
    g_bandPollMs   = pollMs   < 0 ? 0 : pollMs;
    g_bandPollAt   = 0;
}
bool ScHudRowIndicatorShowing(void) { return g_indShowing; }
int ScHudRowBandDiff(void)     { return BandDiff(g_dialog); }
int ScHudRowBandStranded(int* glyphOut) { return BandStranded(g_dialog, glyphOut); }
void ScHudRowIndicatorBox(short* out) {
    const short* b = (const short*)&g_indCtrl[SC_BINDLG_OFF_BOUNDS];
    if (out) for (int i = 0; i < 4; ++i) out[i] = b[i];
}
