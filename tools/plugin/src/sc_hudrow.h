// sc_hudrow.h -- page the bottom-HUD wireframe row through the whole shadow
// selection (task 017, design (c): paging + a native page-indicator control).
//
// THE PROBLEM. The fan-out (sc_fanout.h) commands every unit the player selected
// past the engine's 12-cap, and the circles (sc_circles.h) mark them on the map --
// but the 12-slot wireframe row at the bottom of the screen still denies they
// exist. research/hud-selection-row.md maps that row end to end; this module is
// stage B of that map.
//
// THE MECHANISM. The row is 12 dialog controls (ids 0x21..0x2C) inside the
// rez\statdata.bin dialog. Each button displays and clicks WHATEVER CUnit* sits in
// its 8-byte statUser record -- nothing in the engine's draw or click path asks
// whether that unit is engine-selected (hud-selection-row.md 6). So this module:
//
//   1. detours the per-frame status-area dispatcher 0x00458120. While the shadow
//      list holds <= 12 units it tails straight into the engine's own dispatcher
//      -- the stock path runs stock, single-portrait and multi-select alike. With
//      overflow it fills the 12 buttons from one PAGE of the shadow list itself
//      and skips the engine's layout entirely. Detouring the dispatcher rather
//      than the multi-select act/cond pair is what lets it restore stock even
//      when a shadow click drops the selection to one unit (the engine's single
//      branch never calls the multi-select act);
//   2. wraps the 12 buttons' interact pointers (control+0x2A, plain data writes --
//      no code is patched) with a shim: RIGHT-CLICK on the row flips to the next
//      page; every other event tail-calls the engine's own handler 0x004583E0, so
//      left/shift/ctrl/alt clicks keep their stock meaning on whatever the row
//      currently shows;
//   3. splices ONE extra control into the dialog -- a text indicator ("36 units
//      1-12 (1/3)") whose draw/interact handlers come from the engine's own
//      per-type default tables, so it renders exactly like a loaded control. Its
//      control id is negative, which the CREATE-time handler binder skips by
//      construction (FUN_00418100 requires 0 < index). It is spliced at the TAIL of
//      the child list and drawn in the BAND BELOW the row, not on the buttons --
//      task 048; the head splice meant the wireframes painted over it every frame,
//      and the on-the-buttons box put it across the unit icons the way task 039's
//      group line was. See sc_hudrow.cpp's EnsureSpliced and PlaceIndicator.
//
// THE RULES, inherited from the conductor's stage-B pick:
//   * ANY selection change -- map click, row click, hotkey recall, unit death --
//     snaps back to page 1, which always shows the engine's own 12. Stale pages
//     never survive a selection change.
//   * With no overflow the dialog is pixel-stock: no wrap, no indicator, engine
//     code fills the row. The wrap and the splice are applied lazily on the first
//     overflow display and undone on the way back.
//   * The module writes statUser records, the two module-owned globals above, and
//     nothing else in game memory. It never touches CSprite::selectionIndex or
//     sprite flag 0x08 -- there is no code path here that could (it never reaches
//     a sprite at all); hooktest part [10] poisons and asserts anyway.
//
// THREADING. Everything below except Init/InstallHooks/RemoveHooks/LogStats runs
// on the GAME thread only (the detours and the button shim are called by the
// engine's dispatcher and dialog event loop). The observer thread must not call
// into this module.

#ifndef SC_HUDROW_H
#define SC_HUDROW_H

#include <windows.h>

// `moduleBase` is StarCraft.exe's actual load address; `enabled` comes from
// %SCPLUGIN_HUDROW% (default on in fanout mode). Disabled means every entry point
// below is a no-op, so this feature has its own off switch independent of the mode.
void ScHudRowInit(BYTE* moduleBase, bool enabled);
bool ScHudRowEnabled(void);

// Installs the one detour (dispatcher 0x00458120). Call under the same thread
// suspension as the other hooks. Returns the number installed (0 or 1).
int  ScHudRowInstallHooks(void);

// Un-splices the detours and best-effort restores the 12 wrapped interact
// pointers and un-splices the indicator. Mid-game unload remains unsupported for
// the same reason as sc_circles (the game thread may be inside the shim), but the
// pointer restores are single atomic dword writes, so they are attempted.
void ScHudRowRemoveHooks(void);

void ScHudRowLogStats(void);

// ---------------------------------------------------------------------------
// Test seam (hooktest part [10])
//
// The engine is reached through five pointers: show/hide/update control, the
// original button interact, and the original dispatcher. Replacing them lets the
// whole page machine run against a fake dialog tree in a test process.
// ---------------------------------------------------------------------------

typedef void (*ScHudCtlFn)(DWORD control);
typedef void (*ScHudDispatchFn)(void);
typedef int  (__attribute__((fastcall)) *ScHudInteractFn)(DWORD control, DWORD evt);

void ScHudRowTestBegin(BYTE* fakeModuleBase,
                       ScHudCtlFn show, ScHudCtlFn hide, ScHudCtlFn update,
                       ScHudInteractFn engineInteract,
                       ScHudDispatchFn origDispatch);

// The decision core the detour marshals into -- exposed so the test can drive it
// without any hook installed. Reads the shadow list, decides page-vs-stock, and
// either fills a page or defers to the original dispatcher via the seam pointer.
void ScHudRowOnDispatch(void);

// The button shim's core, driven with a fake control + event.
int  ScHudRowOnButtonEvent(DWORD control, DWORD evt);

int  ScHudRowCurrentPage(void);   // 0-based
int  ScHudRowPageCount(void);
int  ScHudRowGatedCount(void);    // clicks the gate has swallowed
bool ScHudRowIsDiverged(void);    // latched off-to-stock on engine divergence

// Frames the PAGED path actually ran. This module's whole seam is the >12 state, so this is
// the coverage number a run has to print beside its verdict: 0 means the run never reached
// the thing under test, whatever else it says (AGENTS.md, task 041).
int  ScHudRowPagedFrames(void);

// The page indicator: is our line currently on the surface, and in which rect. The rect is
// the LIVE control's own bounds, not a remembered constant -- it is recomputed from the row
// every paged frame (task 048: the line moved out of the icon row into the band below it).
bool ScHudRowIndicatorShowing(void);
void ScHudRowIndicatorBox(short* out);   // out[4] = {left, top, right, bottom}

// THE TWO SCREEN-LEVEL READINGS, exposed so the offline test can drive them. Both are
// DIFFERENCES against copies of the same rect, never ink counts: the pane's own art is in
// this surface, so an ink count over any rect in it saturates and can no longer detect our
// text at all (task 048: indInk read 2368 of 2368 bytes, identically, for three different
// strings). -1 from either is an honest "no answer", never a 0.
//
//   BandDiff      how many of the band's bytes differ from the copy taken with none of our
//                 line on it -- the only number that says the engine DREW it.
//   BandStranded  how many of the bytes our line owns still hold its value after the row has
//                 handed back to stock. 0 is the pass. `*glyphOut` returns the size of that
//                 mask, because a 0 over an empty mask is a blind probe, not a clean band.
int ScHudRowBandDiff(void);
int ScHudRowBandStranded(int* glyphOut);

// TEST SEAM ONLY. The band copies are gated on a wall clock in the game (the redraw walk can
// be tens of thousands of dispatcher calls away, so a call count cannot stand in for it); the
// offline test has no engine and paints synchronously, so it sets both windows to zero. The
// ORDER the windows enforce -- read, see it unchanged, only then trust it -- is unaffected.
void ScHudRowTestSetBandTiming(int settleMs, int pollMs);

#endif // SC_HUDROW_H
