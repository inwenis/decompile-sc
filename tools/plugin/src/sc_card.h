// sc_card.h -- READ the console's two clickable dialogs out of the running process:
// the COMMAND CARD (task 026) and the status pane's PRODUCTION QUEUE STRIP (task 028).
//
// THE PROBLEM. Task 022 could not drive the Ghost's Personnel Cloaking, and task
// 023's four-arm probe narrowed it to a bounded negative: input reaches the card,
// the ability is on the card, and neither a key nor a click issues it. Both arms
// were posted input, which is the one variable neither run could hold fixed.
//
// THE ANSWER IS A READ, NOT A CLICK. research/command-card.md maps the card end to
// end: nine dialog controls, ids 1..9, inside the rez\statbtn%c.bin dialog at
// 0x0068C148; each one carries a Button* in its `user` field (+0x26) and an
// enabled/greyed bit in its flags (+0x18 & 0x2). Both input paths -- the mouse
// (0x00459947) and the hotkey predicate (0x004588C0) -- test that one bit and
// refuse. So the card's own memory names the slot, the ability and the state
// without any input at all.
//
// WHAT THIS MODULE IS. A read-only walk of that dialog, logged on the marker
// channel next to the world scan. It installs NO hook, calls nothing in the game,
// and writes nothing -- which is what lets it run in -Mode observe, the stock arm
// of every plugin-vs-stock comparison. Every read goes through the caller's reader
// (SafeRead in the plugin, a fake in hooktest), so a wrong offset produces a
// missing field rather than a fault inside the game.
//
// THREADING. ScCardScan runs on the OBSERVER thread, like the world scan. It can
// therefore see a card the game thread is mid-way through relaying; that is
// harmless (every pointer is validated, the walk is bounded) and visible, because
// each line carries the raw flags it read.
//
// THE SECOND DIALOG (task 028). "Cancel a queued unit" is NOT a command-card action
// in vanilla: the card's Cancel button (buttonset slot 9, actionParam 0xFE) sends
// "cancel the LAST queued item", and the five icons that address a SPECIFIC queued
// item live in the other console dialog -- the status pane, SC_VA_STATDATA_DIALOG,
// control ids 2..6, one per display index. ScStatusSnapshot walks those the way
// queueLayout 0x004268D0 does (sc_addresses.h quotes it) and reports, per icon, the
// enabled bit BOTH input paths refuse and the unit type the icon is drawing, beside
// the building's own five ring slots. So "which queued item can the player click,
// and what does it show" is a read of the dialog, never a guess at a coordinate and
// never a hash of a frame.

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
    bool  disabled;      // flags & SC_CTRL_FLAG_DISABLED  <- the whole question
    WORD  graphic;       // control+0x24 -- the icon actually being drawn (0xFFFF = blanked)
    DWORD button;        // control+0x26 -- the Button* the layout function assigned
    bool  buttonOk;      // the Button record was readable
    WORD  bSlot;         // Button+0x00
    WORD  bIcon;         // Button+0x02
    DWORD bCond;         // Button+0x04
    DWORD bAction;       // Button+0x08
    WORD  bCondParam;    // Button+0x0C
    WORD  bActParam;     // Button+0x0E
    WORD  bNameStr;      // Button+0x10
    WORD  bDisStr;       // Button+0x12
    // control+0x04 -- s16 left,top,right,bottom, RELATIVE TO THE DIALOG. The
    // engine adds the dialog's own origin (0x00458850 does exactly
    // `dlg->rct.left + child->rct.left`), so an absolute point is root+ctrl.
    // Logged because task 017 10 q1 left "read the button rects from the live
    // dialog rather than hardcoding them" open, and a probe that clicks a guessed
    // coordinate cannot tell "the button refused" from "the click missed".
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

// The per-player tech state the ability buttons are gated on. Reported next to the
// card because the two only mean anything together: "greyed" is available-but-not-
// researched, and a fixture that claims to have granted a tech is checked HERE, in the
// engine's own memory, rather than believed from the generator's read-back of its own
// write (task 026 -- that read-back agreed with an indexing bug and reported success
// for a map the engine never received).
struct ScCardTechState {
    bool ok;
    int  player;
    BYTE available[44];
    BYTE researched[44];
};

// ---------------------------------------------------------------------------
// The status pane's production-queue strip (task 028)
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
    WORD  uIcon;         // statUser+0x04 -- the frame drawn: the unit type, or k+6 empty
    WORD  uMode;         // statUser+0x06 -- 3 occupied, 6 empty
    WORD  uType;         // statUser+0x08 -- the unit type, occupied slots only
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
    // The ring read below is made on the OBSERVER thread, and task 066's phantom bracket
    // makes owned slots non-empty for the length of each queueLayout call on the game
    // thread -- so the read retries around ScQueueIndRingGen and this says whether it
    // ever settled. 0 = the head/queue values may be mid-window and qtype per slot is
    // suspect; the STATQ header line prints it so a parser can refuse rather than trust.
    bool  ringStable;
    BYTE  head;          // CUnit+0xA4
    WORD  queue[SC_BUILD_QUEUE_SLOTS];   // CUnit+0x98, in SLOT order (not display order)
    int   slots;         // how many icon controls the walk found (5 when the strip is up)
    int   shown;         // how many are visible
    int   clickable;     // how many are visible AND NOT disabled -- what the player can click
};

// Walks the strip and logs one STATQ line per icon plus a header and a summary.
// No-op when disabled. Same %SCPLUGIN_CARDSCAN% switch as the card: both are
// read-only walks of the same console, and a suite that wants one wants both.
void ScStatusScan(const char* tag);

// The pure walk, for the test seam: fills `out` (at most SC_STATQ_SLOTS) and `hdr`,
// returns the number of icon controls found. Reads nothing else and logs nothing.
int ScStatusSnapshot(ScStatusHeader* hdr, ScStatusSlot* out, int max);

// %SCPLUGIN_CARDSCAN%; off by default (the existing suites parse this log).
void ScCardInit(BYTE* moduleBase, bool enabled);
bool ScCardEnabled(void);

// Reads all 44 techs for one player. Exposed for the test seam.
bool ScCardReadTechState(int player, ScCardTechState* out);

// Walks the card and logs one CARD line per slot plus a header and a summary.
// No-op when disabled.
void ScCardScan(const char* tag);

// ---------------------------------------------------------------------------
// Test seam (hooktest part [13])
//
// The walk reaches the game through exactly two things: the module base and the
// reader. Replacing both lets the whole thing run against a fake dialog tree in a
// test process, which is the only place the "a greyed button is reported greyed"
// assertion can be made to FAIL on demand.
// ---------------------------------------------------------------------------

void ScCardTestBegin(BYTE* fakeModuleBase, ScCardReadFn reader);
void ScCardTestEnd(void);

// The pure walk: fills `out` (at most SC_CARD_SLOTS entries) and `hdr`, returns the
// number of slots found. Reads nothing else and logs nothing.
int ScCardSnapshot(ScCardHeader* hdr, ScCardSlot* out, int max);

#endif // SC_CARD_H
