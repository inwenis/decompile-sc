// sc_console.cpp -- the console at the bottom of a TALLER screen, and the click
// trace. See sc_console.h for the contract; research/renderer-viewport.md 22
// for the read that settled the design (renderer-viewport.md 19.x is the prior half).
//
// Mechanism notes, each read out of StarCraft.exe 1.16.1:
//
//  * The dialog-layer composite: layer 2's draw (0x0041CB50) draws each visible
//    dialog's controls into the DIALOG'S OWN surface (0x0041C080, root-relative),
//    then per (dialog, dirty rect) blits that surface to a TARGET at the dialog's
//    LIVE bounds (+0x04): 0x0041C810 picks the target by the dialog's flags --
//    `flags & 0x10000000` -> the screen BUFFER (0x6CEFF0; StatRes ships so),
//    otherwise (StatBtn, the minimap, the rails ...) a DIRECT blit into the
//    locked primary (0x004172F0 via ord350). The buffer->glass present (ord432)
//    copies the buffer only where the console ART is transparent (the region at
//    0x006D5E14 = complement(art) over the art's 640x480, rows anchored at
//    screen row 0), which is exactly why a direct-blitted console is never
//    painted over -- and why nothing of the buffer below row 479 or right of
//    column 639 ever reaches the glass by itself (20.3, 22).
//
//  * So a console moved DOWN needs the buffer path, not the direct one: set the
//    0x10000000 bit on every in-game root, and every dialog composites into the
//    buffer at its live bounds, under the cursor (layer 0 draws last) and the
//    tooltip (layer 1); the storm present widen (sc_stormpresent.cpp) then mirrors
//    the WHOLE buffer to the glass each present. Moving the console art's image
//    node instead is provably inert (the first node's x,y are never read), and a
//    full mirror with direct-blit dialogs left in place erases them (the layer
//    walk precedes the present of the same frame).
//
//  * The console art: game\<race>console.pcx is loaded once into the descriptor
//    at 0x00597240, and each console dialog's surface is INITIALISED with the
//    art slice under its bounds AT SURFACE-CREATION TIME (0x004C35F0). A dialog
//    moved after its surface exists takes its art with it; moved before, the
//    copy would read a 480-row image at row 700+. That ordering is why the move
//    waits for the surface.
//
//  * updateControl (0x0041C400, EAX = control) marks the control's CURRENT
//    live-bounds rect into the dirty region, clamped by the .data box the
//    generated table widens (dlgclip.mark.*). Calling it before AND after the
//    bounds write repaints both the vacated and the claimed rect.
//
//  * What the engine bakes OUTSIDE the dialog records -- the hit-test tiers of
//    isPointOverUi, the right-click router's card rect, the minimap's absolute
//    top -- is the generated table's business (console.*, minimap.anchor.*), not
//    this file's.

#include "sc_console.h"

#include <stdio.h>
#include <string.h>

#include "sc_addresses.h"
#include "sc_engine.h"
#include "sc_env.h"
#include "sc_hook.h"
#include "sc_log.h"
#include "sc_screen.h"
#include "sc_session.h"
#include "sc_unit.h"

#include "sc_menu.h"

// The composite-target bit (0x0041C810: `test [dlg+0x18],0x10000000` -> the
// screen buffer). StatRes ships with it (flags 0x7000200D read live, 19.1).
#define SC_DLG_FLAG_COMPOSITE_BUFFER 0x10000000u

#define SC_CONSOLE_MAX_ROOTS   16
#define SC_CONSOLE_TRACE_MAX   2000
#define SC_CONSOLE_NAME_LEN    20

static bool  g_move    = false;   // the down-move: widescreen ACTIVE with a taller playfield
static bool  g_centre  = false;   // the glue roots centred while no game is played (sc_menu.h)
static bool  g_trace   = false;
static bool  g_fullRedraw = false;   // request the engine's full playfield redraw every frame
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
    short dx, dy;       // the translation applied
};
static MoveSlot g_moved[SC_CONSOLE_MAX_ROOTS];
static int      g_movedN = 0;

