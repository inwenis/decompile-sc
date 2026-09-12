// sc_queueind.h -- show that a building holds MORE queued items than the strip draws.
//
// The production strip is five icon controls (ids 2..6) drawing the engine's five-slot
// ring and nothing else (research/production-queue.md 8.1), so a nine-item logical queue
// and a five-item one look identical. This module adds one "+N" for a selected building
// and one "N bldgs  M queued" line for a group, both ENGINE-DRAWN: ONE SC_CTRL_TYPE_LSTATIC
// control spliced into the statdata dialog's child list with its pszText (control+0x14)
// pointed at a plugin-owned buffer, drawn by the engine's own static-text handler
// (research/status-pane-text.md), so font, colour and clipping are the pane's own.
//
// The "+N" is a badge on the LAST queue icon's top-right corner (id 6): the ring is held at
// SC_PRODQ_ENGINE_HOLD = 4 (sc_prodqueue.h), so display slot 4 never holds an engine item --
// greyed for upgrades, phantom-filled for units -- and the count goes on the slot the
// feature itself owns.
// Bounds come from the live control, never hardcoded. Apart from that control and the
// phantom bracket's write-and-restore of ring bytes, it changes no game state: no unit
// field, no resource global, no engine-owned control, no sprite. Off unless
// %SCPLUGIN_QUEUEIND% asks for it (launcher -QueueIndicator 1) and inert in `-Mode
// observe`; off, the dialog's child list is byte-for-byte stock.

#ifndef SC_QUEUEIND_H
#define SC_QUEUEIND_H

#include <windows.h>

// The badge's two frame columns, on top of SC_QIND_CHAR_W's over-reserve for the glyphs.
#define SC_QIND_BADGE_PAD 2
// The engine's static-text draw REFUSES to draw at all when `fontHeight + y > clipBottom`
// (research/status-pane-text.md 3), so the box must be taller than the font, not merely
// tall enough to look right.
#define SC_QIND_BOX_H 16
#define SC_QIND_BOX_W 40
// A deliberate OVER-estimate of the small font's advance per character: reserving too much
// costs a clip rect a little slack (or a badge a little width), while reserving too little
// truncates the string, which reads as a working feature and is worse than drawing nothing.
// Measured live: "4 bldgs  4 queued" cut off inside a box 22 pixels wide.
#define SC_QIND_CHAR_W 7

// THE GROUP LINE'S BAND. A multi-building selection draws the wireframe row and nothing
// else, leaving the strip below the row's lower buttons free -- the only place in the pane
// where a line of text does not sit on unit icons. The band's top is the row's own lowest
// edge (read from the live buttons) plus this gap; one pixel keeps the text off the borders.
#define SC_QIND_BAND_GAP 1
// Fallback minimum height for that band, used only when the font handle cannot be read
// (normally the FONT'S OWN height decides -- see SmallFontHeight). One pixel over the nine
// that measured too short.
#define SC_QIND_BAND_MIN_H 10

// How many queued upgrades the strip can show as ICONS: the four small queue icons (ids
// 3..6). Slot 0's position is taken by the research layout's own icon (id 15), which
// draws the RUNNING item with its progress bar.
#define SC_QIND_UPGRADE_ICONS 4

// How many of `held` research items are drawn as icons. All of them up to the four; past
// that, THREE, so the "+N" for the rest sits on an EMPTY fourth slot rather than on
// another item's art (the same rule the strip applies to units: the engine's ring is held
// at four so the "+N" slot is free). Pure; the frame path draws exactly this many.
int  ScQueueIndUpgradeIcons(int held);

// An enum so the log line and the offline test name the case instead of matching a string.
enum ScQueueIndMode {
    SC_QIND_NONE   = 0,   // nothing to say -- the control is hidden
    SC_QIND_STRIP  = 1,   // one building, more queued than its five icons can draw
    SC_QIND_GROUP  = 2,   // several producing buildings selected
    SC_QIND_UPGRADE = 3   // one building with upgrades queued -- they have no icons at all
};

// Everything the text depends on, read from game memory by the frame path and handed to
// the composer. Pure input, so hooktest can drive the composer with no StarCraft in sight.
struct ScQueueIndView {
    int selection;   // clientSelectionCount (0x0059723D)
    int engineLen;   // occupied slots of the portrait building's ring (CUnit+0x98)
    int overflow;    // items sc_prodqueue is holding for it, or 0
    int upgrades;    // research items sc_upgrades is holding for it, or 0
    int research;    // 1 while the pane holds a RESEARCH layout (SC_VA_STAT_ALL_HIDDEN is
                     // 7 or 8), the only layouts in which the held items are drawn as icons
    int buildings;   // selected buildings with a non-empty logical queue (group case)
    int queued;      // their logical items in total (group case)
    int hudPages;    // sc_hudrow's page count -- >1 means the row indicator owns the space
};

