// sc_queueind.h -- show that a building holds MORE queued items than the strip draws.
//
// Task 033, from the user's words: "when more then 5 units a queued - is the info showing
// that? (some +x number somewhere in tug?)". Today it is not. The production strip in the
// status pane is five icon controls (ids 2..6) that draw the engine's five-slot ring and
// nothing else (research/production-queue.md 8.1), so a nine-item logical queue and a
// five-item one look identical. Task 025 (-ProdQueue) and task 030 (-ProdFan) both ship in
// the play build and neither tells the player what it did.
//
// WHAT IT DRAWS, and with WHAT
//   One "+N" for the selected building, and one "N bldgs  M queued" line for a group. Both
//   are ENGINE-DRAWN TEXT: the module splices ONE control of type SC_CTRL_TYPE_LSTATIC into
//   the statdata dialog's child list, points its pszText (control+0x14) at a plugin-owned
//   buffer and lets the engine's own static-text update handler draw it
//   (research/status-pane-text.md). No art is added, no pixel is plotted by hand, and the
//   font, colour and clipping are the ones every other label in that pane uses.
//
// WHERE IT DRAWS
//   Over the LAST queue icon (control id 6). That is not a decoration choice: while the
//   plugin is holding overflow it keeps the engine's ring at SC_PRODQ_ENGINE_HOLD = 4
//   (sc_prodqueue.h), so display slot 4 -- control id 6 -- is exactly the slot that is
//   drawn EMPTY and greyed. The count goes in the hole the feature itself creates. The
//   bounds are read out of that control at runtime and never hardcoded; the live values on
//   this install are logged by ScQueueIndLogDialog.
//
// THE TWO HOOKS
//   statDisplayDriver 0x004D93F0, the per-frame HUD driver (hud-selection-row.md 4.1). The
//   module runs AFTER the original -- i.e. after the status dispatcher 0x00458120 has laid
//   the pane out and hidden whatever it hides -- which is what lets one control serve both
//   the single-building branch and the multi-select branch, and what lets it re-show itself
//   after the engine's own hide-all sweep. It is deliberately NOT the dispatcher: sc_hudrow
//   already owns that function's 5-byte window.
//
//   queueLayout 0x004268D0 (task 066). For the length of that one call, the ring slots the
//   plugin holds items behind are made NON-EMPTY -- the held item's type is written into the
//   slot before the original runs and the empty sentinel is restored the instant it returns
//   -- so the ENGINE lays the slot out as occupied with its own code: grp/icon/mode/type,
//   the slot label, and enableControl instead of disableControl. That kills task 061's
//   defect at its root: no disableControl ever fires on a slot the plugin owns, so no
//   dwUser=6 event exists to clear a player's PRESSED bit mid-click, and the click's
//   press/activate cycle is byte-for-byte a vanilla occupied slot's. It also deletes this
//   module's own five field writes (task 039's bug class -- hand-writing what the engine
//   writes correctly). See PhantomApply for why the window is unobservable by construction.
//
// WHAT IT NEVER DOES
//   It writes no unit, no resource global and no engine control except the one it created:
//   the game state it touches is its own spliced record plus the redraw-invalidate the
//   engine's own act calls. Off unless %SCPLUGIN_QUEUEIND% asks for it (launcher
//   -QueueIndicator 1), inert in `-Mode observe`, and with it off the dialog's child list is
//   byte-for-byte stock.

#ifndef SC_QUEUEIND_H
#define SC_QUEUEIND_H

#include <windows.h>

// How the indicator is positioned inside its anchor control, in pixels. Both are
// offsets from the anchor's own top-left, so the actual screen position follows the
// dialog wherever the asset puts it.
#define SC_QIND_INSET_X 10
#define SC_QIND_INSET_Y 12
// Room the text box gets. The engine's static-text draw REFUSES to draw at all when
// `fontHeight + y > clipBottom` (research/status-pane-text.md 3), so the box has to be
// taller than the font rather than merely tall enough to look right.
#define SC_QIND_BOX_H 16
#define SC_QIND_BOX_W 40
// A deliberate OVER-estimate of the small font's advance per character. The box is a clip
// rectangle, not a fill, so reserving too much costs nothing and reserving too little
// truncates the string -- which reads as a working feature and is therefore worse than
// drawing nothing at all. Measured live before this existed: "4 bldgs  4 queued" in a box
// 22 pixels wide.
#define SC_QIND_CHAR_W 7