static unsigned g_traceLines   = 0;
static unsigned g_traceDropped = 0;
static unsigned g_frames       = 0;
static unsigned g_moves        = 0;
static unsigned g_menuMoves    = 0;   // glue roots centred (sc_menu.h)
static unsigned g_converted    = 0;   // roots given the buffer-composite bit
static unsigned g_fullFrames   = 0;   // frames that took the engine's full-redraw path on request
static unsigned g_selects      = 0;
static volatile LONG g_selectReq = 0;   // set by the observer's marker poll
static int      g_inGame       = -1;  // last walk's verdict; -1 = no walk has run

// The ten roots that ARE the bottom console (research 19.6's inventory, the
// loaders re-read for 22): they move down by the playfield's growth. StatRes
// (the top bar) and StatLB (the leader board, top-left) stay.
static const char* const kConsoleRoots[] = {
    "Minimap", "TextBox", "Stat_F10", "StatBtn", "StatData", "StatPort", "StatFluf"
};

static bool IsConsoleRoot(const char* name) {
    for (size_t i = 0; i < sizeof(kConsoleRoots) / sizeof(kConsoleRoots[0]); ++i)
        if (strcmp(name, kConsoleRoots[i]) == 0) return true;
    return false;
}

// A dialog's name is its pszText. Game data: copied byte-guarded and sanitised.
static void ReadName(DWORD dlg, char* out, size_t outLen) {
    out[0] = '\0';
    if (!ScReadable(dlg + SC_BINDLG_OFF_TEXT, 4)) return;
    ScLogCopyText(*(DWORD*)(dlg + SC_BINDLG_OFF_TEXT), out, outLen);
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
    if (!ScReadable(dlg + SC_BINDLG_OFF_INTERACT, 4)) return;
    DWORD* fn = (DWORD*)(dlg + SC_BINDLG_OFF_INTERACT);
    if (*fn == (DWORD)&ConsoleInteractShim) return;   // stale table row survived; leave it
    WrapSlot* w = &g_wrap[g_wrapN];
    w->dlg  = dlg;
    w->orig = *fn;
    _snprintf(w->name, sizeof(w->name), "%s", name[0] ? name : "?");
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
        if (!ScReadable(dlg + SC_BINDLG_OFF_INTERACT, 4)) continue;
        DWORD* fn = (DWORD*)(dlg + SC_BINDLG_OFF_INTERACT);
        if (*fn == (DWORD)&ConsoleInteractShim) *fn = g_wrap[i].orig;
    }
    g_wrapN = 0;
    memset(g_wrap, 0, sizeof(g_wrap));
}

// ---------------------------------------------------------------------------
// The move
// ---------------------------------------------------------------------------

// Both surface descriptors, logged as evidence: the draw walk installs +0x36
// and the status allocator fills +0x0C (sc_addresses.h explains the pair).
static void LogSurfaces(DWORD dlg, const char* name) {
    for (int k = 0; k < 2; ++k) {
        DWORD d = dlg + (k == 0 ? SC_BINDLG_OFF_SURFACE : SC_BINDLG_OFF_SURFACE_ALT);
        if (!ScReadable(d, 8)) continue;
        ScLog("CONSOLE surf '%s' +0x%02X: w=%d h=%d bits=0x%08X", name,
              (unsigned)(k == 0 ? SC_BINDLG_OFF_SURFACE : SC_BINDLG_OFF_SURFACE_ALT),
              (int)*(short*)(d + SC_SURFACE_OFF_W),
              (int)*(short*)(d + SC_SURFACE_OFF_H),
              (unsigned)*(DWORD*)(d + SC_SURFACE_OFF_BITS));
    }
}

// Every in-game root composites into the buffer, not the primary. Set once per
// dialog (the bit is a plain dword field the engine never rewrites), and mark
// its rect so the first buffer composite happens on the very next compose.
static void ConvertToBuffer(DWORD dlg, const char* name) {
    if (!ScReadable(dlg + SC_BINDLG_OFF_FLAGS, 4)) return;
    DWORD* flags = (DWORD*)(dlg + SC_BINDLG_OFF_FLAGS);
    if (*flags & SC_DLG_FLAG_COMPOSITE_BUFFER) return;
    *flags |= SC_DLG_FLAG_COMPOSITE_BUFFER;
    ScCtrlUpdate(dlg);
    ++g_converted;
    ScLog("CONSOLE buffer-composite '%s' 0x%08X flags -> 0x%08X", name, (unsigned)dlg,
          (unsigned)*flags);
}