// How many of the strip's five icons the LOGICAL queue can fill -- engine ring first,
// then the plugin's overflow. Pure; the frame path draws exactly this many.
int  ScQueueIndDrawableSlots(const ScQueueIndView* v);

// Fills `out` with the string to draw and returns the mode. SC_QIND_NONE leaves `out`
// empty, and that is the only value for which nothing is drawn.
int  ScQueueIndCompose(char* out, int outLen, const ScQueueIndView* v);

// Reads %SCPLUGIN_QUEUEIND%. Unset/0 -> disabled: no hook, no splice, nothing drawn.
bool ScQueueIndEnabled(void);

// Called once at attach. `enabled` is resolved by the caller so observe mode can refuse
// the feature without this file knowing about modes.
void ScQueueIndInit(BYTE* moduleBase, bool enabled);

// Installs the TWO detours. statDisplayDriver 0x004D93F0, the per-frame HUD driver
// (hud-selection-row.md 4.1), runs AFTER the original -- after the status dispatcher
// 0x00458120 has laid the pane out and hidden what it hides -- so one control serves both
// the single-building and multi-select branches and can re-show itself past the engine's
// hide-all sweep; NOT the dispatcher itself, whose 5-byte window sc_hudrow owns. The other
// is queueLayout 0x004268D0, the phantom bracket (see ScQueueIndRingGen). Returns 1 when
// both went in, 0 otherwise, rolling its own half back so a failure disables the feature
// rather than half-arming it; 0-or-1 because sc_fanout.cpp counts modules, not hooks. Call
// under the shared thread suspension.
int  ScQueueIndInstall(void);
void ScQueueIndRemove(void);

// THE READ-BACK ORACLE. Reads the indicator's state back OUT OF THE LIVE DIALOG -- linked
// into the child chain, the engine's own visible bit, what string pszText actually holds --
// alongside the numbers it was computed from. Never echoes inputs: every field is re-read.
void ScQueueIndLogState(const char* tag);

// THE BADGE (STRIP and UPGRADE): the indicator control's fxnUpdate is this module's own,
// which paints the box into the render target and hands the text to the engine's
// centre-justified handler; GROUP hands it to the left-justified one. Exposed so the test
// can check both pointers and the fill, which it can reach with no engine to call.
void  ScQueueIndFillBadge(DWORD ctrl, DWORD surface);
DWORD ScQueueIndOwnUpdate(void);
DWORD ScQueueIndEngineUpdate(void);

// One line per child of the statdata dialog: id, type, flags, bounds and text. Says which
// controls in that pane are engine-drawn TEXT and where the free pixels are on THIS install,
// not from a public struct map. Read-only, and runs feature-enabled or not, because the
// stock layout is the baseline the indicator is placed against.
void ScQueueIndLogDialog(const char* tag);

void ScQueueIndLogStats(void);

// Rows at the BOTTOM of a queue-slot rect holding the engine's own slot NUMBER, excluded from
// ScQueueIndSlotDiff because two slots legitimately differ there ("1 " against "5 "). Measured:
// compared, these rows add a constant 24 bytes to slotDiff for "+2", "+3" and "+4" alike --
// the digits. Sized from the small font's height plus the label's inset, and every
// QIND line reports the live `fontH=` so the number is checkable rather than assumed.
#define SC_QIND_SLOT_LABEL_ROWS 12

// TWO QUEUE SLOTS, COMPARED ON THE SURFACE. With five of one unit type queued, slot 0 and
// slot 4 are the same picture -- same 38x35 rect, same border graphic, same icon -- so the
// bytes differing between them above the label rows are exactly what this plugin added. A
// check that CAN fail, which an ink count over an engine-drawn icon cannot: ink reads > 0
// whether or not anything of ours was drawn. -1 when the comparison cannot be taken
// honestly: no surface, a missing or hidden control, or unequal rects.
int ScQueueIndSlotDiff(DWORD root, int slotA, int slotB);

