// sc_unit.h -- the reads of a CUnit and of the dialog tree that every module makes.
//
// Six modules independently grew the same handful of helpers: is this pointer a real
// unit array slot, is that unit still linked into its player's list, how long is its
// build queue, walk the dialog's children. They were copied rather than shared for the
// same branch-rebase reason sc_engine.h describes; the bodies were identical, and where
// they were not the difference was an accident rather than a decision (sc_hudrow's list
// walk skipped the per-link bounds check its four siblings all made).
//
// Everything here is a small, stateless read through sc_engine.h's relocation layer, so
// it is header-only: `static inline`, no sc_unit.cpp, nothing to add to a build list.

#ifndef SC_UNIT_H
#define SC_UNIT_H

#include <windows.h>

#include "sc_addresses.h"
#include "sc_engine.h"

// ---------------------------------------------------------------------------
// CUnit
// ---------------------------------------------------------------------------

// Is this a pointer to a real slot of the unit array? The array is a fixed 1700-entry
// global, so a valid CUnit* is exactly an in-range, correctly-strided offset from its
// base. EVERY dereference of a unit pointer the game handed us is gated on this --
// including each link of the list walks below -- because a bad one would otherwise be
// dereferenced inside the game's own thread.
static inline bool ScUnitPtrValid(DWORD unit) {
    if (!unit) return false;
    DWORD arrayBase = ScRuntimeVa(SC_VA_UNIT_ARRAY_BASE);
    if (unit < arrayBase) return false;
    DWORD off = unit - arrayBase;
    if (off % SC_CUNIT_SIZE != 0) return false;
    return (off / SC_CUNIT_SIZE + 1) <= SC_MAX_UNIT_INDEX;   // the wire index is 1-based
}

// index+uniqueness packed exactly as CMDACT_Select / the Right Click builder / the
// Targeted Order builder all do it. 0 for anything out of range, which is what the
// engine encodes too.
static inline WORD ScUnitTag(DWORD unit) {
    if (!ScUnitPtrValid(unit)) return 0;
    DWORD index = (unit - ScRuntimeVa(SC_VA_UNIT_ARRAY_BASE)) / SC_CUNIT_SIZE + 1;
    BYTE uniq = *(BYTE*)(unit + SC_CUNIT_OFF_UNIQUENESS);
    return (WORD)(((WORD)uniq << 11) | (WORD)index);
}

// Reachable from playerUnitList[player] via CUnit+0x6C? A unit in play is linked in
// there by the unit (re)init 0x004A0320 and UNLINKED by the removal path 0x004A0740
// (sc_addresses.h, SC_VA_PLAYER_UNIT_LIST, hud-selection-row.md 6.1). So a unit that
// is NOT reachable has been removed -- killed-and-not-recycled, trigger RemoveUnit,
// archon-consumed -- whichever path dropped it. Transport-loaded and mind-controlled
// units stay linked and read as reachable, which is correct: they are live,
// identity-correct units.
//
// Every link is bounds/stride-validated before it is followed and the walk is
// bounded, so a torn or corrupt list fails closed rather than faulting or hanging.
static inline bool ScUnitInPlayerList(DWORD unit, BYTE player) {
    if (player >= SC_MAX_PLAYERS) return false;
    DWORD head = *(DWORD*)(ScRuntimeVa(SC_VA_PLAYER_UNIT_LIST) + (DWORD)player * 4);
    int n = 0;
    for (DWORD u = head; u && n < SC_MAX_UNITS_WALK; ++n) {
        if (!ScUnitPtrValid(u)) return false;
        if (u == unit) return true;
        u = *(DWORD*)(u + SC_CUNIT_OFF_LIST_NEXT);
    }
    return false;
}

// The same question asked of the unit's OWN player, read out of the unit.
static inline bool ScUnitInOwnPlayerList(DWORD unit) {
    if (!ScUnitPtrValid(unit)) return false;
    return ScUnitInPlayerList(unit, *(BYTE*)(unit + SC_CUNIT_OFF_PLAYER));
}

// The three fields every module reads off a unit it has already validated. Named
// rather than spelled out as a cast at each site, because `*(BYTE*)(u + 0xA5)` is
// where a wrong offset hides.
static inline BYTE  ScUnitUniqueness(DWORD unit) { return *(BYTE*)(unit + SC_CUNIT_OFF_UNIQUENESS); }
static inline BYTE  ScUnitPlayer(DWORD unit)     { return *(BYTE*)(unit + SC_CUNIT_OFF_PLAYER); }
static inline DWORD ScUnitHitPoints(DWORD unit)  { return *(DWORD*)(unit + SC_CUNIT_OFF_HITPOINTS); }
static inline DWORD ScUnitSprite(DWORD unit)     { return *(DWORD*)(unit + SC_CUNIT_OFF_SPRITE); }

// ---------------------------------------------------------------------------
// The engine's five-slot build queue, read and written the way the engine does
// ---------------------------------------------------------------------------

static inline WORD ScUnitQueueSlot(DWORD unit, int slot) {
    return *(WORD*)(unit + SC_CUNIT_OFF_BUILD_QUEUE + (DWORD)slot * 2);
}

