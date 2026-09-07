// sc_console.h -- move the console PIXELS to the right edge at 800 wide, and
// trace which dialog claims a console-region click. Both halves are OFF by
// default, ignored in -Mode observe, and ride one 6-byte detour on the frame
// composer (0x0041E280, HookProbe-verified prologue) so dialog-record writes
// land on the GAME thread between frames, never on the observer thread.
//
// EDGE: once the console dialogs exist AND their surfaces are allocated,
// translate the StatRes and StatBtn root bounds +160 and dirty BOTH old and
// new rect: the layer-2 composite blits each dialog surface at its LIVE bounds
// (+0x04), so an undirtied rect never repaints (research/renderer-viewport.md
// section 18). The shift is relative, so each dialog is translated exactly once
// per game. Widescreen-active only -- at 640 there is no right edge.
//
// TRACE: logs ROOT dialog interact (+0x2A) calls -- mouse-move and timer floods
// dropped -- with the interact's RETURN VALUE. The dispatcher (0x00419FD0)
// offers an event to the roots in list order and STOPS at the first non-zero
// return, so the trace names the click's owner.

#ifndef SC_CONSOLE_H
#define SC_CONSOLE_H

#include <windows.h>

bool ScConsoleEdgeWanted(void);   // %SCPLUGIN_CONSOLE_EDGE%  == 1
bool ScConsoleTraceWanted(void);  // %SCPLUGIN_CONSOLE_TRACE% == 1

// `edge`/`trace` are the caller's gated decisions; observe mode passes
// false/false, which installs nothing.
void ScConsoleInstall(BYTE* moduleBase, bool edge, bool trace);
void ScConsoleRemove(void);
void ScConsoleLogStats(void);

// TEST AID, marker-driven (label 'conedge-select'): on the next frame, select
// the active player's first COMPLETED unit through the engine's own click-path
// pair -- CreateNewUnitSelectionsFromList (0x0049AE40) then CMDACT_Select
// (0x004C0860), the exact order the click handler uses (hud-selection-row.md
// item 4). A posted PLAYFIELD click cannot stand in: the off-screen cnc-ddraw
// harness lands 0 of 8 measured. Called from the observer's marker poll; the
// selection itself runs on the GAME thread inside the frame hook. Inert unless
// the module is installed (never in observe mode).
void ScConsoleOnMarker(const char* label);

#endif // SC_CONSOLE_H