// HOW MANY BYTES OF THE INDICATOR'S BOX ARE OURS: the count differing from a baseline copy
// of those same pixels taken with none of our line in them. 0 means nothing of ours is on
// screen whatever the control's fields say; -1 means no baseline exists for this rect yet
// (it moved, or the dialog is too new) -- an honest "no answer", never a 0. Ink cannot
// answer the question in this dialog: the pane's own art shares the surface, so every rect
// reads saturated (measured live: 1330 of 1330 bytes over a queue icon, 448 of 448 inside
// the indicator's own box) and `ink > 0` holds before anything of ours is drawn.
//
// The MODE decides what it counts. GROUP: the band belongs to no control, so every differing
// byte is the LINE, a text oracle outright. STRIP: the "+N" box sits inside queue icon 6,
// which the phantom bracket has the engine fill, and the baseline predates that fill -- a
// reading is "bytes this plugin is responsible for", not "the badge drew"; ScQueueIndSlotDiff
// is the badge-only oracle there.
//
// The baseline is taken on the GAME thread at the two moments the pane looks as it does
// without us: frames the indicator is hidden -- but NOT the frame it hides on, whose repaint
// has not run yet, so the surface still holds our line -- and just before a show following a
// hidden frame, which gives a dialog's FIRST show an answer, the splice having happened on
// that very frame.
int ScQueueIndBoxDiff(DWORD root);

// ---------------------------------------------------------------------------
// SHARED SURFACE PRIMITIVES. sc_hudrow's indicator asks the same three questions as the
// group line -- where is this dialog's surface, how tall is the small font, what does the
// pane look like without our text -- so both answer them here rather than in two copies.
// ---------------------------------------------------------------------------

// Copy `rect` of the dialog's 8-bit surface into `out`: w*h bytes, or 0 when the rect is not
// wholly on a readable surface or does not fit `outMax`. The caller owns the buffer, so two
// modules can hold copies of two different rects.
int ScQueueIndCopyRect(DWORD root, const short* rect, BYTE* out, int outMax);

// The dialog surface's own {w,h}. Returns 0 when neither candidate offset holds a plausible
// surface -- callers treat that as "do not place a box", never as a zero-sized pane.
int ScQueueIndSurfaceSize(DWORD root, int* w, int* h);

// The height of the font the SC_CTRL_FONT_SMALLEST bit selects, read out of the font's own
// header. 0 means "no answer" (the handle is not up yet), never "zero pixels tall".
int ScQueueIndSmallFontHeight(void);

// The band `want` pixels wide and SC_QIND_BOX_H tall at (left, top), clamped to a
// surfW x surfH surface, written to `box` -- and whether the engine's own draw would
// still draw ALL of a string in it. SC_VA_DRAW_STRING refuses outright when
// `top + fontHeight > clip.bottom` (research/status-pane-text.md 3), so the band is
// measured against the FONT'S own height rather than a constant: a band shorter than the
// font draws nothing while every field read-back says the indicator is fine. A box
// narrower than the string draws a TRUNCATION, worse than nothing because it reads as a
// working feature. `fontH` gets the height that decided, for the caller's own log line.
bool ScQueueIndPlaceBand(int left, int top, int want, int surfW, int surfH,
                         short* box, int* fontH);

// INK: non-background bytes of the dialog's own 8-bit surface inside a rect. That surface is
// BinDlg+0x10 with {u16 w, u16 h} at +0x0C/+0x0E, read off the allocator 0x004C35F0 itself
// (research/status-pane-text.md 4). Answers "did anything get drawn there" from in-process
// memory, which the control's fields cannot -- corroboration only, since WHAT the indicator
// says comes from its pszText. -1 when the surface is unreadable.
int ScQueueIndSurfaceInk(DWORD root, int left, int top, int right, int bottom);

// ---------------------------------------------------------------------------
// Test seam -- the frame path driven against a fake dialog tree from hooktest.exe.
// ---------------------------------------------------------------------------

typedef void (*ScQueueIndCtlFn)(DWORD ctrl);
typedef void (*ScQueueIndDriverFn)(void);

void ScQueueIndTestBegin(BYTE* fakeModuleBase,
                         ScQueueIndCtlFn show, ScQueueIndCtlFn hide, ScQueueIndCtlFn update,
                         ScQueueIndCtlFn enable, ScQueueIndDriverFn origDriver);

// The per-frame body the detour calls. Exposed so the offline test drives exactly the
// code the game drives.
void ScQueueIndOnFrame(void);

int  ScQueueIndCurrentMode(void);
const char* ScQueueIndCurrentText(void);
bool ScQueueIndIsSpliced(void);
bool ScQueueIndIsShown(void);

