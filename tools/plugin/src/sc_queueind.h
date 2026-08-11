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
// THE ONE HOOK
//   statDisplayDriver 0x004D93F0, the per-frame HUD driver (hud-selection-row.md 4.1). The
//   module runs AFTER the original -- i.e. after the status dispatcher 0x00458120 has laid
//   the pane out and hidden whatever it hides -- which is what lets one control serve both
//   the single-building branch and the multi-select branch, and what lets it re-show itself
//   after the engine's own hide-all sweep. It is deliberately NOT the dispatcher: sc_hudrow
//   already owns that function's 5-byte window.
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
int  ScQueueIndInstallHooks(void);
void ScQueueIndRemoveHooks(void);

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

typedef void (*ScQIndCtlFn)(DWORD ctrl);
typedef void (*ScQIndDriverFn)(void);

void ScQueueIndTestBegin(BYTE* fakeModuleBase,
                         ScQIndCtlFn show, ScQIndCtlFn hide, ScQIndCtlFn update,
                         ScQIndDriverFn origDriver);

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
    SC_QIND_STAT_ICONS = 5,     // queue icons filled from the plugin's own overflow
    SC_QIND_STAT__COUNT = 6
};
int ScQueueIndStat(int which);

#endif // SC_QUEUEIND_H
