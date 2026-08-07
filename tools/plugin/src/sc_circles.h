// sc_circles.h -- draw the engine's own selection circle under units the engine does
// not consider selected.
//
// THE PROBLEM. The fan-out (sc_fanout.h) gives one order to every unit the player
// box-selected, past the engine's 12-unit cap. But the engine only draws circles for
// the 12 it actually holds, so 24 units obey a right-click while 12 look ignored.
//
// THE MECHANISM, read out of StarCraft.exe and written up in
// research/selection-circles.md. A selection circle is not a flag the renderer
// consults -- it is an IMAGE (id 0x231 + a per-sprite-type size index, drawfunc 0x0D)
// linked into the sprite's overlay list. The engine attaches it in 0x004E6180 and the
// sprite flag 0x01 records that it is attached. So the plugin does not need to
// reimplement anything: it calls the engine's own attach (0x004D7070) and remove
// (0x004975D0) primitives on the units the cap threw away.
//
// WHAT THIS MODULE DELIBERATELY DOES NOT DO -- and why it is the whole point:
//
//   It never sets sprite flag 0x08 ("selected") and never writes
//   CSprite::selectionIndex (sprite+0x0B).
//
// Exactly one instruction in the entire binary reads selectionIndex -- 0x0046FD77, in
// the click handler -- and it is reached only when the clicked unit's sprite has flag
// 0x08 set. It uses the value as a memmove offset into a 12-entry stack array:
//
//     n = <units in activePlayerSelection, at most 12>
//     if (clicked->sprite->flags & 8) {
//         i = clicked->sprite->selectionIndex;          // 0x0046FD77
//         memmove(&list[i], &list[i+1], (n - 1 - i) * 4);
//     }
//
// There is NO safe value to put there for a unit that is fan-out-selected but not
// engine-selected. A value of 12 or more makes `(n-1-i)` negative and smashes a
// 48-byte stack array; a value of 0..11 is in bounds but silently deletes a DIFFERENT,
// genuinely selected unit from the player's selection. Leaving flag 0x08 clear is what
// makes the whole question moot: our units never enter that branch, so the field is
// never read for them and never has to hold anything.
//
// The cost is that a shadow-selected unit gets a circle but no health bar (the bar is
// the other half of 0x004E6180, and 0x00497620 will only take it off again when 0x08
// is set). That is a deliberate trade, and it is what task 014 was asked for: "Scope
// is the green circles on the battlefield only."

#ifndef SC_CIRCLES_H
#define SC_CIRCLES_H

#include <windows.h>

// One unit we have attached a circle to. `sprite` and `uniqueness` are snapshotted at
// attach time and re-checked at detach: a unit can die in between, and its CSprite
// goes back on the sprite free list where another unit may pick it up.
struct ScCircleUnit {
    DWORD unit;
    DWORD sprite;
    BYTE  uniqueness;   // CUnit+0xA5
    BYTE  player;       // CUnit+0x4C
};

// `moduleBase` is StarCraft.exe's actual load address; `enabled` comes from
// %SCPLUGIN_CIRCLES% (default on in fanout mode). Disabled means every entry point
// below is a no-op, so this feature has its own off switch independent of the mode.
void ScCirclesInit(BYTE* moduleBase, bool enabled);
bool ScCirclesEnabled(void);

// Installs the ONE hook this feature needs: CreateNewUnitSelectionsFromList
// (0x0049AE40), whose entry is where our circles come off before the engine puts its
// own on. Returns true on success. Safe to call when disabled (does nothing, true).
bool ScCirclesInstallHook(void);
void ScCirclesRemoveHook(void);

// Attach a circle to each of `n` units. Detaches whatever was attached before, so a
// caller can simply re-state the whole set. Units already carrying flag 0x08 (the
// engine has them) or flag 0x01 (someone else's circle) are skipped, not adopted.
void ScCirclesShow(const ScCircleUnit* units, int n);

// Detach every circle this module attached. Idempotent.
void ScCirclesHide(void);

int  ScCirclesCount(void);
void ScCirclesLogStats(void);

// ---------------------------------------------------------------------------
// Test seam
//
// The engine primitives are reached through these two function pointers, so
// src/hooktest.cpp can drive the whole attach/detach/staleness state machine against
// fake sprites in its own address space, with no StarCraft and no hooks. What stays
// untestable offline is only whether the ENGINE draws the image -- which is what the
// in-game run is for.
// ---------------------------------------------------------------------------

typedef DWORD (*ScAddCircleFn)(DWORD sprite, DWORD colourByte, DWORD baseImageId);
typedef BYTE  (*ScRemoveCircleFn)(DWORD sprite);

// Points the module at a fake module image and fake primitives. Passing NULL for
// either function pointer restores the real engine calls.
void ScCirclesTestBegin(BYTE* fakeModuleBase, ScAddCircleFn add, ScRemoveCircleFn remove);

#endif // SC_CIRCLES_H
