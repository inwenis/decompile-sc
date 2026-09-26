// sc_circles.h -- draw the engine's own selection circle under the units sc_fanout.h
// selects past the engine's 12-unit cap, which the engine holds no selection for and
// so never draws. Mechanism and full instruction tables: research/selection-circles.md.
//
// A circle is an IMAGE (id 0x231 + per-sprite-type size index, drawfunc 0x0D) spliced
// into the sprite's overlay list, not a flag the renderer consults, so this module
// reimplements nothing: it calls the engine's own attach (0x004D7070) and remove
// (0x004975D0) primitives, and sprite flag 0x01 records that one is attached.
//
// ScCirclesShow / ScCirclesHide are GAME THREAD ONLY: those primitives mutate the
// sprite overlay list and the image free list the game thread walks to render every
// frame, under no lock. Hence circles are not taken off at unload, and unloading
// mid-game is unsupported (tools/plugin/README.md, off switch 3).

#ifndef SC_CIRCLES_H
#define SC_CIRCLES_H

#include <windows.h>

// `sprite` and `uniqueness` are snapshotted at attach and re-checked at detach: a unit
// can die in between, and its CSprite goes back on the sprite free list where another
// unit may pick it up.
struct ScCircleUnit {
    DWORD unit;
    DWORD sprite;
    BYTE  uniqueness;   // CUnit+0xA5
    BYTE  player;       // CUnit+0x4C
};

// `moduleBase` is StarCraft.exe's actual load address; `enabled` comes from
// %SCPLUGIN_CIRCLES% (default on in fanout mode). Disabled makes every entry point
// below a no-op, giving this feature an off switch independent of the mode.
void ScCirclesInit(BYTE* moduleBase, bool enabled);
bool ScCirclesEnabled(void);

// The one hook this feature needs is CreateNewUnitSelectionsFromList (0x0049AE40),
// whose entry is where our circles come off before the engine puts its own on. Returns
// hooks installed: 1 on success, 0 on failure and 0 when disabled, which is not a
// failure. ScCirclesRemove only un-splices, so DLL_PROCESS_DETACH is safe.
int  ScCirclesInstall(void);
void ScCirclesRemove(void);

// Detaches whatever was attached before, so a caller can re-state the whole set. Units
// carrying flag 0x08 (the engine has them) or flag 0x01 (someone else's circle) are
// skipped, not adopted.
//
// Never set flag 0x08 ("selected") or CSprite::selectionIndex (sprite+0x0B): all four
// instructions reading the index sit behind 0x08, and two (0x0046FD77, 0x0049F7B3) use
// it as a memmove offset into a 12-entry stack array -- >=12 smashes 48 bytes of stack,
// 0..11 silently deletes a different, genuinely selected unit. The price of clear 0x08
// is no health bar (the other half of 0x004E6180, taken off by 0x00497620 only when
// 0x08 is set); circles alone are the scope.
void ScCirclesShow(const ScCircleUnit* units, int n);

// Idempotent.
void ScCirclesHide(void);

int  ScCirclesCount(void);
void ScCirclesLogStats(void);

// Test-only: circles abandoned because the game-session epoch moved (sc_session.h).
// Counted apart from `lost` (a unit that failed a per-unit check) because the per-unit
// checks cannot detect a session change, so one counter would hide which one fired.
unsigned ScCirclesStaleSessionCount(void);

// Test seam: the engine primitives are reached through these two function pointers, so
// src/hooktest.cpp can drive the whole attach/detach/staleness state machine against
// fake sprites in its own address space, with no StarCraft and no hooks. Only whether
// the ENGINE draws the image stays untestable offline -- that is the in-game run's job.

typedef DWORD (*ScAddCircleFn)(DWORD sprite, DWORD colourByte, DWORD baseImageId);
typedef BYTE  (*ScRemoveCircleFn)(DWORD sprite);

// NULL for either function pointer restores the real engine calls.
void ScCirclesTestBegin(BYTE* fakeModuleBase, ScAddCircleFn add, ScRemoveCircleFn remove);

#endif // SC_CIRCLES_H