static MoveSlot* FindMoved(DWORD dlg) {
    for (int i = 0; i < g_movedN; ++i)
        if (g_moved[i].dlg == dlg) return &g_moved[i];
    return NULL;
}

// Translate one root by (dx,dy), once, keeping the original for detach. With
// waitSurface, not before the root's surface exists: moving BEFORE 0x004C35F0 has
// copied the console art slice would make that copy read the 480-row console.pcx out of
// range. Returns whether it moved; menu moves log and count apart.
static bool TryMove(DWORD dlg, const char* name, int dx, int dy, bool waitSurface,
                    bool menu) {
    if (!ScReadable(dlg + SC_BINDLG_OFF_BOUNDS, 8)) return false;
    short* bl = ScDlgBounds(dlg);
    MoveSlot* old = FindMoved(dlg);
    if (old) {
        // Glue screens come and go at the same heap addresses: a row whose dialog reads
        // un-moved again is a new dialog in a freed one's memory, and must move too.
        const bool fresh = menu && bl[0] == old->l && bl[1] == old->t &&
                           bl[2] == old->r && bl[3] == old->b;
        if (!fresh) return false;
        *old = g_moved[--g_movedN];
        memset(&g_moved[g_movedN], 0, sizeof(g_moved[g_movedN]));
    }
    if (g_movedN >= (int)(sizeof(g_moved) / sizeof(g_moved[0]))) return false;

    DWORD bits36 = 0, bits0C = 0;
    if (waitSurface) {
        bits36 = ScReadable(dlg + SC_BINDLG_OFF_SURFACE + SC_SURFACE_OFF_BITS, 4)
                     ? *(DWORD*)(dlg + SC_BINDLG_OFF_SURFACE + SC_SURFACE_OFF_BITS) : 0;
        bits0C = ScReadable(dlg + SC_BINDLG_OFF_SURFACE_ALT + SC_SURFACE_OFF_BITS, 4)
                     ? *(DWORD*)(dlg + SC_BINDLG_OFF_SURFACE_ALT + SC_SURFACE_OFF_BITS) : 0;
        if (!bits36 && !bits0C) return false;   // not yet drawn once; try again next frame
    }

    MoveSlot* m = &g_moved[g_movedN];
    m->dlg = dlg; m->l = bl[0]; m->t = bl[1]; m->r = bl[2]; m->b = bl[3];
    m->dx = (short)dx; m->dy = (short)dy;

    if (!menu) LogSurfaces(dlg, name);
    ScCtrlUpdate(dlg);                    // the rect being VACATED goes dirty
    bl[0] = (short)(m->l + dx);
    bl[2] = (short)(m->r + dx);
    bl[1] = (short)(m->t + dy);
    bl[3] = (short)(m->b + dy);
    ScCtrlUpdate(dlg);                    // the rect being CLAIMED goes dirty
    ++g_movedN;
    if (menu) ++g_menuMoves; else ++g_moves;
    ScLog("%s moved '%s' 0x%08X (%d,%d)-(%d,%d) -> (%d,%d)-(%d,%d) "
          "flags=0x%08X surf36bits=0x%08X surf0Cbits=0x%08X",
          menu ? "MENU" : "CONSOLE", name, (unsigned)dlg, m->l, m->t, m->r, m->b,
          (int)bl[0], (int)bl[1], (int)bl[2], (int)bl[3],
          (unsigned)*(DWORD*)(dlg + SC_BINDLG_OFF_FLAGS),
          (unsigned)bits36, (unsigned)bits0C);
    return true;
}

static void UnmoveAll(void) {
    for (int i = 0; i < g_movedN; ++i) {
        DWORD dlg = g_moved[i].dlg;
        if (!ScReadable(dlg + SC_BINDLG_OFF_BOUNDS, 8)) continue;
        short* bl = ScDlgBounds(dlg);
        const MoveSlot* m = &g_moved[i];
        // Restore only if the bounds still read as OUR move; anything else means
        // the record was freed and reused, and writing it would corrupt a stranger.
        if (bl[0] == (short)(m->l + m->dx) && bl[1] == (short)(m->t + m->dy) &&
            bl[2] == (short)(m->r + m->dx) && bl[3] == (short)(m->b + m->dy)) {
            ScCtrlUpdate(dlg);
            bl[0] = m->l; bl[1] = m->t; bl[2] = m->r; bl[3] = m->b;
            ScCtrlUpdate(dlg);
        }
    }
    g_movedN = 0;
    memset(g_moved, 0, sizeof(g_moved));
}

