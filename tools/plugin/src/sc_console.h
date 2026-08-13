// sc_console.h -- task 073: move the console PIXELS to the right edge at 800 wide,
// and instrument the click route that decides who owns a console-region click.
//
// Two independently-gated halves, both OFF by default and both ignored in
// -Mode observe (the plugin's whole-program off switch):
//
//  * %SCPLUGIN_CONSOLE_EDGE%=1  -- the MOVE. Once per game, after the console
//    dialogs exist AND their surfaces are allocated, translate the StatRes
//    (resource bar) and StatBtn (command card) root dialog bounds +160 and mark
//    both the old and the new rect dirty, so the layer-2 composite -- which
//    task 073 read instruction-by-instruction (research/renderer-viewport.md
//    section 18 follow-up) blits every dialog surface to the screen at its LIVE
//    bounds (+0x04) -- repaints both regions on the next frame. 071's prototype
//    moved the same bounds and concluded "the pixels do not follow"; what its
//    picture actually showed is that NOTHING DIRTIED the affected rects, so the
//    composite never ran. The move is only performed while the widescreen table
//    is ACTIVE (there is no right edge to move to at 640).
//
//  * %SCPLUGIN_CONSOLE_TRACE%=1 -- the TRACE (071's instrument, rebuilt: its
//    original lives only in that task's pre-split history). Wraps every ROOT
//    dialog's interact (+0x2A) with a logging shim: one CTRACE line per
//    non-MOUSEMOVE event, carrying the dialog's name, event type, dwUser,
//    cursor x/y and the interact's RETURN VALUE. The event dispatcher
//    (0x00419FD0) offers each event to the roots in list order and STOPS at the
//    first non-zero return -- so the trace names the dialog that claims a click
//    at any position, which is exactly the question blocker 2 asks at x>=640.
//
// Both halves ride one 6-byte detour on the frame composer (0x0041E280,
// HookProbe-verified prologue), so all writes to dialog records happen on the
// GAME thread between frames -- never from the observer thread.

#ifndef SC_CONSOLE_H
#define SC_CONSOLE_H

#include <windows.h>

bool ScConsoleEdgeWanted(void);   // %SCPLUGIN_CONSOLE_EDGE%  == 1
bool ScConsoleTraceWanted(void);  // %SCPLUGIN_CONSOLE_TRACE% == 1

// Installs the frame hook when either half is wanted. `edge`/`trace` are the
// caller's already-gated decisions (observe mode passes false/false).
void ScConsoleInstall(BYTE* moduleBase, bool edge, bool trace);
void ScConsoleRemove(void);
void ScConsoleLogStats(void);

// TEST AID, marker-driven (label 'conedge-select'): on the next frame, select
// the active player's first COMPLETED unit through the engine's own click-path
// pair -- CreateNewUnitSelectionsFromList (0x0049AE40) then CMDACT_Select
// (0x004C0860), the exact order the click handler uses (hud-selection-row.md
// item 4). Exists because the off-screen cnc-ddraw harness cannot feed a posted
// PLAYFIELD click (070: 0/8 measured), and task 073's card-click experiment
// needs a selected producer. Called from the observer's marker poll; the
// selection itself runs on the GAME thread inside the frame hook. Inert unless
// the module is installed (never in observe mode).
void ScConsoleOnMarker(const char* label);

#endif // SC_CONSOLE_H
