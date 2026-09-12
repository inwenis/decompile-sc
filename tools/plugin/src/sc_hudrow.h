// sc_hudrow.h -- page the bottom-HUD wireframe row through the whole shadow
// selection, so the units the fan-out commands past the engine's 12-cap reach the
// row too. research/hud-selection-row.md maps that row end to end.
//
// The row is 12 dialog controls (ids 0x21..0x2C) in the rez\statdata.bin dialog.
// Each button displays and clicks WHATEVER CUnit* sits in its 8-byte statUser
// record -- no engine draw or click path asks whether that unit is engine-selected
// (hud-selection-row.md 6), so filling those records from one PAGE of the shadow
// list is enough. At <= 12 units the stock path runs stock, untouched: the dialog
// is pixel-stock, and the wrap and indicator splice below are applied lazily on
// the first overflow display and undone on the way back.
//
// Detour the status-area dispatcher 0x00458120, not the multi-select act/cond
// pair: the engine's single-unit branch never calls that act, so only the
// dispatcher can restore stock when a shadow click drops the selection to one unit.

#ifndef SC_HUDROW_H
#define SC_HUDROW_H

#include <windows.h>

#include "sc_unit.h"

// GAME THREAD ONLY, except Init/Install/Remove/LogStats: the detour and the button
// shim run inside the engine's dispatcher and dialog event loop, so the observer
// thread must not call in. The module writes statUser records and its own globals
// and nothing else in game memory; it never reaches a sprite, so
// CSprite::selectionIndex and sprite flag 0x08 stay untouched -- the offline
// hooktest poisons every sprite and asserts both anyway, because "no path here
// could" is an argument, not a check.

// `moduleBase` is StarCraft.exe's actual load address; `enabled` comes from
// %SCPLUGIN_HUDROW% (default on in fanout mode). Disabled means every entry point
// below is a no-op, so this feature has its own off switch independent of the mode.
void ScHudRowInit(BYTE* moduleBase, bool enabled);
bool ScHudRowEnabled(void);

// Installs the dispatcher detour (0x00458120) and the wireframe-draw detour (0x00456F50);
// returns 1 when both went in, else 0 with its own half rolled back. Call under the same
// thread suspension as the other hooks.
int  ScHudRowInstall(void);

// THE ROW'S PICTURES. Each button blits frame `unit type` of grpwire.grp, a 131-frame sheet
// of the units plus the six Terran buildings that lift off (CC 106, Barracks 111, Factory
// 113, Starport 114, Science Facility 116, Engineering Bay 122). Every other building id
// below 131 is a "BLANK" placeholder frame and every id past it draws frame 0, the Marine
// (SC_VA_WIREFRAME_DRAW). Vanilla never puts a building there; a building group does. For
// those ids the wireframe draw runs against an all-empty sheet for that one call: border,
// health colours and click stay the engine's, the slot shows no picture.
// The detour's body, exposed so the test drives it with a fake button and a fake original.
void ScHudRowOnWireDraw(DWORD button, DWORD edx, DWORD a, DWORD b, ScCtrlDrawFn orig);
// The sheet a no-picture id is drawn from, for the test to check its shape.
const BYTE* ScHudRowEmptySheet(void);

// Best-effort restore of the detour, the 12 wrapped interact pointers and the
// indicator splice. Mid-game unload stays unsupported (the game thread may be
// inside the shim), but each pointer restore is one atomic dword write, so it is
// attempted anyway.
void ScHudRowRemove(void);

void ScHudRowLogStats(void);

// ---------------------------------------------------------------------------
// Test seam. The engine is reached through exactly five pointers: show/hide/update
// control, the original button interact, and the original dispatcher. Replacing
// them runs the whole page machine against a fake dialog tree in a test process.
// ---------------------------------------------------------------------------

typedef void (*ScHudCtlFn)(DWORD control);
typedef void (*ScHudDispatchFn)(void);
typedef int  (__attribute__((fastcall)) *ScHudInteractFn)(DWORD control, DWORD evt);

void ScHudRowTestBegin(BYTE* fakeModuleBase,
                       ScHudCtlFn show, ScHudCtlFn hide, ScHudCtlFn update,
                       ScHudInteractFn engineInteract,
                       ScHudDispatchFn origDispatch);

// The decision core the detour marshals into -- exposed so the test can drive
// page-vs-stock with no hook installed; stock defers to the original dispatcher
// through the seam pointer.
void ScHudRowOnDispatch(void);

// The button shim's core, driven with a fake control + event. The 12 buttons'
// interact pointers (control+0x2A) are wrapped by plain data write, no code
// patched: RIGHT-CLICK flips to the next page, every other event tail-calls the
// engine's handler 0x004583E0 so left/shift/ctrl/alt keep their stock meaning on
// whatever the row shows.
int  ScHudRowOnButtonEvent(DWORD control, DWORD evt);

// Any selection change -- map click, row click, hotkey recall, unit death -- snaps
// back to page 1, which always shows the engine's own 12: no stale page survives it.
int  ScHudRowCurrentPage(void);   // 0-based
int  ScHudRowPageCount(void);
int  ScHudRowGatedCount(void);    // clicks the gate has swallowed
bool ScHudRowIsDiverged(void);    // latched off-to-stock on engine divergence

// Frames the PAGED path actually ran. This module's whole seam is the >12 state, so this is
// the coverage number a run prints beside its verdict: 0 means the run never reached the
// thing under test, whatever else it says (AGENTS.md § "Generated suites (random, fuzzed,
// property-based)").
int  ScHudRowPagedFrames(void);

// The page indicator ("36 units 1-12 (1/3)") is one extra text control spliced into the
// dialog; its draw/interact handlers come from the engine's per-type default tables, so it
// renders like a loaded control. Its control id is negative, which the CREATE-time handler
// binder skips by construction (FUN_00418100 requires 0 < index). Splice at the TAIL of the
// child list and place it in the BAND BELOW the row: at the head the wireframes paint over
// it every frame, and on the buttons the box sits across the unit icons. The rect below is
// the LIVE control's own bounds, recomputed from the row every paged frame, never a
// remembered constant.
bool ScHudRowIndicatorShowing(void);
void ScHudRowIndicatorBox(short* out);   // out[4] = {left, top, right, bottom}

// Both screen-level readings are DIFFERENCES against copies of the same rect, never ink
// counts: the pane's own art saturates an ink count over any rect in this surface (measured
// 2368 of 2368 bytes, identically, for three different strings). -1 is an honest "no
// answer", never a 0.
//   BandDiff      how many of the band's bytes differ from the copy taken with none of our
//                 line on it -- the only number that says the engine DREW it.
//   BandStranded  how many of the bytes our line owns still hold its value after the row has
//                 handed back to stock; 0 is the pass. `*glyphOut` is the size of that mask,
//                 because a 0 over an empty mask is a blind probe, not a clean band.
int ScHudRowBandDiff(void);
int ScHudRowBandStranded(int* glyphOut);

// TEST SEAM ONLY. The band copies are gated on a wall clock in the game (the redraw walk can
// be tens of thousands of dispatcher calls away, so a call count cannot stand in for it); the
// offline test has no engine and paints synchronously, so it sets both windows to zero. The
// ORDER the windows enforce -- read, see it unchanged, only then trust it -- is unaffected.
void ScHudRowTestSetBandTiming(int settleMs, int pollMs);

#endif // SC_HUDROW_H