// Drop the rows whose dialog has left the list, so a menu session's freed roots never
// fill the table the console needs in game. Only after a walk that reached the list's
// end: a row dropped for a dialog the walk never reached would move that dialog twice.
static void PruneMoved(const DWORD* live, int liveN) {
    int kept = 0;
    for (int i = 0; i < g_movedN; ++i) {
        bool seen = false;
        for (int k = 0; k < liveN && !seen; ++k) seen = (live[k] == g_moved[i].dlg);
        if (seen) g_moved[kept++] = g_moved[i];
    }
    for (int i = kept; i < g_movedN; ++i) memset(&g_moved[i], 0, sizeof(g_moved[i]));
    g_movedN = kept;
}

// ---------------------------------------------------------------------------
// The marker-driven select aid (see the header for why it exists)
// ---------------------------------------------------------------------------

typedef void (__attribute__((stdcall)) *ScCmdactSelectFn)(DWORD count, DWORD* units);

void ScConsoleOnMarker(const char* label) {
    if (!label || (!g_move && !g_trace)) return;
    if (strncmp(label, "conedge-select", 14) == 0) InterlockedExchange(&g_selectReq, 1);
}

static void DoRequestedSelect(void) {
    if (!InterlockedCompareExchange(&g_selectReq, 0, 1)) return;
    DWORD player = ScReadable(ScRuntimeVa(SC_VA_ACTIVE_PLAYER_ID), 4)
                       ? *(DWORD*)ScRuntimeAddr(SC_VA_ACTIVE_PLAYER_ID) : 0xFFFFFFFF;
    if (player >= SC_MAX_PLAYERS) {
        ScLog("CONSOLE select: active player %u out of range -- nothing selected", (unsigned)player);
        return;
    }
    DWORD unit = *(DWORD*)((BYTE*)ScRuntimeAddr(SC_VA_PLAYER_UNIT_LIST) + player * 4);
    int walked = 0;
    while (unit && walked < SC_MAX_UNITS_WALK) {
        if (!ScReadable(unit, 0x150)) { unit = 0; break; }
        if (*(DWORD*)(unit + SC_CUNIT_OFF_FLAGS) & SC_UNIT_FLAG_COMPLETED) break;
        unit = *(DWORD*)(unit + SC_CUNIT_OFF_LIST_NEXT);
        ++walked;
    }
    if (!unit) {
        ScLog("CONSOLE select: no completed unit in player %u's list -- nothing selected",
              (unsigned)player);
        return;
    }
    DWORD list[2] = { unit, 0 };
    ScCreateSelections(list, 1);
    ((ScCmdactSelectFn)ScRuntimeAddr(SC_VA_CMDACT_SELECT))(1, list);
    // The client half: the funnel pair fills activePlayerSelection and the wire,
    // and the status driver's own updateSelectedUnitData (0x004C38B0) copies it
    // into clientSelectionGroup + portrait -- but only when this flag asks it to
    // (0x004D93F0's first instruction reads it). Measured without it: active=1
    // sim=1, client=0, card empty.
    *(BYTE*)ScRuntimeAddr(SC_VA_CLIENT_SEL_CHANGED) = 1;
    ++g_selects;
    ScLog("CONSOLE selected unit=0x%08X type=%d player=%u (engine funnel: 0x0049AE40 "
          "then CMDACT_Select; client_selection_changed set)",
          (unsigned)unit, (int)*(WORD*)(unit + SC_CUNIT_OFF_UNIT_ID), (unsigned)player);
}

// ---------------------------------------------------------------------------
// The per-frame full redraw
// ---------------------------------------------------------------------------