// THE GROUP LINE'S BAND. In a multi-building selection the pane draws the wireframe row and
// nothing else, which leaves the strip of surface below the row's lower buttons free -- the
// only place in that pane where a line of text is not sitting on top of unit icons. The
// band's top is the row's own lowest edge plus this gap, read from the live buttons; the
// gap is the only constant, and one pixel is what keeps the text off the button borders.
#define SC_QIND_BAND_GAP 1
// The fallback minimum height for that band, used only when the font handle cannot be read
// (normally the FONT'S OWN height decides -- see SmallFontHeight). One pixel over the nine
// that were measured too short in task 033.
#define SC_QIND_BAND_MIN_H 10

// Which thing the indicator is currently saying. Kept as an enum so the log line and the
// offline test can name the case rather than matching on the rendered string.
enum ScQueueIndMode {
    SC_QIND_NONE   = 0,   // nothing to say -- the control is hidden
    SC_QIND_STRIP  = 1,   // one building, more queued than its five icons can draw
    SC_QIND_GROUP  = 2,   // several producing buildings selected (task 030's fan-out)
    SC_QIND_UPGRADE = 3   // one building with upgrades queued -- they have no icons at all
};

// Everything the text depends on, read from game memory by the frame path and handed to
// the composer. Pure input, so hooktest can drive the composer with no StarCraft in sight.
struct ScQueueIndView {
    int selection;   // clientSelectionCount (0x0059723D)
    int engineLen;   // occupied slots of the portrait building's ring (CUnit+0x98)
    int overflow;    // items sc_prodqueue is holding for it, or 0
    int upgrades;    // upgrades sc_upgrades is holding for it, or 0
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

// Installs the ONE detour. Returns 1 on success, 0 on failure; a failure disables the
// feature rather than leaving it half-armed. Call under the shared thread suspension.
int  ScQueueIndInstall(void);
void ScQueueIndRemove(void);

// THE READ-BACK ORACLE. Reads the indicator's state back OUT OF THE LIVE DIALOG -- is the
// control linked into the child chain, is the engine's own visible bit set on it, what
// string does its pszText pointer actually hold -- alongside the numbers it was computed
// from. Never echoes the module's own inputs: every field is re-read.
void ScQueueIndLogState(const char* tag);

// One line per child of the statdata dialog: id, type, flags, bounds and text. This is
// what says which controls in that pane are engine-drawn TEXT and where the free pixels
// are, on THIS install, rather than from a public struct map. Read-only; runs whether or
// not the feature is enabled, because the stock layout is the baseline it is placed against.
void ScQueueIndLogDialog(const char* tag);

// One STATS line, on the detach paths beside the other subsystems'.
void ScQueueIndLogStats(void);

// How many rows at the TOP of a queue-slot rect hold the engine's own slot NUMBER, and are
// therefore excluded from ScQueueIndSlotDiff: two slots legitimately differ there ("1 "
// against "5 "). Sized from the small font's height plus the label's own inset, and the
// live font height is reported as `fontH=` on every QIND line so the number is checkable
// rather than assumed.
#define SC_QIND_SLOT_LABEL_ROWS 12

// TWO QUEUE SLOTS, COMPARED ON THE SURFACE. When the queue holds five of one unit type,
// slot 0 and slot 4 are the same picture -- same 38x35 rect, same border graphic, same
// icon -- so the bytes that differ between them below the label rows are exactly what this
// plugin added. That is a check that CAN fail, which an ink count inside a box that
// contains an engine-drawn icon cannot: it reads > 0 whether or not anything of ours was
// drawn (and did, for a whole task). Returns -1 when it cannot be taken honestly: no
// surface, a missing or hidden control, or two rects of different sizes.
int ScQueueIndSlotDiff(DWORD root, int slotA, int slotB);

// HOW MANY BYTES OF THE INDICATOR'S BOX ARE CURRENTLY OURS. The module keeps a copy of
// those same pixels taken with none of our line in them, and this is the count that differs
// from it. 0 means nothing of ours is on the screen no matter what the control's fields say;
// -1 means there is no baseline for this rect yet (it moved, or this dialog is too new),
// which is an honest "no answer" and never a 0. This exists because INK CANNOT ANSWER THE
// QUESTION in this dialog: the pane's own art is in the same surface, so every rect reads
// saturated (measured live: 1330 of 1330 bytes over a queue icon, 448 of 448 inside the
// indicator's own box) and `ink > 0` is true before anything of ours is drawn.
//
// WHAT IT COUNTS DEPENDS ON THE MODE, and the difference matters when you assert on it:
//   GROUP    the band belongs to no control, so every differing byte is the LINE. This is a
//            text oracle outright.
//   STRIP    the "+N" box sits inside queue icon 6 -- the same icon this module fills -- and
//            the baseline is taken before that fill is painted. So a first reading counts the
//            icon we wrote AND the text: "bytes this plugin is responsible for", not "the text
//            drew". The text-specific oracle in that mode is ScQueueIndSlotDiff, where slot 0
//            and slot 4 hold the same art and the only difference left is the string.
//
// The copy is taken on the GAME thread, at two moments, both of which are "the pane as it
// looks without us":
//   * on frames the indicator is hidden -- but NOT the frame it hides on, where the repaint
//     it just asked for has not run yet and the surface still holds our own line;
//   * immediately before a show that follows a hidden frame -- which is what gives the FIRST
//     show of a dialog an answer, since the splice the other site needs happens on that very
//     frame.
int ScQueueIndBoxDiff(DWORD root);

// ---------------------------------------------------------------------------
// SHARED SURFACE PRIMITIVES. sc_hudrow's own indicator has the same three questions this
// module answered for the group line -- where is this dialog's surface, how tall is the
// small font, and what did the pane look like before our text went on it -- and the answer
// is these functions rather than a second copy of them (task 048).
// ---------------------------------------------------------------------------

// Copy `rect` of the dialog's 8-bit surface into `out`. Returns the number of bytes copied
// (w*h), or 0 when the rect is not wholly on a readable surface or does not fit `outMax`.
// The caller owns the buffer, so two modules can hold copies of two different rects.
int ScQueueIndCopyRect(DWORD root, const short* rect, BYTE* out, int outMax);

// The dialog surface's own {w,h}. Returns 1 when it could be read, 0 when neither candidate
// offset holds a plausible surface -- which callers treat as "do not place a box", never as
// a zero-sized pane.
int ScQueueIndSurfaceSize(DWORD root, int* w, int* h);

// The height of the font the SC_CTRL_FONT_SMALLEST bit selects, out of the font's own
// header. `base` is the CALLER's module base, so a test seam driving a fake image gets its
// own answer. 0 means "no answer" (the handle is not up yet), never "zero pixels tall".
int ScQueueIndSmallFontHeight(void);

// INK: how many non-background bytes the dialog's own 8-bit surface holds inside a rect.
// The dialog surface is BinDlg+0x10 with {u16 w, u16 h} at +0x0C/+0x0E -- read off the
// allocator 0x004C35F0 itself (research/status-pane-text.md 4). This answers "did anything
// get drawn there", which a read of the control's fields cannot, and it is in-process
// memory rather than a screen capture. Corroboration, never the content oracle: WHAT the
// indicator says is read from its pszText. Returns -1 when the surface is unreadable.
int ScQueueIndSurfaceInk(DWORD root, int left, int top, int right, int bottom);

// ---------------------------------------------------------------------------
// Test seam -- the frame path driven against a fake dialog tree from hooktest.exe.
// ---------------------------------------------------------------------------

typedef void (*ScQueueIndCtlFn)(DWORD ctrl);
typedef void (*ScQueueIndDriverFn)(void);

void ScQueueIndTestBegin(BYTE* fakeModuleBase,
                         ScQueueIndCtlFn show, ScQueueIndCtlFn hide, ScQueueIndCtlFn update,
                         ScQueueIndDriverFn origDriver);

// The per-frame body the detour calls. Exposed so the offline test drives exactly the
// code the game drives.
void ScQueueIndOnFrame(void);

// Test-only read-back of the module's own state.
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
    // RESERVED (task 066). These two counted the hand-fill of the overflow icons -- slots
    // written and fills refused for a null GRP global. The phantom bracket deleted that
    // fill (the ENGINE writes the slot now), so nothing can increment either; they keep
    // their numbers so no other value silently changes meaning, and they left the
    // QINDSTATS line under the task-030 rule (a printed count must be a count something
    // increments).
    SC_QIND_STAT_ICONS = 5,
    SC_QIND_STAT_NOGRP = 6,
    // Presses RESCUED from the engine's own disable event on a slot the plugin fills
    // (task 061). Not "disable events seen" -- only the ones that arrived while a human
    // was holding the mouse down on that icon, which is what makes a green regression arm
    // with this at 0 a suspicious green rather than a passing one.
    SC_QIND_STAT_PRESSKEPT = 7,
    // THE DENOMINATOR pressKept was published without, and the run that needed it read
    // `pressKept=0` with no way to tell an INERT fix from a race the click happened to
    // win. Both of these are counted on the same path, so the three numbers together say
    // which it was: no disable events on our slots at all means the ownership test never
    // fired; disables but never one during a press means the press was never in flight
    // when it mattered; disables during a press with pressKept still 0 would mean the
    // restore itself is broken. (AGENTS.md, task 030: log ENTRY as well as outcome, or
    // "it never ran" and "it ran and did nothing" are one silence.)
    SC_QIND_STAT_DISABLE_OWNED = 8,    // disable events that reached a slot we own
    SC_QIND_STAT_DISABLE_PRESSED = 9,  // ... of those, ones arriving with a press in flight
    // Task 066. Ring slots phantom-written for the length of one queueLayout call. This is
    // the fix's OWN activity counter, and DISABLE_OWNED above is its tripwire: pre-fix the
    // engine's disable landed on an owned slot EXACTLY once per click (PR #95 measured it
    // deterministic); with the phantom in place queueLayout takes the occupied branch and
    // DISABLE_OWNED must not move at all. A suite asserts the pair -- phantom moving,
    // disableOnOwned still -- which is what stops a green arm meaning "the race was won".
    SC_QIND_STAT_PHANTOM = 10,
    // A slot the overflow map said was the plugin's held a REAL type when the phantom went
    // to write it. That is the rebalance invariant broken (occupied slots contiguous from
    // the head, ring at the hold while overflow exists), so the phantom REFUSES the slot
    // rather than overwrite an engine item, and counts the refusal here. Expected 0.
    SC_QIND_STAT_PHANTOM_DIRTY = 11,
    SC_QIND_STAT__COUNT = 12
};
int ScQueueIndStat(int which);

