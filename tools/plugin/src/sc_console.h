// sc_console.h -- the bottom console on a TALLER screen (the 2x-height step),
// and the click-route trace.
//
//  * THE MOVE (no flag: it is what a taller playfield means). When the generated
//    widescreen table carries a console shift (SC_WS_CONSOLE_SHIFT_Y > 0, i.e.
//    the playfield is taller than the stock 400) and the plugin may write, then
//    in game, every frame from the composer detour:
//      1. every ROOT dialog gets the composite-into-BUFFER bit (0x10000000 at
//         +0x18 -- the bit StatRes ships with), so the dialog layer draws it
//         into the framebuffer at its live bounds instead of blitting straight
//         to the primary. The storm present widen then mirrors the whole frame
//         (sc_stormpresent.cpp). A root left direct-blitting would be erased
//         by that mirror, which is why ALL roots convert, not only the console.
//      2. the ten bottom-console roots (Minimap, TextBox, Stat_F10, StatBtn,
//         StatData, StatPort, StatFluf x4) have their bounds (+0x04) translated
//         DOWN by the shift, once their surfaces exist (the art slice is copied
//         under the live bounds at surface creation), with the vacated and the
//         claimed rect both marked dirty. StatRes (top bar) and StatLB stay.
//      3. the engine's own FULL playfield redraw is requested before every compose
//         (%SCPLUGIN_FULLREDRAW%, default on): the partial path repaints whole
//         sprite rects over cells that are not dirty, which the stock present
//         never shows and the whole-frame mirror does. sc_console.cpp has the read.
//    What the engine bakes outside the dialog records (isPointOverUi's tiers,
//    the right-click router's card rect, the minimap's absolute top, the dirty
//    clip boxes) is in the generated table (console.*, minimap.anchor.*,
//    dlgclip.*). Research: renderer-viewport.md 22.
//
//  * %SCPLUGIN_CONSOLE_TRACE%=1 -- the TRACE. Wraps every ROOT dialog's interact
//    (+0x2A) with a logging shim: one CTRACE line per non-MOUSEMOVE event with
//    the dialog's name, event type, dwUser, cursor x/y and the interact's RETURN
//    VALUE. The dispatcher (0x00419FD0) offers each event to the roots in list
//    order and STOPS at the first non-zero return, so the trace names the dialog
//    that claims a click at any position.
//
// Both -- and the menu centring (sc_menu.h), which moves glue roots from the same walk --
// ride one 6-byte detour on the frame composer (0x0041E280), so all writes
// to dialog records happen on the GAME thread between frames -- never from the
// observer thread. Observe mode (the plugin's off switch) installs neither.
#ifndef SC_CONSOLE_H
#define SC_CONSOLE_H

#include <windows.h>

bool ScConsoleTraceWanted(void);  // %SCPLUGIN_CONSOLE_TRACE% == 1

// True once ScConsoleInstall decided the console is buffer-resident (the move
// is armed): the storm present widen mirrors the WHOLE frame then, and only
// the x>=640 strip otherwise (a direct-blitted console must not be painted over).
bool ScConsoleBufferResident(void);

// The per-frame walk's own answer to "is a game being played": 1 in game, 0 in the
// menus, -1 when nothing determined it (the walk is gated on the move being armed
// and the screen active, so a width-only build never answers). Costs nothing to
// read: the walk already computes it for its own decision.
int ScConsoleInGame(void);

// Installs the frame hook when the move is armed or the trace is wanted.
// writeAllowed is false in observe mode (nothing is installed then).
void ScConsoleInstall(BYTE* moduleBase, bool writeAllowed, bool trace);
void ScConsoleRemove(void);
void ScConsoleLogStats(void);

// Marker channel: "conedge-select" asks the game thread to select the active
// player's first completed unit through the engine's own funnel (19.5) -- the
// off-screen harness cannot post a playfield click under cnc-ddraw.
void ScConsoleOnMarker(const char* label);

#endif