// The partial path of the playfield draw (0x004BD580) repaints every sprite image
// touching ANY dirty cell over its WHOLE rect, so a lower-order sprite under a dirty
// cell is painted over a higher-order neighbour in cells that are not dirty. The
// engine's present copies dirty cells only and never shows it; the whole-frame mirror
// presents the buffer verbatim, so overlapping sprites swap "who is on top" between
// presents. The engine's own full-redraw request -- the scroll steppers
// 0x0049C077..0x0049C0B2 (twins 0x004BD350, 0x00480840): `or byte [0x006CEFB5],1`
// then the marker 0x0041E0D0 over layer 5's whole rect -- makes the compose take the
// full path (whole terrain blit, every on-screen sprite in heap order, full fog).
// Per frame because the composer masks bit 0 away after each draw (0x0041E3A3).
// Every other reader of bit 0 (0x00401106, 0x0047D977, 0x004974B0, 0x00497540,
// 0x004976F3, 0x004977A3, 0x00480893, 0x004D4CE0/4E80/4F10/4FA0/5030) is a
// `test [0x6CEFB5],1 / jne` that skips one redundant image-rect mark (0x004970A0).
static void RequestFullRedraw(void) {
    if (!ScScreenMarkPlayfieldDirty()) return;
    BYTE* layer5Flags = (BYTE*)ScRuntimeAddr(SC_VA_GRAPHIC_LAYERS +
                                             SC_LAYER_PLAYFIELD * SC_LAYER_STRIDE + SC_LAYER_OFF_FLAGS);
    *layer5Flags |= SC_LAYER_FLAG_NEEDS_REDRAW;
    ++g_fullFrames;
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
    if (!ScReadable(ScRuntimeVa(SC_VA_DIALOG_LIST), 4)) return;
    const DWORD head = *(DWORD*)ScRuntimeAddr(SC_VA_DIALOG_LIST);

    // In game? The console roots exist only then. The glue dialogs stay direct-blit (the
    // buffer is never presented there) and are touched only by the menu centring.
    bool inGame = false;
    const bool walk = (g_move || g_centre) && ScScreenActive();
    if (walk) {
        DWORD d = head;
        int k = 0;
        while (d && k < SC_MAX_DIALOGS_WALK) {
            if (!ScReadable(d, SC_BINDLG_SIZE)) break;
            char nm[SC_CONSOLE_NAME_LEN];
            ReadName(d, nm, sizeof(nm));
            if (strcmp(nm, "StatBtn") == 0) { inGame = true; break; }
            d = *(DWORD*)(d + SC_BINDLG_OFF_NEXT);
            ++k;
        }
        g_inGame = inGame ? 1 : 0;
    }
    if (inGame && g_move && g_fullRedraw) RequestFullRedraw();
    const bool atMenu = walk && !inGame && g_centre;
    int mdx = 0, mdy = 0;
    if (atMenu) ScMenuOffset(&mdx, &mdy);

    DWORD live[SC_MAX_DIALOGS_WALK];
    int liveN = 0;
    DWORD dlg = head;
    while (dlg && liveN < SC_MAX_DIALOGS_WALK) {
        if (!ScReadable(dlg, SC_BINDLG_SIZE)) break;
        live[liveN++] = dlg;
        char name[SC_CONSOLE_NAME_LEN];
        ReadName(dlg, name, sizeof(name));
        if (g_trace) WrapRoot(dlg, name);
        if (inGame && g_move) {
            // Every root, not only the console: a root left direct-blitting would
            // be erased by the whole-frame mirror (the F10 menu, tooltips, chat).
            ConvertToBuffer(dlg, name);
            if (IsConsoleRoot(name)) TryMove(dlg, name, 0, ScScreenConsoleShiftY(), true, false);
        } else if (atMenu && ScReadable(dlg + SC_BINDLG_OFF_BOUNDS, 8)) {
            // A full glue screen moves once it rests at (0,0); a popup moves at once,
            // before its first composite. A popup flagged 0x08000000 (the Single Player
            // one reads flags=0xE804000D) draws into its parent's surface at its bounds:
            // the stage-3 cave glue.popup.parentorigin makes that parent-relative, so a moved
            // popup is drawn and hit-tested where it shows (unmoved, it was drawn centred by
            // its parent but clicked at its raw bounds; moved without the cave, the blit ran
            // past the 640x480 surface and the game quit). The glue slide (0x004DCDE2)
            // moves CONTROL rects, root-relative.
            const short* bl = ScDlgBounds(dlg);
            const bool full = bl[2] - bl[0] + 1 >= SC_SCREEN_W && bl[3] - bl[1] + 1 >= SC_SCREEN_H;
            if ((!full || (bl[0] == 0 && bl[1] == 0)) && TryMove(dlg, name, mdx, mdy, false, true))
                ScMenuRequestCopy();   // the primary still holds its art at the old place
        }
        dlg = *(DWORD*)(dlg + SC_BINDLG_OFF_NEXT);
    }
    if (walk && !dlg) PruneMoved(live, liveN);
    if (g_centre) ScMenuOnFrame(atMenu);
}

