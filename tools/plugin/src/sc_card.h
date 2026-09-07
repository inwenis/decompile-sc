// sc_card.h -- READ the console's two clickable dialogs out of the running process: the
// COMMAND CARD and the status pane's PRODUCTION QUEUE STRIP.
//
// research/command-card.md maps the card end to end: nine dialog controls, ids 1..9, inside
// the rez\statbtn%c.bin dialog at 0x0068C148; each carries a Button* in its `user` field
// (+0x26) and an enabled/greyed bit in its flags (+0x18 & 0x2). Both input paths -- the mouse
// (0x00459947) and the hotkey predicate (0x004588C0) -- test that one bit and refuse, so the
// card's own memory names the slot, the ability and the state without any input at all.
// Cancelling a SPECIFIC queued item is not a card action: the card's Cancel (buttonset slot 9,
// actionParam 0xFE) cancels the LAST queued item; the five per-item icons live in the status
// pane, SC_VA_STATDATA_DIALOG, ids 2..6, walked the way queueLayout 0x004268D0 does. Which of
// those icons the player can click is therefore a read of that dialog, never a guessed
// coordinate and never a hash of a frame.
//
// The walk installs no hook, calls nothing in the game and writes nothing, so it runs in
// -Mode observe, the stock arm of every plugin-vs-stock comparison. Every read goes through
// the caller's reader, so a wrong offset produces a missing field rather than a fault inside
// the game.

#ifndef SC_CARD_H
#define SC_CARD_H

#include <windows.h>

#include "sc_addresses.h"

// The reader seam: returns false instead of faulting on an unreadable address.
typedef bool (*ScCardReadFn)(DWORD addr, void* out, size_t n);

struct ScCardSlot {
    DWORD control;       // BinDlg*
    int   index;         // control id, 1..9
    DWORD flags;         // control+0x18
    bool  visible;       // flags & SC_CTRL_FLAG_VISIBLE
    bool  disabled;      // flags & SC_CTRL_FLAG_DISABLED -- the bit both input paths test
    WORD  graphic;       // control+0x24 -- the icon actually being drawn (0xFFFF = blanked)
    DWORD button;        // control+0x26 -- the Button* the layout function assigned
    bool  buttonOk;      // the Button record was readable
    WORD  btnSlot;         // Button+0x00
    WORD  btnIcon;         // Button+0x02
    DWORD btnCond;         // Button+0x04
    DWORD btnAction;       // Button+0x08
    WORD  btnCondParam;    // Button+0x0C
    WORD  btnActParam;     // Button+0x0E
    WORD  btnNameStr;      // Button+0x10
    WORD  btnDisStr;       // Button+0x12
    // control+0x04 -- s16 left,top,right,bottom, RELATIVE TO THE DIALOG. The
    // engine adds the dialog's own origin (0x00458850 does exactly
    // `dlg->rct.left + child->rct.left`), so an absolute point is root+ctrl.
    // Logged so a probe reads the rects from the live dialog: one that clicks a
    // guessed coordinate cannot tell "the button refused" from "the click missed".
    short rect[4];
};

struct ScCardHeader {
    bool  ok;            // the dialog pointer was readable and non-null
    DWORD dialog;        // 0x0068C148
    DWORD root;          // the dialog record the children hang off
    WORD  cardId;        // 0x0068C14C
    WORD  overrideSel;   // 0x0068C1C4  (0xE4 = none)
    WORD  overrideSub;   // 0x0068C1C8  (0xE4 = none)
    DWORD refuseReason;  // 0x0066FF60
    DWORD portrait;      // 0x00597248
    WORD  portraitType;  // CUnit+0x64
    WORD  portraitSet;   // CUnit+0x94 -- the unit's own buttonset id
    WORD  portraitEnergy;// CUnit+0xA2
    BYTE  portraitOwner; // CUnit+0x4C
    WORD  setCount;      // buttonSetTable[cardId].count
    DWORD setButtons;    // buttonSetTable[cardId].buttons
    short rootRect[4];   // the dialog's own origin; slot rects are relative to it
    int   slots;         // how many of the nine controls were found
    int   shown;         // how many are visible
    int   greyed;        // how many are visible AND disabled
};

// The per-player tech state the ability buttons are gated on. Reported next to the card
// because the two only mean anything together: "greyed" is available-but-not-researched.
// Check a fixture's granted tech HERE, in the engine's own memory, never in the generator's
// read-back of its own write -- such a read-back can agree with an indexing bug and report
// success for a map the engine never received.
struct ScCardTechState {
    bool ok;
    int  player;
    BYTE available[SC_TECH_COUNT];
    BYTE researched[SC_TECH_COUNT];
};