enum ScQueueIndStat {
    SC_QIND_STAT_FRAMES = 0,    // frames the detour ran
    SC_QIND_STAT_SHOWS = 1,     // times the text was (re)written and shown
    SC_QIND_STAT_HIDES = 2,     // times it went away because there was nothing to say
    SC_QIND_STAT_SPLICES = 3,   // controls spliced into a dialog child list
    SC_QIND_STAT_REFUSED = 4,   // splices refused (no engine handler for the type)
    // RESERVED: nothing increments these two, since the ENGINE writes the overflow slots
    // under the phantom bracket instead of this module hand-filling them. They keep their
    // numbers so no other value silently changes meaning, and stay off the QINDSTATS line
    // because a printed count must be one something increments (AGENTS.md § "Diagnostics
    // and reporting").
    SC_QIND_STAT_ICONS = 5,
    SC_QIND_STAT_NOGRP = 6,
    // Presses RESCUED from the engine's own disable event on a slot the plugin fills -- not
    // "disable events seen", only ones arriving while a human holds the mouse down on that
    // icon, which is what makes a green regression arm with this at 0 suspicious.
    SC_QIND_STAT_PRESSKEPT = 7,
    // THE DENOMINATOR for pressKept: `pressKept=0` alone cannot tell an INERT fix from a race
    // the click happened to win. All three count on the same path, so together they say which
    // it is -- no disable events on our slots means the ownership test never fired; disables
    // but never one during a press means the press was never in flight when it mattered;
    // disables during a press with pressKept still 0 means the restore itself is broken.
    // (AGENTS.md § "Diagnostics and reporting": log ENTRY as well as outcome, or "it never
    // ran" and "it ran and did nothing" are one silence.)
    SC_QIND_STAT_DISABLE_OWNED = 8,    // disable events that reached a slot we own
    SC_QIND_STAT_DISABLE_PRESSED = 9,  // ... of those, ones arriving with a press in flight
    // Ring slots phantom-written for the length of one queueLayout call: the bracket's OWN
    // activity counter, with DISABLE_OWNED above as its tripwire. Without the phantom the
    // engine's disable lands on an owned slot EXACTLY once per click (measured deterministic);
    // with it, queueLayout takes the occupied branch and DISABLE_OWNED must not move at all.
    // A suite asserts the pair -- phantom moving, disableOnOwned still -- which is what stops
    // a green arm meaning "the race was won".
    SC_QIND_STAT_PHANTOM = 10,
    // A slot the overflow map called the plugin's held a REAL type when the phantom went to
    // write it: the rebalance invariant broken (occupied slots contiguous from the head, ring
    // at the hold while overflow exists). The phantom REFUSES such a slot rather than
    // overwrite an engine item, and counts the refusal here. Expected 0.
    SC_QIND_STAT_PHANTOM_DIRTY = 11,
    // Queue icons 3..6 lit with a held research item / taken back down (one per icon, not
    // per frame: a settled pane moves neither).
    SC_QIND_STAT_UPG_ICON_SHOWS = 12,
    SC_QIND_STAT_UPG_ICON_HIDES = 13,
    SC_QIND_STAT__COUNT = 14
};
int ScQueueIndStat(int which);

// ---------------------------------------------------------------------------
// THE PHANTOM WINDOW's cross-thread guard.
//
// The bracket makes the ring slots the plugin holds items behind NON-EMPTY for the length
// of one queueLayout call, so the ENGINE lays them out occupied with its own code and calls
// enableControl instead of disableControl: no dwUser=6 event exists to clear a player's
// PRESSED bit mid-click, and the click's press/activate cycle is a vanilla occupied slot's.
//
// The window cannot be seen from the game thread: it opens and closes inside one queueLayout
// call frame and every ENGINE reader of the ring runs on that same thread (classification in
// research/production-queue.md 8.8; those ring mutations are multi-store and unsynchronised
// anyway, so an off-thread reader sees torn rings in vanilla too). The readers that CAN land
// inside are this plugin's observer thread (PRODQ/PRODQSEL, PRODFAN, STATQ, QIND) and the
// test harness reading process memory. Both read this generation instead of hoping: odd =
// open, changed across a read = the read straddled one.
// It moves only when a phantom is actually written, so with the feature off (or nothing
// held) it sits at its last even value and readers pay two loads.
unsigned ScQueueIndRingGen(void);

// The generation once no window is open: an open one closes when its queueLayout call
// returns, so this waits (bounded) instead of letting a reader spend its tries inside it.
// Odd only when the wait gave up. Every observer try starts here.
unsigned ScQueueIndRingGenSettled(void);

// THE observer-thread read of one building's ring (head byte + five slots) straight from
// memory, coherent against the window above. Returns 1 when the read settled, 0 when it
// never did, in which case head/ring hold a plain read the caller must PRINT as
// ringStable=0 rather than trust. head may be NULL. (sc_card reads through its reader
// seam instead, with the same generation test around it.)
int ScQueueIndReadRing(DWORD unit, BYTE* head, WORD* ring);

// Test seam for the bracket itself: apply writes the held types into the portrait building's
// empty ring slots (returns how many), restore puts back what was saved. The detour calls
// exactly these around the trampoline; hooktest calls them around a fake layout to prove the
// write/restore is byte-exact and that the generation brackets it.
int  ScQueueIndPhantomApply(void);
void ScQueueIndPhantomRestore(void);

#endif // SC_QUEUEIND_H