static inline void ScUnitSetQueueSlot(DWORD unit, int slot, WORD type) {
    *(WORD*)(unit + SC_CUNIT_OFF_BUILD_QUEUE + (DWORD)slot * 2) = type;
}

// The occupied-slot count. `0xE4` is the empty sentinel and every engine reader tests
// against it (research/production-queue.md 2.4). The plugin's own overflow is NOT
// counted here -- that is the whole point of the two numbers.
static inline int ScUnitQueueLength(DWORD unit) {
    int n = 0;
    for (int i = 0; i < SC_BUILD_QUEUE_SLOTS; ++i) {
        if (ScUnitQueueSlot(unit, i) != SC_BUILD_QUEUE_EMPTY) ++n;
    }
    return n;
}

// ---------------------------------------------------------------------------
// Player resources -- the two counters the engine's own spend and refund move
// ---------------------------------------------------------------------------

static inline DWORD* ScPlayerMinerals(BYTE player) {
    return (DWORD*)(ScRuntimeVa(SC_VA_PLAYER_MINERALS) + (DWORD)player * 4);
}

static inline DWORD* ScPlayerGas(BYTE player) {
    return (DWORD*)(ScRuntimeVa(SC_VA_PLAYER_GAS) + (DWORD)player * 4);
}

// ---------------------------------------------------------------------------
// The BinDialog tree
// ---------------------------------------------------------------------------

static inline DWORD ScDlgChild(DWORD dlg)  { return *(DWORD*)(dlg + SC_BINDLG_OFF_FIRST_CHILD); }
static inline DWORD ScDlgNext(DWORD ctrl)  { return *(DWORD*)(ctrl + SC_BINDLG_OFF_NEXT); }
static inline short ScDlgIndex(DWORD ctrl) { return *(short*)(ctrl + SC_BINDLG_OFF_INDEX); }

// Normalize a dispatcher's argument to the root dialog, the way the engine's own
// layout function does (control -> parent).
static inline DWORD ScDlgRoot(DWORD dialog) {
    if (*(WORD*)(dialog + SC_BINDLG_OFF_TYPE) != 0) {
        return *(DWORD*)(dialog + SC_BINDLG_OFF_PARENT);
    }
    return dialog;
}

// BOUNDED, and that is not paranoia: the log paths run on the OBSERVER thread against
// a list the game thread owns, so a torn `next` has to end the walk rather than spin it.
static inline DWORD ScDlgFindChild(DWORD root, short id) {
    DWORD c = ScDlgChild(root);
    for (int guard = 0; c && guard < SC_MAX_CTRLS_WALK; ++guard, c = ScDlgNext(c)) {
        if (ScDlgIndex(c) == id) return c;
    }
    return 0;
}

// A control's bounds: four shorts at +0x04, in LEFT, TOP, RIGHT, BOTTOM order, and
// RELATIVE TO THE DIALOG -- the engine adds the dialog's own origin (0x00458850 does
// `dlg->rct.left + child->rct.left`), so an absolute point is root + ctrl.
static inline short* ScDlgBounds(DWORD ctrl) { return (short*)(ctrl + SC_BINDLG_OFF_BOUNDS); }

static inline DWORD ScStatDialog(void)   { return *(DWORD*)ScRuntimeAddr(SC_VA_STATDATA_DIALOG); }
static inline DWORD ScPortraitUnit(void) { return *(DWORD*)ScRuntimeAddr(SC_VA_ACTIVE_PORTRAIT_UNIT); }

// ---------------------------------------------------------------------------
// The engine's three control primitives
//
// 0x004186A0 / 0x00418700 take the control in ESI (GPTP unit_stat_selection.cpp
// helpers; our decompile of 0x00425960 shows the same register use) and 0x0041C400
// takes it in EAX. VC6 callee-saved rules preserve EBX/ESI/EDI across the call.
//
// The modules that hook these keep their own one-line wrapper, because each has a test
// seam that stands in for the engine offline. What was copied is the asm, and that is
// what lives here.
// ---------------------------------------------------------------------------

static inline void ScCtrlShow(DWORD ctrl) {
    void* fn = ScRuntimeAddr(SC_VA_SHOW_CONTROL);
    __asm__ __volatile__("calll *%[fn]"
        : : "S"(ctrl), [fn] "r"(fn) : "eax", "ecx", "edx", "cc", "memory");
}

static inline void ScCtrlHide(DWORD ctrl) {
    void* fn = ScRuntimeAddr(SC_VA_HIDE_CONTROL);
    __asm__ __volatile__("calll *%[fn]"
        : : "S"(ctrl), [fn] "r"(fn) : "eax", "ecx", "edx", "cc", "memory");
}

static inline void ScCtrlUpdate(DWORD ctrl) {
    void* fn = ScRuntimeAddr(SC_VA_UPDATE_CONTROL);
    DWORD inout = ctrl;
    __asm__ __volatile__("calll *%[fn]"
        : "+a"(inout) : [fn] "r"(fn) : "ecx", "edx", "cc", "memory");
}

#endif // SC_UNIT_H