// ---------------------------------------------------------------------------
// The status pane's production-queue strip
// ---------------------------------------------------------------------------

struct ScStatusSlot {
    int   display;       // 0..4 -- the WALK position, which is what the engine calls
                         // the display index; the payload a click on it sends
    DWORD control;       // BinDlg*
    int   index;         // control+0x20. The engine assumes index == display + 2
                         // (queueLayout walks by `next`, statusCtrlActivate sends
                         // index - 2), so a run asserts that rather than trusting it
    DWORD flags;         // control+0x18
    bool  visible;       // flags & SC_CTRL_FLAG_VISIBLE
    bool  disabled;      // flags & SC_CTRL_FLAG_DISABLED -- an EMPTY queue slot's icon
    WORD  graphic;       // control+0x24
    DWORD user;          // control+0x26 -- the 12-byte statUser record
    bool  userOk;        // that record was readable
    WORD  userIcon;         // statUser+0x04 -- the frame drawn: the unit type, or k+6 empty
    WORD  userMode;         // statUser+0x06 -- 3 occupied, 6 empty
    WORD  userType;         // statUser+0x08 -- the unit type, occupied slots only
    WORD  queueType;     // the building's OWN buildQueue[(head + display) % 5]
    short rect[4];       // control+0x04, dialog-relative, same arithmetic as a card slot
};

struct ScStatusHeader {
    bool  ok;            // the dialog pointer was readable and non-null
    DWORD dialog;        // 0x0068C1F0
    DWORD root;          // the dialog record the children hang off
    short rootRect[4];   // the dialog's own origin
    DWORD portrait;      // 0x00597248 -- whose queue the strip is showing
    WORD  portraitType;  // CUnit+0x64
    BYTE  portraitOwner; // CUnit+0x4C
    bool  queueOk;       // the portrait unit's ring was readable
    // The ring read below is made on the OBSERVER thread and the engine's phantom bracket makes
    // owned slots non-empty for the length of each queueLayout call on the game thread, so the
    // read retries around ScQueueIndRingGen and this says whether it ever settled: 0 = head and
    // queue may be mid-window and qtype per slot suspect, so the STATQ header line prints it and
    // a parser refuses those numbers rather than trusting them.
    bool  ringStable;
    BYTE  head;          // CUnit+0xA4
    WORD  queue[SC_BUILD_QUEUE_SLOTS];   // CUnit+0x98, in SLOT order (not display order)
    int   slots;         // how many icon controls the walk found (5 when the strip is up)
    int   shown;         // how many are visible
    int   clickable;     // how many are visible AND NOT disabled -- what the player can click
};

// Walks the strip and logs one STATQ line per icon plus a header and a summary; no-op when
// disabled. Shares %SCPLUGIN_CARDSCAN% with the card: a suite that wants one wants both.
void ScStatusScan(const char* tag);

// Pure: fills `hdr` and `out` (at most SC_STATQ_SLOTS), returns the icon count, logs nothing.
int ScStatusSnapshot(ScStatusHeader* hdr, ScStatusSlot* out, int max);

// %SCPLUGIN_CARDSCAN%; off by default (only a suite that parses this log turns it on).
void ScCardInit(BYTE* moduleBase, bool enabled);
bool ScCardEnabled(void);

// Reads all 44 techs for one player. Exposed for the test seam.
bool ScCardReadTechState(int player, ScCardTechState* out);

// Walks the card and logs one CARD line per slot plus a header and a summary; no-op when
// disabled. Runs on the OBSERVER thread, so it can catch a card the game thread is mid-relay:
// harmless (pointers validated, walk bounded) and visible, since each line carries raw flags.
void ScCardScan(const char* tag);

// ---------------------------------------------------------------------------
// Test seam (hooktest parts [14] the card, [16] the strip)
//
// The walk reaches the game through exactly two things: the module base and the reader.
// Replacing both runs the whole thing against a fake dialog tree in a test process, the one
// place the "a greyed button is reported greyed" assertion can be made to FAIL on demand.
// ---------------------------------------------------------------------------

void ScCardTestBegin(BYTE* fakeModuleBase, ScCardReadFn reader);
void ScCardTestEnd(void);

// Pure: fills `hdr` and `out` (at most SC_CARD_SLOTS), returns the slot count, logs nothing.
int ScCardSnapshot(ScCardHeader* hdr, ScCardSlot* out, int max);

#endif // SC_CARD_H