// ---------------------------------------------------------------------------
// The composer detour
// ---------------------------------------------------------------------------

typedef void (*ComposeFn)(void);

static void SC_GAME_ENTRY HkFrameCompose(void) {
    // Work first, then the original: bounds writes, flag writes and dirty marks
    // made here are consumed by the compose that follows in the same call.
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

bool ScConsoleTraceWanted(void) { return ScEnvOptIn("SCPLUGIN_CONSOLE_TRACE"); }
bool ScConsoleBufferResident(void) { return g_move; }
int  ScConsoleInGame(void) { return g_inGame; }

void ScConsoleInstall(BYTE* moduleBase, bool writeAllowed, bool trace) {
    ScEngineSetModuleBase(moduleBase);
    g_trace = trace;
    // The move is not a flag: it is what a taller playfield means. It engages
    // whenever the widescreen table asks for one (CONSOLE_SHIFT_Y > 0) and the
    // plugin may write; the table's own ACTIVE verdict gates it per frame.
    // Stage 3 only: the hit-test tiers, the card rect and the minimap anchors that
    // follow the console are stage-3 sites; a move at stage 2 would be half done.
    g_move = writeAllowed && ScScreenWidescreenWanted() && ScScreenStageWanted() >= SC_WS_STAGE_MAX
             && ScScreenConsoleShiftY() > 0;
    // The menu centring rides the same frame walk; sc_menu.cpp decided whether it is armed.
    g_centre = writeAllowed && ScMenuArmed();
    // The full redraw belongs to the buffer-resident shape (the mirror presents the
    // whole buffer); %SCPLUGIN_FULLREDRAW%=0 is the A/B switch for its cost.
    g_fullRedraw = g_move && ScEnvFlag("SCPLUGIN_FULLREDRAW", true);
    memset(&g_hkCompose, 0, sizeof(g_hkCompose));
    g_wrapN = 0;  memset(g_wrap, 0, sizeof(g_wrap));
    g_movedN = 0; memset(g_moved, 0, sizeof(g_moved));
    g_traceLines = g_traceDropped = g_frames = g_moves = g_menuMoves = g_converted = g_fullFrames = 0;
    g_session = 0;
    g_inGame = -1;
    if (!g_move && !g_trace && !g_centre) {
        ScLog("CONSOLE: off (no console shift in the table; %%SCPLUGIN_CONSOLE_TRACE%% unset)");
        return;
    }
    if (!ScHookInstall(&g_hkCompose, "frameCompose", ScRuntimeAddr(SC_VA_FRAME_COMPOSE),
                       (void*)&HkFrameCompose, (int)sizeof(kPrologueCompose),
                       kPrologueCompose, (int)sizeof(kPrologueCompose))) {
        ScLog("CONSOLE: frame-compose hook failed to install -- feature disabled");
        g_move = g_trace = g_centre = false;
        return;
    }
    ScLog("CONSOLE: ON move=%d trace=%d fullredraw=%d centre=%d (frame hook at 0x0041E280; in game every root "
          "composites into the buffer, and the bottom console moves DOWN %d once its "
          "surfaces exist, old+new rects marked dirty; fullredraw requests the engine's "
          "full playfield path before every compose)",
          g_move ? 1 : 0, g_trace ? 1 : 0, g_fullRedraw ? 1 : 0, g_centre ? 1 : 0,
          ScScreenConsoleShiftY());
}

void ScConsoleRemove(void) {
    UnmoveAll();
    UnwrapAll();
    ScHookRemove(&g_hkCompose);
}

void ScConsoleLogStats(void) {
    if (!g_move && !g_trace && !g_centre && g_frames == 0) return;
    ScLog("CONSOLESTATS frames=%u moves=%u converted=%u fullFrames=%u wrapped=%d traceLines=%u "
          "traceDropped=%u selects=%u menuMoves=%u",
          g_frames, g_moves, g_converted, g_fullFrames, g_wrapN, g_traceLines, g_traceDropped,
          g_selects, g_menuMoves);
}