// ---------------------------------------------------------------------------
// THE PHANTOM WINDOW's cross-thread guard (task 066).
//
// The window itself cannot be seen from the game thread: it opens and closes inside one
// queueLayout call frame, and every ENGINE reader of the ring runs on that same thread
// (the classification is in research/production-queue.md 8.8 -- and structurally, the
// engine's own ring mutations were ALREADY multi-store and unsynchronised, so a reader on
// another thread would have observed torn rings in vanilla). The readers that CAN land
// inside it are this plugin's own observer thread (PRODQ/PRODQSEL, STATQ) and the test
// harness reading process memory. Both read this generation instead of hoping:
// odd = the window is open; changed across a read = the read straddled one. Sequence:
//   g1 = ScQueueIndRingGen(); if (g1 & 1) retry;
//   <read the ring>
//   if (ScQueueIndRingGen() != g1) retry;
// The counter only moves when a phantom was actually written, so with the feature off (or
// nothing held) it sits at its last even value and readers pay two loads.
unsigned ScQueueIndRingGen(void);

// Test seam for the bracket itself: apply writes the held types into the portrait
// building's empty ring slots (returns how many), restore puts back what was saved.
// The detour calls exactly these around the trampoline; hooktest calls them around a
// fake layout to prove the write/restore is byte-exact and the generation brackets it.
int  ScQueueIndPhantomApply(void);
void ScQueueIndPhantomRestore(void);

#endif // SC_QUEUEIND_H
